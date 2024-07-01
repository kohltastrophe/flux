--!optimize 2
--!native

local Color = require(script.Parent.Color)

local Oklab = Color.Oklab

local function Interpolate(a, b, t: number): any
	if typeof(a) == "number" then
		return math.lerp(a :: number, b :: number, t)
	elseif typeof(a) == "CFrame" then
		return a:Lerp(b, t)
	elseif typeof(a) == "Color3" then
		return Oklab.toRGB(Oklab.fromRGB(a):Lerp(Oklab.fromRGB(b), t))
	elseif typeof(a) == "ColorSequenceKeypoint" then
		return ColorSequenceKeypoint.new(
			math.lerp(a.Time, b.Time, t),
			Oklab.toRGB(Oklab.fromRGB(a.Value):Lerp(Oklab.fromRGB(b.Value), t))
		)
	elseif typeof(a) == "DateTime" then
		return DateTime.fromUnixTimestampMillis(math.lerp(a.UnixTimestampMillis, b.UnixTimestampMillis, t))
	elseif typeof(a) == "NumberRange" then
		return NumberRange.new(math.lerp(a.Min, b.Min, t), math.lerp(a.Max, b.Max, t))
	elseif typeof(a) == "NumberSequenceKeypoint" then
		return NumberSequenceKeypoint.new(math.lerp(a.Time, b.Time, t), math.lerp(a.Value, b.Value, t))
	elseif typeof(a) == "PhysicalProperties" then
		return PhysicalProperties.new(
			math.lerp(a.Density, b.Density, t),
			math.lerp(a.Friction, b.Friction, t),
			math.lerp(a.Elasticity, b.Elasticity, t),
			math.lerp(a.FrictionWeight, b.FrictionWeight, t),
			math.lerp(a.ElasticityWeight, b.ElasticityWeight, t)
		)
	elseif typeof(a) == "Ray" then
		return Ray.new(a.Origin:Lerp(b.Origin, t), a.Direction:Lerp(b.Direction, t))
	elseif typeof(a) == "Rect" then
		return Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
	elseif typeof(a) == "Region3" then
		return Region3.new(a.CFrame:Lerp(b.CFrame, t).Position, a.Size:Lerp(b.Size, t))
	elseif typeof(a) == "Region3int16" then
		return Region3int16.new(
			Vector3int16.new(
				math.lerp(a.Min.X, b.Min.X, t),
				math.lerp(a.Min.Y, b.Min.Y, t),
				math.lerp(a.Min.Z, b.Min.Z, t)
			),
			Vector3int16.new(
				math.lerp(a.Max.X, b.Max.X, t),
				math.lerp(a.Max.Y, b.Max.Y, t),
				math.lerp(a.Max.Z, b.Max.Z, t)
			)
		)
	elseif typeof(a) == "UDim" then
		return UDim.new(math.lerp(a.Scale, b.Scale, t), math.lerp(a.Offset, b.Offset, t))
	elseif typeof(a) == "UDim2" then
		return UDim2.new(
			math.lerp(a.X.Scale, b.X.Scale, t),
			math.lerp(a.X.Offset, b.X.Offset, t),
			math.lerp(a.Y.Scale, b.Y.Scale, t),
			math.lerp(a.Y.Offset, b.Y.Offset, t)
		)
	elseif typeof(a) == "Vector2" then
		return a:Lerp(b, t)
	elseif typeof(a) == "Vector2int16" then
		return Vector2int16.new(math.lerp(a.X, b.X, t), math.lerp(a.Y, b.Y, t))
	elseif typeof(a) == "Vector3" then
		return a:Lerp(b, t)
	elseif typeof(a) == "Vector3int16" then
		return Vector3int16.new(math.lerp(a.X, b.X, t), math.lerp(a.Y, b.Y, t), math.lerp(a.Z, b.Z, t))
	else -- fallback
		return if t < 0.5 then a else b
	end
end

return Interpolate
