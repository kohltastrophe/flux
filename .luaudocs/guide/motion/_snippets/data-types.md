## Supported Data Types

Flux interpolates almost all standard Roblox UI and 3D data types directly, so you never need to split out X, Y, and Z components or calculate alphas manually.

Supported types include:

- [`number`](https://create.roblox.com/docs/en-us/luau/numbers) & native Luau `vector`{luau}
- [`UDim`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim) & [`UDim2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim2)
- [`Vector2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2) & [`Vector3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3)
- [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3), [`ColorSequence`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequence) & [`ColorSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequenceKeypoint)
- [`NumberRange`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberRange), [`NumberSequence`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberSequence) & [`NumberSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberSequenceKeypoint)
- [`CFrame`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/CFrame) & [`Rect`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Rect)

> [!NOTE]
> Passing an unsupported type, such as a `boolean`{luau}, `string`{luau}, or `EnumItem`{luau}, raises an error. The one exception is `nil`{luau}: a motion that starts at `nil`{luau} warns and then simply follows its target without animating.

### 🎨 Oklab Color Interpolation {#oklab-color-interpolation}

When animating a [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3), [`ColorSequence`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequence), or [`ColorSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequenceKeypoint), Flux converts colors into the **Oklab perceptual color space** instead of interpolating linear RGB, avoiding muddy or grayish midpoints.

The same perceptual space is available as a standalone toolkit (lighten, saturate, blend, and check contrast) on the [Color](/guide/motion/color) page.
