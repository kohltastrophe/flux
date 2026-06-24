--!strict

export type Context<T> = {
	default: T,
	_current: T,
	get: (self: Context<T>) -> T,
	provide: <R>(self: Context<T>, value: T, fn: () -> R) -> R,
}

local Context = {}

--[[
Reads the current value: the innermost active `provide` on the call stack, falling back to the `default` when
none is active. Callable as `context:get()` or simply `context()`.

[Open Documentation](https://flux.kohl.gg/guide/concepts/context#providing-and-reading)
]]
function Context.get<T>(self: Context<T>): T
	return self._current
end

--[[
Runs `fn` with this context set to `value`, so any `get` reached during `fn` (no matter how deep) sees
`value`; the previous value is restored once `fn` returns. Returns whatever `fn` returns. Callable as
`context:provide(value, fn)` or simply `context(value, fn)`.

[Open Documentation](https://flux.kohl.gg/guide/concepts/context#providing-and-reading)
]]
function Context.provide<T, R>(self: Context<T>, value: T, fn: () -> R): R
	local previous = self._current
	self._current = value

	local ok, result = pcall(fn)

	self._current = previous

	if ok == false then
		error(result, 0)
	end

	return result
end

local ContextMetatable = {
	__index = Context,
	__call = function<T, R>(self: Context<T>, value: T?, fn: (() -> R)?): T | R
		return if fn == nil then Context.get(self) else Context.provide(self, value, fn)
	end,
}

--[[
Creates a dynamically-scoped value with the given `default`, read by any code running under a `provide`
without threading it through arguments. Outside any active provide, reads return `default`. Pair with
[component](https://flux.kohl.gg/guide/concepts/components)s to share theme, services, or the current user
down a tree.

[Open Documentation](https://flux.kohl.gg/guide/concepts/context#creating-a-context)
]]
local function new<T>(default: T): Context<T>
	return setmetatable({
		default = default,
		_current = default,
	}, ContextMetatable) :: any
end

return table.freeze({
	new = new,
})
