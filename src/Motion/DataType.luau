--!strict

local Color = require("./Color")

local Oklab = Color.Oklab

export type Animatable =
	number
	& vector
	& CFrame
	& Color3
	& ColorSequence
	& ColorSequenceKeypoint
	& DateTime
	& NumberRange
	& NumberSequence
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

local IS_ROBLOX = game ~= nil

local packers: { [string]: ({ number }, any) -> () } = {
	number = function(v, value: number)
		v[1] = value
	end,
	vector = function(v, value: vector)
		v[1], v[2], v[3] = value.x, value.y, value.z
	end,
}

local unpackers: { [string]: ({ number }) -> any } = {
	number = function(v): number
		return v[1]
	end,
	vector = function(v): vector
		return vector.create(v[1], v[2], v[3])
	end,
}

if IS_ROBLOX then
	local round = math.round

	local CFrame_new = CFrame.new
	local CFrame_fromAxisAngle = CFrame.fromAxisAngle
	local ColorSequence_new = ColorSequence.new
	local ColorSequenceKeypoint_new = ColorSequenceKeypoint.new
	local DateTime_fromUnixTimestampMillis = DateTime.fromUnixTimestampMillis
	local NumberRange_new = NumberRange.new
	local NumberSequence_new = NumberSequence.new
	local NumberSequenceKeypoint_new = NumberSequenceKeypoint.new
	local PhysicalProperties_new = PhysicalProperties.new
	local Ray_new = Ray.new
	local Rect_new = Rect.new
	local Region3_new = Region3.new
	local Region3int16_new = Region3int16.new
	local UDim_new = UDim.new
	local UDim2_new = UDim2.new
	local Vector2_new = Vector2.new
	local Vector3_new = Vector3.new
	local Vector2int16_new = Vector2int16.new
	local Vector3int16_new = Vector3int16.new

	local Oklab_toRGB = Oklab.toRGB
	local Oklab_fromRGB = Oklab.fromRGB

	-- stylua: ignore start
	function packers.CFrame(t, v: CFrame) local p, a = v:ToAxisAngle(); t[1], t[2], t[3], t[4], t[5], t[6], t[7] = v.X, v.Y, v.Z, p.X, p.Y, p.Z, a end
	function packers.Color3(t, v: Color3) local o = Oklab_fromRGB(v); t[1], t[2], t[3] = o.X, o.Y, o.Z end
	function packers.ColorSequence(t, v: ColorSequence) for i, k in v.Keypoints do local o = Oklab_fromRGB(k.Value); i = (i - 1) * 4; t[i + 1], t[i + 2], t[i + 3], t[i + 4] = k.Time, o.X, o.Y, o.Z end end
	function packers.ColorSequenceKeypoint(t, v: ColorSequenceKeypoint) local o = Oklab_fromRGB(v.Value); t[1], t[2], t[3], t[4] = v.Time, o.X, o.Y, o.Z end
	function packers.DateTime(t, v: DateTime) t[1] = v.UnixTimestampMillis end
	function packers.NumberRange(t, v: NumberRange) t[1], t[2] = v.Min, v.Max end
	function packers.NumberSequence(t, v: NumberSequence) for i, k in v.Keypoints do i = (i - 1) * 3; t[i + 1], t[i + 2], t[i + 3] = k.Time, k.Value, k.Envelope end end
	function packers.NumberSequenceKeypoint(t, v: NumberSequenceKeypoint) t[1], t[2], t[3] = v.Value, v.Time, v.Envelope end
	function packers.PhysicalProperties(t, v: PhysicalProperties) t[1], t[2], t[3], t[4], t[5] = v.Density, v.Friction, v.Elasticity, v.FrictionWeight, v.ElasticityWeight end
	function packers.Ray(t, v: Ray) t[1], t[2], t[3], t[4], t[5], t[6] = v.Origin.X, v.Origin.Y, v.Origin.Z, v.Direction.X, v.Direction.Y, v.Direction.Z end
	function packers.Rect(t, v: Rect) t[1], t[2], t[3], t[4] = v.Min.X, v.Min.Y, v.Max.X, v.Max.Y end
	-- FUTURE: support rotated Region3s if/when they become constructable
	function packers.Region3(t, v: Region3) t[1], t[2], t[3], t[4], t[5], t[6] = v.CFrame.X, v.CFrame.Y, v.CFrame.Z, v.Size.X, v.Size.Y, v.Size.Z end
	function packers.Region3int16(t, v: Region3int16) t[1], t[2], t[3], t[4], t[5], t[6] = v.Min.X, v.Min.Y, v.Min.Z, v.Max.X, v.Max.Y, v.Max.Z end
	function packers.UDim(t, v: UDim) t[1], t[2] = v.Scale, v.Offset end
	function packers.UDim2(t, v: UDim2) t[1], t[2], t[3], t[4] = v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset end
	function packers.Vector2(t, v: Vector2) t[1], t[2] = v.X, v.Y end
	function packers.Vector2int16(t, v: Vector2int16) t[1], t[2] = v.X, v.Y end
	function packers.Vector3(t, v: Vector3) t[1], t[2], t[3] = v.X, v.Y, v.Z end
	function packers.Vector3int16(t, v: Vector3int16) t[1], t[2], t[3] = v.X, v.Y, v.Z end

	function unpackers.CFrame(t): CFrame local p, a = CFrame_new(t[1], t[2], t[3]), Vector3_new(t[4], t[5], t[6]); if a.Magnitude < 1e-6 then return p end; return p * CFrame_fromAxisAngle(a, t[7]) end
	function unpackers.Color3(t): Color3 return Oklab_toRGB(Vector3_new(t[1], t[2], t[3]), false) end
	function unpackers.ColorSequence(t): ColorSequence local k = {}; for i = 1, #t, 4 do table.insert(k, ColorSequenceKeypoint_new(t[i], Oklab_toRGB(Vector3_new(t[i + 1], t[i + 2], t[i + 3]), true))) end; return ColorSequence_new(k) end
	function unpackers.ColorSequenceKeypoint(t): ColorSequenceKeypoint return ColorSequenceKeypoint_new(t[1], Oklab_toRGB(Vector3_new(t[2], t[3], t[4]), false)) end
	function unpackers.DateTime(t): DateTime return DateTime_fromUnixTimestampMillis(t[1]) end
	function unpackers.NumberRange(t): NumberRange return NumberRange_new(t[1], t[2]) end
	function unpackers.NumberSequence(t): NumberSequence local k = {}; for i = 1, #t, 3 do table.insert(k, NumberSequenceKeypoint_new(t[i], t[i + 1], t[i + 2])) end; return NumberSequence_new(k) end
	function unpackers.NumberSequenceKeypoint(t): NumberSequenceKeypoint return NumberSequenceKeypoint_new(t[2], t[1], t[3]) end
	function unpackers.PhysicalProperties(t): PhysicalProperties return PhysicalProperties_new(t[1], t[2], t[3], t[4], t[5]) end
	function unpackers.Ray(t): Ray return Ray_new(Vector3_new(t[1], t[2], t[3]), Vector3_new(t[4], t[5], t[6])) end
	function unpackers.Rect(t): Rect return Rect_new(t[1], t[2], t[3], t[4]) end
	-- FUTURE: support rotated Region3s if/when they become constructable
	function unpackers.Region3(t): Region3 local p, h = Vector3_new(t[1], t[2], t[3]), Vector3_new(t[4] / 2, t[5] / 2, t[6] / 2); return Region3_new(p - h, p + h) end
	function unpackers.Region3int16(t): Region3int16 return Region3int16_new(Vector3int16_new(round(t[1]), round(t[2]), round(t[3])), Vector3int16_new(round(t[4]), round(t[5]), round(t[6]))) end
	function unpackers.UDim(t): UDim return UDim_new(t[1], round(t[2])) end
	function unpackers.UDim2(t): UDim2 return UDim2_new(t[1], round(t[2]), t[3], round(t[4])) end
	function unpackers.Vector2(t): Vector2 return Vector2_new(t[1], t[2]) end
	function unpackers.Vector2int16(t): Vector2int16 return Vector2int16_new(round(t[1]), round(t[2])) end
	function unpackers.Vector3(t): Vector3 return Vector3_new(t[1], t[2], t[3]) end
	function unpackers.Vector3int16(t): Vector3int16 return Vector3int16_new(round(t[1]), round(t[2]), round(t[3])) end
	-- stylua: ignore end
end
local DataType = {}

--- Unpacks an array of numbers into a given animatable data type
function DataType.unpack(arr: { number }, t: string): any
	local unpack = unpackers[t]
	return if unpack then unpack(arr) else nil
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
	if pack then
		pack(arr, value)
	end

	return arr
end

return table.freeze(DataType)
