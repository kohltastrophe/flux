--!strict

local Graph = require("./Graph")

local new = Graph.new
local untrack = Graph.untrack

--[[ Runs `handler` untracked to recover from `err`, re-raising the handler's own error (with its original message preserved) if it throws in turn. ]]
local function recover<T>(handler: (err: unknown) -> T, err: unknown): T
	local ok, result
	untrack(function()
		ok, result = pcall(handler, err)
	end)
	if ok then
		return result
	end
	error(result, 0)
end

--[[
Creates a [computed](https://flux.kohl.gg/guide/concepts/computeds) that evaluates `tryFn` and, if it throws,
falls back to `fallback`, re-running and recovering automatically whenever its tracked dependencies change.
`fallback` may be a static value or a recovery function receiving the caught error; a recovery function runs
[untracked](https://flux.kohl.gg/guide/concepts/tracking) so it cannot accidentally subscribe to extra
dependencies. Pass `equals` to customize change detection (default `==`).

[Open Documentation](https://flux.kohl.gg/guide/tips/errors#structured-error-handling-flux-safe-and-flux-catch)
]]
local function safe<T>(
	tryFn: () -> T,
	fallback: T | (err: unknown) -> T,
	equals: ((a: T, b: T) -> boolean)?
): Graph.Node<T>
	return new(function()
		local ok, result = pcall(tryFn)
		if ok then
			return result
		end
		if type(fallback) == "function" then
			return recover(fallback, result)
		end
		return fallback
	end, nil, equals)
end

--[[
Synchronously runs `fn` and, if it throws, recovers with `handler`: a plain try/recover with no reactive
node created. Both `fn` and `handler` run [untracked](https://flux.kohl.gg/guide/concepts/tracking), so reads
inside them don't subscribe the surrounding [computed](https://flux.kohl.gg/guide/concepts/computeds) or
[effect](https://flux.kohl.gg/guide/concepts/effects). If `handler` itself throws, that error propagates.

[Open Documentation](https://flux.kohl.gg/guide/tips/errors#structured-error-handling-flux-safe-and-flux-catch)
]]
local function catch<T>(fn: () -> T, handler: (err: unknown) -> T): T
	local ok, result
	untrack(function()
		ok, result = pcall(fn)
	end)
	if ok then
		return result
	end
	return recover(handler, result)
end

return table.freeze({
	safe = safe,
	catch = catch,
})
