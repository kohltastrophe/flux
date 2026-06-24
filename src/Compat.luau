--!strict

-- Roblox/headless (vanilla Luau CLI) runtime compat: `warn` and `task` only
-- exist in Roblox; each fallback is the closest semantic the bare VM offers.

local warnShim = warn or print

local function resume(fnOrThread: any, ...: any): thread
	local thread = if type(fnOrThread) == "thread" then fnOrThread else coroutine.create(fnOrThread)
	coroutine.resume(thread, ...)
	return thread
end

local taskShim = task
	or {
		spawn = resume,
		defer = resume,
		cancel = function(thread: thread)
			coroutine.close(thread)
		end,
	} :: any

local function traceback(err: any, level: number?): any
	return if type(err) == "string" then debug.traceback(err, level) else err
end

return table.freeze({
	isRoblox = game ~= nil,
	traceback = traceback,
	warn = warnShim,
	task = taskShim,
})
