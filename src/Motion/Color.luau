--!strict

local sRGB = {}

local function fromLinear(channel: number): number
	if channel < 0.0031308 then
		return channel * 12.92
	else
		return channel ^ (1 / 2.4) * 1.055 - 0.055
	end
end

local function toLinear(channel: number): number
	if channel < 0.04045 then
		return channel / 12.92
	else
		return ((channel + 0.055) / 1.055) ^ 2.4
	end
end

--- Converts linear sRGB space to sRGB space
function sRGB.fromLinear(color: Color3): Color3
	return Color3.new(fromLinear(color.R), fromLinear(color.G), fromLinear(color.B))
end

--- Converts sRGB space to linear sRGB space
function sRGB.toLinear(color: Color3): Color3
	return Color3.new(toLinear(color.R), toLinear(color.G), toLinear(color.B))
end

local Oklab = {}

--- Converts a Color3 in linear sRGB space to a Vector3 in Oklab space
function Oklab.fromLinear(color: Color3): Vector3
	local R, G, B = color.R, color.G, color.B
	local l = R * 0.4122214708 + G * 0.5363325363 + B * 0.0514459929
	local m = R * 0.2119034982 + G * 0.6806995451 + B * 0.1073969566
	local s = R * 0.0883024619 + G * 0.2817188376 + B * 0.6299787005

	local l_ = l ^ (1 / 3)
	local m_ = m ^ (1 / 3)
	local s_ = s ^ (1 / 3)

	return Vector3.new(
		l_ * 0.2104542553 + m_ * 0.7936177850 - s_ * 0.0040720468,
		l_ * 1.9779984951 - m_ * 2.4285922050 + s_ * 0.4505937099,
		l_ * 0.0259040371 + m_ * 0.7827717662 - s_ * 0.8086757660
	)
end

--- Oklab (L, a, b) -> linear sRGB (r, g, b) as three plain numbers, no allocation.
local function oklabToLinearRGB(L: number, A: number, B: number): (number, number, number)
	local l_ = L + 0.3963377774 * A + 0.2158037573 * B
	local m_ = L - 0.1055613458 * A - 0.0638541728 * B
	local s_ = L - 0.0894841775 * A - 1.2914855480 * B

	local l = l_ * l_ * l_
	local m = m_ * m_ * m_
	local s = s_ * s_ * s_

	return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
end

--- Converts a Vector3 in Oklab space to a Color3 in linear sRGB space.
function Oklab.toLinear(color: Vector3, clamped: boolean?): Color3
	local L, A, B = color.X, color.Y, color.Z
	local r, g, b = oklabToLinearRGB(L, A, B)

	if clamped ~= false and (r < 0 or g < 0 or b < 0 or r > 1 or g > 1 or b > 1) then
		local L0 = math.clamp(L, 0, 1)
		local lo, hi = 0, 1
		for _ = 1, 12 do
			local mid = (lo + hi) / 2
			local mr, mg, mb = oklabToLinearRGB(L0, A * mid, B * mid)
			if mr >= 0 and mg >= 0 and mb >= 0 and mr <= 1 and mg <= 1 and mb <= 1 then
				lo = mid
			else
				hi = mid
			end
		end
		r, g, b = oklabToLinearRGB(L0, A * lo, B * lo)
	end

	return Color3.new(r, g, b)
end

--- Converts a Vector3 in HCL space (hue in degrees) to a Vector3 in Oklab space
function Oklab.fromHCL(hcl: Vector3): Vector3
	local h = math.rad(hcl.X)
	local c = hcl.Y

	local l = hcl.Z
	local a = c * math.cos(h)
	local b = c * math.sin(h)

	return Vector3.new(l, a, b)
end

--- Converts a Vector3 in Oklab space to a Vector3 in HCL space (hue in degrees, [0, 360))
function Oklab.toHCL(lab: Vector3): Vector3
	local h = math.deg(math.atan2(lab.Z, lab.Y))
	if h < 0 then
		h += 360
	end
	local c = math.sqrt(lab.Y ^ 2 + lab.Z ^ 2)
	local l = lab.X

	return Vector3.new(h, c, l)
end

