## Supported Data Types

Flux interpolates almost all standard Roblox UI and 3D data types directly, so you don't need to split out `X`, `Y`, and `Z` components or calculate alphas by hand.

Supported types include:

- [`number`](https://create.roblox.com/docs/luau/numbers) & native Luau `vector`
- [`UDim`](https://create.roblox.com/docs/reference/engine/datatypes/UDim) & [`UDim2`](https://create.roblox.com/docs/reference/engine/datatypes/UDim2) (`Offset` components round to whole pixels on each step)
- [`Vector2`](https://create.roblox.com/docs/reference/engine/datatypes/Vector2) & [`Vector3`](https://create.roblox.com/docs/reference/engine/datatypes/Vector3)
- [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3), [`ColorSequence`](https://create.roblox.com/docs/reference/engine/datatypes/ColorSequence) & [`ColorSequenceKeypoint`](https://create.roblox.com/docs/reference/engine/datatypes/ColorSequenceKeypoint) (`ColorSequence` snaps to the new target when keypoint counts differ)
- [`NumberRange`](https://create.roblox.com/docs/reference/engine/datatypes/NumberRange), [`NumberSequence`](https://create.roblox.com/docs/reference/engine/datatypes/NumberSequence) & [`NumberSequenceKeypoint`](https://create.roblox.com/docs/reference/engine/datatypes/NumberSequenceKeypoint) (`NumberSequence` snaps when keypoint counts differ)
- [`CFrame`](https://create.roblox.com/docs/reference/engine/datatypes/CFrame) (position plus unit quaternion rotation with shortest-arc alignment) & [`Rect`](https://create.roblox.com/docs/reference/engine/datatypes/Rect)

Passing an unsupported type (such as a `boolean`, `string`, or `EnumItem`) or calling `:set(nil)` raises an error (`motion(nil)` is a read, while a reactive source returning `nil` or a mismatched datatype is ignored). A motion whose initial target is `nil` warns once and follows subsequent targets without animating.

### Oklab Color Interpolation {#oklab-color-interpolation}

When animating a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3), [`ColorSequence`](https://create.roblox.com/docs/reference/engine/datatypes/ColorSequence), or [`ColorSequenceKeypoint`](https://create.roblox.com/docs/reference/engine/datatypes/ColorSequenceKeypoint), Flux converts colors into the **Oklab perceptual color space** instead of interpolating linear RGB, avoiding muddy or grayish midpoints.

The same perceptual space is available as a standalone toolkit (lighten, saturate, blend, and check contrast) on the [Color](/guide/motion/color) page.
