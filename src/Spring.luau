--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")

local Package = script.Parent
local State = require(Package.State)
local DataType = require(Package.DataType)

type SpringState<T> = State.State<T> & {
	_springGoal: any,
	_springSpeed: any,
	_springDamping: any,
	_activeTargetP: { number },
	_activeStartP: { number },
	_activeStartV: { number },
	_activeLatestP: { number },
	_activeLatestV: { number },
	_activeType: string,
	_activeNumSprings: number,
	_activeGoal: any,
	_activeDamping: number?,
	_activeSpeed: number?,
	_springInit: number?,

	-- Internal methods injected by Spring
	wake: (SpringState<T>) -> (),
	Destroy: (SpringState<T>) -> (),
}

local EPSILON = 1e-4

local isState = State.isState

local springs: { [SpringState<any>]: boolean } = {}
setmetatable(springs :: { [SpringState<any>]: boolean }, { __mode = "_k" })

-- Analytical Spring Solver
-- Returns position and velocity coefficients based on time, damping, and speed
local function springCoefficients(t: number, damping: number, speed: number)
	if t == 0 or speed == 0 then
		return 1, 0, 0, 1
	end

	local posPos, posVel, velPos, velVel

	if damping > 1 then
		-- Overdamped
		local alpha = math.sqrt(damping ^ 2 - 1)
		local z1 = -speed * (alpha + damping)
		local z2 = speed * (alpha - damping)
		local exp1 = math.exp(t * z1)
		local exp2 = math.exp(t * z2)

		-- Coefficient used to normalize the derivation
		local co = -0.5 / (alpha * speed)

		posPos = (exp2 * z1 - exp1 * z2) * co
		posVel = (exp1 - exp2) * co / speed
		velPos = (exp2 - exp1) * co * speed
		velVel = (exp1 * z1 - exp2 * z2) * co
	elseif damping == 1 then
		-- Critically damped
		local t_speed = t * speed
		local exp = math.exp(-t_speed)

		posPos = exp * (1 + t_speed)
		posVel = exp * t
		velPos = exp * (-speed * t_speed)
		velVel = exp * (1 - t_speed)
	else
		-- Underdamped
		local alpha = speed * math.sqrt(1 - damping ^ 2)
		local beta = speed * damping
		local exp = math.exp(-beta * t)
		local c = math.cos(alpha * t)
		local s = math.sin(alpha * t)
		local invAlpha = 1 / alpha

		posPos = exp * (c + beta * invAlpha * s)
		posVel = exp * s * invAlpha
		velPos = -exp * (speed * speed * invAlpha * s)
		velVel = exp * (c - beta * invAlpha * s)
	end

	return posPos, posVel, velPos, velVel
end

local function wake(spring: SpringState<any>)
	if not spring._springInit then
		spring._springInit = os.clock()
	end
end

local function sleep(spring: SpringState<any>)
	if spring._springInit then
		spring._springInit = nil

		-- Snap to target to ensure strict equality at rest
		for i = 1, spring._activeNumSprings do
			(spring._activeLatestP :: { number })[i] = (spring._activeTargetP :: { number })[i];
			(spring._activeLatestV :: { number })[i] = 0
		end

		spring._value = DataType.pack(spring._activeLatestP, spring._activeType) :: any
		task.spawn(spring._update, spring, true, true, true)
	end
end

local function initSpring(
	spring: SpringState<any>,
	goal: any,
	goalType: string,
	speed: number,
	damping: number,
	discontinuous: boolean
)
	local targetP = DataType.unpack(goal, goalType)
	spring._activeTargetP = targetP
	spring._activeNumSprings = #targetP
	spring._activeType = goalType
	spring._activeGoal = goal
	spring._activeDamping = damping
	spring._activeSpeed = speed

	if discontinuous or not spring._activeLatestP then
		spring._activeStartP = table.clone(targetP)
		spring._activeLatestP = table.clone(targetP)
		spring._activeStartV = table.create(spring._activeNumSprings, 0)
		spring._activeLatestV = table.create(spring._activeNumSprings, 0)

		-- Immediate set: ensures value is ready synchronously after initSpring returns
		spring._value = DataType.pack(targetP, goalType) :: any
		task.spawn(spring._update, spring, true, true, true)
	else
		-- Continuation: Reset start position to current position relative to new target logic
		spring._activeStartP = table.clone(spring._activeLatestP)
		spring._activeStartV = table.clone(spring._activeLatestV)
		wake(spring)
	end
