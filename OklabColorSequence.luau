--!strict

-- OklabColorSequence by @Ap0sentada
-- Creates ColorSequences whose intermediate colors are interpolated in Oklab.
-- API mirrors ColorSequence.new, with an optional trailing `segments` argument:

--   OklabColorSequence.new(Color3)
--   OklabColorSequence.new(Color3, Color3, segments?)
--   OklabColorSequence.new({ ColorSequenceKeypoint }, segments?)
--   OklabColorSequence.new(ColorSequence, segments?)
--   OklabColorSequence.new({ Color3 }, segments?)   -- evenly distributed over [0, 1]

-- math reference for the algo: https://bottosson.github.io/posts/oklab/

const OklabColorSequence = {
	_DefaultSegments = 16;
	_MinSegments = 1;
	_MaxKeypoints = 20; -- roblox ColorSequence keypoint limit
}

type OklabColor = {
	L: number,
	a: number,
	b: number,
}

type Stop = {
	Time: number,
	Oklab: OklabColor,
	Source: Color3, -- original color, used at the endpoints to keep exact precision
}

local function Linearize(channel: number): number
	if channel <= 0.04045 then
		return channel / 12.92
	end

	return ((channel + 0.055) / 1.055) ^ 2.4
end

local function GammaCorrect(channel: number): number
	if channel <= 0.0031308 then
		return 12.92 * channel
	end

	return 1.055 * (channel ^ (1 / 2.4)) - 0.055
end

local function ToOklab(color: Color3): OklabColor
	local red = Linearize(color.R)
	local green = Linearize(color.G)
	local blue = Linearize(color.B)

	local l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
	local m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
	local s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue

	-- max(0, x) guards against NaN if a value ends up slightly negative
	local lRoot = math.max(0, l) ^ (1 / 3)
	local mRoot = math.max(0, m) ^ (1 / 3)
	local sRoot = math.max(0, s) ^ (1 / 3)

	return {
		L = 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
		a = 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
		b = 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot,
	}
end

local function FromOklab(color: OklabColor): Color3
	local lRoot = color.L + 0.3963377774 * color.a + 0.2158037573 * color.b
	local mRoot = color.L - 0.1055613458 * color.a - 0.0638541728 * color.b
	local sRoot = color.L - 0.0894841775 * color.a - 1.2914855480 * color.b

	local l = lRoot * lRoot * lRoot
	local m = mRoot * mRoot * mRoot
	local s = sRoot * sRoot * sRoot

	local red = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	local green = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	local blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

	-- Color3.new is used instead of Color3.fromRGB to avoid 8-bit quantization.
	-- Out-of-gamut channels are clamped per channel.
	return Color3.new(
		math.clamp(GammaCorrect(math.max(0, red)), 0, 1),
		math.clamp(GammaCorrect(math.max(0, green)), 0, 1),
		math.clamp(GammaCorrect(math.max(0, blue)), 0, 1)
	)
end

local function LerpOklab(from: OklabColor, to: OklabColor, alpha: number): OklabColor
	return {
		L = from.L + (to.L - from.L) * alpha,
		a = from.a + (to.a - from.a) * alpha,
		b = from.b + (to.b - from.b) * alpha,
	}
end

local function MakeStop(time: number, color: Color3): Stop
	return {
		Time = time,
		Oklab = ToOklab(color),
		Source = color,
	}
end

local function StopsFromKeypoints(keypoints: { ColorSequenceKeypoint }): { Stop }
	local count = #keypoints

	assert(count >= 2, "OklabColorSequence.new expects at least two keypoints")
	assert(
		count <= OklabColorSequence._MaxKeypoints,
		string.format("OklabColorSequence.new supports at most %d keypoints", OklabColorSequence._MaxKeypoints)
	)
	assert(keypoints[1].Time == 0, "First keypoint must have Time = 0")
	assert(keypoints[count].Time == 1, "Last keypoint must have Time = 1")

	local stops: { Stop } = {}

	for index, keypoint in keypoints do
		assert(
			typeof(keypoint) == "ColorSequenceKeypoint",
			string.format("Keypoint at index %d must be a ColorSequenceKeypoint", index)
		)

		if index > 1 then
			assert(keypoint.Time > keypoints[index - 1].Time, "Keypoint times must be strictly ascending")
		end

		stops[index] = MakeStop(keypoint.Time, keypoint.Value)
	end

	return stops
