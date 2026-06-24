--!strict

local Graph = require("./Graph")

local new = Graph.new
local readDep = Graph.readDep
local set = Graph.Node.set
local untrack = Graph.untrack
local retrack = Graph.retrack
local scope = Graph.scope
local withOwner = Graph.withOwner

type Node<T> = Graph.Node<T>

local DEFAULT_SYMBOL = table.freeze({ type = "SwitchDefault" }) :: any

local Conditional = {}

--[[
Sentinel key for `Flux.switch` maps: the factory stored under this key mounts whenever the source value matches no
other key, the conditional's catch-all branch. Unmatched values share this <em>stable</em> key,
so switching between two different unmatched values does not rebuild the branch.

[Open Documentation](https://flux.kohl.gg/guide/concepts/conditionals#a-default-branch)
]]
Conditional.default = DEFAULT_SYMBOL

local function mount(source: any, select: (value: any) -> (any, ((value: () -> any) -> any)?)): Node<any>
	local activeKey: any = nil
	local activeBranch: Node<any>? = nil
	local hasMounted = false

	local output = new(nil :: any)

	local function valueOf()
		return readDep(source)
	end

	local driver = new(function()
		local value = readDep(source)
		local key, factory = select(value)

		if hasMounted and key == activeKey then
			return
		end
		hasMounted = true
		activeKey = key

		untrack()
		local previous = activeBranch
		activeBranch = nil
		if previous ~= nil then
			previous:Destroy()
		end

		if factory ~= nil then
			-- Mount the branch as a ROOT scope: withOwner(nil) keeps it off the driver's
			-- child list (the driver disposes its children every re-run), and scope() clears
			-- tracking so the factory's reads don't subscribe the driver. We destroy it
			-- ourselves on the next swap and on output destroy.
			local branch, result
			local ok, err = pcall(withOwner, nil :: any, function()
				branch, result = scope(function()
					return factory(valueOf)
				end)
			end)
			if ok then
				activeBranch = branch
				set(output, result)
			else
				-- scope() already tore down the partially-built branch before re-raising
				set(output, nil)
				hasMounted = false
				activeKey = nil
				retrack()
				error(err, 0)
			end
		else
			set(output, nil)
		end
		retrack()
	end, true)

	output:onDestroy(function()
		driver:Destroy()
		local branch = activeBranch
		activeBranch = nil
		if branch ~= nil then
			branch:Destroy()
		end
	end)

	Graph.onDestroy(function()
		output:Destroy()
	end)

	return output
end

Conditional._mount = mount

local function showSelect(component: (value: () -> any) -> any, fallback: ((value: () -> any) -> any)?, keyed: boolean?)
	return function(value: any): (any, ((value: () -> any) -> any)?)
		local factory = if value then component else fallback
		return (if keyed then value else not not value), factory
	end
end

local function switchSelect(map: { [any]: (value: () -> any) -> any })
	return function(value: any): (any, ((value: () -> any) -> any)?)
		local factory = map[value]
		if factory == nil then
			local default = map[DEFAULT_SYMBOL]
			if default ~= nil then
				return DEFAULT_SYMBOL, default
			end
		end
		return value, factory
	end
end

Conditional._showSelect = showSelect
Conditional._switchSelect = switchSelect

--[[
Mounts `component` while `condition` is truthy, swapping to `fallback` (if given) when it
turns falsy. The chosen factory runs once per mount in its own branch
[scope](https://flux.kohl.gg/guide/concepts/scopes) (the effects and cleanups it registers are
torn down automatically on the next swap) and receives a `value` accessor for the live
`condition` value. Returns a
[node](https://flux.kohl.gg/guide/concepts/signals) usable at a numeric
index of [`Flux.new`](https://flux.kohl.gg/guide/roblox/creation#the-flux-new-function) /
[`Flux.edit`](https://flux.kohl.gg/guide/roblox/hydration#the-flux-edit-function).
@param condition - The reactive source; re-runs only when its truthiness flips, not on every change.
@param component - Branch factory mounted while `condition` is truthy; receives `(value)`.
@param fallback - Optional branch factory mounted while `condition` is falsy; receives `(value)`.

[Open Documentation](https://flux.kohl.gg/guide/concepts/conditionals#showing-one-of-two-branches)
]]
function Conditional.show<T, F>(
	condition: Node<any> | (() -> any) | any,
	component: (value: () -> any) -> T,
	fallback: ((value: () -> any) -> F)?
): Node<any>
	return mount(condition, showSelect(component, fallback))
end

--[[
Identity-keyed variant of [`Flux.show`](https://flux.kohl.gg/guide/concepts/conditionals#keyed-show): instead
of rebuilding only when `condition`'s truthiness flips, it rebuilds whenever the value's <em>identity</em>
changes, so swapping one truthy value for another remounts the branch with fresh state. The chosen factory
runs in its own branch [scope](https://flux.kohl.gg/guide/concepts/scopes) and receives a `value` accessor; since the
value is fixed for the branch's lifetime, reading `value()` in the factory body yields it directly. Mirrors
SolidJS's <code>&lt;Show keyed&gt;</code>.
@param condition - The reactive source; re-runs whenever its value changes identity, not just truthiness.
@param component - Branch factory mounted while `condition` is truthy; receives `(value)`.
@param fallback - Optional branch factory mounted while `condition` is falsy; receives `(value)`.

[Open Documentation](https://flux.kohl.gg/guide/concepts/conditionals#keyed-show)
]]
function Conditional.showKeyed<T, F>(
	condition: Node<any> | (() -> any) | any,
	component: (value: () -> any) -> T,
	fallback: ((value: () -> any) -> F)?
): Node<any>
	return mount(condition, showSelect(component, fallback, true))
end

--[[
Mounts the branch keyed by `source`'s current value. Curries: pass the reactive
`source`, then a map of <code>value → factory</code>; the matching factory runs once in its own
branch [scope](https://flux.kohl.gg/guide/concepts/scopes) and receives a `value`
accessor. For a keyed branch `value()` is the matched key (fixed for the branch's lifetime); under
`Flux.default` (which mounts for any unmatched value), `value()` tracks the live unmatched value.
Returns a [node](https://flux.kohl.gg/guide/concepts/signals)
usable at a numeric index of [`Flux.new`](https://flux.kohl.gg/guide/roblox/creation#the-flux-new-function) /
[`Flux.edit`](https://flux.kohl.gg/guide/roblox/hydration#the-flux-edit-function).

[Open Documentation](https://flux.kohl.gg/guide/concepts/conditionals#switching-between-many-branches)
]]
function Conditional.switch<K>(source: Node<K> | (() -> K) | K)
	return function<T>(map: { [K]: (value: () -> K) -> T }): Node<T?>
		return mount(source, switchSelect(map :: any)) :: any
	end
end

return table.freeze(Conditional)
