# OklabColorSequence

Smoother gradients for Roblox Studio. `OklabColorSequence` builds a `ColorSequence` whose intermediate colors are interpolated in the [Oklab](https://bottosson.github.io/posts/oklab/) color space instead of plain RGB.

Roblox interpolates between `ColorSequence` keypoints linearly in RGB, which often produces muddy or dark midpoints (for example, blue to yellow passes through a dull gray). Oklab is perceptually uniform, so the same gradient looks cleaner and more natural.

The API mirrors `ColorSequence.new`, so switching is usually a one-word change.

```lua
-- Before
gradient.Color = ColorSequence.new(Color3.fromRGB(0, 80, 255), Color3.fromRGB(255, 220, 0))

-- After
gradient.Color = OklabColorSequence.new(Color3.fromRGB(0, 80, 255), Color3.fromRGB(255, 220, 0))
```

## Features

- Same call shapes as `ColorSequence.new`, plus an optional `segments` argument
- Accepts `Color3`, `{ Color3 }`, `{ ColorSequenceKeypoint }` or an existing `ColorSequence`
- Original keypoints are preserved exactly (time and color); only the spans between them are subdivided
- Uses `Color3.new` internally, so results are not quantized to 8 bits
- Automatically respects the 20 keypoint limit of `ColorSequence`

## Requirements

The module uses recent Luau syntax (`const` and the `//` floor division operator). Make sure your environment supports them. If it doesn't, replace `const` with `local` and `a // b` with `math.floor(a / b)`, if you are using an old version of Luau.

## Installation

Copy `OklabColorSequence.lua` into your project as a `ModuleScript` and require it:

```lua
local OklabColorSequence = require(path.to.OklabColorSequence)
```

## Usage

### Two colors

```lua
gradient.Color = OklabColorSequence.new(StartColor, EndColor)
```

### A list of colors

Colors are distributed evenly over `[0, 1]`.

```lua
gradient.Color = OklabColorSequence.new({
	StartColor,
	EndColor,
}) -- 16 segments by default

gradient.Color = OklabColorSequence.new({ Red, Green, Blue }, 8)
```

### Keypoints

Works exactly like `ColorSequence.new`, so you control where each color sits.

```lua
gradient.Color = OklabColorSequence.new({
	ColorSequenceKeypoint.new(0, StartColor),
	ColorSequenceKeypoint.new(0.3, MidColor),
	ColorSequenceKeypoint.new(1, EndColor),
}, 8)
```

### Converting an existing `ColorSequence`

```lua
gradient.Color = OklabColorSequence.new(gradient.Color)
```

## API

### `OklabColorSequence.new`

```lua
OklabColorSequence.new(color: Color3): ColorSequence
OklabColorSequence.new(color0: Color3, color1: Color3, segments: number?): ColorSequence
OklabColorSequence.new(colors: { Color3 }, segments: number?): ColorSequence
OklabColorSequence.new(keypoints: { ColorSequenceKeypoint }, segments: number?): ColorSequence
OklabColorSequence.new(sequence: ColorSequence, segments: number?): ColorSequence
```

| Parameter  | Type     | Description                                                                 |
| ---------- | -------- | --------------------------------------------------------------------------- |
| `segments` | `number?` | Number of subdivisions between each pair of stops. Defaults to `16`.        |

Returns a `ColorSequence` ready to assign to `UIGradient.Color`, particle emitters, beams, trails and so on.

#### Overload details

| Call                                | `segments` position |
| ----------------------------------- | ------------------- |
| `new(Color3)`                       | not applicable (returns a constant `ColorSequence`) |
| `new(Color3, Color3, segments?)`    | 3rd argument        |
| `new({ ... }, segments?)`           | 2nd argument        |
| `new(ColorSequence, segments?)`     | 2nd argument        |

## How it works

1. Each input color is converted from sRGB to Oklab.
2. For every pair of neighboring stops, `segments - 1` intermediate colors are computed by linear interpolation in Oklab.
3. The intermediate colors are converted back to sRGB and emitted as keypoints.
4. The original stops are emitted unchanged, so their exact colors and times are kept.

Since `ColorSequence` still interpolates linearly in RGB between keypoints, using more segments makes the result closer to a true Oklab gradient.

## Limits and behavior

- **Maximum of 20 keypoints.** This is a Roblox limit. If `segments` is too large for the number of stops, it is reduced automatically so the result fits:

  | Stops | Pairs | Max segments per pair | Resulting keypoints |
  | ----- | ----- | --------------------- | ------------------- |
  | 2     | 1     | 19                    | 20                  |
  | 3     | 2     | 9                     | 19                  |
  | 5     | 4     | 4                     | 17                  |
  | 20    | 19    | 1                     | 20                  |

- **Segments are distributed evenly per pair**, regardless of how long each span is.
- **Keypoint rules** match `ColorSequence`: the first keypoint must be at `0`, the last at `1`, and times must be strictly ascending. Duplicate times (used for hard color stops) are not supported.
- **Out-of-gamut colors** produced during interpolation are clamped per channel. This is rare between valid sRGB colors, but it can slightly shift hue in extreme cases.
- **Invalid input** raises an error through `assert` (wrong types, fewer than two colors, more than 20 keypoints, and so on).

## Examples

### UI gradient

```lua
local gradient = Instance.new("UIGradient")
gradient.Color = OklabColorSequence.new(
	Color3.fromRGB(255, 94, 98),
	Color3.fromRGB(255, 195, 113)
)
gradient.Parent = frame
```

bellow, the difference between the UIGrtadient interpolated with the standard Roblox calculation, and the one interpolated by the Oklab algorithm
<img width="1916" height="897" alt="example" src="https://github.com/user-attachments/assets/8ee2955e-ff13-46eb-aaeb-39deb2d5c966" />


### Rainbow with a custom segment count

```lua
gradient.Color = OklabColorSequence.new({
	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(0, 0, 255),
	Color3.fromRGB(255, 0, 255),
}, 3)
```

### Particle emitter

```lua
emitter.Color = OklabColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 30)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 20, 20)),
}, 6)
```

## Performance

Building a sequence performs a small, fixed amount of math (one conversion per stop plus one per generated keypoint). It is intended to be called at setup time. If you build many gradients, cache the resulting `ColorSequence` instead of recreating it every frame.


## Credits

The Oklab color space was created by [Björn Ottosson](https://bottosson.github.io/posts/oklab/). The conversion matrices used here come from his work.

## License

Released under the [MIT License](LICENSE). You are free to use, modify and distribute this library, including in commercial projects.