end

local function stepSpring(spring: SpringState<any>, dt: number)
	local startTime = spring._springInit
	if not startTime then
		return
	end

	local elapsed = os.clock() - startTime
	local damping = spring._activeDamping or 1
	local speed = spring._activeSpeed or 1

	local posPos, posVel, velPos, velVel = springCoefficients(elapsed, damping, speed)
	local isMoving = false

	for i = 1, spring._activeNumSprings do
		local startP = (spring._activeStartP :: { number })[i]
		local targetP = (spring._activeTargetP :: { number })[i]
		local startV = (spring._activeStartV :: { number })[i]

		local displacement = startP - targetP
		local newDisp = displacement * posPos + startV * posVel
		local newVel = displacement * velPos + startV * velVel

		-- NaN protection
		if newDisp ~= newDisp or newVel ~= newVel then
			newDisp, newVel = 0, 0
		end

		-- Check for sleep threshold
		if math.abs(newDisp) > EPSILON or math.abs(newVel) > EPSILON then
			isMoving = true
		end

		(spring._activeLatestP :: { number })[i] = newDisp + targetP;
		(spring._activeLatestV :: { number })[i] = newVel
	end

	if isMoving then
		spring._value = DataType.pack(spring._activeLatestP, spring._activeType) :: any
		-- We pass 'true' to _update to skip tween/spring logic inside State, preventing recursion loops
		-- (State._update params: forceUpdate, noTween, noCompute, deferredUpdate)
		task.spawn(spring._update, spring, true, true, true)
	else
		sleep(spring)
	end
end

-- Helper to ensure proper cleanup when the spring state is destroyed
local function destroySpring(spring: SpringState<any>)
	springs[spring] = nil
	State.Destroy(spring)
end

RunService.Heartbeat:Connect(function(dt)
	for spring in springs do
		if not spring._springInit then
			continue
		end

		local goal = spring._springGoal
		if isState(goal) then
			goal = goal._value
		end

		local speed = spring._springSpeed
		if isState(speed) then
			speed = speed._value
		end

		local damping = spring._springDamping
		if isState(damping) then
			damping = damping._value
		end

		local goalType = typeof(goal)
		local discontinuous = goalType ~= spring._activeType

		if
			discontinuous
			or goal ~= spring._activeGoal
			or speed ~= spring._activeSpeed
			or damping ~= spring._activeDamping
		then
			initSpring(spring :: any, goal, goalType, speed, damping, discontinuous)
		end

		stepSpring(spring :: any, dt)
	end
end)

local Spring = {}
Spring.__index = Spring

function Spring.new<T>(
	goal: State.Stateful<T>,
	speed: State.Stateful<number>?,
	damping: State.Stateful<number>?
): State.State<T>
	local self: SpringState<T>

	-- Handle State vs Function vs Raw
	if type(goal) == "function" then
		self = State.compute(goal) :: any
	elseif State.isState(goal) and (goal :: any)._computation == nil then
		-- Wrap existing state to avoid modifying the source state directly
		self = State.compute(function()
			return (goal :: any)()
		end) :: any
	else
		self = State.new(goal) :: any
	end

	self._springGoal = self._value -- Set initial goal
	self._springSpeed = speed or 10
	self._springDamping = damping or 1

	-- Patch methods
	self.wake = wake
	self.Destroy = destroySpring

	initSpring(self, self._value, typeof(self._value), State.raw(speed or 10), State.raw(damping or 1), true)
	springs[self] = true

	return self
end

return Spring
