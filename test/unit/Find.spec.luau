--!nonstrict
local IS_ROBLOX = game ~= nil

local Flux
local sert
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Flux = require(ReplicatedStorage:WaitForChild("Flux")) :: any
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
else
	Flux = require("../../src") :: any
	sert = require("../sert") :: any
end

local test = sert.test
local rtest = sert.rtest
local expect = sert
local Find = Flux.Find

test("find.parent · query packed for Edit's warnings (expected warn)", function()
	local props = { Name = "target" }
	local sel = Find.Parent("Inner.Frame")(props)
	expect(sel[1] == Find.Symbol and sel[3] == props and sel[4] == "Inner.Frame", "packs query for warnings")
	-- exercise the selector-miss warn end-to-end: a fake instance with no Parent
	local fake = { Parent = nil }
	expect((pcall(function()
		Flux.edit(fake)({ sel })
	end)) == true, "selector miss warns without erroring")
end)

-- Find.Path wraps a plain function, so sel[2] is the traversal itself in both
-- runtimes; drive it directly with fake instances for headless coverage.
local walkPath = Find.Path("")({})[2]

local function fakeInstance(name, parent)
	local inst = { Name = name, Parent = parent, _children = {} }
	function inst.FindFirstChild(self, childName)
		for _, child in self._children do
			if child.Name == childName then
				return child
			end
		end
		return nil
	end
	if parent then
		table.insert(parent._children, inst)
	end
	return inst
end

test("find.path · walks dot-separated child names", function()
	local root = fakeInstance("Root")
	local a = fakeInstance("A", root)
	local b = fakeInstance("B", a)
	fakeInstance("Decoy", root)

	expect(walkPath(root, "A.B") == b, "descends two named segments")
	expect(walkPath(root, "A") == a, "resolves a single segment")
	expect(walkPath(root, "A.Missing") == nil, "returns nil when a segment misses")
	expect(walkPath(root, "Missing.B") == nil, "returns nil when the first segment misses")
end)

test("find.path · Parent and ^ segments climb, empty segments are skipped", function()
	local root = fakeInstance("Root")
	local a = fakeInstance("A", root)
	local b = fakeInstance("B", a)

	expect(walkPath(b, "Parent") == a, "'Parent' climbs one level")
	expect(walkPath(b, "^.^") == root, "'^' chains climb multiple levels")
	expect(walkPath(b, "^.B") == b, "climb then descend round-trips")
	expect(walkPath(root, "^") == nil, "climbing past a nil Parent returns nil")
	expect(walkPath(root, "") == root, "empty path resolves to the instance itself")
	expect(walkPath(root, ".A..B.") == b, "stray dots are skipped, not treated as misses")
end)

test("find.path · query packed for Edit's warnings", function()
	local props = { Name = "target" }
	local sel = Find.Path("Inner.Frame")(props)
	expect(sel[1] == Find.Symbol and sel[3] == props and sel[4] == "Inner.Frame", "packs query for warnings")
end)

rtest("find.path · resolves a nested path end-to-end via Flux.edit", function()
	local root = Instance.new("Folder")
	local a = Instance.new("Frame")
	a.Name = "A"
	a.Parent = root
	local b = Instance.new("Frame")
	b.Name = "B"
	b.Parent = a

	Flux.edit(root)({ Find.Path("A.B")({ LayoutOrder = 8 }) })
	expect(b.LayoutOrder == 8, "Find.Path resolved the nested child and applied props")

	Flux.edit(b)({ Find.Path("^.^.A")({ LayoutOrder = 2 }) })
	expect(a.LayoutOrder == 2, "Find.Path climbed with ^ and descended again")
	root:Destroy()
end)

rtest("find.child · FindFirstChild matches named child and applies props", function()
	local root = Instance.new("Folder")
	local child = Instance.new("Frame")
	child.Name = "Target"
	child.Parent = root
	local decoy = Instance.new("Frame")
	decoy.Name = "Other"
	decoy.Parent = root

	Flux.edit(root)({ Find.Child("Target")({ LayoutOrder = 7 }) })

	expect(child.LayoutOrder == 7, "Find.Child resolved the named child and applied props")
	expect(decoy.LayoutOrder == 0, "Find.Child did not touch the non-matching child")
	root:Destroy()
end)

rtest("find.childClass · FindFirstChildOfClass matches by exact class", function()
	local root = Instance.new("Folder")
	local label = Instance.new("TextLabel")
	label.Parent = root
	local frame = Instance.new("Frame")
	frame.Parent = root

	Flux.edit(root)({ Find.ChildClass("TextLabel")({ LayoutOrder = 3 }) })

	expect(label.LayoutOrder == 3, "Find.ChildClass resolved the exact-class child")
	expect(frame.LayoutOrder == 0, "Find.ChildClass ignored the other-class child")
	root:Destroy()
end)

