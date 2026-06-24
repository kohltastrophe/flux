---
title: Color
description: A perceptual color toolkit built on the same Oklab space that powers Flux animations.
outline: deep
---

# Color

Flux animates colors through the **Oklab perceptual color space** so transitions stay vibrant instead of dipping through muddy grays. That same machinery is exposed as a standalone toolkit under `Flux.Color`{lua}, so you can manipulate, build, and analyze colors with the same perceptual quality outside of an animation.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local Color = Flux.Color
```

Every verb takes and returns a standard [`Color3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Color3), and results are always mapped back into the displayable sRGB gamut (see [Gamut handling](#gamut-handling)). These are plain functions (pass a [`Signal`](/guide/concepts/signals)'s current color in, get a color out), so they compose naturally inside a [`Computed`](/guide/concepts/computeds).

## Manipulation

These verbs adjust one perceptual attribute at a time, leaving the others untouched.

| Function                            | Effect                                    |
| ----------------------------------- | ----------------------------------------- |
| `Color.lighten(c, amount)`{luau}    | Raises perceptual lightness               |
| `Color.darken(c, amount)`{luau}     | Lowers perceptual lightness               |
| `Color.saturate(c, amount)`{luau}   | Raises chroma, preserving hue & lightness |
| `Color.desaturate(c, amount)`{luau} | Lowers chroma, preserving hue & lightness |
| `Color.rotateHue(c, degrees)`{luau} | Rotates hue around the wheel              |
| `Color.grayscale(c)`{luau}          | Removes all chroma, preserving lightness  |

`amount` is an **additive** step in Oklab units. Because Oklab is perceptually uniform, the same `amount` produces the same perceived change regardless of the starting color: `lighten(c, 0.1)`{luau} is the same nudge whether `c` is dark or light. `darken` is exactly `lighten` with a negative amount, and `desaturate` is `saturate` negated.

```luau
local brand = Color3.fromRGB(82, 120, 255)

local hovered = Color.lighten(brand, 0.08)
local pressed = Color.darken(brand, 0.08)
local muted = Color.desaturate(brand, 0.05)
local accent = Color.rotateHue(brand, 180) -- complementary hue
```

`rotateHue` takes **degrees** (`180` is the complementary hue, `360` a full turn) and wraps automatically. `grayscale` collapses chroma to zero while keeping the color's perceptual lightness, so the gray reads at the same brightness as the original, unlike a luminance-based desaturation.

## Blending

`Color.mix(a, b, t)`{luau} interpolates between two colors in Oklab. `t = 0`{luau} returns `a`, `t = 1`{luau} returns `b`, and the path is identical to the one a [spring](/guide/motion/spring) or [tween](/guide/motion/tween) travels, so a static blend and an animated transition always agree.

```luau
local midpoint = Color.mix(Color3.new(1, 0, 0), Color3.new(0, 0, 1), 0.5)
```

`t` is **not** clamped, so values outside `[0, 1]` extrapolate beyond the endpoints (the result is still gamut-mapped to a valid color).

## Construction

`Color.fromTemperature(kelvin)`{luau} returns the color of a blackbody at a given color temperature, clamped to `[1000, 40000]`{luau} K: low values are warm/orange, high values are cool/blue.

```luau
local candlelight = Color.fromTemperature(1900)
local daylight = Color.fromTemperature(6500)
local overcast = Color.fromTemperature(12000)
```

## Accessibility

Built on the WCAG definition of relative luminance:

| Function                                  | Returns                                                  |
| ----------------------------------------- | -------------------------------------------------------- |
| `Color.luminance(c)`{luau}                | Relative luminance, `0` (black) to `1` (white)           |
| `Color.contrast(a, b)`{luau}              | Contrast ratio, `1` (identical) to `21` (black vs white) |
| `Color.readable(bg, dark?, light?)`{luau} | Whichever candidate is more legible on `bg`              |

`readable` defaults to black/white text but accepts custom candidates, returning whichever has the higher contrast against the background:

```luau
local label = new "TextLabel" {
    BackgroundColor3 = brand,
    TextColor3 = Color.readable(brand), -- black or white, whichever reads better
}
```

## Working in Oklab directly

Each manipulation, blend, and construction verb has a mirror under `Color.Oklab`{luau} that takes and returns a raw Oklab [`Vector3`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3) (`X` = lightness, `Y`/`Z` = the a/b chroma axes) instead of a `Color3`. Use these to chain several transforms without paying the `Color3`↔Oklab conversion at every step:

```luau
-- One conversion in, one out, not six round-trips
local lab = Color.Oklab.fromRGB(brand)
lab = Color.Oklab.lighten(lab, 0.1)
lab = Color.Oklab.saturate(lab, 0.05)
lab = Color.Oklab.rotateHue(lab, 20)
local result = Color.Oklab.toRGB(lab)
```

The Oklab variants return **raw** (un-gamut-mapped) Oklab; clipping happens when you convert back with `toRGB`. The accessibility functions (`luminance`/`contrast`/`readable`) have no Oklab variant; they are defined in the sRGB domain.

## Color spaces

The lower-level conversions are available for direct use:

| Function                                                                        | Converts                                                                    |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `Color.Oklab.fromRGB(c)`{luau} / `Color.Oklab.toRGB(lab, clamped?)`{luau}       | sRGB `Color3` ↔ Oklab `Vector3`                                             |
| `Color.Oklab.fromLinear(c)`{luau} / `Color.Oklab.toLinear(lab, clamped?)`{luau} | Linear sRGB `Color3` ↔ Oklab `Vector3`                                      |
| `Color.Oklab.fromHCL(hcl)`{luau} / `Color.Oklab.toHCL(lab)`{luau}               | HCL `Vector3` (`X` = hue°, `Y` = chroma, `Z` = lightness) ↔ Oklab `Vector3` |
| `Color.sRGB.fromLinear(c)`{luau} / `Color.sRGB.toLinear(c)`{luau}               | sRGB `Color3` ↔ linear sRGB `Color3`                                        |

### Gamut handling

When a manipulated color falls outside the sRGB gamut (common when you `saturate` or `lighten` toward the edge of what a screen can show), `toRGB`/`toLinear` map it back to the gamut boundary while **preserving its hue and lightness** ([Björn Ottosson's gamut clipping](https://bottosson.github.io/posts/gamutclipping/)), rather than clamping each channel independently and twisting the hue. This is the default; pass `clamped = false`{luau} to get the raw, unclipped conversion.
