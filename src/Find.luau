local Type = require("./Type")

local Symbol = table.freeze({ type = "Symbol" }) :: Type.Symbol

local module = {
	Symbol = Symbol,
}

local function indexParent(instance: Instance)
	return instance.Parent
end

local function queryFirst(instance: Instance, query: string)
	return instance:QueryDescendants(query)[1]
end

--stylua: ignore start
module.Ancestor = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.FindFirstAncestor, properties, query } end
end :: any) :: Type.Selector

module.AncestorClass = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.FindFirstAncestorOfClass, properties, query } end
end :: any) :: Type.ClassSelector

module.AncestorIsA = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.FindFirstAncestorWhichIsA, properties, query } end
end :: any) :: Type.ClassSelector

module.Child = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.FindFirstChild, properties, query } end
end :: any) :: Type.Selector

module.ChildClass = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.FindFirstChildOfClass, properties, query } end
end :: any) :: Type.ClassSelector

module.ChildIsA = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.FindFirstChildWhichIsA, properties, query } end
end :: any) :: Type.ClassSelector

module.Descendant = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.FindFirstDescendant, properties, query } end
end :: any) :: Type.Selector

module.Parent = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, indexParent, properties } end
end :: any) :: Type.Selector

module.Query = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, game.QueryDescendants, properties, query } end
end :: any) :: Type.Selector

module.QueryFirst = (function(query: string)
	return function(properties: Type.Map<any>) return { Symbol, queryFirst, properties, query } end
end :: any) :: Type.Selector
--stylua: ignore end

return module
