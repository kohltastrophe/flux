--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert, IS_ROBLOX = env.Flux, env.sert, env.IS_ROBLOX

local test = sert.test
local expect = sert
local settle = env.settle
local Instance = env.Instance
local workspace = env.workspace
local Bind = if IS_ROBLOX
	then require((game :: any).ReplicatedStorage.Flux.Bind) :: any
	else require("../../src/Bind") :: any
local expectError = sert.throws
local flush = Flux.flush

test("property · follows a property and an attribute via $ and _attr_, and stops when destroyed", function()
	local box = Instance.new("TextBox")
	box.Text = "a"
	box:SetAttribute("Health", 10)
	local text = Flux.property(box, "Text")
	local health = Flux.property(box, "$Health")
	local healthUnderscore = Flux.property(box, "_attr_Health")
	local terse = Flux(box, "Text")
	local terseAttr = Flux(box, "$Health")
	expect(
		text:get() == "a"
			and terse:get() == "a"
			and health:get() == 10
			and healthUnderscore:get() == 10
			and terseAttr:get() == 10,
		"seeded from the instance"
	)
	box.Text = "b"
	box:SetAttribute("Health", 5)
	settle()
	expect(
		text:get() == "b"
			and terse:get() == "b"
			and health:get() == 5
			and healthUnderscore:get() == 5
			and terseAttr:get() == 5,
		"follows changes"
	)
	text:Destroy()
	healthUnderscore:Destroy()
	terseAttr:Destroy()
	box.Text = "c"
	settle()
	expect(text:peek() ~= "c" and terse:get() == "c", "a destroyed node stops following")
	box:Destroy()
end)

test("property · follows an instance tag reactively via # and _tag_ prefixes", function()
	local frame = Instance.new("Frame")
	local other = Instance.new("Frame")
	frame:AddTag("PreExisting")
	frame.Parent = workspace
	other.Parent = workspace

	local hasEnemy = Flux.property(frame, "#Enemy")
	local hasEnemyUnderscore = Flux.property(frame, "_tag_Enemy")
	local viaCall = Flux(frame, "#Enemy")
	local hasPre = Flux.property(frame, "#PreExisting")
	expect(
		hasEnemy:get() == false and hasEnemyUnderscore:get() == false and viaCall:get() == false,
		"seeded with false when tag is absent"
	)
	expect(hasPre:get() == true, "seeded with true when tag is already present")

	other:AddTag("Enemy")
	settle()
	expect(hasEnemy:get() == false and hasEnemyUnderscore:get() == false, "tag added to another instance is ignored")

	frame:AddTag("Enemy")
	settle()
	expect(
		hasEnemy:get() == true and hasEnemyUnderscore:get() == true and viaCall:get() == true,
		"updates to true when tag is added"
	)

	frame.Parent = nil
	settle()
	expect(hasEnemy:get() == true, "unparenting an instance does not falsely clear its #Tag node")
	frame.Parent = workspace

	frame:RemoveTag("Enemy")
	settle()
	expect(
		hasEnemy:get() == false and hasEnemyUnderscore:get() == false and viaCall:get() == false,
		"updates to false when tag is removed"
	)

	hasEnemy:Destroy()
	hasEnemyUnderscore:Destroy()
	frame:AddTag("Enemy")
	settle()
	expect(hasEnemy:get() == nil and viaCall:get() == true, "destroyed tag node stops following")

	viaCall:Destroy()
	hasPre:Destroy()
	other:Destroy()
	frame:Destroy()

	local doomed = Instance.new("Frame")
	doomed.Parent = workspace
	local doomedTag = Flux.property(doomed, "#Enemy")
	expect(doomedTag:get() == false, "seeded before instance destroy")
	local cs = env.Compat.services.CollectionService
	local addedBefore = #cs:GetInstanceAddedSignal("Enemy")._listeners
	doomed:Destroy()
	expect(
		#cs:GetInstanceAddedSignal("Enemy")._listeners < addedBefore,
		"destroying instance disconnects CollectionService tag listeners"
	)
	doomedTag:Destroy()
end)

test("property & call · reject non-Instance, missing property, non-string or empty prefix names", function()
	expectError(function()
		Flux.property({} :: any, "Text")
	end, "expects an Instance")
	expectError(function()
		Flux(123, "Name")
	end, "only an Instance takes a property name")

	local box = Instance.new("TextBox")
	expectError(function()
		Flux(box)
	end, "expects a property")
	expectError(function()
		Flux(box, true)
	end, "expects a property")
	expectError(function()
		Flux.property(box, 5 :: any)
	end, "expects a property")
	expectError(function()
		Flux.property(box, "$")
	end, 'after "$" cannot be empty')
	expectError(function()
		Flux.property(box, "#")
	end, 'after "#" cannot be empty')
	expectError(function()
		Flux.property(box, "_attr_")
	end, 'after "_attr_" cannot be empty')
	expectError(function()
		Flux.property(box, "_tag_")
	end, 'after "_tag_" cannot be empty')
	box:Destroy()
end)

