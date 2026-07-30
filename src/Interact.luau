--!strict

local Graph = require("./Graph")

local isNode = Graph.isNode

export type Group = {
	activate: (self: Group, state: Graph.Node<boolean>) -> (),
	deactivate: (self: Group, state: Graph.Node<boolean>) -> (),
	toggle: (self: Group, state: Graph.Node<boolean>) -> (),
	clear: (self: Group) -> (),
	_active: Graph.Node<boolean>?,
}

local GroupMT = {}
GroupMT.__index = GroupMT

-- Surfaces member mistakes (a plain value, a computed's function) at the caller's line.
local function assertState(state: any)
	if not isNode(state) then
		error(`Exclusive group expected a boolean Node, got {typeof(state)}`, 3)
	end
end

--[[
Activates `state` (sets it `true`) and deactivates the group's previously active
[node](https://flux.kohl.gg/guide/concepts/signals), if different. Both writes land before the
next [flush](https://flux.kohl.gg/guide/tips/testing#deterministic-effects-with-flux-flush), so effects
only ever observe the settled result.

[Open Documentation](https://flux.kohl.gg/guide/utilities/interact#exclusive-groups)
]]
function GroupMT.activate(self: Group, state: Graph.Node<boolean>)
	assertState(state)
	local previous = self._active
	if previous ~= nil and previous ~= state then
		previous:set(false)
	end
	self._active = state
	state:set(true)
end

--[[
Deactivates `state` (sets it `false`), releasing the group's active slot when `state` holds it.
Deactivating a member that is not the active one still sets it `false`.

[Open Documentation](https://flux.kohl.gg/guide/utilities/interact#exclusive-groups)
]]
function GroupMT.deactivate(self: Group, state: Graph.Node<boolean>)
	assertState(state)
	if self._active == state then
		self._active = nil
	end
	state:set(false)
end

--[[
Flips `state`: activates it when inactive (closing the previously active member), deactivates it
when active. The read is untracked, so toggling inside an effect never subscribes it.

[Open Documentation](https://flux.kohl.gg/guide/utilities/interact#exclusive-groups)
]]
function GroupMT.toggle(self: Group, state: Graph.Node<boolean>)
	assertState(state)
	if state:peek() then
		self:deactivate(state)
	else
		self:activate(state)
	end
end

--[[
Deactivates whichever member is active, if any: the outside-click dismiss for an open floating
menu, without knowing which menu it is.

[Open Documentation](https://flux.kohl.gg/guide/utilities/interact#exclusive-groups)
]]
function GroupMT.clear(self: Group)
	local active = self._active
	if active ~= nil then
		self._active = nil
		active:set(false)
	end
end

--[[
Creates an exclusive group: at most one boolean [node](https://flux.kohl.gg/guide/concepts/signals)
is active per group, so activating a member deactivates the previous one. One group per concern
(open menus, hovered controls, modal dialogs) replaces the "close everything else first"
bookkeeping those UIs otherwise need.

[Open Documentation](https://flux.kohl.gg/guide/utilities/interact#exclusive-groups)
]]
local function exclusive(): Group
	return setmetatable({}, GroupMT) :: any
end

--[[
Whether the point `(x, y)` lies within `object`'s absolute bounds (inclusive, ignoring rotation).
Coordinates are inset-relative, matching `InputObject.Position` and `AbsolutePosition`.

[Open Documentation](https://flux.kohl.gg/guide/utilities/interact#pointin)
]]
local function pointIn(x: number, y: number, object: GuiObject): boolean
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	return x >= position.X and x <= position.X + size.X and y >= position.Y and y <= position.Y + size.Y
end

--[[
Whether input at `(x, y)` would be claimed by an `Active` gui (or `GuiButton`) rendered
<strong>above</strong> `object`, e.g. dropping a hover state while a floating menu covers the
control. Outside a `BasePlayerGui` (a plugin dock, a `SurfaceGui` in workspace) nothing can claim
the point, so this yields `false`.

[Open Documentation](https://flux.kohl.gg/guide/utilities/interact#sunk)
]]
local function sunk(x: number, y: number, object: GuiObject): boolean
	local root = object:FindFirstAncestorWhichIsA("BasePlayerGui")
	if root == nil then
		return false
	end
	for _, gui in root:GetGuiObjectsAtPosition(x, y) do
		if gui == object then
			break
		elseif gui.Active or gui:IsA("GuiButton") then
			return true
		end
	end
	return false
end

return table.freeze({
	exclusive = exclusive,
	pointIn = pointIn,
	sunk = sunk,
})
