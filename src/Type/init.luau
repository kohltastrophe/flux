local Graph = require("./Graph")
local Instances = require("@self/Instances")

export type Action = () -> ()
export type Consumer = (...any) -> ()
export type Producer = () -> ...any
export type Function = (...any) -> ...any

export type Map<T> = { [T]: any }
export type Symbol = { read type: "Symbol" }

type __ATTR = "__ATTR"
type __CLEAN = "__CLEAN"
type __EVENT = "__EVENT"
type __REF = "__REF"
type __TAG = "__TAG"

type GraphNode = Graph.Node<any>

export type function Properties(instance: type?)
	local result = types.newtable(nil, { index = types.number, readresult = types.any })
	local events = types.newtable(nil, { index = types.number, readresult = types.never })

	while instance do
		for i, v in instance:properties() do
			local connector = v.read and v.read.tag == "table" and v.read:readproperty(types.singleton("Connect"))
			if connector then
				local params = connector:parameters().head
				if not params then
					continue
				end
				local listener = params[2]
				if not listener then
					continue
				end
				result:setproperty(i, types.optional(listener))
				events:setproperty(i, types.optional(listener))
			elseif v.write then
				local t =
					types.optional(types.unionof(v.write, types.newfunction({}, { head = { v.write } }), GraphNode))
				result:setproperty(i, t)
			end
		end

		instance = instance:readparent()
	end

	local attrEventIndexer = { index = types.string, readresult = types.newfunction({ head = { types.any } }) }
	events:setproperty(__ATTR, types.optional(types.newtable(nil, attrEventIndexer)))

	result:setproperty(__ATTR, types.optional(types.newtable(nil, { index = types.string, readresult = types.any })))
	result:setproperty(__TAG, types.optional(types.newtable(nil, { index = types.number, readresult = types.any })))
	result:setproperty(__CLEAN, types.optional(types.newtable(nil, { index = types.number, readresult = types.any })))
	result:setproperty(__EVENT, types.optional(events))
	result:setproperty(__REF, types.optional(types.unionof(Consumer, GraphNode))) -- Consumer or Flux.State type

	return result
end

export type Selection = { Symbol | (any) -> Selection | { any } }

type Find_Ancestor = "Find.Ancestor"
type Find_AncestorClass = "Find.AncestorClass"
type Find_AncestorIsA = "Find.AncestorIsA"
type Find_Child = "Find.Child"
type Find_ChildClass = "Find.ChildClass"
type Find_ChildIsA = "Find.ChildIsA"
type Find_Descendant = "Find.Descendant"
type Find_Parent = "Find.Parent"
type Find_Query = "Find.Query"
type Find_QueryFirst = "Find.QueryFirst"

export type function EditProperties(instance: type?)
	local result = Properties(instance)
	local t = types.optional(Selection)

	result:setproperty(Find_Ancestor, t)
	result:setproperty(Find_AncestorClass, t)
	result:setproperty(Find_AncestorIsA, t)
	result:setproperty(Find_Child, t)
	result:setproperty(Find_ChildClass, t)
	result:setproperty(Find_ChildIsA, t)
	result:setproperty(Find_Descendant, t)
	result:setproperty(Find_Parent, t)
	result:setproperty(Find_Query, t)
	result:setproperty(Find_QueryFirst, t)

	return result
end

export type Creatable = Instances.Creatable
export type Editable = Instances.Editable

export type Resolve<Name> = index<Creatable, Name>

return nil
