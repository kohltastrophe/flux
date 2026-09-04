## Supported Data Types

Flux interpolates almost all standard Roblox UI and 3D data types directly, so you never need to split out X, Y, and Z components or calculate alphas manually.

Supported types include:

- [`number`](https://create.roblox.com/docs/en-us/luau/numbers)
- [`UDim`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim) & [`UDim2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim2)
- [`Vector2`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2), [`Vector3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3), [`Vector2int16`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2int16), [`Vector3int16`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3int16)
- [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3)
- [`CFrame`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/CFrame)
- [`NumberRange`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberRange), [`NumberSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/NumberSequenceKeypoint), [`ColorSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequenceKeypoint)
- [`Rect`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Rect), [`Ray`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Ray), [`PhysicalProperties`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/PhysicalProperties), [`DateTime`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/DateTime)
- [`Region3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Region3), [`Region3int16`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Region3int16)

> [!NOTE]
> Passing an unsupported type, such as a `boolean`{luau}, `string`{luau}, `EnumItem`{luau}, or a whole `ColorSequence`{luau} / `NumberSequence`{luau} (animate their individual keypoints instead), raises an error. The one exception is `nil`{luau}: a motion that starts at `nil`{luau} warns and then simply follows its target without animating.

### 🎨 Oklab Color Interpolation {#oklab-color-interpolation}

When animating a [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3) (or the color of a [`ColorSequenceKeypoint`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/ColorSequenceKeypoint)), Flux bypasses standard linear RGB interpolation, which often produces muddy or grayish intermediate colors. Instead, colors are converted into the **Oklab perceptual color space** for the duration of the animation, producing vibrant, naturally blended transitions that match how the human eye perceives light.

The same perceptual space is available as a standalone toolkit (lighten, saturate, blend, build from temperature, and check contrast) on the [Color](/guide/motion/color) page.
