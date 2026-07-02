--!strict

local Color = require("@self/Color")
local Compat = require("./Compat")
local DataType = require("@self/DataType")
local Engine = require("@self/Engine")
local Graph = require("./Graph")

local PACK = DataType.pack

local isNode = Graph.isNode
local raw = Graph.raw
local read = Graph.read

type Spring<T> = {
	impulse: (self: Graph.Node<T>, delta: T) -> (),
	setVelocity: (self: Graph.Node<T>, velocity: T) -> (),
}

local warn = Compat.warn

local tempArray = { 0, 0, 0, 0, 0, 0, 0 }

local NodeToMotion: { [Graph.Node<any>]: Engine.Spring | Engine.Tween } = {}

local MotionStateMetatable = {}

for key, method in Graph.Node :: any do
	(MotionStateMetatable :: any)[key] = method
end
MotionStateMetatable.__index = MotionStateMetatable

--[[
Retargets the animation: the motion now eases toward `value` from wherever it
currently is, preserving momentum. Equivalent to calling the motion node directly,
`motion(value)`. The new goal may itself be reactive, in which case the motion
re-targets automatically whenever it changes.

[Open Documentation](https://flux.kohl.gg/guide/motion/spring#reactive-targets)
]]
function MotionStateMetatable.set<T>(self: Graph.Node<T>, value: T)
	local motion = NodeToMotion[self]
	Engine.setTarget(motion, PACK(tempArray, value, motion.typeString))
end

--[[
Adds `delta` to the spring's current velocity,
nudging it without changing the goal, useful for a flick or kick on a drag release.
<em>Spring only</em>; calling it on a [`Flux.tween`](https://flux.kohl.gg/guide/motion/tween)
warns and is ignored.

[Open Documentation](https://flux.kohl.gg/guide/motion/spring#velocity-control-impulse-set-velocity)
]]
function MotionStateMetatable.impulse<T>(self: Graph.Node<T>, delta: T)
	local spring = NodeToMotion[self]
	if spring == nil or spring.type ~= Engine.TYPE_SPRING then
		warn(`:impulse() is only valid on a spring; ignoring`)
		return
	end
	Engine.addVelocity(spring :: Engine.Spring, PACK(tempArray, delta, spring.typeString))
end

--[[
Overwrites the spring's velocity outright, replacing
any existing momentum without changing the goal. Use `impulse` to add to the current velocity
instead. <em>Spring only</em>; calling it on a
[`Flux.tween`](https://flux.kohl.gg/guide/motion/tween) warns and is ignored.

[Open Documentation](https://flux.kohl.gg/guide/motion/spring#velocity-control-impulse-set-velocity)
]]
function MotionStateMetatable.setVelocity<T>(self: Graph.Node<T>, velocity: T)
	local spring = NodeToMotion[self]
	if spring == nil or spring.type ~= Engine.TYPE_SPRING then
		warn(`:setVelocity() is only valid on a spring; ignoring`)
		return
	end
	Engine.setVelocity(spring :: Engine.Spring, PACK(tempArray, velocity, spring.typeString))
end

function MotionStateMetatable.__call<T>(self: Graph.Node<T>, value: any?): any?
	if value ~= nil then
		MotionStateMetatable.set(self, value)
		return
	else
		return read(self)
	end
end

--[[
Tears the motion down early: stops the animation, removes it from the engine's stepped set, and disposes
the underlying [node](https://flux.kohl.gg/guide/concepts/signals). You rarely call this; on
[scope](https://flux.kohl.gg/guide/concepts/scopes) teardown the engine registration is released
automatically and the node, a plain signal, is reclaimed by the GC.

[Open Documentation](https://flux.kohl.gg/guide/motion/spring)
]]
function MotionStateMetatable:Destroy()
	local motion = NodeToMotion[self]
	NodeToMotion[self] = nil
	Engine.destroy(motion)
	Graph.Node.Destroy(self)
end

local Motion = {
	Color = Color,
	DataType = DataType,
	Engine = Engine,
	NodeToMotion = NodeToMotion,

	--[[
	Advances every active [spring](https://flux.kohl.gg/guide/motion/spring) and
	[tween](https://flux.kohl.gg/guide/motion/tween) by one frame. Wired automatically to each
	[`RunService.Heartbeat`](https://create.roblox.com/docs/reference/engine/classes/RunService) under
	Roblox, so you rarely call it yourself; drive it manually only when stepping motion deterministically
	in tests.

	[Open Documentation](https://flux.kohl.gg/guide/tips/testing#full-engine-tests-in-ci)
	]]
	step = Engine.step,
}

--- Returns whether the given value is a reactive motion.
function Motion.isMotion(obj: unknown): boolean
	return type(obj) == "table" and getmetatable(obj) == MotionStateMetatable
end

local function attachEffect(stateNode: Graph.Node<any>, fn: () -> ())
	local effectNode = Graph.new(fn, true)
	stateNode:onDestroy(function()
		effectNode:Destroy()
	end)
end

local function packOrFallback(target: any, initialVal: any, typeStr: string): Graph.Node<any>?
	PACK(tempArray, initialVal, typeStr)
	if #tempArray ~= 0 then
		return nil
	end

	if typeStr == "nil" then
		warn("Animating a nil value; following the goal without animation")
		local stateNode = Graph.new(initialVal)
		if isNode(target) then
			attachEffect(stateNode, function()
				stateNode:set(read(target))
			end)
		end
		return stateNode
	end

	error(`Cannot animate a {typeStr} value`, 3)
end

--[[
Creates a [node](https://flux.kohl.gg/guide/concepts/signals) that springs toward `target`, animating any
supported value type (numbers, [`Vector2`](https://create.roblox.com/docs/reference/engine/datatypes/Vector2),
[`UDim2`](https://create.roblox.com/docs/reference/engine/datatypes/UDim2),
[`Color3`](https://create.roblox.com/docs/reference/engine/datatypes/Color3), …). When `target` is reactive
the spring re-targets on every change, carrying its momentum through. Read the returned node anywhere to
subscribe to the live animated value.
@param target - The goal value, static or a reactive [node](https://flux.kohl.gg/guide/concepts/signals); the spring eases toward it.
@param frequency - Oscillations per second, where higher snaps faster. Defaults to a tuned value; may be reactive.
@param damping - The damping ratio: `1` is critically damped (no overshoot), `<1` springs past and settles, `>1` is sluggish. May be reactive.

[Open Documentation](https://flux.kohl.gg/guide/motion/spring#basic-usage)
]]
function Motion.spring<T>(target: T, frequency: number?, damping: number?): Graph.Node<T> & Spring<T>
	local initialVal = raw(target)
	local typeStr = typeof(initialVal)

	local fallback = packOrFallback(target, initialVal, typeStr)
	if fallback ~= nil then
		return fallback :: any
	end

	local stateNode = Graph.new(initialVal)
	local spring = Engine.newSpring(#tempArray, typeStr, stateNode)

	NodeToMotion[stateNode] = spring
	local function unregister()
		NodeToMotion[stateNode] = nil
		Engine.destroy(spring)
	end

	stateNode:onDestroy(unregister)
	Graph.onDestroy(unregister)
	Engine.setCurrent(spring, tempArray)
	Engine.setupSpring(spring, frequency, damping)

	if isNode(target) or isNode(frequency) or isNode(damping) then
		local reactiveSetup = isNode(frequency) or isNode(damping)
		attachEffect(stateNode, function()
			if reactiveSetup then
				Engine.setupSpring(spring, read(frequency), read(damping))
			end
			Engine.setTarget(spring, PACK(tempArray, read(target), typeStr))
		end)
	end

	return setmetatable(stateNode, MotionStateMetatable) :: any
end

--[[
Creates a [node](https://flux.kohl.gg/guide/concepts/signals) that animates toward `target` over a fixed
duration described by a [`TweenInfo`](https://create.roblox.com/docs/reference/engine/datatypes/TweenInfo)
(easing style, direction, time, repeats). When `target` or the
[`TweenInfo`](https://create.roblox.com/docs/reference/engine/datatypes/TweenInfo) is reactive the tween
restarts toward the new goal. Read the returned node to subscribe to the live animated value. Prefer a
[`Flux.spring`](https://flux.kohl.gg/guide/motion/spring) for momentum-driven, interruptible motion.

[Open Documentation](https://flux.kohl.gg/guide/motion/tween#basic-usage)
]]
function Motion.tween<T>(target: T, tweenInfo: TweenInfo?): Graph.Node<T>
	local initialVal = raw(target)
	local typeStr = typeof(initialVal)

	local fallback = packOrFallback(target, initialVal, typeStr)
	if fallback ~= nil then
		return fallback :: any
	end

	local stateNode = Graph.new(initialVal)
	local tween = Engine.newTween(#tempArray, typeStr, stateNode)

	NodeToMotion[stateNode] = tween
	local function unregister()
		NodeToMotion[stateNode] = nil
		Engine.destroy(tween)
	end
	stateNode:onDestroy(unregister)
	Graph.onDestroy(unregister)
	Engine.setCurrent(tween, tempArray)
	Engine.setupTween(tween, raw(tweenInfo))

	if isNode(target) or isNode(tweenInfo) then
		attachEffect(stateNode, function()
			local i = read(tweenInfo)
			if tween.info ~= i then
				Engine.setupTween(tween, i)
			end
			Engine.setTarget(tween, PACK(tempArray, read(target), typeStr))
		end)
	end

	return setmetatable(stateNode, MotionStateMetatable) :: any
end

return table.freeze(Motion)
