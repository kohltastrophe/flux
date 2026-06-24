--!strict

local Color = require("./Color")

local Oklab = Color.Oklab

export type Animatable =
	number
	& CFrame
	& Color3
	& ColorSequenceKeypoint
	& DateTime
	& NumberRange
	& NumberSequenceKeypoint
	& PhysicalProperties
	& Ray
	& Rect
	& Region3
	& Region3int16
	& UDim
	& UDim2
	& Vector2
	& Vector2int16
	& Vector3
	& Vector3int16

local round = math.round

local Oklab_toRGB = Oklab.toRGB
local Oklab_fromRGB = Oklab.fromRGB

local IS_ROBLOX = game ~= nil
local CFrame_new = if IS_ROBLOX then CFrame.new else nil :: any
local CFrame_fromAxisAngle = if IS_ROBLOX then CFrame.fromAxisAngle else nil :: any
local ColorSequenceKeypoint_new = if IS_ROBLOX then ColorSequenceKeypoint.new else nil :: any
local DateTime_fromUnixTimestampMillis = if IS_ROBLOX then DateTime.fromUnixTimestampMillis else nil :: any
local NumberRange_new = if IS_ROBLOX then NumberRange.new else nil :: any
local NumberSequenceKeypoint_new = if IS_ROBLOX then NumberSequenceKeypoint.new else nil :: any
local PhysicalProperties_new = if IS_ROBLOX then PhysicalProperties.new else nil :: any
local Ray_new = if IS_ROBLOX then Ray.new else nil :: any
local Rect_new = if IS_ROBLOX then Rect.new else nil :: any
local Region3_new = if IS_ROBLOX then Region3.new else nil :: any
local Region3int16_new = if IS_ROBLOX then Region3int16.new else nil :: any
local UDim_new = if IS_ROBLOX then UDim.new else nil :: any
local UDim2_new = if IS_ROBLOX then UDim2.new else nil :: any
local Vector2_new = if IS_ROBLOX then Vector2.new else nil :: any
local Vector3_new = if IS_ROBLOX then Vector3.new else nil :: any
local Vector2int16_new = if IS_ROBLOX then Vector2int16.new else nil :: any
local Vector3int16_new = if IS_ROBLOX then Vector3int16.new else nil :: any

local DataType = {}

local unpackers: { [string]: ({ number }) -> any } = {
	-- stylua: ignore start
	number = function(v) return v[1] end,
	CFrame = function(v) local p, a = CFrame_new(v[1], v[2], v[3]), Vector3_new(v[4], v[5], v[6]); if a.Magnitude < 1e-6 then return p end; return p * CFrame_fromAxisAngle(a, v[7]) end,
	Color3 = function(v) return Oklab_toRGB(Vector3_new(v[1], v[2], v[3]), false) end,
	ColorSequenceKeypoint = function(v) return ColorSequenceKeypoint_new(v[4], Oklab_toRGB(Vector3_new(v[1], v[2], v[3]), false)) end,
	DateTime = function(v) return DateTime_fromUnixTimestampMillis(v[1]) end,
	NumberRange = function(v) return NumberRange_new(v[1], v[2]) end,
	NumberSequenceKeypoint = function(v) return NumberSequenceKeypoint_new(v[2], v[1], v[3]) end,
	PhysicalProperties = function(v) return PhysicalProperties_new(v[1], v[2], v[3], v[4], v[5]) end,
	Ray = function(v) return Ray_new(Vector3_new(v[1], v[2], v[3]), Vector3_new(v[4], v[5], v[6])) end,
	Rect = function(v) return Rect_new(v[1], v[2], v[3], v[4]) end,
	-- FUTURE: support rotated Region3s if/when they become constructable
	Region3 = function(v) local position, halfSize = Vector3_new(v[1], v[2], v[3]), Vector3_new(v[4] / 2, v[5] / 2, v[6] / 2); return Region3_new(position - halfSize, position + halfSize) end,
	Region3int16 = function(v) return Region3int16_new(Vector3int16_new(round(v[1]), round(v[2]), round(v[3])), Vector3int16_new(round(v[4]), round(v[5]), round(v[6]))) end,
	UDim = function(v) return UDim_new(v[1], round(v[2])) end,
	UDim2 = function(v) return UDim2_new(v[1], round(v[2]), v[3], round(v[4])) end,
	Vector2 = function(v) return Vector2_new(v[1], v[2]) end,
	Vector2int16 = function(v) return Vector2int16_new(round(v[1]), round(v[2])) end,
	Vector3 = function(v) return Vector3_new(v[1], v[2], v[3]) end,
	Vector3int16 = function(v) return Vector3int16_new(round(v[1]), round(v[2]), round(v[3])) end,
	-- stylua: ignore end
}

