--!strict

local Color = require("@self/Color")
local DataType = require("@self/DataType")
local Engine = require("@self/Engine")
local Graph = require("./Graph")

local PACK = DataType.pack

local isNode = Graph.isNode
local raw = Graph.raw
local read = Graph.read

local Motion = {
	Color = Color,
	DataType = DataType,
	Engine = Engine,

	step = Engine.step,
}

local tempArray = { 0, 0, 0, 0, 0, 0, 0 }

local NodeToMotion: { [Graph.Node<any>]: Engine.Spring | Engine.Tween } = {}

local MotionStateMetatable = {}
MotionStateMetatable.__index = MotionStateMetatable

-- inject common fields
for key, method in Graph.Node :: any do
	if key ~= "__call" and key ~= "Destroy" and key ~= "__index" then
		(MotionStateMetatable :: any)[key] = method
	end
end

function MotionStateMetatable.__call<T>(self: Graph.Node<T>, value: any?): any?
	if value ~= nil then
		local motion = NodeToMotion[self]
		Engine.setTarget(motion, PACK(tempArray, value, motion.typeString))
		return
	else
		return read(self)
	end
end

function MotionStateMetatable.set<T>(self: Graph.Node<T>, value: T)
	local motion = NodeToMotion[self]
	Engine.setTarget(motion, PACK(tempArray, value, motion.typeString))
end

function MotionStateMetatable:Destroy()
	local motion = NodeToMotion[self]
	NodeToMotion[self] = nil
	Engine.destroy(motion)
	Graph.Node.Destroy(self)
end

function Motion.spring<T>(target: T, frequency: number?, damping: number?): Graph.Node<T>
	local initialVal = raw(target)
	local typeStr = typeof(initialVal)

	PACK(tempArray, initialVal, typeStr)

	local stateNode = Graph.new(initialVal)
	local spring = Engine.newSpring(#tempArray, typeStr, stateNode)

	NodeToMotion[stateNode] = spring
	Engine.setCurrent(spring, tempArray)
	Engine.setupSpring(spring, frequency, damping)

	if isNode(target) or isNode(frequency) or isNode(damping) then
		local effectNode = Graph.new(function()
			Engine.setupSpring(spring, read(frequency), read(damping))
			Engine.setTarget(spring, PACK(tempArray, read(target), typeStr))
		end, true)

		stateNode:onDestroy(function()
			effectNode:Destroy()
		end)
	end

	return setmetatable(stateNode, MotionStateMetatable) :: any
end

function Motion.tween<T>(target: T, tweenInfo: TweenInfo): Graph.Node<T>
	local initialVal = raw(target)
	local typeStr = typeof(initialVal)

	PACK(tempArray, initialVal, typeStr)

	local stateNode = Graph.new(initialVal)
	local tween = Engine.newTween(#tempArray, typeStr, stateNode)

	NodeToMotion[stateNode] = tween
	Engine.setCurrent(tween, tempArray)
	Engine.setupTween(tween, raw(tweenInfo))

	if isNode(target) or isNode(tweenInfo) then
		local effectNode = Graph.new(function()
			local i = read(tweenInfo)
			if tween.info ~= i then
				Engine.setupTween(tween, i)
			end
			Engine.setTarget(tween, PACK(tempArray, read(target), typeStr))
		end, true)

		stateNode:onDestroy(function()
			effectNode:Destroy()
		end)
	end

	return setmetatable(stateNode, MotionStateMetatable) :: any
end

return Motion
