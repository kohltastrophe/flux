--!strict

export type Cleanable = () -> () | Instance | RBXScriptConnection | any | thread | { [number]: Cleanable }

local Compat = require("./Compat")

local warn = Compat.warn
local task = Compat.task
local traceback = Compat.traceback

local function invoke(fn: any, arg: any?)
	local ok, err = xpcall(fn, traceback, arg)
	if ok == false then
		warn("Cleanup error:", err)
	end
end

local Clean: (obj: Cleanable) -> ()

local function cleanTable(obj: any)
	if type(obj.Destroy) == "function" then
		local inst: any = obj
		inst:Destroy()
	elseif type(obj.destroy) == "function" then
		local inst: any = obj
		inst:destroy()
	elseif type(obj.Disconnect) == "function" then
		local inst: any = obj
		inst:Disconnect()
	elseif type(obj.disconnect) == "function" then
		local inst: any = obj
		inst:disconnect()
	elseif obj[1] ~= nil then
		for _, subtask in obj do
			Clean(subtask)
		end
	end
end

--[[
Recursively disposes a `Cleanable`, the same teardown that runs when a scope is destroyed. Call it to
clean up something by hand.
A Roblox [`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) is `Destroy`ed, an
[`RBXScriptConnection`](https://create.roblox.com/docs/reference/engine/datatypes/RBXScriptConnection) is
`Disconnect`ed, a suspended thread is cancelled, and a function is invoked. A table is cleaned by its
`Destroy`/`destroy`/`Disconnect`/`disconnect` method if present, otherwise treated as a nested array and each element cleaned in turn.
Errors during cleanup are caught and warned, never re-raised.

[Open Documentation](https://flux.kohl.gg/guide/concepts/scopes#manual-cleanup-with-flux-clean)
]]
function Clean(obj: Cleanable)
	local t = typeof(obj)
	if t == "Instance" then
		pcall(game.Destroy, obj :: Instance)
	elseif t == "RBXScriptConnection" then
		if obj.Connected then
			obj:Disconnect()
		end
	elseif t == "table" then
		invoke(cleanTable, obj)
	elseif t == "function" then
		invoke(obj)
	elseif t == "thread" then
		if coroutine.status(obj :: thread) == "suspended" then
			pcall(task.cancel, obj :: thread)
		end
	end
end

return Clean