--- Converts a Color3 in sRGB space to a Vector3 in Oklab space
function Oklab.fromRGB(rgb: Color3): Vector3
	return Oklab.fromLinear(sRGB.toLinear(rgb))
end

--- Converts a Vector3 in Oklab space to a Color3 in sRGB space
function Oklab.toRGB(lab: Vector3, clamped: boolean?): Color3
	return sRGB.fromLinear(Oklab.toLinear(lab, clamped))
end

--- Raises Oklab lightness by `amount`
function Oklab.lighten(lab: Vector3, amount: number): Vector3
	return Vector3.new(math.clamp(lab.X + amount, 0, 1), lab.Y, lab.Z)
end

--- Lowers Oklab lightness by `amount`
function Oklab.darken(lab: Vector3, amount: number): Vector3
	return Oklab.lighten(lab, -amount)
end

--- Raises chroma by `amount`, preserving hue and lightness
function Oklab.saturate(lab: Vector3, amount: number): Vector3
	local a, b = lab.Y, lab.Z
	local c = math.sqrt(a * a + b * b)
	if c < 1e-6 then
		-- Achromatic (or float noise): no stable hue direction to grow along
		return lab
	end
	local scale = math.max(c + amount, 0) / c
	return Vector3.new(lab.X, a * scale, b * scale)
end

--- Lowers chroma by `amount`, preserving hue and lightness
function Oklab.desaturate(lab: Vector3, amount: number): Vector3
	return Oklab.saturate(lab, -amount)
end

--- Rotates hue by `degrees`, preserving chroma and lightness.
function Oklab.rotateHue(lab: Vector3, degrees: number): Vector3
	local r = math.rad(degrees)
	local cos, sin = math.cos(r), math.sin(r)
	local a, b = lab.Y, lab.Z
	return Vector3.new(lab.X, a * cos - b * sin, a * sin + b * cos)
end

--- Removes all chroma, preserving Oklab lightness.
function Oklab.grayscale(lab: Vector3): Vector3
	return Vector3.new(lab.X, 0, 0)
end

--- Returns an Oklab Vector3 linearly interpolated between lab1 and lab2 by the given alpha. Equivalent to `lab1:Lerp(lab2, alpha)`.
function Oklab.mix(lab1: Vector3, lab2: Vector3, alpha: number): Vector3
	return lab1:Lerp(lab2, alpha)
end

-- Tanner Helland's blackbody approximation (sRGB channels, 0–1), max channel normalised to 1.
-- Range clamped to [1000, 40000] K.
local function tannerHelland(kelvin: number): (number, number, number)
	local temp = math.clamp(kelvin, 1000, 40000) / 100
	local r, g, b

	if temp <= 66 then
		r = 255
	else
		r = math.clamp(329.698727446 * (temp - 60) ^ -0.1332047592, 0, 255)
	end

	if temp <= 66 then
		g = math.clamp(99.4708025861 * math.log(temp) - 161.1195681661, 0, 255)
	else
		g = math.clamp(288.1221695283 * (temp - 60) ^ -0.0755148492, 0, 255)
	end

	if temp >= 66 then
		b = 255
	elseif temp <= 19 then
		b = 0
	else
		b = math.clamp(138.5177312231 * math.log(temp - 10) - 305.0447927307, 0, 255)
	end

	return r / 255, g / 255, b / 255
end

--- Oklab colour of a blackbody at `kelvin`. (1000–40000 K)
function Oklab.fromTemperature(kelvin: number): Vector3
	local r, g, b = tannerHelland(kelvin)
	return Oklab.fromLinear(sRGB.toLinear(Color3.new(r, g, b)))
end

local Color = {
	Oklab = table.freeze(Oklab),
	sRGB = table.freeze(sRGB),
}

local fromRGB = Oklab.fromRGB
local toRGB = Oklab.toRGB

--[[
Raises the perceptual lightness of a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3)
by `amount`, working in Oklab so the shift looks uniform across hues. Pass a negative `amount` (or use
`Color.darken`) to go darker.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#manipulation)
]]
function Color.lighten(c: Color3, amount: number): Color3
	return toRGB(Oklab.lighten(fromRGB(c), amount))
