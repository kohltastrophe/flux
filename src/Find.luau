--!strict

local Compat = require("./Compat")
local Type = require("./Type")

local warn = Compat.warn

local Symbol = table.freeze({ type = "Symbol" }) :: Type.Symbol

local function indexParent(instance: Instance)
	return instance.Parent
end

local function queryFirst(instance: Instance, query: string)
	return instance:QueryDescendants(query)[1]
end

local function selector(find: any): any
	local fn = if type(find) ~= "string" then find elseif Compat.isRoblox then (game :: any)[find] else nil
	return function(query: string)
		return function(properties: Type.Map<any>)
			return { Symbol, fn, properties, query }
		end
	end
end

type Fallback<Name> = index<Type.Editable & { [string]: Instance }, Name>

export type ClassSelector = <T>(className: T | keyof<Type.Editable>) -> (Type.EditProperties<Fallback<T>>) -> Selection
export type Selector = <T>(name: T & Instance & string) -> (Type.EditProperties<T>) -> Selection

local module = {
	Symbol = Symbol,
	--[[
	Selects the first ancestor named `name` via
	[`Instance:FindFirstAncestor`](https://create.roblox.com/docs/reference/engine/classes/Instance#FindFirstAncestor),
	then applies the property table to it. Use to reach an
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) above the hydrated element
	in the tree.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#available-selectors)
	]]
	Ancestor = selector("FindFirstAncestor") :: Selector,
	--[[
	Selects the first ancestor of class `className` via
	[`Instance:FindFirstAncestorOfClass`](https://create.roblox.com/docs/reference/engine/classes/Instance#FindFirstAncestorOfClass),
	then applies the property table to that matched
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance). Matches the exact
	`ClassName`.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#available-selectors)
	]]
	AncestorClass = selector("FindFirstAncestorOfClass") :: ClassSelector,
	--[[
	Selects the first ancestor whose class is or inherits `className` via
	[`Instance:FindFirstAncestorWhichIsA`](https://create.roblox.com/docs/reference/engine/classes/Instance#FindFirstAncestorWhichIsA),
	then applies the property table. Unlike `AncestorClass`, this honors the
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) inheritance chain.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#available-selectors)
	]]
	AncestorIsA = selector("FindFirstAncestorWhichIsA") :: ClassSelector,
	--[[
	Selects the first child named `name` via
	[`Instance:FindFirstChild`](https://create.roblox.com/docs/reference/engine/classes/Instance#FindFirstChild),
	then applies the property table to it. The most common selector for reaching a named
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) one level down.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#instance-selectors-flux-find)
	]]
	Child = selector("FindFirstChild") :: Selector,
	--[[
	Selects the first child of class `className` via
	[`Instance:FindFirstChildOfClass`](https://create.roblox.com/docs/reference/engine/classes/Instance#FindFirstChildOfClass),
	then applies the property table to that matched
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance). Matches the exact
	`ClassName`.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#available-selectors)
	]]
	ChildClass = selector("FindFirstChildOfClass") :: ClassSelector,
	--[[
	Selects the first child whose class is or inherits `className` via
	[`Instance:FindFirstChildWhichIsA`](https://create.roblox.com/docs/reference/engine/classes/Instance#FindFirstChildWhichIsA),
	then applies the property table. Unlike `ChildClass`, this honors the
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) inheritance chain.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#available-selectors)
	]]
	ChildIsA = selector("FindFirstChildWhichIsA") :: ClassSelector,
	--[[
	Selects the first descendant named `name` via
	[`Instance:FindFirstDescendant`](https://create.roblox.com/docs/reference/engine/classes/Instance#FindFirstDescendant),
	then applies the property table to it. Searches the entire subtree, not just direct children of the
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance).

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#instance-selectors-flux-find)
	]]
	Descendant = selector("FindFirstDescendant") :: Selector,
	--[[
	Selects the hydrated element's [`Instance.Parent`](https://create.roblox.com/docs/reference/engine/classes/Instance#Parent),
	then applies the property table to it. Use to reach one level up the tree without naming the parent.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#instance-selectors-flux-find)
	]]
	Parent = selector(indexParent) :: Selector,
	--[[
	Selects <strong>every</strong> descendant matching a Roblox path query via
	[`Instance:QueryDescendants`](https://create.roblox.com/docs/reference/engine/classes/Instance#QueryDescendants),
	applying the property table to each matched
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance). Fan out one property table
	across many elements at once.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#instance-selectors-flux-find)
	]]
	Query = selector("QueryDescendants") :: Selector,
	--[[
	Selects only the <strong>first</strong> descendant matching a Roblox path query via
	[`Instance:QueryDescendants`](https://create.roblox.com/docs/reference/engine/classes/Instance#QueryDescendants),
	then applies the property table to that single
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance). The single-match counterpart
	to `Query`.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/hydration#instance-selectors-flux-find)
	]]
	QueryFirst = selector(queryFirst) :: Selector,
}

function module.resolve(applied: { any }, instance: Instance, apply: (Instance, Type.Map<any>) -> ())
	local result = applied[2](instance, applied[4])
	local properties = applied[3]

	if typeof(result) == "Instance" then
		apply(result, properties)
	elseif typeof(result) == "table" then
		for _, item in result do
			if typeof(item) == "Instance" then
				apply(item, properties)
			else
				warn(`Instance expected for query {applied[4]}, got {typeof(item)}`)
			end
		end
	else
		warn(`Instance expected for query {applied[4]}, got {typeof(result)}`)
	end
end

return table.freeze(module)
