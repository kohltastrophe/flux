--!strict

local Compat = require("./Compat")
local Graph = require("./Graph")

local raw = Graph.raw
local new = Graph.new
local readDep = Graph.readDep
local rawDep = Graph.rawDep
local untrack = Graph.untrack
local retrack = Graph.retrack

local task = Compat.task

local function gatedOff(src: any, input: any): boolean
	return src ~= nil and (input == nil or input == false)
end

--[[
The state of an [async](https://flux.kohl.gg/guide/concepts/async) node, derived from its `.error`/`.loading` and whether a fetch has resolved.
- `unresolved` (nothing fetched yet)
- `pending` (first fetch in flight, no value)
- `refreshing` (fetch in flight over an existing value)
- `ready` (resolved)
- `errored` (last fetch threw)
]]
export type AsyncState = "unresolved" | "pending" | "ready" | "refreshing" | "errored"

export type Async<T> = {
	data: Graph.Node<T?>,
	error: Graph.Node<string?>,
	loading: Graph.Node<boolean>,
	state: Graph.Node<AsyncState>,
	Destroy: (self: Async<T>) -> (),
	refetch: (self: Async<T>, info: any?) -> (),
	mutate: (self: Async<T>, value: T) -> (),
	_resolved: Graph.Node<boolean>,
	_effect: Graph.Node<any>,
	_src: any,
	_fetcher: any,
	_fetchId: number,
}

local function runFetcher<T>(self: Async<T>, input: any, currentId: number, refetching: boolean?)
	local ok, result = pcall(self._fetcher, input, raw(self.data), refetching)
	if currentId == self._fetchId then
		self.loading:set(false)
		if ok then
			self._resolved:set(true)
			self.data:set(result)
		else
			self.error:set(tostring(result))
		end
	end
end

--[[ Bumps the race guard and spawns a fetch with the freshly-read `input`. ]]
local function trigger<T>(self: Async<T>, input: any, refetching: boolean?)
	self._fetchId += 1
	local currentId = self._fetchId

	self.loading:set(true)
	self.error:set(nil)

	untrack()
	task.spawn(runFetcher, self, input, currentId, refetching)
	retrack()
end

local Async = {}
Async.__index = Async

--[[
Creates a non-blocking asynchronous [node](https://flux.kohl.gg/guide/concepts/signals) that runs yielding
work off the reactive graph and exposes its progress as four nodes: `.data`, `.error`, `.loading`, and
`.state`. A race guard discards stale results, so only the latest fetch ever writes back. When a `source` is
given and it reads `nil` or `false`, the fetch is gated off until the source turns truthy. Read those nodes
inside a [computed](https://flux.kohl.gg/guide/concepts/computeds) or
[effect](https://flux.kohl.gg/guide/concepts/effects) to render loading and error states reactively.
@param source - A tracked input: a [node](https://flux.kohl.gg/guide/concepts/signals) or a computation whose value is passed to the fetcher; the fetcher re-runs whenever it changes. Omit it (pass the fetcher first) for a one-shot fetch. A `nil`/`false` source value gates the fetch off until it becomes truthy.
@param fetcher - The untracked yielding work, called as `fetcher(value, previous, refetching)` where `previous` is the previously resolved data and `refetching` flags a manual refetch. Reactive reads inside it are <strong>not</strong> tracked as dependencies.
@param initialValue - The starting `.data` value before the first fetch resolves.

[Open Documentation](https://flux.kohl.gg/guide/concepts/async#creating-an-async-node)
]]
function Async.new<S, T>(source: any, fetcher: ((S?, T, any) -> T) | T?, initialValue: T?): Async<T>
	local src: any = source
	local fetch: any = fetcher
	local init: any = initialValue
	if type(fetch) ~= "function" then
		src, fetch, init = nil, source, fetcher
	end

	local self: any = setmetatable({
		data = new(init),
		error = new(nil :: string?),
		loading = new(false),
		state = nil :: any,
		_resolved = new(false),
		_effect = nil :: any,
		_src = src,
		_fetcher = fetch,
		_fetchId = 0,
	}, Async)

	self.state = new(function(): AsyncState
		if self.error:get() ~= nil then
			return "errored"
		elseif self.loading:get() then
			return if self._resolved:get() then "refreshing" else "pending"
		elseif self._resolved:get() then
			return "ready"
		else
			return "unresolved"
		end
	end)

	self._effect = new(function()
		local input = readDep(src)
		if gatedOff(src, input) then
			self._fetchId += 1
			self.loading:set(false)
			self.error:set(nil)
			return
		end
		trigger(self, input, false)
	end, true)

	return self
end

--[[
Destroys the async node, cleaning up all resources.

[Open Documentation](https://flux.kohl.gg/guide/concepts/async)
]]
function Async.Destroy<T>(self: Async<T>)
	self.state:Destroy()
	self._resolved:Destroy()
	self.data:Destroy()
	self.error:Destroy()
	self.loading:Destroy()
	self._effect:Destroy()

	self._fetchId += 1

	-- Nil the fields but keep the shape intact, so a late refetch/mutate doesn't error
	self.data = nil :: any
	self.error = nil :: any
	self.loading = nil :: any
	self.state = nil :: any
	self._resolved = nil :: any
	self._effect = nil :: any
	self._src = nil
	self._fetcher = nil
end

--[[
Optimistically writes `data` and invalidates any in-flight fetch.

[Open Documentation](https://flux.kohl.gg/guide/concepts/async)
]]
function Async.mutate<T>(self: Async<T>, value: T)
	if self._effect == nil then
		return
	end
	self._fetchId += 1
	self.loading:set(false)
	self.error:set(nil)
	self._resolved:set(true)
	self.data:set(value)
end

--[[
Re-runs the fetcher with the current source value without writing the source node.
An optional `refetching` payload is forwarded to the fetcher (defaults to `true`).

[Open Documentation](https://flux.kohl.gg/guide/concepts/async)
]]
function Async.refetch<T>(self: Async<T>, refetching: any?)
	if self._effect == nil then
		return
	end
	local src = self._src
	local input = rawDep(src)
	if gatedOff(src, input) then
		return
	end
	trigger(self, input, if refetching == nil then true else refetching)
end

return table.freeze(Async)