end

--[[
Lowers the perceptual lightness of a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3)
by `amount`, working in Oklab so the shift looks uniform across hues. The inverse of `Color.lighten`.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#manipulation)
]]
function Color.darken(c: Color3, amount: number): Color3
	return toRGB(Oklab.darken(fromRGB(c), amount))
end

--[[
Raises the chroma of a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3) by `amount`
(making it more vivid) while preserving its perceptual hue and lightness in Oklab. Achromatic colours have
no hue to grow along and pass through unchanged.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#manipulation)
]]
function Color.saturate(c: Color3, amount: number): Color3
	return toRGB(Oklab.saturate(fromRGB(c), amount))
end

--[[
Lowers the chroma of a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3) by `amount`
(washing it out) while preserving its perceptual hue and lightness in Oklab. The inverse of `Color.saturate`.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#manipulation)
]]
function Color.desaturate(c: Color3, amount: number): Color3
	return toRGB(Oklab.desaturate(fromRGB(c), amount))
end

--[[
Rotates the hue of a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3) by `degrees`
around the Oklab colour wheel, preserving chroma and lightness. `degrees` is in <strong>degrees</strong>
(not turns); `360` is a full revolution and negative values rotate the other way.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#manipulation)
]]
function Color.rotateHue(c: Color3, degrees: number): Color3
	return toRGB(Oklab.rotateHue(fromRGB(c), degrees))
end

--[[
Strips all chroma from a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3),
returning the neutral grey of the same perceptual lightness in Oklab. A truer grey than averaging RGB channels.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#manipulation)
]]
function Color.grayscale(c: Color3): Color3
	return toRGB(Oklab.grayscale(fromRGB(c)))
end

--[[
Perceptually blends two [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3)s in
Oklab, where `t` is the fraction from `a` (`0`) to `b` (`1`). Mixing through Oklab avoids the muddy midpoints
of a raw RGB lerp. `t` is unclamped: values outside <code>[0, 1]</code> extrapolate, matching how
[`Flux.spring`](https://flux.kohl.gg/guide/motion/spring) and [`Flux.tween`](https://flux.kohl.gg/guide/motion/tween)
animate colour.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#blending)
]]
function Color.mix(a: Color3, b: Color3, t: number): Color3
	return toRGB(Oklab.mix(fromRGB(a), fromRGB(b), t))
end

--[[
Returns the [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3) a blackbody glows at
`kelvin`: warm orange around `2000`, neutral near `6500`, cool blue beyond. `kelvin` is clamped to the
<code>[1000, 40000]</code> K range. Handy for warm/cool lighting tints.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#construction)
]]
function Color.fromTemperature(kelvin: number): Color3
	local r, g, b = tannerHelland(kelvin)
	return Color3.new(r, g, b)
end

--[[
The WCAG relative luminance of a [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3),
from `0` (black) to `1` (white). This is the perceived brightness used to compute `Color.contrast`, weighting
green most and blue least.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#accessibility)
]]
function Color.luminance(c: Color3): number
	local lin = sRGB.toLinear(c)
	return 0.2126 * lin.R + 0.7152 * lin.G + 0.0722 * lin.B
end

--[[
The WCAG contrast ratio between two [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3)s,
from `1` (identical) to `21` (black on white). The result is order-independent. WCAG asks for at least
<code>4.5</code> for body text and <code>3</code> for large text.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#accessibility)
]]
function Color.contrast(a: Color3, b: Color3): number
	local la = Color.luminance(a)
	local lb = Color.luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

--[[
Picks whichever foreground [`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3) reads
more legibly on `bg`: the one with the higher WCAG contrast ratio. `dark` and `light` default to black
and white; pass your own brand tints to keep on-brand text readable over any background.

[Open Documentation](https://flux.kohl.gg/guide/motion/color#accessibility)
]]
function Color.readable(bg: Color3, dark: Color3?, light: Color3?): Color3
	local d = dark or Color3.new(0, 0, 0)
	local l = light or Color3.new(1, 1, 1)
	if Color.contrast(bg, d) >= Color.contrast(bg, l) then
		return d
	end
	return l
end

return table.freeze(Color)
