--!nonstrict
local env = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Model = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("Model")) :: any
	else require("../lib/Model") :: any

local Flux = env.Flux
local sert = env.sert
local test = sert.test
local expect = sert
local new = Flux
local flush = Flux.flush

test("show · a throwing component is warned and does not strand tracking", function()
	local cond = Flux.signal(true)
	local node = Flux.show(cond, function()
		error("component boom")
	end)
	local warnings = env.warnings(flush)
	expect(#warnings == 1, `the build error was warned once, got {#warnings}`)
	local probe = Flux.signal(1)
	local seen = 0
	local e = Flux.effect(function()
		probe()
		seen += 1
	end)
	flush()
	probe:set(2)
	flush()
	expect(seen == 2, "tracking restored after a throwing component")
	expect(node() == nil, "output is nil after the failed build")
	e:Destroy()
	node:Destroy()
end)

test("show · the value accessor tracks the live condition without remounting", function()
	local user = Flux.signal({ name = "Ada" })
	local builds, seen = 0, nil
	local node = Flux.show(user, function(value)
		builds += 1
		Flux.effect(function()
			seen = value().name
		end)
		return "panel"
	end)
	flush()
	expect(builds == 1 and seen == "Ada", "mounted once; accessor effect saw the initial value")

	user:set({ name = "Grace" })
	flush()
	expect(builds == 1, "no rebuild across a truthy -> truthy change")
	expect(seen == "Grace", "accessor effect re-ran with the live value")
	node:Destroy()
end)

test("switch · the default branch value accessor tracks the live unmatched value", function()
	local route = Flux.signal("home")
	local defaultBuilds, seen = 0, {}
	local node = Flux.switch(route)({
		home = function(value)
			return "home:" .. value()
		end,
		[Flux.otherwise] = function(value)
			defaultBuilds += 1
			Flux.effect(function()
				seen[#seen + 1] = value()
			end)
			return "default"
		end,
	})
	flush()
	expect(node() == "home:home", "keyed branch value() returns the matched key")

	route:set("about")
	flush()
	route:set("contact")
	flush()
	expect(defaultBuilds == 1, "the one default mount is reused across unmatched values")
	expect(table.concat(seen, ",") == "about,contact", "default accessor tracked each live unmatched value")
	node:Destroy()
end)

test("show and switch · mount, swap and unmount real instances under a parent", function()
	local cond, key = Flux.signal(true), Flux.signal("red")
	local cases = {
		{
			"show",
			function()
				return Flux.show(cond, function()
					return Flux.new("Frame")({ Name = "Branch" })
				end)
			end,
			{ "Branch" },
			function()
				cond:set(false)
			end,
			{},
		},
		{
			"switch",
			function()
				return Flux.switch(key)({
					red = function()
						return Flux.new("Frame")({ Name = "Red" })
					end,
					blue = function()
						return Flux.new("Frame")({ Name = "Blue" })
					end,
				})
			end,
			{ "Red" },
			function()
				key:set("blue")
			end,
			{ "Blue" },
		},
	}
	local function names(parent)
		local list = {}
		for _, child in parent:GetChildren() do
			table.insert(list, child.Name)
		end
		return list
	end
	for _, case in cases do
		local root
		local s = Flux.scope(function()
			root = Flux.new("Frame")({ Name = "Root", case[2]() })
		end)
		flush()
		expect.eq(names(root), case[3], `{case[1]}: mounted under the parent`)
		case[4]()
		flush()
		expect.eq(names(root), case[5], `{case[1]}: after the change`)
		expect.eq(
			env.warnings(function()
				s:Destroy()
			end),
			{},
			`{case[1]}: unmounts without a warning`
		)
	end
end)

test("presence · an exit keeps the branch mounted until done", function()
	local visible = Flux.signal(true)
	local exitingNode, finish
	local builds, cleaned = 0, 0
	local node = Flux.presence(visible, function(exiting, done)
		builds += 1
		exitingNode, finish = exiting, done
		Flux.cleanup(function()
			cleaned += 1
		end)
		return { tag = "P" }
	end)
	flush()
	expect(node().tag == "P" and builds == 1 and exitingNode() == false, "mounted and not exiting")

	finish()
	flush()
	expect(node() ~= nil and cleaned == 0, "done() outside an exit is ignored")

	visible:set(false)
	flush()
	expect(exitingNode() == true, "a falsy condition starts the exit")
	expect(node().tag == "P" and cleaned == 0, "the branch stays mounted while exiting")

	finish()
	flush()
	expect(node() == nil and cleaned == 1, "done() unmounts the branch")

	visible:set(true)
	flush()
	expect(builds == 2 and node().tag == "P", "turning truthy again mounts a fresh branch")
	node:Destroy()
end)

test("presence · re-entering during an exit reverses it", function()
	local visible = Flux.signal(true)
	local exitingNode, finish
	local builds = 0
	local node = Flux.presence(visible, function(exiting, done)
		builds += 1
		exitingNode, finish = exiting, done
		return "P"
	end)
	flush()
	visible:set(false)
	flush()

	finish()
	visible:set(true)
	flush()
	expect(builds == 1 and node() == "P", "the same branch stays; the stale done() is dropped")
	expect(exitingNode() == false, "exiting flips back")

	visible:set(false)
	flush()
	flush()
	expect(exitingNode() == true and node() == "P", "a new exit waits for its own done()")
	finish()
	flush()
	expect(node() == nil, "which unmounts")
	node:Destroy()
end)

test("presence · done() from a branch effect unmounts on the same flush", function()
	local visible = Flux.signal(true)
	local cleaned = 0
	local node = Flux.presence(visible, function(exiting, done)
		Flux.effect(function()
			if exiting() then
				done()
			end
		end)
		Flux.cleanup(function()
			cleaned += 1
		end)
		return "P"
	end)
	flush()
	visible:set(false)
	flush()
	expect(node() == nil and cleaned == 1, "unmounted within one flush")
	node:Destroy()
end)

test("presence · keeps an exiting instance parented until done", function()
	local visible = Flux.signal(true)
	local finish
	local root
	local s = Flux.scope(function()
		local panel = Flux.presence(visible, function(_, done)
			finish = done
			return Flux.new("Frame")({ Name = "Panel" })
		end)
		root = Flux.new("Frame")({ Name = "Root", panel })
	end)
	flush()
	expect(root:FindFirstChild("Panel") ~= nil, "mounted")
	visible:set(false)
	flush()
	expect(root:FindFirstChild("Panel") ~= nil, "still parented while exiting")
	finish()
	flush()
	expect(root:FindFirstChild("Panel") == nil, "unparented after done")
	s:Destroy()
end)

test("presence · destroys exiting node on completion or Destroy, and throwing factory recovers", function()
	local visible = Flux.signal(true)
	local exitDestroyed = 0
	local finishFn: (() -> ())?
	local out = Flux.presence(visible, function(exiting, done)
		exiting:onDestroy(function()
			exitDestroyed += 1
		end)
		finishFn = done
		return "mounted"
	end)
	flush()
	expect(out() == "mounted" and exitDestroyed == 0, "mounted with live exiting node")

	visible:set(false)
	flush()
	expect(exitDestroyed == 0, "exiting node still alive while exit animation is in progress")
	assert(finishFn)()
	flush()
	expect(out() == nil and exitDestroyed == 1, "completing exit destroys the per-mount exiting node")

	visible:set(true)
	flush()
	expect(out() == "mounted" and exitDestroyed == 1, "re-mounted with a fresh exiting node")
	out:Destroy()
	expect(exitDestroyed == 2, "destroying presence output destroys the active exiting node")

	local bad = Flux.presence(Flux.signal(true), function()
		error("presence boom")
	end)
	local warnings = env.warnings(flush)
	expect(#warnings == 1 and bad() == nil, "throwing presence factory warns once and leaves output nil")
	bad:Destroy()
end)

test("show · presence · a branch is torn down before its owner's cleanups", function()
	for _, kind in { "show", "presence" } do
		local order = {}
		local s = Flux.scope(function()
			local function branch()
				Flux.cleanup(function()
					table.insert(order, "branch")
				end)
				return "B"
			end
			local node = if kind == "show" then Flux.show(true, branch) else Flux.presence(true, branch)
			Flux.cleanup(function()
				table.insert(order, "owner")
			end)
			return node
		end)
		flush()
		s:Destroy()
		expect.eq(table.concat(order, ","), "branch,owner", kind)
	end
end)

test("show · an owner's re-run tears down the branch it built before", function()
	local source = Flux.signal(1)
	local cleaned = 0
	local owner = Flux.computed(function()
		source:get()
		return Flux.show(true, function()
			Flux.cleanup(function()
				cleaned += 1
			end)
			return "B"
		end)
	end)
	owner:get()
	flush()
	source:set(2)
	owner:get()
	flush()
	expect.eq(cleaned, 1, "the first run's branch went with the re-run")
	owner:Destroy()
	expect.eq(cleaned, 2)
end)

test("show · a branch can take back an instance before the owner's frames are destroyed", function()
	local lent = env.Instance.new("Frame")
	lent.Name = "Lent"
	local s = Flux.scope(function()
		local branch = Flux.show(true, function()
			Flux.cleanup(function()
				lent.Parent = nil
			end)
			local holder = Flux.new("Frame")({ Name = "Holder" })
			lent.Parent = holder
			return holder
		end)
		Flux.new("Frame")({ Name = "Root", branch })
	end)
	flush()
	expect(lent.Parent ~= nil and lent.Parent.Name == "Holder", "mounted")
	expect.eq(
		env.warnings(function()
			s:Destroy()
		end),
		{},
		"the teardown warns nothing"
	)
	local folder = env.Instance.new("Folder")
	expect(
		pcall(function()
			lent.Parent = folder
		end),
		"the lent frame survived its owner's teardown"
	)
	folder:Destroy()
end)

-- Conditional models ----------------------------------------------------------------------------------------------

local TABLE_A, TABLE_B = { id = "A" }, { id = "B" }
local function showValue(value: any): string
	return if type(value) == "table" then `table {value.id}` else tostring(value)
end

local BRANCH_DOMAIN: { any } = { nil, false, true, 1, TABLE_A, TABLE_B, "x", "y", "z" }
local OTHER_KEY = {}
local BRANCH_CASES = {
	{ id = "show", kind = "show", withFallback = false, useGetter = false, directDestroy = true },
	{ id = "show+fb", kind = "show", withFallback = true, useGetter = true, directDestroy = false },
	{ id = "showKeyed", kind = "showKeyed", withFallback = false, useGetter = true, directDestroy = true },
	{ id = "showKeyed+fb", kind = "showKeyed", withFallback = true, useGetter = false, directDestroy = false },
	{ id = "switch", kind = "switch", withFallback = false, useGetter = false, directDestroy = true },
	{ id = "switch+other", kind = "switch+otherwise", withFallback = false, useGetter = true, directDestroy = false },
}

local function selectCaseBranch(caseSpec: any, value: any): (any, string?)
	local kind = caseSpec.kind
	if kind == "switch" or kind == "switch+otherwise" then
		if value == "x" or value == "y" then
			return value, value
		elseif kind == "switch+otherwise" then
			return OTHER_KEY, "otherwise"
		end
		return value, nil
	end
	local key = if kind == "showKeyed" then value else not not value
	return key, if value then "on" elseif caseSpec.withFallback then "off" else nil
end

local function syncBranchModel(state: any)
	if not state.dirty then
		return
	end
	state.dirty = false
	local value = state.value
	for _, caseSpec in BRANCH_CASES do
		local cState = state.cases[caseSpec.id]
		local key, name = selectCaseBranch(caseSpec, value)
		if not cState.mounted or key ~= cState.activeKey then
			cState.mounted, cState.activeKey = true, key
			if cState.live then
				cState.live.retired = true
			end
			cState.live = nil
			if name then
				cState.count += 1
				cState.live = { name = name, value = value }
			end
		end
	end
end

local pendingBranchState: any = nil
sert.model("show/showKeyed/switch · the mounted branch follows the source's key", {
	init = function()
		local state: any = {
			value = nil,
			dirty = true,
			cases = {},
		}
		for _, caseSpec in BRANCH_CASES do
			state.cases[caseSpec.id] = { mounted = false, activeKey = nil, live = nil, count = 0 }
		end
		syncBranchModel(state)
		pendingBranchState = state
		return state
	end,
	setup = function()
		local state = pendingBranchState
		pendingBranchState = nil
		local source = Flux.signal(nil :: any)
		local sut: any = {
			state = state,
			source = source,
			cases = {},
		}
		for _, caseSpec in BRANCH_CASES do
			local mounts = {}
			local function factory(name: string)
				return function(value)
					local mount = { branch = name, cleaned = 0, value = value() }
					table.insert(mounts, mount)
					Flux.cleanup(function()
						mount.cleaned += 1
					end)
					return mount
				end
			end
			local input: any = if caseSpec.useGetter
				then function()
					return source:get()
				end
				else source
			local node
			local owner = Flux.scope(function()
				if caseSpec.kind == "switch" or caseSpec.kind == "switch+otherwise" then
					local map: { [any]: any } = { x = factory("x"), y = factory("y") }
					if caseSpec.kind == "switch+otherwise" then
						map[Flux.otherwise] = factory("otherwise")
					end
					node = Flux.switch(input)(map)
				elseif caseSpec.kind == "show" then
					node = Flux.show(input, factory("on"), if caseSpec.withFallback then factory("off") else nil)
				else
					node = Flux.showKeyed(input, factory("on"), if caseSpec.withFallback then factory("off") else nil)
				end
			end)
			sut.cases[caseSpec.id] = { spec = caseSpec, owner = owner, node = node, mounts = mounts }
		end
		Flux.flush()
		return sut
	end,
	teardown = function(sut)
		local state = sut.state
		Flux.flush()
		syncBranchModel(state)
		for _, caseSpec in BRANCH_CASES do
			local cSut = sut.cases[caseSpec.id]
			if caseSpec.directDestroy then
				cSut.node:Destroy()
			else
				cSut.owner:Destroy()
			end
		end
		for _, caseSpec in BRANCH_CASES do
			local cSut = sut.cases[caseSpec.id]
			for index, mount in cSut.mounts do
				sert.eq(mount.cleaned, 1, `{caseSpec.id}: mount {index} ({mount.branch}) cleaned up once in all`)
			end
			cSut.owner:Destroy()
		end
		Flux.flush()
	end,
	commands = {
		set = {
			weight = 3,
			gen = function(_state, g)
				return BRANCH_DOMAIN[g:int(1, #BRANCH_DOMAIN)]
			end,
			run = function(sut, value)
				sut.source:set(value)
			end,
			next = function(state, value)
				state.value = value
				state.dirty = true
			end,
		},
		flush = {
			weight = 2,
			run = function()
				Flux.flush()
			end,
			next = function(state)
				syncBranchModel(state)
			end,
		},
	},
	invariants = {
		mountNeverCleanedTwice = function(_state, sut)
			for _, cSut in sut.cases do
				for _, mount in cSut.mounts do
					sert(mount.cleaned <= 1, "mount never cleaned more than once")
				end
			end
		end,
		activeMountNotCleanedWhileSynced = function(state, sut)
			if state.dirty then
				return
			end
			for id, cState in state.cases do
				local mounts = sut.cases[id].mounts
				if cState.live ~= nil and #mounts > 0 then
					sert.eq(mounts[#mounts].cleaned, 0, `{id}: active mount not cleaned while synced`)
				end
			end
		end,
		mountCountMatchesReference = function(state, sut)
			if state.dirty then
				return
			end
			for _, caseSpec in BRANCH_CASES do
				local cState = state.cases[caseSpec.id]
				local cSut = sut.cases[caseSpec.id]
				sert.eq(#cSut.mounts, cState.count, `{caseSpec.id}: one factory call per key change`)
			end
		end,
		retiredMountsCleanedOnce = function(state, sut)
			if state.dirty then
				return
			end
			for _, caseSpec in BRANCH_CASES do
				local cState = state.cases[caseSpec.id]
				local cSut = sut.cases[caseSpec.id]
				for index, mount in cSut.mounts do
					local alive = index == #cSut.mounts and cState.live ~= nil
					sert.eq(
						mount.cleaned,
						if alive then 0 else 1,
						`{caseSpec.id}: mount {index} ({mount.branch}) cleaned up once when swapped out`
					)
				end
			end
		end,
		liveBranchMatchesReference = function(state, sut)
			if state.dirty then
				return
			end
			for _, caseSpec in BRANCH_CASES do
				local cState = state.cases[caseSpec.id]
				local cSut = sut.cases[caseSpec.id]
				if cState.live then
					local mount = cSut.mounts[#cSut.mounts]
					sert(cSut.node:peek() == mount, `{caseSpec.id}: the output is the live mount`)
					sert.eq(
						mount.branch,
						cState.live.name,
						`{caseSpec.id}: {showValue(state.value)} mounts {cState.live.name}`
					)
					sert(
						mount.value == cState.live.value,
						`{caseSpec.id}: value() in the factory is the value it mounted for`
					)
				else
					sert(cSut.node:peek() == nil, `{caseSpec.id}: no branch for {showValue(state.value)}`)
				end
			end
		end,
	},
}, {
	runs = 150,
	length = 14,
	exhaustive = { size = 2 },
})

local function syncPresenceState(state: any)
	if not state.dirty then
		return
	end
	state.dirty = false
	if state.visible then
		if state.mode == "unmounted" then
			state.mode = "mounted"
			state.count += 1
		elseif state.mode == "exiting" then
			state.mode = "mounted"
		end
		state.pendingDone = false
	else
		if state.pendingDone then
			if state.mode == "exiting" then
				state.mode = "unmounted"
			end
			state.pendingDone = false
		elseif state.mode == "mounted" then
			state.mode = "exiting"
		end
	end
end

local pendingPresenceState: any = nil
sert.model("presence · mounts on truthy, holds during exit, reverses on re-truthy, and unmounts on done", {
	init = function()
		local state = {
			mode = "unmounted",
			visible = false,
			count = 0,
			pendingDone = false,
			dirty = false,
		}
		pendingPresenceState = state
		return state
	end,
	setup = function()
		local state = pendingPresenceState
		pendingPresenceState = nil
		local visible = Flux.signal(false)
		local mounts = {}
		local node
		local owner = Flux.scope(function()
			node = Flux.presence(visible, function(exiting, done)
				local mount = { exiting = exiting, done = done, cleaned = 0 }
				table.insert(mounts, mount)
				Flux.cleanup(function()
					mount.cleaned += 1
				end)
				return mount
			end)
		end)
		Flux.flush()
		return {
			state = state,
			visible = visible,
			mounts = mounts,
			node = node,
			owner = owner,
		}
	end,
	teardown = function(sut)
		Flux.flush()
		syncPresenceState(sut.state)
		sut.node:Destroy()
		sut.owner:Destroy()
		Flux.flush()
		for i, mount in sut.mounts do
			sert.eq(mount.cleaned, 1, `mount {i} cleaned once after Destroy`)
		end
	end,
	commands = {
		set = {
			weight = 4,
			gen = sert.gen.bool(),
			run = function(sut, v)
				sut.visible:set(v)
			end,
			next = function(state, v)
				state.visible = v
				state.dirty = true
			end,
		},
		done = {
			weight = 3,
			run = function(sut)
				if #sut.mounts > 0 then
					sut.mounts[#sut.mounts].done()
				end
			end,
			next = function(state, _, _)
				if state.count > 0 and state.mode == "exiting" and not state.visible then
					state.pendingDone = true
					state.dirty = true
				end
			end,
		},
		flush = {
			weight = 3,
			run = function()
				Flux.flush()
			end,
			next = function(state)
				syncPresenceState(state)
			end,
		},
	},
	invariants = {
		neverCleanedMoreThanOnce = function(_state, sut)
			for _, mount in sut.mounts do
				sert(mount.cleaned <= 1, "presence mount never cleaned more than once")
			end
		end,
		mountCountMatches = function(state, sut)
			if state.dirty then
				return
			end
			sert.eq(#sut.mounts, state.count, "mount count matches reference")
		end,
		outputMatchesMode = function(state, sut)
			if state.dirty then
				return
			end
			if state.mode == "unmounted" then
				sert(sut.node:peek() == nil, "output is nil when unmounted")
			else
				local active = sut.mounts[#sut.mounts]
				sert(sut.node:peek() == active, "output is the active mount")
				sert.eq(active.exiting:peek(), state.mode == "exiting", "exiting node matches state")
				sert.eq(active.cleaned, 0, "active mount not yet cleaned")
			end
		end,
		retiredMountsCleanedOnce = function(state, sut)
			if state.dirty then
				return
			end
			for i = 1, #sut.mounts - (if state.mode == "unmounted" then 0 else 1) do
				sert.eq(sut.mounts[i].cleaned, 1, `retired mount {i} cleaned once`)
			end
		end,
	},
}, {
	runs = 150,
	length = 16,
	exhaustive = { size = 2 },
})

local PICK_DOMAIN: { any } = { nil, false, "A", "B" }
local function genPickValue(_state, g): any
	return PICK_DOMAIN[g:int(1, #PICK_DOMAIN)]
end

local pendingPickState: any = nil
sert.model("pick/fallback · the value matches and a reader re-runs only when it changes", {
	init = function()
		local state = {
			cond = true :: any,
			whenTrue = "A" :: any,
			whenFalse = "B" :: any,
			val = nil :: any,
			def = "A" :: any,
			expectedPick3 = "A" :: any,
			expectedPick2 = "A" :: any,
			expectedFb = "A" :: any,
			expectedRuns = { pick3 = 1, pick2 = 1, fb = 1 },
			unusedEvaluated = false,
		}
		pendingPickState = state
		return state
	end,
	setup = function()
		local state = pendingPickState
		pendingPickState = nil
		local condSig = Flux.signal(true :: any)
		local trueSig = Flux.signal("A" :: any)
		local falseSig = Flux.signal("B" :: any)
		local valSig = Flux.signal(nil :: any)
		local defSig = Flux.signal("A" :: any)

		local evals = { trueBranch = 0, falseBranch = 0, defBranch = 0 }
		local runs = { pick3 = 0, pick2 = 0, fb = 0 }
		local pick3, pick2, fb
		local rPick3, rPick2, rFb
		local scope = Flux.scope(function()
			pick3 = Flux.pick(condSig, function()
				evals.trueBranch += 1
				return trueSig:get()
			end, function()
				evals.falseBranch += 1
				return falseSig:get()
			end)
			pick2 = Flux.pick(function()
				return condSig:get()
			end, trueSig)
			fb = Flux.fallback(valSig, function()
				evals.defBranch += 1
				return defSig:get()
			end)
			rPick3 = Flux.computed(function()
				runs.pick3 += 1
				return pick3()
			end)
			rPick2 = Flux.computed(function()
				runs.pick2 += 1
				return pick2()
			end)
			rFb = Flux.computed(function()
				runs.fb += 1
				return fb()
			end)
		end)
		sert(rPick3:get() == "A" and runs.pick3 == 1, "pick starts at A")
		sert(rPick2:get() == "A" and runs.pick2 == 1, "pick (omitFalse) starts at A")
		sert(rFb:get() == "A" and runs.fb == 1, "fallback starts at A")

		return {
			state = state,
			scope = scope,
			condSig = condSig,
			trueSig = trueSig,
			falseSig = falseSig,
			valSig = valSig,
			defSig = defSig,
			rPick3 = rPick3,
			rPick2 = rPick2,
			rFb = rFb,
			evals = evals,
			runs = runs,
		}
	end,
	teardown = function(sut)
		sut.scope:Destroy()
		Flux.flush()
	end,
	commands = {
		setCond = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value)
				sut.condSig:set(value)
				sut.rPick3:get()
				sut.rPick2:get()
			end,
			next = function(state, value)
				state.cond = value
				local next3 = if state.cond then state.whenTrue else state.whenFalse
				local next2 = if state.cond then state.whenTrue else nil
				if next3 ~= state.expectedPick3 then
					state.expectedRuns.pick3 += 1
					state.expectedPick3 = next3
				end
				if next2 ~= state.expectedPick2 then
					state.expectedRuns.pick2 += 1
					state.expectedPick2 = next2
				end
			end,
		},
		setTrue = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value)
				local state = sut.state
				local beforeEvals = sut.evals.trueBranch
				sut.trueSig:set(value)
				sut.rPick3:get()
				sut.rPick2:get()
				if not state.cond and sut.evals.trueBranch ~= beforeEvals then
					state.unusedEvaluated = true
				end
			end,
			next = function(state, value)
				state.whenTrue = value
				local next3 = if state.cond then state.whenTrue else state.whenFalse
				local next2 = if state.cond then state.whenTrue else nil
				if next3 ~= state.expectedPick3 then
					state.expectedRuns.pick3 += 1
					state.expectedPick3 = next3
				end
				if next2 ~= state.expectedPick2 then
					state.expectedRuns.pick2 += 1
					state.expectedPick2 = next2
				end
			end,
		},
		setFalse = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value)
				local state = sut.state
				local beforeEvals = sut.evals.falseBranch
				sut.falseSig:set(value)
				sut.rPick3:get()
				sut.rPick2:get()
				if state.cond and sut.evals.falseBranch ~= beforeEvals then
					state.unusedEvaluated = true
				end
			end,
			next = function(state, value)
				state.whenFalse = value
				local next3 = if state.cond then state.whenTrue else state.whenFalse
				if next3 ~= state.expectedPick3 then
					state.expectedRuns.pick3 += 1
					state.expectedPick3 = next3
				end
			end,
		},
		setVal = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value)
				sut.valSig:set(value)
				sut.rFb:get()
			end,
			next = function(state, value)
				state.val = value
				local nextFb = if state.val == nil then state.def else state.val
				if nextFb ~= state.expectedFb then
					state.expectedRuns.fb += 1
					state.expectedFb = nextFb
				end
			end,
		},
		setDefault = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value)
				local state = sut.state
				local beforeEvals = sut.evals.defBranch
				sut.defSig:set(value)
				sut.rFb:get()
				if state.val ~= nil and sut.evals.defBranch ~= beforeEvals then
					state.unusedEvaluated = true
				end
			end,
			next = function(state, value)
				state.def = value
				local nextFb = if state.val == nil then state.def else state.val
				if nextFb ~= state.expectedFb then
					state.expectedRuns.fb += 1
					state.expectedFb = nextFb
				end
			end,
		},
	},
	invariants = {
		unusedBranchNeverEvaluated = function(state)
			sert(not state.unusedEvaluated, "unused branch is never evaluated")
		end,
		pickMatchesReference = function(state, sut)
			sert.eq(sut.rPick3:get(), state.expectedPick3, "pick matches reference")
			sert.eq(sut.runs.pick3, state.expectedRuns.pick3, "pick reader re-runs only when value changes")
		end,
		pickOmitFalseMatchesReference = function(state, sut)
			sert.eq(sut.rPick2:get(), state.expectedPick2, "pick (omitFalse) matches reference")
			sert.eq(sut.runs.pick2, state.expectedRuns.pick2, "pick (omitFalse) reader re-runs only when value changes")
		end,
		fallbackMatchesReference = function(state, sut)
			sert.eq(sut.rFb:get(), state.expectedFb, "fallback matches reference")
			sert.eq(sut.runs.fb, state.expectedRuns.fb, "fallback reader re-runs only when value changes")
		end,
	},
}, {
	runs = 150,
	length = 16,
	exhaustive = { size = 1 },
})

-- For -----------------------------------------------------------------------------------------------------------------

local For = { value = Flux.forValue, index = Flux.forIndex }

test("forValue · duplicates share one mapped instance, with a warning", function()
	local list = new({ "x", "x", "y" })
	local mapRuns = 0
	local mapped = For.value(list, function(indexNode, value)
		mapRuns += 1
		return { value = value }
	end)
	local out
	local warnings = env.warnings(function()
		out = mapped:get()
	end)
	expect(#warnings == 1 and string.find(warnings[1], "duplicate values", 1, true) ~= nil, "warned once")
	expect(out[1] == out[2] and out[1] ~= out[3], "shared mapped instance")
	expect(mapRuns == 2, "mapper runs once per unique value")
	mapped:Destroy()
end)

test("forIndex · node and function elements stay opaque", function()
	local userNode = new(5)
	local items = {}
	local list = new({ userNode })
	local mapped = For.index(list, function(index, item)
		table.insert(items, item)
		return item
	end)
	mapped:get()
	expect(items[1] ~= userNode and items[1]:get() == userNode, "item node boxes the user node")
	list:set({ 42 })
	mapped:get()
	expect(userNode:get() == 5, "reassignment leaves the user node intact")
	list:set({})
	mapped:get()
	expect(getmetatable(userNode) ~= nil, "eviction doesn't destroy the user node")
	mapped:Destroy()
	expect(getmetatable(userNode) ~= nil, "mapper destroy doesn't destroy the user node")

	local fnCalls = 0
	local fnEl = function()
		fnCalls += 1
	end
	local list2 = new({ fnEl })
	local mapped2 = For.index(list2, function(index, item)
		return item:get()
	end)
	expect(mapped2:get()[1] == fnEl and fnCalls == 0, "fn element returned raw, never executed")
end)

test("for · non-table source returns empty array and recovers cleanly after mapFn throws", function()
	local src = new(nil :: any)
	local cleaned = 0
	local nodeDestroyed = 0
	local mapped = For.value(src, function(indexNode, _value)
		indexNode:onDestroy(function()
			nodeDestroyed += 1
		end)
		return function()
			cleaned += 1
		end
	end)
	expect(#mapped:get() == 0, "non-table source maps to empty table")
	src:set({ "row1", "row2" })
	expect(#mapped:get() == 2, "populates once source becomes a table")
	mapped:Destroy()
	expect(nodeDestroyed == 2 and cleaned == 2, "mapper Destroy tears down all row nodes and disposes cached results")

	local shouldThrow = true
	local src2 = new({ "ok", "bad" })
	local mapped2 = For.value(src2, function(_index, val)
		if shouldThrow and val == "bad" then
			error("row boom")
		end
		return string.upper(val)
	end)
	sert.throws(function()
		mapped2:get()
	end, "row boom")

	shouldThrow = false
	src2:set({ "ok", "fixed" })
	local res = mapped2:get()
	expect(#res == 2 and res[1] == "OK" and res[2] == "FIXED", "subsequent evaluation succeeds cleanly")
	mapped2:Destroy()
end)

local function counters(): { maps: number, disposed: number, nodeDestroyed: number, cleaned: number }
	return { maps = 0, disposed = 0, nodeDestroyed = 0, cleaned = 0 }
end

local function makeMapperSpec(
	map: any,
	genList: (state: any, g: any) -> { any },
	keyOf: (list: { any }, i: number) -> any,
	check
)
	local function row(rows: { [any]: any }, key: any)
		local counts = rows[key]
		if counts == nil then
			counts = counters()
			rows[key] = counts
		end
		return counts
	end

	local function readAndCheck(state: any, sut: any)
		local result = sut.mapper:get()
		if not state.changed then
			sert(result == sut.lastResult, "no list change, no rebuild (mapper and teardown reads untracked)")
		end
		sert.eq(#result, #state.current, "one result per element")
		local nextLive = {}
		for i = 1, #state.current do
			local key = keyOf(state.current, i)
			local counts = row(state.rows, key)
			local before = state.live[key]
			if before ~= nil then
				sert(result[i] == before, `the row for {key} keeps its result`)
				sert.eq(counts.maps, counts.disposed + 1, `a surviving row ({key}) is not re-mapped`)
			else
				sert.eq(counts.maps, counts.disposed + 1, `a new row ({key}) is mapped once`)
			end
			nextLive[key] = result[i]
		end
		check(result, state.current)
		state.live = nextLive
		state.changed = false
		sut.lastResult = result
	end

	local pendingState: any = nil
	return {
		init = function()
			local state = {
				current = {},
				live = {} :: { [any]: any },
				rows = {} :: { [any]: any },
				changed = true,
			}
			pendingState = state
			return state
		end,
		setup = function()
			local state = pendingState
			pendingState = nil
			local rows = state.rows
			local list = Flux.signal({})
			local noise = Flux.signal(0)
			local mapper
			local owner = Flux.scope(function()
				mapper = map(list, function(a, b, key)
					local counts = row(rows, key)
					counts.maps += 1
					noise:get()
					Flux.cleanup(function()
						counts.cleaned += 1
						noise:get()
					end)
					local node = if Flux.isNode(a) then a else b
					node:onDestroy(function()
						counts.nodeDestroyed += 1
					end)
					return {
						a = a,
						b = b,
						Destroy = function()
							counts.disposed += 1
							noise:get()
						end,
					}
				end)
			end)
			local sut = {
				state = state,
				list = list,
				noise = noise,
				mapper = mapper,
				owner = owner,
				lastResult = nil :: any,
			}
			readAndCheck(state, sut)
			return sut
		end,
		teardown = function(sut)
			local state = sut.state
			readAndCheck(state, sut)
			sut.mapper:Destroy()
			sut.owner:Destroy()
			Flux.flush()
			for key, counts in state.rows do
				sert.eq(counts.disposed, counts.maps, `{key}: destroying the mapper disposes every row once`)
				sert.eq(counts.nodeDestroyed, counts.maps, `{key}: and destroys every node once`)
				sert.eq(counts.cleaned, counts.maps, `{key}: and runs every cleanup once`)
			end
		end,
		commands = {
			set = {
				weight = 3,
				gen = genList,
				run = function(sut, nextList)
					sut.list:set(table.clone(nextList))
				end,
				next = function(state, nextList)
					state.current = table.clone(nextList)
					state.changed = true
				end,
			},
			noise = {
				weight = 1,
				run = function(sut)
					sut.noise:set(sut.noise:peek() + 1)
				end,
			},
			read = {
				weight = 2,
				run = function(sut)
					readAndCheck(sut.state, sut)
				end,
			},
		},
		invariants = {
			teardownCountNeverExceedsMaps = function(state)
				for _, counts in state.rows do
					expect(
						counts.disposed <= counts.maps
							and counts.nodeDestroyed <= counts.maps
							and counts.cleaned <= counts.maps,
						"teardown counts never exceed map count"
					)
				end
			end,
			rowLifecyclesBalanced = function(state, sut)
				if state.changed then
					return
				end
				sert.eq(#sut.lastResult, #state.current, "one result per element")
				check(sut.lastResult, state.current)
				for key, counts in state.rows do
					local alive = if state.live[key] ~= nil then 1 else 0
					sert.eq(counts.disposed, counts.maps - alive, `{key}: each removed row's result disposed once`)
					sert.eq(counts.nodeDestroyed, counts.maps - alive, `{key}: and its node destroyed once`)
					sert.eq(counts.cleaned, counts.maps - alive, `{key}: and its cleanup run once`)
				end
			end,
		},
	}
end

local FOR_VALUE_POOL = { "a", "b", "c", "d" }
sert.model(
	"forValue · rows follow unique values: mapped once per new value, torn down once",
	makeMapperSpec(function(source, mapFn)
		return Flux.forValue(source, function(indexNode, value)
			return mapFn(indexNode, value, value)
		end)
	end, function(_state, g)
		local pool, out = table.clone(FOR_VALUE_POOL), {}
		for _ = 1, g:int(0, math.min(#FOR_VALUE_POOL, g.size + 1)) do
			table.insert(out, table.remove(pool, g:int(1, #pool)))
		end
		return out
	end, function(list, i)
		return list[i]
	end, function(result, list)
		for i, value in list do
			sert(result[i].b == value and result[i].a:peek() == i, `row {i} holds {value} with index {i}`)
		end
	end),
	{
		runs = 150,
		length = 12,
		exhaustive = { size = 2 },
	}
)

sert.model(
	"forIndex · rows follow positions: mapped once per new slot, torn down once",
	makeMapperSpec(function(source, mapFn)
		return Flux.forIndex(source, function(index, itemNode)
			return mapFn(index, itemNode, index)
		end)
	end, function(_state, g)
		return g:list(function(g)
			return g:int(1, 3)
		end, 0, math.min(4, g.size + 1))
	end, function(_, i)
		return i
	end, function(result, list)
		for i, value in list do
			sert(result[i].a == i and result[i].b:peek() == value, `slot {i} holds {value}`)
		end
	end),
	{
		runs = 150,
		length = 12,
		exhaustive = { size = 2 },
	}
)

-- Selector ------------------------------------------------------------------------------------------------------------

test("selector · a custom equals re-tests every key after an in-place update", function()
	local row = { id = 1 }
	local source = new(row)
	local sel = Flux.selector(source, function(value, key)
		return value.id == key
	end)
	local reads, seen = {}, {}
	for k = 1, 2 do
		reads[k] = Flux.effect(function()
			seen[k] = sel(k)
		end)
	end
	flush()
	expect(seen[1] == true and seen[2] == false, "seeded by the comparator")
	row.id = 2
	source:update()
	flush()
	expect(seen[1] == false and seen[2] == true, "the same value, mutated, is re-tested")
	for k = 1, 2 do
		reads[k]:Destroy()
	end
	sel:Destroy()
end)

local function selectorRef(custom: boolean, value: number?, key: number): boolean
	if custom then
		return value ~= nil and value % 3 == key % 3
	end
	return value == key
end

local function genSelectorValue(_state, g): number?
	local n = g:int(0, 5)
	return if n == 0 then nil else n
end

local function checkSelectorFlush(state: any, sut: any, where: string)
	Flux.flush()
	local value = sut.source:peek()
	for _, reader in sut.readers do
		local expected = selectorRef(reader.custom, value, reader.key)
		sert.eq(reader.value, expected, `{where}: reader of key {reader.key} (custom: {reader.custom})`)
		if reader.checked ~= nil then
			local flipped = expected ~= reader.checked
			local reran = reader.runs - reader.checkedRuns
			if reran > state.maxReran then
				state.maxReran = reran
			end
			sert(reran <= 1, `{where}: key {reader.key} re-ran at most once`)
			if not flipped and not state.earlyRun then
				if reran ~= 0 then
					state.spuriousRun = true
				end
				sert(reran == 0, `{where}: key {reader.key} did not flip, so did not re-run`)
			end
		end
		reader.checked, reader.checkedRuns = expected, reader.runs
	end
	state.earlyRun = false
	state.dirty = false
end

local pendingSelectorState: any = nil
sert.model("selector · per-key readers match the reference and only flipped keys re-run", {
	init = function()
		local state = {
			value = 1 :: number?,
			dirty = false,
			earlyRun = false,
			maxReran = 0,
			spuriousRun = false,
		}
		pendingSelectorState = state
		return state
	end,
	setup = function()
		local state = pendingSelectorState
		pendingSelectorState = nil
		local source = Flux.signal(1 :: number?)
		local noise = Flux.signal(0)
		local sut: any = {
			state = state,
			source = source,
			noise = noise,
			getterRuns = 0,
			selStd = nil,
			selCustom = nil,
			selScope = nil,
			readerScope = nil,
			readers = {},
		}
		sut.selScope = Flux.scope(function()
			sut.selStd = Flux.selector(source)
			sut.selCustom = Flux.selector(function()
				sut.getterRuns += 1
				return source:get()
			end, function(v, k)
				return selectorRef(true, v, k)
			end)
		end)
		Flux.flush()
		sut.readerScope = Flux.scope(function() end)
		return sut
	end,
	teardown = function(sut)
		local state = sut.state
		checkSelectorFlush(state, sut, "end")
		sut.selStd:Destroy()
		sut.selScope:Destroy()
		sut.source:set((sut.source:peek() or 0) + 1)
		Flux.flush()
		for _, reader in sut.readers do
			sert.eq(reader.runs, reader.checkedRuns, `key {reader.key}: a destroyed selector re-runs no reader`)
		end
		sert(not pcall(sut.selStd, 1), "a read after Destroy errors (std)")
		sert(not pcall(sut.selCustom, 1), "a read after Destroy errors (custom)")
		sut.readerScope:Destroy()
		sut.selCustom:Destroy()
		Flux.flush()
	end,
	commands = {
		set = {
			weight = 4,
			gen = genSelectorValue,
			run = function(sut, value)
				sut.source:set(value)
			end,
			next = function(state, value)
				state.value = value
				state.dirty = true
			end,
		},
		noise = {
			weight = 1,
			run = function(sut)
				local state = sut.state
				checkSelectorFlush(state, sut, "before noise")
				sut.noise:set(sut.noise:peek() + 1)
				local before = sut.getterRuns
				checkSelectorFlush(state, sut, "noise")
				sert.eq(sut.getterRuns, before, "an unrelated write does not re-run the source getter")
			end,
		},
		peek = {
			weight = 2,
			gen = function(_state, g)
				return { key = g:int(1, 5), tracked = g:bool(), custom = g:bool() }
			end,
			run = function(sut, arg)
				local sel = if arg.custom then sut.selCustom else sut.selStd
				local expected = selectorRef(arg.custom, sut.source:peek(), arg.key)
				if arg.tracked then
					local probe = Flux.computed(function()
						return sel(arg.key)
					end)
					sert.eq(probe:get(), expected, `a fresh tracked read of key {arg.key} is current before the flush`)
					probe:Destroy()
				else
					sert.eq(
						sel:get(arg.key),
						expected,
						`an untracked read of key {arg.key} is current before the flush`
					)
				end
				sut.state.earlyRun = true
			end,
		},
		reader = {
			weight = 3,
			gen = function(_state, g)
				return { key = g:int(1, 5), custom = g:bool() }
			end,
			run = function(sut, arg)
				local sel = if arg.custom then sut.selCustom else sut.selStd
				local reader = Model.reader(sut.readerScope, true, function()
					return sel(arg.key)
				end)
				reader.key = arg.key
				reader.custom = arg.custom
				table.insert(sut.readers, reader)
			end,
			next = function(state)
				state.dirty = true
			end,
		},
		drop = {
			weight = 1,
			gen = function(_state, g)
				return g:int(1, 8)
			end,
			run = function(sut, index)
				if #sut.readers > 0 then
					local i = math.clamp(index, 1, #sut.readers)
					table.remove(sut.readers, i).node:Destroy()
				end
			end,
		},
		flush = {
			weight = 3,
			run = function(sut)
				checkSelectorFlush(sut.state, sut, "flush")
			end,
		},
	},
	invariants = {
		noOverrunOrSpuriousRun = function(state)
			expect(state.maxReran <= 1, "key reader re-ran at most once")
			expect(not state.spuriousRun, "unflipped key reader never re-ran")
		end,
		readersMatchReferenceWhenFlushed = function(state, sut)
			if state.dirty then
				return
			end
			for _, reader in sut.readers do
				if reader.checked ~= nil then
					local expected = selectorRef(reader.custom, state.value, reader.key)
					sert.eq(reader.value, expected, `reader of key {reader.key} matches reference`)
				end
			end
		end,
	},
}, {
	runs = 150,
	length = 16,
	exhaustive = { size = 2 },
})

local flickerTest = if env.IS_ROBLOX and game:GetService("Players").LocalPlayer == nil then sert.test.skip else test
flickerTest("conditional & list layout · transitions settle cleanly without visibility or rect flicker", function()
	local Layout = sert.roblox.Layout
	local Flicker = sert.roblox.Flicker
	local UDim2 = env.UDim2
	local rs = if env.IS_ROBLOX then game:GetService("RunService") else nil

	local showBanner = Flux.signal(true)
	local items = Flux.signal({ "Alpha", "Beta" })
	local idxItems = Flux.signal({ 10, 20 })
	local bannerFrame: Frame? = nil
	local rowFrames: { [string]: Frame } = {}
	local slotFrames: { [number]: Frame } = {}
	local columnFrame: Frame

	local screenParent = if env.IS_ROBLOX
		then (if game:GetService("Players").LocalPlayer
			then game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			else env.workspace)
		else env.engine.LocalPlayer.PlayerGui
	local screen
	local scope = Flux.scope(function()
		columnFrame = Flux.new("Frame")({
			Name = "Column",
			Position = UDim2.fromOffset(16, 16),
			Size = UDim2.fromOffset(240, 260),
			Flux.list({ gap = 6 }),
			Flux.show(showBanner, function()
				local f = Flux.new("Frame")({
					Name = "Banner",
					LayoutOrder = 0,
					Size = UDim2.fromOffset(240, 28),
				})
				bannerFrame = f
				return f
			end),
			Flux.forValue(items, function(indexNode, label)
				local row = Flux.new("Frame")({
					Name = `Row_{label}`,
					LayoutOrder = indexNode,
					Size = UDim2.fromOffset(240, 24),
				})
				rowFrames[label] = row
				return row
			end),
			Flux.forIndex(idxItems, function(idx, _valNode)
				local slot = Flux.new("Frame")({
					Name = `Slot_{idx}`,
					LayoutOrder = 10 + idx,
					Size = UDim2.fromOffset(240, 24),
				})
				slotFrames[idx] = slot
				return slot
			end),
		})
		screen = Flux.new("ScreenGui")({
			Parent = screenParent,
			Enabled = true,
			columnFrame,
		})
	end)
	sert.defer(function()
		scope:Destroy()
		screen:Destroy()
		Flux.flush()
	end)

	env.frame()
	local settleOpts = { stableFrames = 2, runService = rs }
	expect(Layout.settle(screen, settleOpts) <= 30, "initial conditional/list layout settled")
	expect(bannerFrame ~= nil and Layout.geometry.visible(bannerFrame :: any), "banner is visible")
	expect(rowFrames.Alpha ~= nil and Layout.geometry.visible(rowFrames.Alpha), "Row_Alpha is visible")
	Layout.fitsParent(columnFrame)

	-- Insertion across forValue and forIndex
	items:set({ "Alpha", "Beta", "Gamma" })
	idxItems:set({ 10, 20, 30 })
	flush()
	Flicker.steady(rowFrames.Gamma, { step = env.frame, stableFrames = 2, label = "Row_Gamma enter" })
	Layout.fitsParent(columnFrame)

	-- Permutation across forValue and forIndex
	items:set({ "Gamma", "Alpha", "Beta" })
	idxItems:set({ 30, 10, 20 })
	flush()
	Flicker.steady(rowFrames.Gamma, { step = env.frame, stableFrames = 2, label = "Row_Gamma permutation" })
	Layout.fitsParent(columnFrame)

	-- Removal across forValue, forIndex, and conditional banner hide
	showBanner:set(false)
	items:set({ "Gamma", "Beta" })
	idxItems:set({ 30, 20 })
	flush()
	Flicker.steady(rowFrames.Beta, {
		step = env.frame,
		stableFrames = 2,
		label = "Row_Beta shift on removal and banner hide",
	})
	Layout.fitsParent(columnFrame)

	expect(Layout.settle(screen, settleOpts) <= 30, "post-transition layout settled")
end)

local pendingSweepState: any = nil
sert.model("selector · subscription lifecycle and cache sweeping evicts unobserved keys and preserves active keys", {
	init = function()
		local state = {
			active = "k1",
			subscribed = { k1 = false, k2 = false, k3 = false, k4 = false } :: { [string]: boolean },
			sweptSinceUnsub = false,
		}
		pendingSweepState = state
		return state
	end,
	setup = function()
		local state = pendingSweepState
		pendingSweepState = nil
		local active = Flux.signal("k1")
		local sel = Flux.selector(active)
		local lazyComputeds: { [string]: any } = {}
		local subs: { [string]: any } = {}
		local seen: { [string]: boolean } = {}
		local scope = Flux.scope(function()
			for i = 1, 4 do
				local k = `k{i}`
				lazyComputeds[k] = Flux.computed(function()
					return sel(k)
				end)
			end
		end)
		return {
			state = state,
			scope = scope,
			active = active,
			sel = sel,
			lazyComputeds = lazyComputeds,
			subs = subs,
			seen = seen,
			probeCounter = 0,
		}
	end,
	teardown = function(sut)
		for _, eff in sut.subs do
			eff:Destroy()
		end
		sut.scope:Destroy()
		sut.sel:Destroy()
		flush()
	end,
	commands = {
		SelectKey = {
			weight = 3,
			gen = function(_state, g)
				return `k{g:int(1, 4)}`
			end,
			run = function(sut, key)
				sut.active:set(key)
				flush()
			end,
			next = function(state, key)
				state.active = key
			end,
		},
		SubscribeKey = {
			weight = 3,
			gen = function(_state, g)
				return `k{g:int(1, 4)}`
			end,
			run = function(sut, key)
				if sut.subs[key] ~= nil then
					return
				end
				sut.subs[key] = Flux.effect(function()
					sut.seen[key] = sut.sel(key)
				end)
				flush()
			end,
			next = function(state, key)
				state.subscribed[key] = true
			end,
		},
		UnsubscribeKey = {
			weight = 2,
			gen = function(_state, g)
				return `k{g:int(1, 4)}`
			end,
			run = function(sut, key)
				local eff = sut.subs[key]
				if eff ~= nil then
					sut.subs[key] = nil
					sut.seen[key] = nil
					eff:Destroy()
				end
			end,
			next = function(state, key)
				state.subscribed[key] = false
				state.sweptSinceUnsub = false
			end,
		},
		ReadLazyComputed = {
			weight = 2,
			gen = function(_state, g)
				return `k{g:int(1, 4)}`
			end,
			run = function(sut, key)
				sert.eq(sut.lazyComputeds[key](), sut.state.active == key, `lazy computed for {key}`)
			end,
			next = function(state)
				state.sweptSinceUnsub = false
			end,
		},
		TriggerSweep = {
			weight = 2,
			run = function(sut)
				sut.probeCounter += 1
				local probeKey = `probe_{sut.probeCounter}`
				(sut.sel :: any)._sweepAt = 0
				local c = Flux.computed(function()
					return sut.sel(probeKey)
				end)
				c()
				c:Destroy()
				flush()
			end,
			next = function(state)
				state.sweptSinceUnsub = true
			end,
		},
	},
	invariants = {
		unobservedKeysEvictedAfterSweep = function(state, sut)
			if not state.sweptSinceUnsub then
				return
			end
			for k, isSub in state.subscribed do
				expect(isSub or (sut.sel :: any)._nodes[k] == nil, `unobserved key {k} evicted after sweep`)
			end
		end,
		activeSubscribersAndLazyComputedsMatchSelection = function(state, sut)
			local activeCount = 0
			for k, isSub in state.subscribed do
				local want = state.active == k
				if isSub then
					activeCount += 1
					sert.eq(sut.seen[k], want, `subscribed effect for {k}`)
					expect((sut.sel :: any)._nodes[k] ~= nil, `subscribed key {k} retained in _nodes`)
				end
				sert.eq(sut.sel:get(k), want, `untracked sel:get({k})`)
			end
			if state.sweptSinceUnsub then
				sert.eq((sut.sel :: any)._count, activeCount, "swept _count matches active subscriber count")
			end
		end,
	},
}, {
	runs = 120,
	length = 16,
	exhaustive = { size = 2 },
})

local lastDynamicControls: {
	showAlert: any,
	tab: any,
	valueItems: any,
	indexItems: any,
} = nil :: any

sert.roblox.Layout.matrix(
	"conditional · dynamic forValue, forIndex, show, and switch UI reconciliation",
	function(parent, preset)
		local viewport = preset.size
		local UDim2 = env.UDim2
		local hostParent, cleanHost = env.mountUi(parent, viewport)
		local showAlert = Flux.signal(true)
		local tab = Flux.signal("value")
		local valueItems = Flux.signal({ "Sword", "Shield", "Potion" })
		local indexItems = Flux.signal({ 10, 20, 30 })

		local root: Frame
		local scope = Flux.scope(function()
			local w = math.min(viewport.X - 24, 420)
			local h = math.min(viewport.Y - 24, 360)
			root = Flux.new("Frame")({
				Name = "DynamicPanel",
				Parent = hostParent,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(w, h),
				Flux.padding(10),
				Flux.list({ direction = "y", gap = 6 }),
				Flux.show(showAlert, function()
					return Flux.new("Frame")({
						Name = "AlertBanner",
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 28),
						Flux.new("TextLabel")({
							Name = "AlertText",
							Size = UDim2.fromScale(1, 1),
							Text = "System Online",
							TextSize = 12,
							TextScaled = true,
						}),
					})
				end),
				Flux.switch(tab)({
					value = function()
						return Flux.new("Frame")({
							Name = "ValueList",
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 140),
							Flux.list({ direction = "y", gap = 4 }),
							Flux.forValue(valueItems, function(idx, item)
								return Flux.new("Frame")({
									Name = `Val_{item}`,
									LayoutOrder = idx,
									Size = UDim2.new(1, 0, 0, 24),
									Flux.new("TextLabel")({
										Size = UDim2.fromScale(1, 1),
										Text = function()
											return `#{idx()} {item}`
										end,
										TextSize = 12,
										TextScaled = true,
									}),
								})
							end),
						})
					end,
					index = function()
						return Flux.new("Frame")({
							Name = "IndexList",
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 140),
							Flux.list({ direction = "y", gap = 4 }),
							Flux.forIndex(indexItems, function(idx, valNode)
								return Flux.new("Frame")({
									Name = `Idx_{idx}`,
									LayoutOrder = idx,
									Size = UDim2.new(1, 0, 0, 24),
									Flux.new("TextLabel")({
										Size = UDim2.fromScale(1, 1),
										Text = function()
											return `Slot {idx}: {valNode()}`
										end,
										TextSize = 12,
										TextScaled = true,
									}),
								})
							end),
						})
					end,
				}),
			})
		end)
		flush()
		lastDynamicControls = {
			showAlert = showAlert,
			tab = tab,
			valueItems = valueItems,
			indexItems = indexItems,
		}
		return {
			root = root,
			cleanup = function()
				scope:Destroy()
				root:Destroy()
				cleanHost()
				flush()
			end,
		}
	end,
	{
		audit = { textOverflow = not env.IS_ROBLOX },
		check = function(root, vp)
			local RobloxLayout = sert.roblox.Layout
			local controls = lastDynamicControls
			local checkText = not env.IS_ROBLOX
			RobloxLayout.fitsParent(root :: GuiObject)
			RobloxLayout.audit(root, { viewport = vp.size, textOverflow = checkText })

			local valList = root:FindFirstChild("ValueList") :: Frame
			expect(valList ~= nil, "ValueList initially mounted")
			local sword = valList:FindFirstChild("Val_Sword") :: Frame
			local shield = valList:FindFirstChild("Val_Shield") :: Frame
			local potion = valList:FindFirstChild("Val_Potion") :: Frame
			env.expectSpacing({ sword, shield, potion }, "Y", 4)
			RobloxLayout.aligned({ sword, shield, potion }, "left")

			-- Reorder + insert + hide banner
			controls.showAlert:set(false)
			controls.valueItems:set({ "Potion", "Bow", "Sword" })
			flush()
			RobloxLayout.fitsParent(root :: GuiObject)
			RobloxLayout.audit(root, { viewport = vp.size, textOverflow = checkText })
			expect(root:FindFirstChild("AlertBanner") == nil, "AlertBanner unmounted when showAlert is false")
			local bow = valList:FindFirstChild("Val_Bow") :: Frame
			expect(valList:FindFirstChild("Val_Shield") == nil, "Val_Shield unmounted")
			env.expectSpacing({ potion, bow, sword }, "Y", 4)

			-- Switch to forIndex tab and mutate
			controls.tab:set("index")
			controls.indexItems:set({ 100, 200, 300, 400 })
			flush()
			RobloxLayout.fitsParent(root :: GuiObject)
			RobloxLayout.audit(root, { viewport = vp.size, textOverflow = checkText })
			local idxList = root:FindFirstChild("IndexList") :: Frame
			expect(idxList ~= nil, "IndexList mounted on switch")
			local i1 = idxList:FindFirstChild("Idx_1") :: Frame
			local i2 = idxList:FindFirstChild("Idx_2") :: Frame
			local i3 = idxList:FindFirstChild("Idx_3") :: Frame
			local i4 = idxList:FindFirstChild("Idx_4") :: Frame
			env.expectSpacing({ i1, i2, i3, i4 }, "Y", 4)
			RobloxLayout.aligned({ i1, i2, i3, i4 }, "left")
		end,
	}
)

sert.laws.differential("conditional · forValue and forIndex reconciliation matches functional oracle", {
	gen = sert.gen.list(sert.gen.list(sert.gen.pick({ "A", "B", "C", "D", "E", "F" }), 0, 5), 1, 8),
	oracle = function(steps: { { string } })
		local final = steps[#steps]
		local byVal: { string } = {}
		local seen: { [string]: boolean } = {}
		local rank = 0
		for _, item in final do
			if not seen[item] then
				seen[item] = true
				rank += 1
				table.insert(byVal, `{rank}:{item}`)
			end
		end
		local byIdx: { string } = {}
		for i, item in final do
			table.insert(byIdx, `{i}={item}`)
		end
		return `{table.concat(byVal, ",")}|{table.concat(byIdx, ",")}`
	end,
	sut = function(steps: { { string } })
		local valSig = Flux.signal({} :: { string })
		local idxSig = Flux.signal({} :: { string })
		local valContainer: Frame
		local idxContainer: Frame
		local scope = Flux.scope(function()
			valContainer = Flux.new("Frame")({
				Flux.forValue(valSig, function(idxNode, val)
					return Flux.new("TextLabel")({
						Name = val,
						LayoutOrder = idxNode,
						Text = function()
							return `{idxNode()}:{val}`
						end,
					})
				end),
			})
			idxContainer = Flux.new("Frame")({
				Flux.forIndex(idxSig, function(idx, valNode)
					return Flux.new("TextLabel")({
						Name = `Slot_{idx}`,
						LayoutOrder = idx,
						Text = function()
							return `{idx}={valNode()}`
						end,
					})
				end),
			})
		end)
		for _, step in steps do
			local uniq: { string } = {}
			local seen: { [string]: boolean } = {}
			for _, v in step do
				if not seen[v] then
					seen[v] = true
					table.insert(uniq, v)
				end
			end
			valSig:set(uniq)
			idxSig:set(step)
			flush()
		end
		local valChildren = valContainer:GetChildren()
		table.sort(valChildren, function(a: any, b: any)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local gotVal: { string } = {}
		for _, c in valChildren do
			table.insert(gotVal, (c :: TextLabel).Text)
		end

		local idxChildren = idxContainer:GetChildren()
		table.sort(idxChildren, function(a: any, b: any)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local gotIdx: { string } = {}
		for _, c in idxChildren do
			table.insert(gotIdx, (c :: TextLabel).Text)
		end

		scope:Destroy()
		valContainer:Destroy()
		idxContainer:Destroy()
		flush()
		return `{table.concat(gotVal, ",")}|{table.concat(gotIdx, ",")}`
	end,
}, { runs = 60 })

test(
	"forKey · maps by key once per item, keeps untouched rows asleep, warns on duplicate keys, and cleans up scopes",
	function()
		type Entry = { id: string?, label: string }
		local rowA: Entry = { id = "a", label = "Alpha" }
		local rowB: Entry = { id = "b", label = "Beta" }
		local list = Flux.signal({ rowA, rowB })
		local builds = 0
		local keyCalls = 0
		local evalsByKey: { [string]: number } = { a = 0, b = 0 }
		local unmounted = 0

		local scope, mapped = Flux.scope(function()
			return Flux.forKey(list, function(entry: Entry)
				keyCalls += 1
				return entry.id
			end, function(index, item)
				builds += 1
				Flux.cleanup(function()
					unmounted += 1
				end)
				local labelComp = Flux.computed(function()
					local cur = item()
					if cur.id then
						evalsByKey[cur.id] = (evalsByKey[cur.id] or 0) + 1
					end
					return cur.label
				end)
				return Flux.computed(function()
					return `{index()}:{labelComp()}`
				end)
			end)
		end)

		flush()
		expect(mapped()[1]() == "1:Alpha" and mapped()[2]() == "2:Beta", "initial mapped rows")
		expect(builds == 2, "two unique keys built initially")
		expect(keyCalls == 2, "keyOf called exactly once per item on initial pass")
		expect(evalsByKey.a == 1 and evalsByKey.b == 1, "each row evaluated once")

		-- Update only rowB (keeping rowA identical reference) -> rowA's item signal stays asleep!
		keyCalls = 0
		local uniqueWarnings = env.warnings(function()
			list:set({ rowA, { id = "b", label = "Beta2" } })
			expect(mapped()[1]() == "1:Alpha" and mapped()[2]() == "2:Beta2", "updated rowB label")
		end)
		expect(#uniqueWarnings == 0, "unique keys emit zero warnings")
		expect(keyCalls == 2, "keyOf called once per item on update")
		expect(builds == 2, "no rows rebuilt")
		expect(evalsByKey.a == 1 and evalsByKey.b == 2, "unchanged sibling rowA stays asleep in O(1)")

		-- Reorder and rebuild both tables
		list:set({
			{ id = "b", label = "Beta3" },
			{ id = "a", label = "Alpha2" },
		})
		flush()
		expect(builds == 2, "rebuilt item tables with existing keys update in place without rebuilding rows")
		expect(mapped()[1]() == "1:Beta3" and mapped()[2]() == "2:Alpha2", "updated labels and reordered indices")

		-- Replacing one of two unique keys with a duplicate of the other still sweeps the evicted key ('b') even though #list == 2
		local dupSweepWarnings = env.warnings(function()
			list:set({
				{ id = "a", label = "Alpha3" },
				{ id = "a", label = "AlphaDup" },
			})
			mapped()
			flush()
		end)
		expect(
			#dupSweepWarnings == 1 and unmounted == 1,
			"evicted key 'b' unmounts even when duplicate keeps #list == 2"
		)

		-- Duplicate keys warn with Flux.forKey prefix
		local warned = env.warnings(function()
			list:set({
				{ id = "dup", label = "First" },
				{ id = "dup", label = "Second" },
			})
			mapped()
			flush()
		end)
		expect(#warned == 1 and string.find(warned[1], "Flux.forKey", 1, true) ~= nil, "duplicate keys warn accurately")
		expect(unmounted == 2, "leaving key 'a' unmounts and runs row cleanups")

		-- Item with nil key falls back to item identity, and itemNode destroys on eviction and mapper Destroy
		local rawItem: Entry = { id = nil, label = "NilKey" }
		local itemDestroyed = 0
		local itemScope, mappedItems = Flux.scope(function()
			return Flux.forKey(list, function(e: Entry)
				return e.id
			end, function(_idx, itemNode)
				itemNode:onDestroy(function()
					itemDestroyed += 1
				end)
				return "row"
			end)
		end)
		list:set({ rawItem, { id = "keep", label = "Keep" } })
		mapped()
		mappedItems()
		flush()
		expect(mapped()[1]() == "1:NilKey" and builds == 5 and unmounted == 3, "nil key falls back to item identity")
		list:set({ { id = "keep", label = "Keep" } })
		mapped()
		mappedItems()
		flush()
		expect(itemDestroyed == 1, "evicting a keyed row destroys its item signal")
		itemScope:Destroy()
		expect(itemDestroyed == 2, "destroying forKey destroys remaining item signals")

		scope:Destroy()
		expect(unmounted == 5, "destroying outer scope tears down remaining mapped row")
	end
)

test("conditional · show/presence error recovery, stale exit done guard, and selector sweep/Destroy", function()
	-- show: factory reads are untracked; throwing directly from a mounted branch resets output from non-nil to nil and resets activeKey
	local cond = Flux.signal(0 :: any)
	local innerUntracked = Flux.signal("a")
	local showBuilds = 0
	local showScope, shown = Flux.scope(function()
		return Flux.showKeyed(cond, function(val)
			showBuilds += 1
			innerUntracked() -- must be untracked by driver
			local v = val()
			if v == 1 then
				error("branch boom")
			end
			return `ok:{tostring(v)}`
		end)
	end)
	flush()
	expect(shown() == "ok:0" and showBuilds == 1, "initial showKeyed value")
	innerUntracked:set("b")
	flush()
	expect(showBuilds == 1, "reads inside show factory do not re-trigger driver")
	cond:set(1) -- transition directly from mounted "ok:0" to throwing branch so set(output, nil) is exercised
	local warned = env.warnings(flush)
	expect(#warned == 1 and shown() == nil, "throwing branch warns and resets non-nil output to nil")
	-- Also verify non-keyed show resets activeKey so a subsequent truthy value re-mounts
	local boolCond = Flux.signal(1 :: any)
	local boolShow = Flux.show(boolCond, function(val)
		local v = val()
		if v == 1 then
			error("bool boom")
		end
		return `ok:{tostring(v)}`
	end)
	env.warnings(flush)
	boolCond:set(2)
	flush()
	expect(boolShow() == "ok:2", "healing on next truthy value re-mounts cleanly")
	boolShow:Destroy()
	showScope:Destroy()

	-- presence: throwing mount destroys exit node and resets output; factory reads are untracked; premature done() is ignored
	local badExitDestroyed = 0
	local badPresCond = Flux.signal(false)
	local badPres = Flux.presence(badPresCond, function(exiting)
		exiting:onDestroy(function()
			badExitDestroyed += 1
		end)
		error("presence boom")
	end)
	flush()
	badPresCond:set(true)
	local presWarned = env.warnings(flush)
	expect(
		#presWarned == 1 and badPres() == nil and badExitDestroyed == 1,
		"throwing presence destroys exit node and leaves output nil"
	)
	badPres:Destroy()

	local presCond = Flux.signal(true)
	local presUntracked = Flux.signal(1)
	local presMounts = 0
	local capturedDone: (() -> ())? = nil
	local capturedExiting: any = nil
	local exitNodeDestroyed = 0
	local presScope, pres = Flux.scope(function()
		return Flux.presence(presCond, function(exiting, done)
			presMounts += 1
			presUntracked()
			capturedExiting = exiting
			capturedDone = done
			exiting:onDestroy(function()
				exitNodeDestroyed += 1
			end)
			return "mounted"
		end)
	end)
	flush()
	presUntracked:set(2)
	flush()
	expect(pres() == "mounted" and presMounts == 1 and capturedExiting() == false, "presence mounted untracked");
	(capturedDone :: () -> ())() -- premature done while present: must be ignored
	flush()
	expect(pres() == "mounted", "premature done() while not exiting is ignored")

	presCond:set(false)
	flush()
	expect(capturedExiting() == true and pres() == "mounted", "first exit started")
	presCond:set(true)
	flush()
	expect(capturedExiting() == false and pres() == "mounted", "re-entry cancels first exit")
	presCond:set(false)
	flush()
	expect(capturedExiting() == true, "second exit started");
	(capturedDone :: () -> ())()
	flush()
	expect(pres() == nil and exitNodeDestroyed == 1, "completing second exit unmounts and destroys exiting node")
	presScope:Destroy()

	-- selector: >40 unobserved keys sweep cleanly while keeping 20 observed keys, and Destroy tears down per-key nodes
	local selSrc = Flux.signal(1)
	local sel = Flux.selector(selSrc)
	local obsScopes = {}
	local destroyedKeys = 0
	for i = 1, 20 do
		local k = i
		obsScopes[i] = Flux.scope(function()
			Flux.effect(function()
				sel(k)
			end)
		end)
	end
	for i = 21, 70 do
		local k = i
		local tempScope = Flux.scope(function()
			Flux.effect(function()
				sel(k)
			end)
		end)
		flush()
		tempScope:Destroy() -- drops observer so _nodes[k] becomes eligible for sweep
	end
	selSrc:set(2)
	flush()
	expect(sel(2) == true and sel(1) == false, "observed keys stay accurate across >SWEEP_MIN sweep");
	(sel :: any)._nodes[2]:onDestroy(function()
		destroyedKeys += 1
	end)
	sel:Destroy()
	expect(destroyedKeys == 1, "selector:Destroy destroys internal per-key nodes")
	for _, pair in obsScopes do
		pair:Destroy()
	end
end)

test("show · value accessor keeps lastValid during branch switch and onDestroy", function()
	local user = Flux.signal({ name = "Ada" } :: { name: string }?)
	local onDestroyVal: any = nil
	local seenName: string? = nil

	local node = Flux.show(user, function(value)
		local upper = Flux.computed(function()
			return string.upper(value().name)
		end)
		Flux.effect(function()
			seenName = upper()
		end)
		Flux.cleanup(function()
			onDestroyVal = value()
		end)
		return upper
	end)

	flush()
	expect(seenName == "ADA", "initial mounted branch computes name")

	user:set({ name = "Grace" })
	flush()
	expect(seenName == "GRACE", "truthy update keeps branch alive and updates derived value")

	local warnings = env.warnings(function()
		user:set(nil)
		flush()
	end)
	expect(#warnings == 0, `switching away from branch should not error on inner computed, got {#warnings}`)
	expect(onDestroyVal ~= nil and onDestroyVal.name == "Grace", "onDestroy reads last valid branch value")
	expect(node() == nil, "show output clears to nil after branch unmounts")

	node:Destroy()
end)

test("forIndex / forValue / forKey · non-table transitions clean up rows and recover from aborted builds", function()
	local destroyed = 0
	local list = Flux.signal({ "a", "b" } :: any)
	local mapped = Flux.forIndex(list, function(_, item)
		Flux.cleanup(function()
			destroyed += 1
		end)
		return item
	end)

	local first = mapped()
	expect(#first == 2, "forIndex maps initial rows")
	list:set(nil :: any)
	local cleared = mapped()
	expect(#cleared == 0, "forIndex returns empty array on nil source")
	expect(destroyed == 2, `forIndex destroys previous rows on non-table transition, got {destroyed}`)

	list:set({ "c" })
	expect(#mapped() == 1 and mapped()[1]() == "c", "forIndex rebuilds cleanly after nil source")
	mapped:Destroy()

	-- Aborted rebuild + non-table transition resets cache and recovers
	local shouldThrow = true
	local keyedSource = Flux.signal({ { id = 1 }, { id = 2 } } :: any)
	local partialCleaned = 0
	local keyed = Flux.forKey(keyedSource, function(item)
		return item.id
	end, function(_, item)
		if shouldThrow and item:peek().id == 2 then
			error("row 2 boom")
		end
		Flux.cleanup(function()
			partialCleaned += 1
		end)
		return item
	end)

	local ok = pcall(function()
		return keyed()
	end)
	expect(not ok, "aborted row build raises on read")

	shouldThrow = false
	keyedSource:set("not-a-table" :: any)
	expect(#keyed() == 0, "non-table transition after aborted rebuild returns empty table")
	expect(partialCleaned == 1, `non-table transition cleans up surviving partial row, got {partialCleaned}`)

	keyedSource:set({ { id = 3 } })
	local recovered = keyed()
	expect(#recovered == 1 and recovered[1]().id == 3, "forKey recovers cleanly after non-table reset")
	keyed:Destroy()
end)

test("forIndex / forValue / forKey · rejects non-function callbacks eagerly", function()
	expect(not pcall(Flux.forIndex, {}, 123 :: any), "forIndex rejects non-function mapFn")
	expect(not pcall(Flux.forValue, {}, "bad" :: any), "forValue rejects non-function mapFn")
	expect(not pcall(Flux.forKey, {}, "bad" :: any, function()
		return 1
	end), "forKey rejects non-function keyOf")
	expect(not pcall(Flux.forKey, {}, function(v: any)
		return v
	end, "bad" :: any), "forKey rejects non-function mapFn")
end)

test("forValue / forKey / selector · handles NaN safely without table index errors", function()
	local nan = 0 / 0

	local valWarnings = env.warnings(function()
		local mapped = Flux.forValue({ nan, nan }, function(idx)
			return idx
		end)
		expect(#mapped() == 2, "forValue maps array containing duplicate NaN without crashing")
		mapped:Destroy()
	end)
	expect(#valWarnings == 1, `forValue warns once on duplicate NaN items, got {#valWarnings}`)

	local keyWarnings = env.warnings(function()
		local mapped = Flux.forKey({ nan }, function(item)
			return item
		end, function(_, item)
			return item
		end)
		local rows = mapped()
		expect(#rows == 1 and rows[1]() ~= rows[1](), "forKey maps NaN entry with identity fallback")
		mapped:Destroy()
	end)
	expect(#keyWarnings == 1, `forKey warns once on NaN key fallback, got {#keyWarnings}`)

	local src = Flux.signal(nan :: any)
	local defaultSel = Flux.selector(src)
	local defaultSeen: boolean? = nil
	local e1 = Flux.effect(function()
		defaultSeen = defaultSel(nan)
	end)
	flush()
	expect(defaultSeen == false, "default selector treats NaN == NaN as false without table index error")
	src:set(1)
	flush()
	expect(defaultSeen == false and defaultSel(1) == true, "default selector still matches non-NaN keys")

	local nanSel = Flux.selector(src, function(a, b)
		return (a ~= a and b ~= b) or a == b
	end)
	local nanSeen: boolean? = nil
	local e2 = Flux.effect(function()
		nanSeen = nanSel(nan)
	end)
	flush()
	expect(nanSeen == false, "custom selector reads initial non-NaN state for NaN key")
	src:set(nan)
	flush()
	expect(nanSeen == true, "custom selector flips observed NaN slot to true when source becomes NaN")
	src:set(2)
	flush()
	expect(nanSeen == false, "custom selector flips observed NaN slot back to false when leaving NaN")

	e1:Destroy()
	e2:Destroy()
	defaultSel:Destroy()
	nanSel:Destroy()
end)

test(
	"forIndex / forValue / forKey · empty-list fallback caches scope while empty and disposes on fill, non-table, or destroy",
	function()
		local emptyRuns, emptyCleanups = 0, 0
		local list = Flux.signal({} :: { any })

		for _, entry in
			{
				{
					name = "forIndex",
					make = function(src: any, fb: any)
						return Flux.forIndex(src, function(_i, item)
							return Flux.new("Frame")({ Name = tostring(item()) })
						end, fb)
					end,
				},
				{
					name = "forValue",
					make = function(src: any, fb: any)
						return Flux.forValue(src, function(_i, value)
							return Flux.new("Frame")({ Name = tostring(value) })
						end, fb)
					end,
				},
				{
					name = "forKey",
					make = function(src: any, fb: any)
						return Flux.forKey(src, function(item)
							return item.id
						end, function(_i, item)
							return Flux.new("Frame")({ Name = item().name })
						end, fb)
					end,
				},
			}
		do
			emptyRuns, emptyCleanups = 0, 0
			list:set({})
			local tick = Flux.signal(0)
			local tickEffects = 0
			local mapped = entry.make(list, function()
				emptyRuns += 1
				Flux.effect(function()
					tick()
					tickEffects += 1
				end)
				Flux.cleanup(function()
					emptyCleanups += 1
				end)
				return Flux.new("TextLabel")({ Name = `Empty_{emptyRuns}` })
			end)
			local host = Flux.new("Frame")({
				mapped,
			})
			flush()
			local firstOut = host:FindFirstChild("Empty_1")
			expect(emptyRuns == 1 and firstOut ~= nil, `{entry.name}: initial empty list mounts fallback`)
			expect(tickEffects == 1, `{entry.name}: fallback scoped effect ran`)

			list:set({})
			flush()
			expect(
				emptyRuns == 1 and host:FindFirstChild("Empty_1") == firstOut and emptyCleanups == 0,
				`{entry.name}: staying empty reuses cached fallback without remounting`
			)

			list:set({ if entry.name == "forKey" then { id = 1, name = "Row1" } else "Row1" })
			flush()
			expect(
				emptyCleanups == 1 and host:FindFirstChild("Empty_1") == nil and host:FindFirstChild("Row1") ~= nil,
				`{entry.name}: filling list disposes fallback scope and swaps to mapped row`
			)

			tick:set(1)
			flush()
			expect(tickEffects == 1, `{entry.name}: disposed fallback effect no longer reacts`)

			list:set({})
			flush()
			expect(
				emptyRuns == 2 and host:FindFirstChild("Empty_2") ~= nil and host:FindFirstChild("Row1") == nil,
				`{entry.name}: emptying list again mounts fresh fallback`
			)

			list:set(nil :: any)
			flush()
			expect(emptyCleanups == 2 and #host:GetChildren() == 0, `{entry.name}: non-table disposes active fallback`)

			list:set({})
			flush()
			expect(
				emptyRuns == 3 and host:FindFirstChild("Empty_3") ~= nil,
				`{entry.name}: returning to empty table remounts fallback`
			)
			host:Destroy()
			flush()
			expect(
				#host:GetChildren() == 0 and emptyCleanups == 2,
				`{entry.name}: destroying host unparents fallback child while keeping unowned mapper alive`
			)
			mapped:Destroy()
			flush()
			expect(emptyCleanups == 3, `{entry.name}: destroying mapper disposes active fallback`)
		end

		-- Edge cases: nil-returning fallback, throwing fallback, and non-function fallback
		local emptySrc = Flux.signal({} :: { string })
		local nilRuns = 0
		local nilNode = Flux.forValue(emptySrc, function(_i, v)
			return v
		end, function()
			nilRuns += 1
			return nil
		end)
		expect(#nilNode() == 0 and nilRuns == 1, "nil-returning fallback produces empty array and caches")
		emptySrc:set({})
		expect(#nilNode() == 0 and nilRuns == 1, "cached nil-returning fallback does not rerun")
		nilNode:Destroy()

		local boomNode = Flux.forIndex({}, function()
			return 1
		end, function()
			error("empty boom")
		end)
		sert.throws(function()
			boomNode()
		end, "empty boom")
		boomNode:Destroy()

		sert.throws(function()
			Flux.forIndex({}, function()
				return 1
			end, "not a function" :: any)
		end, "fallback must be a function")

		-- Unowned cleanable returned by fallback is disposed when items mount
		local unownedDisposed = 0
		local unownedSrc = Flux.signal({} :: { string })
		local unownedNode = Flux.forValue(unownedSrc, function(_i, v)
			return v
		end, function()
			return {
				Destroy = function()
					unownedDisposed += 1
				end,
			}
		end)
		expect(#unownedNode() == 1 and unownedDisposed == 0, "unowned fallback cleanable stays alive while empty")
		unownedSrc:set({ "x" })
		expect(unownedNode()[1] == "x" and unownedDisposed == 1, "filling list disposes unowned fallback cleanable")
		unownedNode:Destroy()

		-- Mapper row sweep accounting: replacing 2 rows with 1 new row (seen == cacheN - added) still sweeps old rows
		local sweepCleaned: { [string]: number } = {}
		local sweepSrc = Flux.signal({ "a", "b" })
		local sweepNode = Flux.forValue(sweepSrc, function(_i, v)
			Flux.cleanup(function()
				sweepCleaned[v] = (sweepCleaned[v] or 0) + 1
			end)
			return v
		end)
		expect(#sweepNode() == 2, "initial 2-item list builds both rows")
		sweepSrc:set({ "c" })
		expect(
			#sweepNode() == 1 and sweepCleaned.a == 1 and sweepCleaned.b == 1 and sweepCleaned.c == nil,
			"shrinking to 1 disjoint item sweeps both removed rows"
		)
		sweepSrc:set({})
		expect(#sweepNode() == 0 and sweepCleaned.c == 1, "emptying list sweeps final row")
		sweepNode:Destroy()

		-- forKey NaN key falls back to item identity and preserves mapped row across moves
		local nanRow = { name = "nan" }
		local okRow = { id = "ok", name = "ok" }
		local nanSrc = Flux.signal({ nanRow } :: { any })
		local nanBuilds, nanCleanups = 0, 0
		local nanLastIdx: any = nil
		local nanNode: any
		local nanWarns = env.warnings(function()
			nanNode = Flux.forKey(nanSrc, function(item)
				return if item == nanRow then 0 / 0 else item.id
			end, function(idx, item)
				if item() == nanRow then
					nanBuilds += 1
					nanLastIdx = idx
					Flux.cleanup(function()
						nanCleanups += 1
					end)
				end
				return item().name
			end)
			expect(nanNode()[1] == "nan" and nanBuilds == 1 and nanLastIdx() == 1, "forKey builds NaN-key row")
			nanSrc:set({ okRow, nanRow })
			expect(
				nanNode()[1] == "ok"
					and nanNode()[2] == "nan"
					and nanBuilds == 1
					and nanCleanups == 0
					and nanLastIdx() == 2,
				"forKey reuses NaN-key row by item identity when moved"
			)
		end)
		expect(#nanWarns == 2, "forKey warns on each NaN key evaluation")
		nanNode:Destroy()

		-- Aborted mapper rebuild -> non-table reset cleans partial rows and preserves outer tracking
		local shouldThrow = true
		local abortSrc = Flux.signal({ "first", "boom" } :: { string }?)
		local afterSrc = Flux.signal(0)
		local firstCleaned = 0
		local abortNode = Flux.forValue(abortSrc, function(_i, v)
			if v == "boom" and shouldThrow then
				error("row boom")
			end
			if v == "first" then
				Flux.cleanup(function()
					firstCleaned += 1
				end)
			end
			return v
		end)
		sert.throws(function()
			abortNode()
		end, "row boom")
		expect(firstCleaned == 0, "aborted rebuild leaves already-created row alive until reset")

		local outerRuns = 0
		local outer = Flux.computed(function()
			outerRuns += 1
			pcall(function()
				return abortNode()
			end)
			return afterSrc()
		end)
		abortSrc:set(nil)
		expect(outer() == 0 and firstCleaned == 1, "non-table transition after aborted rebuild cleans partial rows")
		afterSrc:set(1)
		expect(outer() == 1 and outerRuns == 2, "retrack after non-table cleanup keeps downstream reads tracked")
		shouldThrow = false
		abortSrc:set({ "recovered" })
		expect(abortNode()[1] == "recovered", "mapper recovers cleanly after non-table reset")
		outer:Destroy()
		abortNode:Destroy()

		-- Throwing empty fallback preserves outer reactive tracking via retrack
		local errSrc = Flux.signal({} :: { string })
		local errAfter = Flux.signal(10)
		local errNode = Flux.forIndex(errSrc, function(_i, v)
			return v
		end, function()
			error("empty retrack boom")
		end)
		local errOuterRuns = 0
		local errOuter = Flux.computed(function()
			errOuterRuns += 1
			pcall(function()
				return errNode()
			end)
			return errAfter()
		end)
		expect(errOuter() == 10 and errOuterRuns == 1, "outer computed captures fallback throw")
		errAfter:set(20)
		expect(
			errOuter() == 20 and errOuterRuns == 2,
			"retrack after throwing empty fallback keeps downstream reads tracked"
		)
		errOuter:Destroy()
		errNode:Destroy()
	end
)

test(
	"forIndex, forValue, forKey · throwing mapFn or keyOf cleans up row state and preserves outer tracking",
	function()
		local function verifyThrowingMapper(
			label: string,
			makeMapped: (src: any, onRow: (failNow: boolean) -> ()) -> any
		)
			local src = Flux.signal({ { id = 1 }, { id = 2 } })
			local ping = Flux.signal(0)
			local outerDep = Flux.signal("a")
			local cleanups = 0
			local leakedRuns = 0
			local outerRuns = 0

			local mapped = makeMapped(src, function(failNow: boolean)
				if failNow then
					Flux.cleanup(function()
						cleanups += 1
					end)
					Flux.effect(function()
						ping()
						leakedRuns += 1
					end)
					error(`{label} boom`, 0)
				end
			end)

			local outer = Flux.computed(function()
				outerRuns += 1
				local ok = pcall(mapped)
				return { ok = ok, dep = outerDep() }
			end)

			local res1 = outer()
			expect(not res1.ok and res1.dep == "a" and outerRuns == 1, `{label}: throwing mapper error caught cleanly`)
			expect(cleanups == 1, `{label}: row cleanup runs when mapper throws (got {cleanups})`)

			local baselineLeaked = leakedRuns
			ping:set(1)
			flush()
			expect(leakedRuns == baselineLeaked, `{label}: leaked row effects do not survive throw`)

			outerDep:set("b")
			local res2 = outer()
			expect(
				not res2.ok and res2.dep == "b" and outerRuns == 2,
				`{label}: outer computed retains downstream tracking after throw`
			)

			outer:Destroy()
			mapped:Destroy()
			src:Destroy()
			ping:Destroy()
			outerDep:Destroy()
		end

		verifyThrowingMapper("forIndex", function(src, onRow)
			return Flux.forIndex(src, function(idx)
				onRow(idx == 2)
				return idx
			end)
		end)

		verifyThrowingMapper("forValue", function(src, onRow)
			return Flux.forValue(src, function(_idx, val)
				onRow(val.id == 2)
				return val.id
			end)
		end)

		verifyThrowingMapper("forKey mapFn", function(src, onRow)
			return Flux.forKey(src, function(item)
				return item.id
			end, function(idx)
				onRow(idx:peek() == 2)
				return idx:peek()
			end)
		end)

		-- Throwing keyOf in forKey cleans up built rows on recovery sweep and restores outer tracking
		local src = Flux.signal({ { id = 1 }, { id = 2 } })
		local outerDep = Flux.signal(1)
		local keyOuterRuns = 0
		local rowCleanups = 0
		local throwKey = true
		local mappedKey = Flux.forKey(src, function(item)
			if throwKey and item.id == 2 then
				error("keyOf boom", 0)
			end
			return item.id
		end, function(_idx, item)
			Flux.cleanup(function()
				rowCleanups += 1
			end)
			return item:peek().id
		end)
		local outer = Flux.computed(function()
			keyOuterRuns += 1
			local ok = pcall(mappedKey)
			return { ok = ok, dep = outerDep() }
		end)
		local r1 = outer()
		expect(not r1.ok and r1.dep == 1 and keyOuterRuns == 1, "forKey keyOf error propagates cleanly")
		outerDep:set(2)
		local r2 = outer()
		expect(
			not r2.ok and r2.dep == 2 and keyOuterRuns == 2,
			"forKey keyOf throw preserves outer downstream tracking"
		)
		throwKey = false
		src:set({ { id = 3 } })
		local r3 = outer()
		expect(r3.ok and rowCleanups == 1, "forKey sweep cleans up rows cached before aborted keyOf throw")
		outer:Destroy()
		mappedKey:Destroy()
		src:Destroy()
		outerDep:Destroy()
	end
)
