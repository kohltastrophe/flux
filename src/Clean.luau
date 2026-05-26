--!strict
--!optimize 2
export type Cleanable = () -> () | Instance | RBXScriptConnection | any | thread | { [number]: Cleanable }

--- Cleans up an object, disconnecting any connections and destroying any instances.
local function Clean(obj: Cleanable)
	local t = typeof(obj)
	if t == "Instance" then
		pcall(game.Destroy, obj :: Instance)
	elseif t == "RBXScriptConnection" then
		if obj.Connected then
			obj:Disconnect()
		end
	elseif t == "table" then
		if type(obj.Destroy) == "function" then
			local inst: any = obj
			inst:Destroy()
		elseif type(obj.destroy) == "function" then
			local inst: any = obj
			inst:destroy()
		elseif obj[1] ~= nil then
			for _, subtask in obj do
				Clean(subtask)
			end
		end
	elseif t == "function" then
		obj()
	elseif t == "thread" then
		if coroutine.status(obj :: thread) == "suspended" then
			task.cancel(obj :: thread)
		end
	end
end

return Clean