rtest("find.childIsA · FindFirstChildWhichIsA matches by class inheritance", function()
	local root = Instance.new("Folder")
	-- A TextButton IsA GuiObject/GuiButton but is NOT class "Frame";
	-- ChildIsA("GuiButton") must still match it where ChildClass would not.
	local button = Instance.new("TextButton")
	button.Parent = root

	Flux.edit(root)({ Find.ChildIsA("GuiButton")({ LayoutOrder = 5 }) })

	expect(button.LayoutOrder == 5, "Find.ChildIsA matched a subclass instance via IsA")
	root:Destroy()
end)

rtest("find.ancestor · FindFirstAncestor matches named ancestor", function()
	local grand = Instance.new("Folder")
	grand.Name = "Grand"
	local parent = Instance.new("Folder")
	parent.Name = "Mid"
	parent.Parent = grand
	local leaf = Instance.new("Frame")
	leaf.Parent = parent

	Flux.edit(leaf)({ Find.Ancestor("Grand")({ Name = "Renamed" }) })

	expect(grand.Name == "Renamed", "Find.Ancestor resolved the named ancestor and applied props")
	expect(parent.Name == "Mid", "Find.Ancestor did not touch the nearer ancestor")
	grand:Destroy()
end)

rtest("find.ancestorClass · FindFirstAncestorOfClass matches by exact class", function()
	local screen = Instance.new("ScreenGui")
	local mid = Instance.new("Folder")
	mid.Parent = screen
	local leaf = Instance.new("Frame")
	leaf.Parent = mid

	Flux.edit(leaf)({ Find.AncestorClass("ScreenGui")({ Enabled = false }) })

	expect(screen.Enabled == false, "Find.AncestorClass resolved the exact-class ancestor")
	screen:Destroy()
end)

rtest("find.ancestorIsA · FindFirstAncestorWhichIsA matches by inheritance", function()
	-- A ScreenGui IsA LayerCollector/GuiBase2d but its class name is "ScreenGui".
	local screen = Instance.new("ScreenGui")
	local mid = Instance.new("Folder")
	mid.Parent = screen
	local leaf = Instance.new("Frame")
	leaf.Parent = mid

	Flux.edit(leaf)({ Find.AncestorIsA("LayerCollector")({ Enabled = false }) })

	expect(screen.Enabled == false, "Find.AncestorIsA matched the ancestor via IsA")
	screen:Destroy()
end)

rtest("find.descendant · FindFirstDescendant matches deep named descendant", function()
	local root = Instance.new("Folder")
	local mid = Instance.new("Folder")
	mid.Parent = root
	local deep = Instance.new("Frame")
	deep.Name = "Deep"
	deep.Parent = mid

	-- FindFirstDescendant is FFlag-gated and throws where off (Find.resolve has no
	-- pcall, so it'd propagate out of edit); only assert where the method is live
	local descendantAvailable = pcall(function()
		return Instance.new("Folder"):FindFirstDescendant("x")
	end)
	if not descendantAvailable then
		return
	end

	-- FindFirstDescendant requires a recursive descendant (not a direct child).
	Flux.edit(root)({ Find.Descendant("Deep")({ LayoutOrder = 9 }) })

	expect(deep.LayoutOrder == 9, "Find.Descendant resolved a nested named descendant")
	root:Destroy()
end)

rtest("find.queryFirst · QueryDescendants returns first match", function()
	local root = Instance.new("Folder")
	local a = Instance.new("Frame")
	a.Name = "Boxed"
	a.Parent = root
	local b = Instance.new("Frame")
	b.Name = "Boxed"
	b.Parent = root

	-- QueryFirst takes QueryDescendants(query)[1]; exactly one instance is applied.
	-- A bare token in QueryDescendants is a CLASS filter; `#` matches by Name.
	Flux.edit(root)({ Find.QueryFirst("#Boxed")({ LayoutOrder = 4 }) })

	local touched = (a.LayoutOrder == 4 and 1 or 0) + (b.LayoutOrder == 4 and 1 or 0)
	expect(touched == 1, "Find.QueryFirst applied props to exactly one (the first) match")
	root:Destroy()
end)

rtest("find.query · QueryDescendants applies to every match (multi-apply path)", function()
	local root = Instance.new("Folder")
	local a = Instance.new("Frame")
	a.Name = "Boxed"
	a.Parent = root
	local b = Instance.new("Frame")
	b.Name = "Boxed"
	b.Parent = root
	local c = Instance.new("Frame")
	c.Name = "Unboxed"
	c.Parent = root

	-- Query returns a table; Find.resolve must iterate and apply to each instance.
	-- A bare token in QueryDescendants is a CLASS filter; `#` matches by Name.
	Flux.edit(root)({ Find.Query("#Boxed")({ LayoutOrder = 6 }) })

	expect(a.LayoutOrder == 6, "Find.Query applied props to the first match")
	expect(b.LayoutOrder == 6, "Find.Query applied props to the second match (multi-apply)")
	expect(c.LayoutOrder == 0, "Find.Query did not touch the non-matching instance")
	root:Destroy()
end)

return {}
