--!optimize 2
--!native
--!strict
--!nolint LocalShadow

local Package = script.Parent
local Type = require(Package.Type)
local Color = require(Package.Color)
local Oklab = Color.Oklab

local DataType = {}

--- Packs an array of numbers into a given animatable data type
function DataType.pack(numbers: { number }, typeString: string): Type.Animatable?
	if typeString == "number" then
		return numbers[1]
	elseif typeString == "CFrame" then
		return CFrame.new(numbers[1], numbers[2], numbers[3])
			* CFrame.fromAxisAngle(Vector3.new(numbers[4], numbers[5], numbers[6]).Unit, numbers[7])
	elseif typeString == "Color3" then
		return Oklab.toRGB(Vector3.new(numbers[1], numbers[2], numbers[3]), false)
	elseif typeString == "ColorSequenceKeypoint" then
		return ColorSequenceKeypoint.new(
			numbers[4],
			Oklab.toRGB(Vector3.new(numbers[1], numbers[2], numbers[3]), false)
		)
	elseif typeString == "DateTime" then
		return DateTime.fromUnixTimestampMillis(numbers[1])
	elseif typeString == "NumberRange" then
		return NumberRange.new(numbers[1], numbers[2])
	elseif typeString == "NumberSequenceKeypoint" then
		return NumberSequenceKeypoint.new(numbers[2], numbers[1], numbers[3])
	elseif typeString == "PhysicalProperties" then
		return PhysicalProperties.new(numbers[1], numbers[2], numbers[3], numbers[4], numbers[5])
	elseif typeString == "Ray" then
		return Ray.new(Vector3.new(numbers[1], numbers[2], numbers[3]), Vector3.new(numbers[4], numbers[5], numbers[6]))
	elseif typeString == "Rect" then
		return Rect.new(numbers[1], numbers[2], numbers[3], numbers[4])
	elseif typeString == "Region3" then
		-- FUTURE: support rotated Region3s if/when they become constructable
		local position = Vector3.new(numbers[1], numbers[2], numbers[3])
		local halfSize = Vector3.new(numbers[4] / 2, numbers[5] / 2, numbers[6] / 2)
		return Region3.new(position - halfSize, position + halfSize)
	elseif typeString == "Region3int16" then
		return Region3int16.new(
			Vector3int16.new(math.round(numbers[1]), math.round(numbers[2]), math.round(numbers[3])),
			Vector3int16.new(math.round(numbers[4]), math.round(numbers[5]), math.round(numbers[6]))
		)
	elseif typeString == "UDim" then
		return UDim.new(numbers[1], math.round(numbers[2]))
	elseif typeString == "UDim2" then
		return UDim2.new(numbers[1], math.round(numbers[2]), numbers[3], math.round(numbers[4]))
	elseif typeString == "Vector2" then
		return Vector2.new(numbers[1], numbers[2])
	elseif typeString == "Vector2int16" then
		return Vector2int16.new(math.round(numbers[1]), math.round(numbers[2]))
	elseif typeString == "Vector3" then
		return Vector3.new(numbers[1], numbers[2], numbers[3])
	elseif typeString == "Vector3int16" then
		return Vector3int16.new(math.round(numbers[1]), math.round(numbers[2]), math.round(numbers[3]))
	else
		return nil
	end
end

--- Unpacks an animatable type into an array of numbers
function DataType.unpack(value: unknown, typeString: string): { number }
	if typeString == "number" then
		local value = value :: number
		return { value }
	elseif typeString == "CFrame" then
		local value = value :: CFrame
		-- FUTURE: is there a better way of doing this? doing distance
		-- calculations on `angle` may be incorrect
		local axis, angle = value:ToAxisAngle()
		return { value.X, value.Y, value.Z, axis.X, axis.Y, axis.Z, angle }
	elseif typeString == "Color3" then
		local value = value :: Color3
		local lab = Oklab.fromRGB(value)
		return { lab.X, lab.Y, lab.Z }
	elseif typeString == "ColorSequenceKeypoint" then
		local value = value :: ColorSequenceKeypoint
		local lab = Oklab.fromRGB(value.Value)
		return { lab.X, lab.Y, lab.Z, value.Time }
	elseif typeString == "DateTime" then
		local value = value :: DateTime
		return { value.UnixTimestampMillis }
	elseif typeString == "NumberRange" then
		local value = value :: NumberRange
		return { value.Min, value.Max }
	elseif typeString == "NumberSequenceKeypoint" then
		local value = value :: NumberSequenceKeypoint
		return { value.Value, value.Time, value.Envelope }
	elseif typeString == "PhysicalProperties" then
		local value = value :: PhysicalProperties
		return { value.Density, value.Friction, value.Elasticity, value.FrictionWeight, value.ElasticityWeight }
	elseif typeString == "Ray" then
		local value = value :: Ray
		return {
			value.Origin.X,
			value.Origin.Y,
			value.Origin.Z,
			value.Direction.X,
			value.Direction.Y,
			value.Direction.Z,
		}
	elseif typeString == "Rect" then
		local value = value :: Rect
		return { value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }
	elseif typeString == "Region3" then
		local value = value :: Region3
		-- FUTURE: support rotated Region3s if/when they become constructable
		return {
			value.CFrame.X,
			value.CFrame.Y,
			value.CFrame.Z,
			value.Size.X,
			value.Size.Y,
			value.Size.Z,
		}
	elseif typeString == "Region3int16" then
		local value = value :: Region3int16
		return { value.Min.X, value.Min.Y, value.Min.Z, value.Max.X, value.Max.Y, value.Max.Z }
	elseif typeString == "UDim" then
		local value = value :: UDim
		return { value.Scale, value.Offset }
	elseif typeString == "UDim2" then
		local value = value :: UDim2
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif typeString == "Vector2" then
		local value = value :: Vector2
		return { value.X, value.Y }
	elseif typeString == "Vector2int16" then
		local value = value :: Vector2int16
		return { value.X, value.Y }
	elseif typeString == "Vector3" then
		local value = value :: Vector3
		return { value.X, value.Y, value.Z }
	elseif typeString == "Vector3int16" then
		local value = value :: Vector3int16
		return { value.X, value.Y, value.Z }
	else
		return {}
	end
end

return DataType
