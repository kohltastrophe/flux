--!strict
--!native
--!optimize 2

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

local CFrame_new = CFrame.new
local CFrame_fromAxisAngle = CFrame.fromAxisAngle
local Vector3_new = Vector3.new
local ColorSequenceKeypoint_new = ColorSequenceKeypoint.new
local DateTime_fromUnixTimestampMillis = DateTime.fromUnixTimestampMillis
local NumberRange_new = NumberRange.new
local NumberSequenceKeypoint_new = NumberSequenceKeypoint.new
local PhysicalProperties_new = PhysicalProperties.new
local Ray_new = Ray.new
local Rect_new = Rect.new
local Region3_new = Region3.new
local Region3int16_new = Region3int16.new
local UDim_new = UDim.new
local UDim2_new = UDim2.new
local Vector2_new = Vector2.new
local Vector2int16_new = Vector2int16.new
local Vector3int16_new = Vector3int16.new

local DataType = {}

--- Unpacks an array of numbers into a given animatable data type
function DataType.unpack(arr: { number }, t: string): any
	if t == "number" then
		return arr[1]
	elseif t == "CFrame" then
		return CFrame_new(arr[1], arr[2], arr[3])
			* CFrame_fromAxisAngle(Vector3_new(arr[4], arr[5], arr[6]).Unit, arr[7])
	elseif t == "Color3" then
		return Oklab.toRGB(Vector3_new(arr[1], arr[2], arr[3]), false)
	elseif t == "ColorSequenceKeypoint" then
		return ColorSequenceKeypoint_new(arr[4], Oklab_toRGB(Vector3_new(arr[1], arr[2], arr[3]), false))
	elseif t == "DateTime" then
		return DateTime_fromUnixTimestampMillis(arr[1])
	elseif t == "NumberRange" then
		return NumberRange_new(arr[1], arr[2])
	elseif t == "NumberSequenceKeypoint" then
		return NumberSequenceKeypoint_new(arr[2], arr[1], arr[3])
	elseif t == "PhysicalProperties" then
		return PhysicalProperties_new(arr[1], arr[2], arr[3], arr[4], arr[5])
	elseif t == "Ray" then
		return Ray_new(Vector3_new(arr[1], arr[2], arr[3]), Vector3_new(arr[4], arr[5], arr[6]))
	elseif t == "Rect" then
		return Rect_new(arr[1], arr[2], arr[3], arr[4])
	elseif t == "Region3" then
		-- FUTURE: support rotated Region3s if/when they become constructable
		local position = Vector3_new(arr[1], arr[2], arr[3])
		local halfSize = Vector3_new(arr[4] / 2, arr[5] / 2, arr[6] / 2)
		return Region3_new(position - halfSize, position + halfSize)
	elseif t == "Region3int16" then
		return Region3int16_new(
			Vector3int16_new(round(arr[1]), round(arr[2]), round(arr[3])),
			Vector3int16_new(round(arr[4]), round(arr[5]), round(arr[6]))
		)
	elseif t == "UDim" then
		return UDim_new(arr[1], round(arr[2]))
	elseif t == "UDim2" then
		return UDim2_new(arr[1], round(arr[2]), arr[3], round(arr[4]))
	elseif t == "Vector2" then
		return Vector2_new(arr[1], arr[2])
	elseif t == "Vector2int16" then
		return Vector2int16_new(round(arr[1]), round(arr[2]))
	elseif t == "Vector3" then
		return Vector3_new(arr[1], arr[2], arr[3])
	elseif t == "Vector3int16" then
		return Vector3int16_new(round(arr[1]), round(arr[2]), round(arr[3]))
	else
		return nil
	end
end

local clear = table.clear

--- Packs an animatable type into an array of numbers
function DataType.pack(arr: { number }, value: Animatable, t: string)
	clear(arr)

	if t == "number" then
		arr[1] = value
	elseif t == "CFrame" then
		-- FUTURE: is there a better way of doing this? doing distance
		-- calculations on `angle` may be incorrect
		local axis, angle = (value):ToAxisAngle()
		arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7] =
			value.X, value.Y, value.Z, axis.X, axis.Y, axis.Z, angle
	elseif t == "Color3" then
		local lab = Oklab_fromRGB(value)
		arr[1], arr[2], arr[3] = lab.X, lab.Y, lab.Z
	elseif t == "ColorSequenceKeypoint" then
		local lab = Oklab_fromRGB(value.Value)
		arr[1], arr[2], arr[3], arr[4] = lab.X, lab.Y, lab.Z, value.Time
	elseif t == "DateTime" then
		arr[1] = value.UnixTimestampMillis
	elseif t == "NumberRange" then
		arr[1], arr[2] = value.Min, value.Max
	elseif t == "NumberSequenceKeypoint" then
		arr[1], arr[2], arr[3] = value.Value, value.Time, value.Envelope
	elseif t == "PhysicalProperties" then
		arr[1], arr[2], arr[3], arr[4], arr[5] =
			value.Density, value.Friction, value.Elasticity, value.FrictionWeight, value.ElasticityWeight
	elseif t == "Ray" then
		arr[1], arr[2], arr[3], arr[4], arr[5], arr[6] =
			value.Origin.X, value.Origin.Y, value.Origin.Z, value.Direction.X, value.Direction.Y, value.Direction.Z
	elseif t == "Rect" then
		arr[1], arr[2], arr[3], arr[4] = value.Min.X, value.Min.Y, value.Max.X, value.Max.Y
	elseif t == "Region3" then
		-- FUTURE: support rotated Region3s if/when they become constructable
		arr[1], arr[2], arr[3], arr[4], arr[5], arr[6] =
			value.CFrame.X, value.CFrame.Y, value.CFrame.Z, value.Size.X, value.Size.Y, value.Size.Z
	elseif t == "Region3int16" then
		arr[1], arr[2], arr[3], arr[4], arr[5], arr[6] =
			value.Min.X, value.Min.Y, value.Min.Z, value.Max.X, value.Max.Y, value.Max.Z
	elseif t == "UDim" then
		arr[1], arr[2] = value.Scale, value.Offset
	elseif t == "UDim2" then
		arr[1], arr[2], arr[3], arr[4] = value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset
	elseif t == "Vector2" then
		arr[1], arr[2] = value.X, value.Y
	elseif t == "Vector2int16" then
		arr[1], arr[2] = value.X, value.Y
	elseif t == "Vector3" then
		arr[1], arr[2], arr[3] = value.X, value.Y, value.Z
	elseif t == "Vector3int16" then
		arr[1], arr[2], arr[3] = value.X, value.Y, value.Z
	end

	return arr
end

return DataType