test("bind.to · a failing write is warned and the remaining bindings still apply", function()
	local holder = Instance.new("ObjectValue")
	holder.Name = "Holder"
	local label = Instance.new("TextLabel")
	local v = Flux(nil :: any)
	Bind.to(v, holder, "Value")
	Bind.to(v, label, "Tint", true)

	local red = env.Color3.new(1, 0, 0)
	local warned = env.warnings(function()
		v:set(red)
		flush()
	end)
	expect(#warned >= 1, "the failing write warned")
	expect(
		string.find(warned[1], 'failed to set property "Value" of Holder', 1, true) ~= nil,
		`with the instance and key: {warned[1]}`
	)
	expect(label:GetAttribute("Tint") == red, "the other write applied")

	local target = Instance.new("Folder")
	v:set(target)
	flush()
	expect(holder.Value == target, "binding keeps working after a failed write")

	holder:Destroy()
	label:Destroy()
	target:Destroy()
end)

test("bind.children · a stale disconnect doesn't sever the live binding, to another parent or the same one", function()
	for _, same in { false, true } do
		local screen = Instance.new("ScreenGui")
		local parentA = Instance.new("Frame")
		parentA.Parent = screen
		local parentB = if same then parentA else Instance.new("Frame")
		parentB.Parent = screen

		local c1 = Instance.new("Frame")
		local node = Flux.signal(c1)
		local discA = Bind.children(node, parentA)
		local discB = Bind.children(node, parentB)
		expect(c1.Parent == parentB, "rebound")

		discA()
		local c2 = Instance.new("Frame")
		node:set(c2)
		flush()
		expect(c2.Parent == parentB, `the live binding survives the stale unbind (same parent: {same})`)

		discB()
		local c3 = Instance.new("Frame")
		node:set(c3)
		flush()
		expect(c3.Parent == nil and c2.Parent == nil, `the current unbind still works (same parent: {same})`)
		screen:Destroy()
	end
end)

test("bind.to · a shared node keeps writing after the first binding's scope dies", function()
	local node = Flux.signal("one")
	local first, second = Instance.new("StringValue"), Instance.new("StringValue")
	local scopeA = Flux.scope(function()
		Bind.to(node, first, "Value")
	end)
	Bind.to(node, second, "Value")

	node:set("two")
	flush()
	expect(second.Value == "two", "binding written while scopeA is alive")

	scopeA:Destroy()
	node:set("three")
	flush()
	expect(second.Value == "three", "surviving binding still written after scopeA dies")
	first:Destroy()
	second:Destroy()
end)

test("bind.children · re-parenting before a change flushes doesn't leak old children", function()
	local screen = Instance.new("ScreenGui")
	local A = Instance.new("Frame")
	A.Name = "A"
	A.Parent = screen
	local B = Instance.new("Frame")
	B.Name = "B"
	B.Parent = screen

	local c1 = Instance.new("Frame")
	local c2 = Instance.new("Frame")
	local node = Flux.signal(c1)

	Bind.children(node, A)
	expect(c1.Parent == A, "c1 parented under A")

	node:set(c2)
	Bind.children(node, B)

	expect(c2.Parent == B, "c2 parented under B")
	expect(c1.Parent == nil, "stale c1 is not left behind under A")
	flush()
	screen:Destroy()
end)

test("bind.children · mounting a nested node doesn't subscribe the code that built the parent", function()
	local first, second = Instance.new("Frame"), Instance.new("Frame")
	local inner = Flux.signal(first)
	local children = Flux.signal({ inner })
	local builds, frame = 0, nil
	local s = Flux.scope(function()
		Flux.effect(function()
			builds += 1
			frame = Flux.new("Frame")({ children })
		end)
	end)
	flush()
	expect(builds == 1 and first.Parent == frame, "built once, with the nested node's child mounted")
	inner:set(second)
	flush()
	expect(builds == 1, `the effect that built the frame didn't re-run: {builds} builds`)
	expect(second.Parent == frame and first.Parent == nil, "the binding itself still follows the nested node")
	s:Destroy()
	first:Destroy()
	second:Destroy()
end)

test("bind · a property that fills a cache it read shows what it filled", function()
	local key = Flux.signal("a")
	local function lookup(): () -> string
		local cache = Flux.signal({})
		return function(): string
			local k = key:get()
			local hit = cache:get()[k]
			if hit then
				return hit
			end
			env.task.spawn(function()
				local current = cache:peek()
				local filled = table.clone(current)
				filled[k] = string.upper(k)
				cache:set(filled)
			end)
			return "..."
		end
	end
	local byFunction, byComputed
	local scope = Flux.scope(function()
		byFunction = Flux.new("TextLabel")({ Text = lookup() })
		byComputed = Flux.new("TextLabel")({ Text = Flux.computed(lookup()) })
	end)
	flush()
	expect(byFunction.Text == "A", `a bound function shows the first answer, not {byFunction.Text}`)
	expect(byComputed.Text == "A", `a bound computed shows the first answer, not {byComputed.Text}`)
	key:set("b")
	flush()
	expect(byFunction.Text == "B" and byComputed.Text == "B", `and the next: {byFunction.Text}, {byComputed.Text}`)
	scope:Destroy()
end)

test("model · isModel and modelNode recognise a model; Flux.model rejects a non-node", function()
	local node = Flux("text")
	local model = Flux.model(node)
	expect(Flux.isModel(model) and Flux.modelNode(model) == node, "a model and its node")
	expect(not Flux.isModel(node) and Flux.modelNode(node) == nil, "a node is not a model")
	expect(not Flux.isModel("text") and Flux.modelNode(nil) == nil, "nor is a plain value")
	expectError(function()
		Flux.model("not a node")
	end, "expects a reactive node")
end)

test("bind · late Bind.children attachment, model destroy pruning, and untracked initial Bind.to write", function()
	local inner = Flux.signal(Flux.new("Frame")({ Name = "First" }))
	local outer = Flux.signal({ inner })
	local p1 = Flux.new("Folder")({})
	local p2 = Flux.new("Folder")({})

	local scope1 = Flux.scope(function()
		Flux.edit(p1)({ outer })
	end)
	flush()
	expect(p1:FindFirstChild("First") ~= nil, "p1 received initial nested child")

	local scope2 = Flux.scope(function()
		Flux.edit(p2)({ outer })
	end)
	flush()

	local second = Flux.new("Frame")({ Name = "Second" })
	inner:set(second)
	flush()
	expect(p2:FindFirstChild("Second") ~= nil, "p2 tracks inner child node even when attached after outer flushed")
	scope1:Destroy()
	scope2:Destroy()
	p1:Destroy()
	p2:Destroy()

	local shared = Flux.signal("hello")
	local sharedTag = Flux.signal(true)
	local boxA = Flux.new("TextBox")({ Text = Flux.model(shared), _tag_Active = Flux.model(sharedTag) })
	local boxB = Flux.new("TextBox")({ Text = Flux.model(shared), _tag_Active = Flux.model(sharedTag) })
	boxA:Destroy()
	boxB:Destroy()
	local afterCount = if (shared :: any)[1].destroys then #(shared :: any)[1].destroys else 0
	local afterTagCount = if (sharedTag :: any)[1].destroys then #(sharedTag :: any)[1].destroys else 0
	expect(
		afterCount == 0 and afterTagCount == 0,
		`destroying model-bound instances prunes node destroys: {afterCount}/{afterTagCount}`
	)
	shared:Destroy()
	sharedTag:Destroy()

	local source = Flux.signal("init")
	local outerTrigger = Flux.signal(0)
	local outerRuns = 0
	local frame = Flux.new("Frame")({})
	local listenerScope = Flux.scope(function()
		local propNode = Flux.property(frame, "Name")
		Flux.effect(function()
			propNode()
		end)
	end)
	flush()
	local ownerScope = Flux.scope(function()
		Flux.effect(function()
			outerRuns += 1
			outerTrigger()
			Flux.edit(frame)({ Name = source })
		end)
	end)
	flush()
	expect(
		outerRuns == 1 and frame.Name == "init",
		"initial synchronous Bind.to write does not re-trigger enclosing effect"
	)
	ownerScope:Destroy()
	listenerScope:Destroy()
	frame:Destroy()
end)

local function syncMountedChildren(sut: any, mountedIds: { number })
	for _, c in sut.pool do
		c.Parent = nil
		c.LayoutOrder = 0
	end
	local list = {}
	for _, id in mountedIds do
		table.insert(list, sut.pool[id])
	end
	sut.childrenSig:set(list)
	flush()
end

local pendingBindState: any = nil
sert.model("bind · dynamic DOM hierarchy and two-way Flux.property/Flux.model binding reconciliation", {
	init = function()
		local state = {
			mounted = {} :: { number },
			text = "t0",
			score = 10,
			active = false,
		}
		pendingBindState = state
		return state
	end,
	setup = function()
		local state = pendingBindState
		pendingBindState = nil
		local textSig = Flux.signal("t0")
		local attrSig = Flux.signal(10)
		local tagSig = Flux.signal(false)
		local childrenSig = Flux.signal({} :: { any })

		local pool = {
			Flux.new("Frame")({ Name = "Child1" }),
			Flux.new("Frame")({ Name = "Child2" }),
			Flux.new("Frame")({ Name = "Child3" }),
			Flux.new("Frame")({ Name = "Child4" }),
		}

		local host, propText, propAttr, propTag
		local scope = Flux.scope(function()
			host = Flux.new("TextBox")({
				Name = "BindHost",
				Parent = workspace,
				Text = Flux.model(textSig),
				_attr_Score = Flux.model(attrSig),
				_tag_Active = Flux.model(tagSig),
				childrenSig,
			})
			propText = Flux.property(host, "Text")
			propAttr = Flux.property(host, "$Score")
			propTag = Flux.property(host, "#Active")
		end)
		flush()
		settle()

		return {
			state = state,
			scope = scope,
			host = host,
			pool = pool,
			childrenSig = childrenSig,
			textSig = textSig,
			attrSig = attrSig,
			tagSig = tagSig,
			propText = propText,
			propAttr = propAttr,
			propTag = propTag,
		}
	end,
	teardown = function(sut)
		sut.scope:Destroy()
		for _, c in sut.pool do
			c:Destroy()
		end
		sut.host:Destroy()
		flush()
		sert.eq(env.idle(Flux), nil, "zero-leak reactive state on teardown")
		sert.eq(env.drained(Flux), nil, "zero pending effects on teardown")
	end,
	commands = {
		MountChild = {
			weight = 3,
			gen = function(_state, g)
				return g:int(1, 4)
			end,
			run = function(sut, id)
				local state = sut.state
				if table.find(state.mounted, id) ~= nil then
					return
				end
				local nextIds = table.clone(state.mounted)
				table.insert(nextIds, id)
				syncMountedChildren(sut, nextIds)
			end,
			next = function(state, id)
				if table.find(state.mounted, id) == nil then
					table.insert(state.mounted, id)
				end
			end,
		},
		UnmountChild = {
			weight = 2,
			gen = function(_state, g)
				return g:int(1, 4)
			end,
			run = function(sut, id)
				local state = sut.state
				local idx = table.find(state.mounted, id)
				if idx == nil then
					return
				end
				local nextIds = table.clone(state.mounted)
				table.remove(nextIds, idx)
				syncMountedChildren(sut, nextIds)
			end,
			next = function(state, id)
				local idx = table.find(state.mounted, id)
				if idx ~= nil then
					table.remove(state.mounted, idx)
				end
			end,
		},
		ReorderChildren = {
			weight = 2,
			run = function(sut)
				local state = sut.state
				if #state.mounted < 2 then
					return
				end
				local nextIds = {}
				for i = #state.mounted, 1, -1 do
					table.insert(nextIds, state.mounted[i])
				end
				syncMountedChildren(sut, nextIds)
			end,
			next = function(state)
				if #state.mounted < 2 then
					return
				end
				local rev = {}
				for i = #state.mounted, 1, -1 do
					table.insert(rev, state.mounted[i])
				end
				state.mounted = rev
			end,
		},
		WriteSignalProp = {
			weight = 2,
			gen = function(_state, g)
				return `sig_{g:int(1, 20)}`
			end,
			run = function(sut, val)
				sut.textSig:set(val)
				flush()
			end,
			next = function(state, val)
				state.text = val
			end,
		},
		MutateInstanceProp = {
			weight = 2,
			gen = function(_state, g)
				return `inst_{g:int(1, 20)}`
			end,
			run = function(sut, val)
				sut.host.Text = val
				settle()
				flush()
			end,
			next = function(state, val)
				state.text = val
			end,
		},
		MutateAttribute = {
			weight = 2,
			gen = function(_state, g)
				return { score = g:int(1, 50), viaInstance = g:bool() }
			end,
			run = function(sut, arg)
				if arg.viaInstance then
					sut.host:SetAttribute("Score", arg.score)
					settle()
				else
					sut.attrSig:set(arg.score)
				end
				flush()
			end,
			next = function(state, arg)
				state.score = arg.score
			end,
		},
		ToggleTag = {
			weight = 2,
			gen = function(_state, g)
				return { active = g:bool(), viaInstance = g:bool() }
			end,
			run = function(sut, arg)
				if arg.viaInstance then
					if arg.active then
						sut.host:AddTag("Active")
					else
						sut.host:RemoveTag("Active")
					end
				else
					sut.tagSig:set(arg.active)
					flush()
				end
				settle()
				flush()
			end,
			next = function(state, arg)
				state.active = arg.active
			end,
		},
	},
	invariants = {
		unmountedChildNeverRetainedInHost = function(state, sut)
			for id, inst in sut.pool do
				expect(
					table.find(state.mounted, id) ~= nil or inst.Parent == nil,
					`unmounted child #{id} has nil Parent`
				)
			end
		end,
		childrenOrderMatchesState = function(state, sut)
			local children = sut.host:GetChildren()
			sert.eq(#children, #state.mounted, "mounted child count")
			for idx, id in state.mounted do
				local expected = sut.pool[id]
				sert.eq(children[idx], expected, `GetChildren()[{idx}] identity`)
				sert.eq((children[idx] :: Frame).LayoutOrder, idx, `GetChildren()[{idx}] LayoutOrder`)
			end
		end,
		twoWayPropertyAndModelParity = function(state, sut)
			sert.eq(sut.host.Text, state.text, "host.Text")
			sert.eq(sut.textSig:peek(), state.text, "textSig")
			sert.eq(sut.propText:peek(), state.text, "Flux.property Text")

			sert.eq(sut.host:GetAttribute("Score"), state.score, "host Score attribute")
			sert.eq(sut.attrSig:peek(), state.score, "attrSig")
			sert.eq(sut.propAttr:peek(), state.score, "Flux.property $Score")

			sert.eq(sut.host:HasTag("Active"), state.active, "host Active tag")
			sert.eq(sut.tagSig:peek(), state.active, "tagSig")
			sert.eq(sut.propTag:peek(), state.active, "Flux.property #Active")
		end,
	},
}, {
	runs = 120,
	length = 16,
	exhaustive = { size = 2 },
})

test("listen · fires only on updates after subscribing and stops when disconnected or destroyed", function()
	local v = Flux(1)
	local received = {}
	local disconnect = Flux.listen(v, function(val)
		table.insert(received, val)
	end)
	expect(type(disconnect) == "function", "listen returns a disconnect function")
	flush()
	expect(#received == 0, "listen does not fire on initial flush when value has not changed")

	v(2)
	flush()
	expect(#received == 1 and received[1] == 2, "listener receives first update")

	v(3)
	flush()
	expect(#received == 2 and received[2] == 3, "listener receives subsequent updates")

	disconnect()
	disconnect()
	v(4)
	flush()
	expect(#received == 2, "listener stops firing after disconnect")

	local received2 = {}
	Flux.listen(v, function(val)
		table.insert(received2, val)
	end)
	v:Destroy()
	v(5)
	flush()
	expect(#received2 == 0, "destroyed node clears listeners")
end)

test("listen · hears immediate mutation before first flush and survives scope teardown on shared node", function()
	local v = Flux("a")
	local seen = {}
	Flux.listen(v, function(val)
		table.insert(seen, val)
	end)
	v("b")
	flush()
	expect(#seen == 1 and seen[1] == "b", "mutation immediately after listen before first flush is observed")

	local shared = Flux.signal("one")
	local out = {}
	local scopeA = Flux.scope(function()
		Flux.listen(shared, function() end)
	end)
	Flux.listen(shared, function(val)
		table.insert(out, val)
	end)
	shared:set("two")
	flush()
	expect(out[#out] == "two", "listener notified while scopeA is alive")

	scopeA:Destroy()
	shared:set("three")
	flush()
	expect(out[#out] == "three", "surviving listener still notified after first listener's scope dies")
end)

test("listen · callbacks run untracked, ownerless, and safe across mid-flush add/remove and Bind.children", function()
	local src = Flux(10)
	local unrelated = Flux(100)
	local ownerSeen: any = "unset"
	local reactiveSeen: any = "unset"
	local innerDisposed = 0
	local runs = 0

	Flux.listen(src, function(_val)
		runs += 1
		ownerSeen = Flux.getOwner()
		reactiveSeen = Flux.isReactive()
		local _ = unrelated()
		local c = Flux.computed(function()
			return 1
		end)
		c:onDestroy(function()
			innerDisposed += 1
		end)
	end)

	src(20)
	flush()
	expect(
		runs == 1 and ownerSeen == nil and reactiveSeen == false,
		"listener ran untracked and ownerless on src update"
	)

	unrelated(200)
	flush()
	expect(runs == 1, "reading unrelated signal inside listener does not subscribe src's bind effect")

	src(30)
	flush()
	expect(runs == 2 and innerDisposed == 0, "listener runs ownerless without bind effect adopting created nodes")

	-- Multi-listener mid-flush add and disconnect safety
	local multi = Flux(0)
	local log = {}
	local discA: () -> ()
	local discB: () -> ()
	local function addC()
		Flux.listen(multi, function(v2)
			table.insert(log, `C:{v2}`)
		end)
	end
	discA = Flux.listen(multi, function(val)
		table.insert(log, `A:{val}`)
		discB()
		addC()
	end)
	discB = Flux.listen(multi, function(val)
		table.insert(log, `B:{val}`)
		discA()
		addC()
	end)

	multi(1)
	flush()
	expect(#log == 1, "disconnecting sibling listener mid-flush prevents it from firing, and newly added C waits")
	multi(2)
	flush()
	expect(table.find(log, "C:2") ~= nil, "listener added mid-flush fires on subsequent update")

	-- Re-attaching Bind.children on a listened node does not falsely trigger listeners
	local childA = Instance.new("Frame")
	local childB = Instance.new("Frame")
	local parent1 = Instance.new("Frame")
	local parent2 = Instance.new("Frame")
	local childNode = Flux.signal(childA)
	local childEvents = 0
	Flux.listen(childNode, function()
		childEvents += 1
	end)
	local unbind1 = Bind.children(childNode, parent1)
	flush()
	local unbind2 = Bind.children(childNode, parent2)
	flush()
	expect(
		childEvents == 0,
		"attaching or re-parenting Bind.children does not fire listen when node value is unchanged"
	)
	childNode:set(childB)
	flush()
	expect(childEvents == 1, "listener still fires when childNode updates after Bind.children restart")
	unbind1()
	unbind2()
	childA:Destroy()
	childB:Destroy()
	parent1:Destroy()
	parent2:Destroy()

	expectError(function()
		Flux.listen("not a node" :: any, function() end)
	end, "expects a reactive node")
	expectError(function()
		Flux.listen(src, "not a function" :: any)
	end, "expects a function")
end)

test("property & Bind.from · owning scope teardown disconnects property, attribute, and tag listeners", function()
	local frame = Instance.new("Frame")
	frame.Name = "Initial"
	frame:SetAttribute("Score", 1)
	frame.Parent = workspace

	local propNode: any
	local attrNode: any
	local tagNode: any
	local scope = Flux.scope(function()
		propNode = Flux.property(frame, "Name")
		attrNode = Flux.property(frame, "$Score")
		tagNode = Flux.property(frame, "#Highlighted")
	end)

	frame.Name = "Updated"
	frame:SetAttribute("Score", 2)
	frame:AddTag("Highlighted")
	settle()
	expect(propNode:peek() == "Updated" and attrNode:peek() == 2 and tagNode:peek() == true, "active bindings follow")

	scope:Destroy()
	frame.Name = "AfterDestroy"
	frame:SetAttribute("Score", 3)
	frame:RemoveTag("Highlighted")
	settle()
	expect(
		propNode:peek() == "Updated" and attrNode:peek() == 2 and tagNode:peek() == true,
		"scope teardown disconnects property, attribute, and tag listeners"
	)

	-- Child-scoped Bind.from on an outer signal disconnects without destroying the outer signal
	local outer = Flux.signal("")
	local childScope = Flux.scope(function()
		Bind.from(outer, frame, "Name")
	end)
	expect(outer:peek() == "AfterDestroy", "Bind.from syncs initial value")
	childScope:Destroy()
	frame.Name = "PostChildDestroy"
	settle()
	expect(outer:peek() == "AfterDestroy", "child scope teardown disconnects Bind.from listener")
	outer:set("StillWritable")
	expect(outer:peek() == "StillWritable", "outer signal stays alive after child scope teardown")

	-- Stale release closure on the SAME signal after replacement does not evict newer claim, and dual attr+prop buckets stay independent
	local sig1 = Flux.signal("One")
	local rel1 = Bind.to(sig1, frame, "Name", false)
	Bind.attach(frame, "Name", false, rel1)
	Bind.release(frame, "Name", false)
	sig1:set("Two")
	local rel2 = Bind.to(sig1, frame, "Name", false)
	Bind.attach(frame, "Name", false, rel2)
	rel1() -- stale release from first binding on the SAME signal must not drop second claim
	sig1:set("Three")
	flush()
	expect(frame.Name == "Three", "second claim on same signal survived stale release")
	Bind.release(frame, "Name", false)
	sig1:set("IgnoredAfterRelease")
	flush()
	expect(frame.Name == "Three", "cleanly released by Bind.release")

	local dualSig = Flux.signal("InitDual")
	local relProp = Bind.to(dualSig, frame, "Name", false)
	local relAttr = Bind.to(dualSig, frame, "DualAttr", true)
	relAttr() -- release attr bucket while prop bucket remains active
	dualSig:set("PropOnly")
	flush()
	expect(
		frame.Name == "PropOnly" and frame:GetAttribute("DualAttr") == "InitDual",
		"releasing attr keeps prop bucket live"
	)
	local relAttr2 = Bind.to(dualSig, frame, "DualAttr", true)
	relProp() -- release prop bucket while attr bucket remains active
	dualSig:set("AttrOnly")
	flush()
	expect(
		frame.Name == "PropOnly" and frame:GetAttribute("DualAttr") == "AttrOnly",
		"releasing prop keeps attr bucket live"
	)
	relAttr2()
	dualSig:set("NoneActive")
	flush()
	expect(frame:GetAttribute("DualAttr") == "AttrOnly", "both buckets released")

	-- Flux.on with defer = true preserves initial prevInput and returns initial prevResult
	local onDep = Flux.signal("a")
	local deferredStep = Flux.on(onDep, function(inp, prevInp, prevRes)
		return `{inp}:{tostring(prevInp)}:{tostring(prevRes)}`
	end, true)
	expect(deferredStep("seed") == "seed", "deferred Flux.on returns prevResult on initial call")
	onDep:set("b")
	expect(
		deferredStep("seed2") == "b:a:seed2",
		"second call receives initial input as prevInput and latest prevResult"
	)

	-- Bind.to inside an effect or scope isolatesChanged side-effects from outer tracking and ownership
	local sideSig = Flux.signal(1)
	local innerLeak = 0
	local sideInst = Instance.new("Frame")
	sideInst:GetPropertyChangedSignal("Name"):Connect(function()
		sideSig()
		Flux.effect(function()
			innerLeak += 1
		end)
	end)
	local outerRuns = 0
	local effNode = Flux.effect(function()
		outerRuns += 1
		local r = Bind.to(Flux.signal("InEffect"), sideInst, "Name", false)
		r()
	end)
	flush()
	expect(outerRuns == 1, "outer effect ran once")
	sideSig:set(2)
	flush()
	expect(outerRuns == 1, "Bind.to inside effect did not subscribe outer effect to Changed reads")
	effNode:Destroy()
	local ownerScope = Flux.scope(function()
		local r = Bind.to(Flux.signal("InScope"), sideInst, "Name", false)
		r()
	end)
	ownerScope:Destroy()
	sideInst:Destroy()

	local host = Instance.new("Frame")
	host.Parent = workspace
	local kid1 = Instance.new("Frame")
	local kid2 = Instance.new("Frame")
	local kid3 = Instance.new("Frame")
	local kidsSig = Flux.signal(kid1 :: any)
	local heardKids = 0
	local unlistenKids = Flux.listen(kidsSig, function()
		heardKids += 1
	end)
	local reactiveMountScope = Flux.scope(function()
		return Flux.effect(function()
			Bind.children(kidsSig, host, 5)
		end)
	end)
	flush()
	reactiveMountScope:Destroy()
	Bind.children(kidsSig, host, 5)
	expect(kid1.Parent == host and kid1.LayoutOrder == 5, "single-Instance Bind.children applies layoutOrder offset")
	kidsSig:set({ kid2, kid3 })
	flush()
	expect(
		heardKids >= 1 and kid1.Parent == nil and kid2.LayoutOrder == 5 and kid3.LayoutOrder == 6,
		"Bind.children keeps pre-existing Flux.listen alive and applies sequential layoutOrder"
	)
	unlistenKids()
	host:Destroy()
	kidsSig:set(Instance.new("Frame"))
	flush()

	frame:Destroy()
end)

sert.test("bind.from · cleans up destroys entries on instance destroy and preserves computed onDestroy", function()
	local sharedSig = Flux.signal("")
	for i = 1, 5 do
		local frame = Instance.new("Frame")
		frame.Name = `Item{i}`
		Bind.from(sharedSig, frame, "Name")
		frame:Destroy()
	end
	local destroys = (sharedSig :: any)[1].destroys
	expect(destroys == nil or #destroys == 0, "destroying bound instances removes bindDestroy hooks from shared node")

	local frame = Instance.new("Frame")
	frame.Name = "First"
	local comp = Flux.computed(function()
		return "First"
	end)
	local userDestroyed = false
	Bind.from(comp, frame, "Name")
	comp:onDestroy(function()
		userDestroyed = true
	end)
	comp:Destroy()
	expect(userDestroyed, "destroying computed with Bind.from still runs subsequent onDestroy callbacks")
	frame:Destroy()
	sharedSig:Destroy()
end)

test("fromSignal · bridges RBXScriptSignal and custom Connect/connect tables and cleans up", function()
	local disconnected = 0
	local listeners = {}
	local customUpper = {
		Connect = function(_self, fn)
			table.insert(listeners, fn)
			return {
				Disconnect = function()
					disconnected += 1
					local idx = table.find(listeners, fn)
					if idx then
						table.remove(listeners, idx)
					end
				end,
			}
		end,
	}

	local node = Flux.fromSignal(customUpper, "idle")
	expect(node:peek() == "idle", "fromSignal seeds initial value")
	listeners[1]("active")
	expect(node:peek() == "active", "fromSignal updates node when Connect signal fires")
	node:Destroy()
	expect(disconnected == 1, "fromSignal disconnects on node:Destroy()")

	local scopeDisconnected = 0
	local lowerListeners = {}
	local customLower = {
		connect = function(_self, fn)
			table.insert(lowerListeners, fn)
			return function()
				scopeDisconnected += 1
				local idx = table.find(lowerListeners, fn)
				if idx then
					table.remove(lowerListeners, idx)
				end
			end
		end,
	}

	local scope, scopedNode = Flux.scope(function()
		return Flux.fromSignal(customLower)
	end)
	expect(scopedNode:peek() == nil, "fromSignal defaults initial to nil")
	lowerListeners[1](42)
	expect(scopedNode:peek() == 42, "lowercase :connect signal fires node")
	scope:Destroy()
	expect(scopeDisconnected == 1, "enclosing scope teardown disconnects fromSignal listener")

	-- RBXScriptSignal via Instance.Changed
	local box = Instance.new("TextBox")
	box.Text = "one"
	local changedNode = Flux.fromSignal(box.Changed, "Text")
	expect(changedNode:peek() == "Text", "fromSignal supports RBXScriptSignal with initial")
	box.Text = "two"
	settle()
	expect(changedNode:peek() == "Text", "RBXScriptSignal event updates node")
	changedNode:Destroy()
	box:Destroy()

	-- Strict proxy metatable table passed to Flux(proxy) does not fail getSignalConnector
	local strictProxy = setmetatable({}, {
		__index = function(_, key)
			error(`strict miss: {key}`)
		end,
	})
	local proxySig = Flux(strictProxy)
	expect(proxySig:peek() == strictProxy, "Flux(strictProxy) creates a signal rather than crashing")
	proxySig:Destroy()

	expectError(function()
		Flux.fromSignal(123 :: any)
	end, "Flux.fromSignal expects an RBXScriptSignal or signal with :Connect()")
end)

test("bind · idle BindData teardown fires onUnobserved and cleanly rebinds across listen, to, and children", function()
	local s = Flux.signal("A")
	local obs, unobs = 0, 0
	s:onObserved(function()
		obs += 1
	end)
	s:onUnobserved(function()
		unobs += 1
	end)

	local host = Instance.new("Frame")
	host.Parent = workspace
	local lbl = Instance.new("TextLabel")
	lbl.Parent = host
	local heard = 0

	local unlisten = Bind.listen(s, function()
		heard += 1
	end)
	local stopTo = Bind.to(s, lbl, "Text", false)
	expect(obs == 1 and unobs == 0, "listen + to observe shared signal once")

	stopTo()
	expect(obs == 1 and unobs == 0, "stopping to keeps listen active and observed")

	unlisten()
	expect(obs == 1 and unobs == 1, "stopping final binding tears down idle BindData and fires onUnobserved")
	local destroys = (s :: any)[1].destroys
	expect(destroys == nil or #destroys == 0, "idle BindData teardown prunes node destroys")

	stopTo = Bind.to(s, lbl, "Text", false)
	flush()
	expect(obs == 2 and unobs == 1, "rebinding Bind.to re-creates BindData and fires onObserved")
	s:set("B")
	flush()
	expect(lbl.Text == "B", "rebound Bind.to tracks updates")

	unlisten = Bind.listen(s, function()
		heard += 1
	end)
	s:set("C")
	flush()
	expect(lbl.Text == "C" and heard >= 1, "rebound Bind.listen receives subsequent updates")
	stopTo()
	unlisten()
	expect(obs == 2 and unobs == 2, "releasing rebound listen + to tears down BindData again")

	local childA = Instance.new("Frame")
	local childB = Instance.new("Frame")
	local kidsSig = Flux.signal({ childA } :: any)
	local kObs, kUnobs = 0, 0
	kidsSig:onObserved(function()
		kObs += 1
	end)
	kidsSig:onUnobserved(function()
		kUnobs += 1
	end)

	local stopKids = Bind.children(kidsSig, host)
	flush()
	expect(kObs == 1 and kUnobs == 0 and childA.Parent == host, "Bind.children observes and mounts childA")
	stopKids()
	expect(kObs == 1 and kUnobs == 1 and childA.Parent == nil, "stopping Bind.children tears down idle BindData")

	stopKids = Bind.children(kidsSig, host)
	flush()
	expect(kObs == 2 and kUnobs == 1 and childA.Parent == host, "rebinding Bind.children re-observes signal")
	kidsSig:set({ childB })
	flush()
	expect(childA.Parent == nil and childB.Parent == host, "rebound Bind.children updates mounted children")
	stopKids()
	expect(kObs == 2 and kUnobs == 2, "releasing rebound Bind.children fires onUnobserved")

	host:Destroy()
	lbl:Destroy()
	childA:Destroy()
	childB:Destroy()
	s:Destroy()
	kidsSig:Destroy()
end)
