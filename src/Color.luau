--!optimize 2
--!native

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
function sRGB.fromLinear(c: Color3): Color3
	return Color3.new(fromLinear(c.R), fromLinear(c.G), fromLinear(c.B))
end

--- Converts sRGB space to linear sRGB space
function sRGB.toLinear(c: Color3): Color3
	return Color3.new(toLinear(c.R), toLinear(c.G), toLinear(c.B))
end

local Oklab = {}

--- Converts a Color3 in linear sRGB space to a Vector3 in Oklab space
function Oklab.fromLinear(c: Color3): Vector3
	local l = c.R * 0.4122214708 + c.G * 0.5363325363 + c.B * 0.0514459929
	local m = c.R * 0.2119034982 + c.G * 0.6806995451 + c.B * 0.1073969566
	local s = c.R * 0.0883024619 + c.G * 0.2817188376 + c.B * 0.6299787005

	local l_ = l ^ (1 / 3)
	local m_ = m ^ (1 / 3)
	local s_ = s ^ (1 / 3)

	return Vector3.new(
		l_ * 0.2104542553 + m_ * 0.7936177850 - s_ * 0.0040720468,
		l_ * 1.9779984951 - m_ * 2.4285922050 + s_ * 0.4505937099,
		l_ * 0.0259040371 + m_ * 0.7827717662 - s_ * 0.8086757660
	)
end

--- Converts a Vector3 in Oklab space to a Color3 in linear sRGB space, clamps channels by default
function Oklab.toLinear(c: Vector3, clamped: boolean?): Color3
	local l_ = c.X + 0.3963377774 * c.Y + 0.2158037573 * c.Z
	local m_ = c.X - 0.1055613458 * c.Y - 0.0638541728 * c.Z
	local s_ = c.X - 0.0894841775 * c.Y - 1.2914855480 * c.Z

	local l = l_ ^ 3
	local m = m_ ^ 3
	local s = s_ ^ 3

	local r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	local b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

	if clamped ~= false then
		r = math.clamp(r, 0, 1)
		g = math.clamp(g, 0, 1)
		b = math.clamp(b, 0, 1)
	end

	return Color3.new(r, g, b)
end

--- Converts a Vector3 in HCL space to a Vector3 in Oklab space
function Oklab.fromHCL(hcl: Vector3): Vector3
	local h = hcl.X * 2 * math.pi
	local c = hcl.Y

	local l = hcl.Z
	local a = c * math.cos(h)
	local b = c * math.sin(h)

	return Vector3.new(l, a, b)
end

--- Converts a Vector3 in Oklab space to a Vector3 in HCL space
function Oklab.toHCL(lab: Vector3): Vector3
	local h = math.atan2(lab.Z, lab.Y) / (2 * math.pi)
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

local Color = {
	Oklab = Oklab,
	sRGB = sRGB,
}

return Color
