--!optimize 2
--!native

local RunService = game:GetService("RunService")

local Package = script.Parent

local State = require(Package.State)
local DataType = require(Package.DataType)

local function springCoefficients(time: number, damping: number, speed: number): (number, number, number, number)
	-- if time or speed is 0, then the spring won't move
	if time == 0 or speed == 0 then
		return 1, 0, 0, 1
	end
	local posPos, posVel, velPos, velVel

	if damping > 1 then
		-- overdamped spring

		local alpha = math.sqrt(damping ^ 2 - 1)
		local negHalf_over_alpha_speed = -0.5 / (alpha * speed)
		local z1 = speed * (alpha + damping) * -1
		local z2 = speed * (alpha - damping)
		local exp1 = math.exp(time * z1)
		local exp2 = math.exp(time * z2)

		posPos = (exp2 * z1 - exp1 * z2) * negHalf_over_alpha_speed
		posVel = (exp1 - exp2) * negHalf_over_alpha_speed / speed
		velPos = (exp2 - exp1) * negHalf_over_alpha_speed * speed
		velVel = (exp1 * z1 - exp2 * z2) * negHalf_over_alpha_speed
	elseif damping == 1 then
		-- critically damped spring

		local time_speed = time * speed
		local time_speed_neg1 = time_speed * -1
		local exp = math.exp(time_speed_neg1)

		posPos = exp * (time_speed + 1)
		posVel = exp * time
		velPos = exp * (time_speed_neg1 * speed)
		velVel = exp * (time_speed_neg1 + 1)
	else
		-- underdamped spring

		local alpha = speed * math.sqrt(1 - damping ^ 2)
		local overAlpha = 1 / alpha
		local exp = math.exp(-1 * time * speed * damping)
		local sin = math.sin(alpha * time)
		local cos = math.cos(alpha * time)
		local exp_sin = exp * sin
		local exp_cos = exp * cos
		local exp_sin_speed_damping_overAlpha = exp_sin * speed * damping * overAlpha

		posPos = exp_sin_speed_damping_overAlpha + exp_cos
		posVel = exp_sin * overAlpha
		velPos = -1 * (exp_sin * alpha + speed * damping * exp_sin_speed_damping_overAlpha)
		velVel = exp_cos - exp_sin_speed_damping_overAlpha
	end

	return posPos, posVel, velPos, velVel
end

local EPSILON = 0.00001
local springs = setmetatable({}, { __mode = "_k" })

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for spring in springs do
		local goal, speed, damping = State.rawVariadic(spring._springGoal, spring._springSpeed, spring._springDamping)
		local goalType = typeof(goal)
		local discontinuous = goalType ~= spring._activeType

		if not discontinuous and spring._springInit then
			local isMoving = false
			local elapsed = now - spring._springInit
			local posPos, posVel, velPos, velVel = springCoefficients(elapsed, damping, speed)

			for index = 1, spring._activeNumSprings do
				local startP = spring._activeStartP[index]
				local targetP = spring._activeTargetP[index]
				local startV = spring._activeStartV[index]
				local startD = startP - targetP
				local latestD = startD * posPos + startV * posVel
				local latestV = startD * velPos + startV * velVel
				if latestD ~= latestD or latestV ~= latestV then
					print("NAN")
					latestD, latestV = 0, 0
				end
				if math.abs(latestD) > EPSILON or math.abs(latestV) > EPSILON then
					isMoving = true
				end
				local latestP = latestD + targetP
				spring._activeLatestP[index] = latestP
				spring._activeLatestV[index] = latestV
			end

			if not isMoving then
				for index = 1, spring._activeNumSprings do
					spring._activeLatestP[index] = spring._activeTargetP[index]
				end
				spring._springInit = nil
			end

			spring._value = DataType.pack(spring._activeLatestP, spring._activeType) :: any
		end

		if
			discontinuous
			or goal ~= spring._activeGoal
			or speed ~= spring._activeSpeed
			or damping ~= spring._activeDamping
		then
			spring._activeTargetP = DataType.unpack(goal, goalType)
			spring._activeNumSprings = #spring._activeTargetP
			if discontinuous then
				spring._activeStartP = table.clone(spring._activeTargetP)
				spring._activeLatestP = table.clone(spring._activeTargetP)
				spring._activeStartV = table.create(spring._activeNumSprings, 0)
				spring._activeLatestV = table.create(spring._activeNumSprings, 0)
			else
				spring._activeStartP = table.clone(spring._activeLatestP or {})
				spring._activeStartV = table.clone(spring._activeLatestV or {})
			end
			spring._activeType = goalType
			spring._activeGoal = goal
			spring._activeDamping = damping
			spring._activeSpeed = speed
			spring._springInit = now
		end

		task.spawn(spring._update, spring, true, true, nil, true)
	end
end)

local Spring = { _springs = springs }
Spring.__index = Spring

function Spring.new<T>(
	goal: State.Stateful<any>,
	speed: State.Stateful<any>?,
	damping: State.Stateful<any>?
): State.State<T>
	local self = State.new(State.raw(goal))
	self._springGoal = goal
	self._springSpeed = speed or 10
	self._springDamping = damping or 1
	Spring._springs[self] = true
	return self
end

return Spring