local packers: { [string]: ({ number }, any) -> () } = {
	-- stylua: ignore start
	number = function(v, value) v[1] = value end,
	CFrame = function(v, value) local axis, angle = (value :: CFrame):ToAxisAngle(); v[1], v[2], v[3], v[4], v[5], v[6], v[7] = value.X, value.Y, value.Z, axis.X, axis.Y, axis.Z, angle end,
	Color3 = function(v, value) local lab = Oklab_fromRGB(value); v[1], v[2], v[3] = lab.X, lab.Y, lab.Z end,
	ColorSequenceKeypoint = function(v, value) local lab = Oklab_fromRGB(value.Value); v[1], v[2], v[3], v[4] = lab.X, lab.Y, lab.Z, value.Time end,
	DateTime = function(v, value) v[1] = value.UnixTimestampMillis end,
	NumberRange = function(v, value) v[1], v[2] = value.Min, value.Max end,
	NumberSequenceKeypoint = function(v, value) v[1], v[2], v[3] = value.Value, value.Time, value.Envelope end,
	PhysicalProperties = function(v, value) v[1], v[2], v[3], v[4], v[5] = value.Density, value.Friction, value.Elasticity, value.FrictionWeight, value.ElasticityWeight end,
	Ray = function(v, value) v[1], v[2], v[3], v[4], v[5], v[6] = value.Origin.X, value.Origin.Y, value.Origin.Z, value.Direction.X, value.Direction.Y, value.Direction.Z end,
	Rect = function(v, value) v[1], v[2], v[3], v[4] = value.Min.X, value.Min.Y, value.Max.X, value.Max.Y end,
	-- FUTURE: support rotated Region3s if/when they become constructable
	Region3 = function(v, value) v[1], v[2], v[3], v[4], v[5], v[6] = value.CFrame.X, value.CFrame.Y, value.CFrame.Z, value.Size.X, value.Size.Y, value.Size.Z end,
	Region3int16 = function(v, value) v[1], v[2], v[3], v[4], v[5], v[6] = value.Min.X, value.Min.Y, value.Min.Z, value.Max.X, value.Max.Y, value.Max.Z end,
	UDim = function(v, value) v[1], v[2] = value.Scale, value.Offset end,
	UDim2 = function(v, value) v[1], v[2], v[3], v[4] = value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset end,
	Vector2 = function(v, value) v[1], v[2] = value.X, value.Y end,
	Vector2int16 = function(v, value) v[1], v[2] = value.X, value.Y end,
	Vector3 = function(v, value) v[1], v[2], v[3] = value.X, value.Y, value.Z end,
	Vector3int16 = function(v, value) v[1], v[2], v[3] = value.X, value.Y, value.Z end,
	-- stylua: ignore end
}

--- Unpacks an array of numbers into a given animatable data type
function DataType.unpack(arr: { number }, t: string): any
	local unpack = unpackers[t]
	return if unpack ~= nil then unpack(arr) else nil
end

--- Returns the unpacker for an animatable type
function DataType.unpacker(t: string): (({ number }) -> any)?
	return unpackers[t]
end

local clear = table.clear

--- Packs an animatable type into an array of numbers; an unanimatable type leaves (and returns) the array empty
function DataType.pack(arr: { number }, value: Animatable, t: string)
	clear(arr)

	local pack = packers[t]
	if pack ~= nil then
		pack(arr, value)
	end

	return arr
end

return table.freeze(DataType)
