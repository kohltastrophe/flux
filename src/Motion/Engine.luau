--!strict
--!native
--!optimize 2

local TweenService = game:GetService("TweenService")

local DataType = require("./DataType")
local Graph = require("../Graph")

local setNode = Graph.set
local UNPACK = DataType.unpack

local Engine = { now = os.clock() }

local TYPE_TWEEN = 1
local TYPE_SPRING = 2
local EPSILON = 1e-4

export type Motion = {
	type: number,
	count: number,
	node: Graph.Node<any>,
	typeString: string,
	target: { number },
	value: { number },
	vel: { number },
}

export type Spring = Motion & {
	frequency: number,
	damping: number,
}

export type Tween = Motion & {
	info: TweenInfo,
	startTime: number,
	repeatsLeft: number,
	reversing: boolean,
	start: { number },
}

local activeSprings: { [Motion]: any } = {}
local activeTweens: { [Motion]: any } = {}

function Engine.newSpring(count: number, typeString: string, node: any): Spring
	return {
		type = TYPE_SPRING,
		count = count,
		node = node,
		typeString = typeString or "number",

		target = table.create(count, 0),
		value = table.create(count, 0),
		vel = table.create(count, 0),

		frequency = nil :: any,
		damping = nil :: any,
	}
end

function Engine.newTween(count: number, typeString: string, node: any): Tween
	return {
		type = TYPE_TWEEN,
		count = count,
		node = node,
		typeString = typeString or "number",

		start = table.create(count, 0),
		target = table.create(count, 0),
		value = table.create(count, 0),
		vel = table.create(count, 0),

		info = nil :: any,
		startTime = nil :: any,
		repeatsLeft = nil :: any,
		reversing = nil :: any,
	}
end

function Engine.destroy(motion: Spring | Tween)
	activeSprings[motion] = nil
	activeTweens[motion] = nil
	table.clear(motion)
end

function Engine.setupSpring(spring: Spring, frequency: number?, damping: number?)
	spring.type = TYPE_SPRING
	spring.frequency = frequency or 1
	spring.damping = damping or 1

	activeSprings[spring] = spring.node
end

function Engine.setupTween(tween: Tween, tweenInfo: TweenInfo)
	if tweenInfo == nil then
		tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)
	end

	tween.type = TYPE_TWEEN
	tween.info = tweenInfo
	tween.startTime = Engine.now + tweenInfo.DelayTime
	tween.repeatsLeft = tweenInfo.RepeatCount
	tween.reversing = false

	local start = tween.start
	for i, v in tween.value do
		start[i] = v
	end

	activeTweens[tween] = tween.node
end

function Engine.setCurrent(motion: Spring | Tween, arr: { number })
	local target, value, vel = motion.target, motion.value, motion.vel
	table.clear(target)
	table.clear(value)
	table.clear(vel)

	for i, v in arr do
		target[i] = v
		value[i] = v
		vel[i] = 0
	end

	if motion.type == TYPE_TWEEN then
		local start = (motion :: Tween).start
		table.clear(start)
		for i, v in arr do
			start[i] = v
		end
	end

	motion.count = #arr
end

function Engine.setTarget(motion: Spring | Tween, arr: { number })
	local activeMap = activeSprings

	if motion.type == TYPE_TWEEN then
		motion = motion :: Tween
		activeMap = activeTweens
		local start, value = motion.start, motion.value
		for i = 1, #arr do
			start[i] = value[i]
		end
		motion.startTime = Engine.now
		motion.repeatsLeft = motion.info.RepeatCount
		motion.reversing = false
	end

	if #arr ~= motion.count then
		Engine.setCurrent(motion, arr)
	else
		local target = motion.target
		for i, v in arr do
			target[i] = v
		end
	end

	activeMap[motion] = motion.node
end

local function stepSpring(motion: Spring, now: number, dt: number)
	local f = motion.frequency
	local d = motion.damping
	local w = math.tau * f

	local isSleeping = true
	local expTerm: number, cosTerm: number, sinTerm: number, r1: number, r2: number, exp1: number, exp2: number, wd: number
	local target, value, m_vel = motion.target, motion.value, motion.vel

	if d == 1 then
		expTerm = math.exp(-w * dt)
	elseif d < 1 then
		wd = w * math.sqrt(1 - d * d)
		expTerm = math.exp(-d * w * dt)
		cosTerm = math.cos(wd * dt)
		sinTerm = math.sin(wd * dt)
	else
		wd = w * math.sqrt(d * d - 1)
		r1 = -w * d + wd
		r2 = -w * d - wd
		exp1 = math.exp(r1 * dt)
		exp2 = math.exp(r2 * dt)
	end

	for c, pos in value do
		local tar: number = target[c]
		local vel: number = m_vel[c]

		if math.abs(pos - tar) > EPSILON or math.abs(vel) > EPSILON then
			isSleeping = false
			if d == 1 then -- CRITICALLY DAMPED
				local c1 = pos - tar
				local c2 = vel + w * c1
				value[c] = tar + (c1 + c2 * dt) * expTerm
				m_vel[c] = (c2 - w * (c1 + c2 * dt)) * expTerm
			elseif d < 1 then -- UNDERDAMPED
				local c1 = pos - tar
				local c2 = (vel + w * d * c1) / wd
				value[c] = tar + expTerm * (c1 * cosTerm + c2 * sinTerm)
				m_vel[c] = expTerm * (vel * cosTerm - (c1 * wd + c2 * d * w) * sinTerm)
			else -- OVERDAMPED
				local c2 = (vel - r1 * (pos - tar)) / (r2 - r1)
				local c1 = pos - tar - c2
				value[c] = tar + c1 * exp1 + c2 * exp2
				m_vel[c] = c1 * r1 * exp1 + c2 * r2 * exp2
			end
		end
	end

	if isSleeping then
		for c, tar in target do
			value[c] = tar
			m_vel[c] = 0
		end
		activeSprings[motion] = nil
	end
end

local function stepTween(tween: Tween, now: number)
	local elapsed = now - tween.startTime
	if elapsed < 0 then
		return
	end

	local tInfo = tween.info
	local duration = tInfo.Time
	local alpha = if duration > 0 then elapsed / duration else 1
	local isReversing = tween.reversing

	if alpha >= 1 then
		if tInfo.Reverses and not isReversing then
			tween.reversing = true
			tween.startTime += duration
			alpha = (now - tween.startTime) / duration
			isReversing = true
		else
			if tween.repeatsLeft > 0 or tInfo.RepeatCount < 0 then
				if tween.repeatsLeft > 0 then
					tween.repeatsLeft -= 1
				end
				tween.reversing = false
				tween.startTime += duration
				alpha = (now - tween.startTime) / duration
				isReversing = false
			else
				alpha = 1
				activeTweens[tween] = nil
			end
		end
	end

	alpha = TweenService:GetValue(alpha, tInfo.EasingStyle, tInfo.EasingDirection)
	if isReversing then
		alpha = 1 - alpha
	end

	local value, target = tween.value, tween.target
	for i, start in tween.start do
		value[i] = start + (target[i] - start) * alpha
	end
end

function Engine.step()
	local now = os.clock()
	local dt = now - Engine.now
	Engine.now = now

	for spring: Spring, node: Graph.Node<any> in activeSprings do
		stepSpring(spring, now, dt)
		setNode(node, UNPACK(spring.value, spring.typeString))
	end

	for tween: Tween, node: Graph.Node<any> in activeTweens do
		stepTween(tween, now)
		setNode(node, UNPACK(tween.value, tween.typeString))
	end
end

return Engine