end

local function StopsFromColors(colors: { Color3 }): { Stop }
	local count = #colors

	assert(count >= 2, "OklabColorSequence.new expects at least two colors")
	assert(
		count <= OklabColorSequence._MaxKeypoints,
		string.format("OklabColorSequence.new supports at most %d input colors", OklabColorSequence._MaxKeypoints)
	)

	local stops: { Stop } = {}

	for index, color in colors do
		assert(typeof(color) == "Color3", string.format("Color at index %d must be a Color3", index))
		stops[index] = MakeStop((index - 1) / (count - 1), color)
	end

	return stops
end

-- Converts any supported input into an ordered list of stops.
-- `second` is only read in the (Color3, Color3) form, where it is the end color.
local function ResolveStops(first: any, second: any): { Stop }
	local firstType = typeof(first)

	if firstType == "Color3" then
		assert(typeof(second) == "Color3", "Expected a second Color3")
		return {
			MakeStop(0, first),
			MakeStop(1, second),
		}
	end

	if firstType == "ColorSequence" then
		return StopsFromKeypoints(first.Keypoints)
	end

	assert(type(first) == "table", "OklabColorSequence.new expects a Color3, ColorSequence or table")

	local list = first :: { any }
	local sample = list[1]

	if typeof(sample) == "ColorSequenceKeypoint" then
		return StopsFromKeypoints(list :: { ColorSequenceKeypoint })
	end

	return StopsFromColors(list :: { Color3 })
end

--[[
	Creates a ColorSequence interpolated in Oklab.
	Input keypoints/colors are preserved; each span between two of them is
	subdivided into up to `segments` parts (limited by the 20 keypoint maximum).

	`second` is overloaded to mirror ColorSequence.new:
	  - (Color3, Color3, segments?) -> `second` is the end color, `third` is segments
	  - every other form            -> `second` is segments
]]
function OklabColorSequence.new(
	first: Color3 | { Color3 } | { ColorSequenceKeypoint } | ColorSequence,
	second: (Color3 | number)?,
	third: number?
): ColorSequence
	-- ColorSequence.new(Color3): constant color, nothing to interpolate
	if typeof(first) == "Color3" and (second == nil or type(second) == "number") then
		return ColorSequence.new(first)
	end

	-- (Color3, Color3, segments?) takes segments from the 3rd argument; the rest use the 2nd
	local segments: number?
	if typeof(first) == "Color3" then
		segments = third
	else
		assert(second == nil or type(second) == "number", "segments must be a number")
		segments = second :: number?
	end

	local stops = ResolveStops(first, second)
	local pairCount = #stops - 1

	local maxSegmentsPerPair = math.max(
		OklabColorSequence._MinSegments,
		(OklabColorSequence._MaxKeypoints - 1) // pairCount
	)
	local segmentCount = math.clamp(
		math.floor(segments or OklabColorSequence._DefaultSegments),
		OklabColorSequence._MinSegments,
		maxSegmentsPerPair
	)

	local keypoints: { ColorSequenceKeypoint } = {}

	for pairIndex = 1, pairCount do
		local from = stops[pairIndex]
		local to = stops[pairIndex + 1]

		-- step 0 is the source stop itself (original color, no Oklab round trip)
		table.insert(keypoints, ColorSequenceKeypoint.new(from.Time, from.Source))

		for step = 1, segmentCount - 1 do
			local alpha = step / segmentCount
			local time = from.Time + (to.Time - from.Time) * alpha
			local color = FromOklab(LerpOklab(from.Oklab, to.Oklab, alpha))

			table.insert(keypoints, ColorSequenceKeypoint.new(time, color))
		end
	end

	-- the final stop closes the sequence with its original color
	local last = stops[#stops]
	table.insert(keypoints, ColorSequenceKeypoint.new(last.Time, last.Source))

	return ColorSequence.new(keypoints)
end

return OklabColorSequence
