--!strict
--!native
--!optimize 2

local Graph = require("./Graph")

local new = Graph.new

export type Async<T> = {
	data: Graph.Node<T?>,
	error: Graph.Node<string?>,
	loading: Graph.Node<boolean>,
	Destroy: (self: Async<T>) -> (),
	_effect: Graph.Node<any>,
	_fetchId: number,
}

local function destroy<T>(self: Async<T>)
	self.data:Destroy()
	self.error:Destroy()
	self.loading:Destroy()
	self._effect:Destroy()
	table.clear(self :: any)
end

local function update<T>(self: Async<T>, fn: any, currentId: number)
	local success, result = pcall(fn)

	-- Only update state if this is still the most recent fetch
	if currentId == self._fetchId then
		self.loading:set(false)
		if success then
			self.data:set(result)
		else
			self.error:set(tostring(result))
		end
	end
end

--- Creates a non-blocking asynchronous reactive node.
--- @param fn: () -> T - Asynchronous function. Dependencies must be read BEFORE the first yield.
--- @param initialValue: T? - The starting value before the first fetch completes[cite: 4].
--- @return Async<T>
local function async<T>(fn: () -> T, initialValue: T?): Async<T>
	local self: any = {
		data = new(initialValue),
		error = new(nil :: string?),
		loading = new(false),
		Destroy = destroy,
		_effect = nil :: any,
		_fetchId = 0,
	}

	self._effect = new(function()
		self._fetchId += 1
		local currentId = self._fetchId

		self.loading:set(true)
		self.error:set(nil)

		task.spawn(update, self, fn, currentId)
	end, true)

	return self
end

return async
