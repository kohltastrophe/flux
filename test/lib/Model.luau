--!nonstrict
local env = require("./env")
local Flux = env.Flux

local Model = {}

function Model.isolated(body: (owners: { any }) -> ())
	assert(type(body) == "function", "Model.isolated expects a function")
	local owners = {}
	local ok, err = pcall(body, owners)
	for index = #owners, 1, -1 do
		owners[index]:Destroy()
	end
	Flux.flush()
	if not ok then
		error(err, 0)
	end
end

function Model.ops(g: any, weights: { { any } }): { any }
	return g:list(function(g)
		return g:weighted(weights)
	end)
end

function Model.reader(owner: any, effect: boolean, read: () -> any): any
	local reader = { effect = effect, runs = 0, checkedRuns = 0, value = nil, node = nil }
	Flux.withOwner(owner, function()
		reader.node = (if effect then Flux.effect else Flux.computed)(function()
			reader.runs += 1
			reader.value = read()
			return reader.value
		end)
	end)
	if not effect then
		reader.node:get()
	end
	return reader
end

function Model.float(g: any, lo: number, hi: number): number
	return lo + (hi - lo) * g:int(0, 10000) / 10000
end

return table.freeze(Model)
