--!strict
--!native
--!optimize 2

local Graph = require("./Graph")

local new = Graph.new
local get = Graph.get
local set = Graph.set
local isReactive = Graph.isReactive

local proxyCache = {} :: { [{ [any]: any }]: any }
local proxyToRaw = {} :: { [any]: { [any]: any } }
local proxyToNodes = {} :: { [any]: { Graph.Node<any> } }

local STORE_SYMBOL: any = table.freeze({})

local StoreMetatable

local function createProxy<T>(target: T): T
	if proxyCache[target] then
		return proxyCache[target] :: any
	end

	local proxy = setmetatable({}, StoreMetatable)

	proxyCache[target] = proxy
	proxyToRaw[proxy] = target
	proxyToNodes[proxy] = {}

	return proxy :: any
end

StoreMetatable = {
	__index = function(proxy, key: any)
		local target = proxyToRaw[proxy]
		local value = rawget(target, key)

		if isReactive() then
			local nodes = proxyToNodes[proxy]
			local node = nodes[key]
			if node == nil then
				node = new(value)
				nodes[key] = node
			end
			get(node)
		end

		if type(value) == "table" then
			return createProxy(value)
		end

		return value
	end,

	__newindex = function(proxy, key: any, newValue: any)
		local target = proxyToRaw[proxy]
		local rawValue = proxyToRaw[newValue] or newValue
		local oldValue = rawget(target, key)

		if oldValue ~= rawValue or type(rawValue) == "table" then
			rawset(target, key, rawValue)

			local nodes = proxyToNodes[proxy]
			local node = nodes[key]
			if node ~= nil then
				set(node, rawValue)
			end

			local tracker = nodes[STORE_SYMBOL]
			if tracker then
				set(tracker, target, true)
			end
		end
	end,

	__iter = function(proxy)
		local target = proxyToRaw[proxy]
		local nodes = proxyToNodes[proxy]

		local tracker = nodes[STORE_SYMBOL]
		if not tracker then
			tracker = Graph.new(target)
			nodes[STORE_SYMBOL] = tracker
		end
		get(tracker :: any)

		return next, target
	end,

	__len = function(proxy)
		local target = proxyToRaw[proxy]
		local nodes = proxyToNodes[proxy]

		local tracker = nodes[STORE_SYMBOL]
		if not tracker then
			tracker = Graph.new(target)
			nodes[STORE_SYMBOL] = tracker
		end
		get(tracker :: any)

		return #target
	end,
}

local Store = {}

function Store.new<T>(initialState: T): T
	assert(type(initialState) == "table", "Store initialState must be a table")
	return createProxy(initialState)
end

function Store.destroy<T>(proxy: T)
	local target = proxyToRaw[proxy]
	if not target then
		return
	end

	local nodes = proxyToNodes[proxy]

	proxyCache[target] = nil
	proxyToRaw[proxy] = nil
	proxyToNodes[proxy] = nil
	setmetatable(proxy, nil)

	for _, node in nodes do
		node:Destroy()
	end
	table.clear(nodes)

	for _, value in target do
		if type(value) == "table" then
			local nestedProxy = proxyCache[value]
			if nestedProxy then
				Store.destroy(nestedProxy)
			end
		end
	end
end

function Store.unwrap<T>(proxy: T): T
	return (proxyToRaw[proxy] or proxy) :: T
end

return table.freeze(Store)
