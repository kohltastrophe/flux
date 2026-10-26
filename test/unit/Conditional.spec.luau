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

sert.prop("show/showKeyed/switch · the mounted branch follows the source's key", function(g)
	Model.isolated(function(owners)
		local kind = g:pick({ "show", "showKeyed", "switch", "switch+otherwise" })
		local isSwitch = kind == "switch" or kind == "switch+otherwise"
		local withFallback = g:bool()
		local domain: { any } = if isSwitch
			then { nil, "x", "y", "z", "w" }
			else { nil, false, true, 1, TABLE_A, TABLE_B }
		local function genValue(g): any
			return domain[g:int(1, if isSwitch then 5 else 6)]
		end

		local OTHER = {}
		local function selectBranch(value: any): (any, string?)
			if isSwitch then
				if value == "x" or value == "y" then
					return value, value
				elseif kind == "switch+otherwise" then
					return OTHER, "otherwise"
				end
				return value, nil
			end
			local key = if kind == "showKeyed" then value else not not value
			return key, if value then "on" elseif withFallback then "off" else nil
		end

		local source = Flux.signal(genValue(g))
		local input = if g:bool()
			then function()
				return source:get()
			end
			else source
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
		local node
		local owner = Flux.scope(function()
			if isSwitch then
				local map: { [any]: any } = { x = factory("x"), y = factory("y") }
				if kind == "switch+otherwise" then
					map[Flux.otherwise] = factory("otherwise")
				end
				node = Flux.switch(input)(map)
			elseif kind == "show" then
				node = Flux.show(input, factory("on"), if withFallback then factory("off") else nil)
			else
				node = Flux.showKeyed(input, factory("on"), if withFallback then factory("off") else nil)
			end
		end)
		table.insert(owners, owner)
		g:note("%s(%s), fallback: %s", kind, showValue(source:peek()), tostring(withFallback))

		local mounted = false
		local activeKey: any = nil
		local live: any = nil
		local count = 0
		local function check(where: string)
			Flux.flush()
			local value = source:peek()
			local key, name = selectBranch(value)
			if not mounted or key ~= activeKey then
				mounted, activeKey = true, key
				if live then
					live.retired = true
				end
				live = nil
				if name then
					count += 1
					live = { name = name, value = value }
				end
			end
			sert.eq(#mounts, count, `{where}: one factory call per key change`)
			for index, mount in mounts do
				local alive = index == #mounts and live ~= nil
				sert.eq(
					mount.cleaned,
					if alive then 0 else 1,
					`{where}: mount {index} ({mount.branch}) cleaned up once when swapped out`
				)
			end
			if live then
				local mount = mounts[#mounts]
				sert(node:peek() == mount, `{where}: the output is the live mount`)
				sert.eq(mount.branch, live.name, `{where}: {showValue(value)} mounts {live.name}`)
				sert(mount.value == live.value, `{where}: value() in the factory is the value it mounted for`)
			else
				sert(node:peek() == nil, `{where}: no branch for {showValue(value)}`)
			end
		end
		check("initial")

		for _, op in Model.ops(g, { { 3, "set" }, { 2, "flush" } }) do
			if op == "set" then
				local value = genValue(g)
				g:note("source = %s", showValue(value))
				source:set(value)
			else
				g:note("flush")
				check("flush")
			end
		end
		check("end")

		local direct = g:bool()
		g:note(if direct then "node:Destroy()" else "owner:Destroy()")
		if direct then
			node:Destroy()
		else
			owner:Destroy()
		end
		for index, mount in mounts do
			sert.eq(mount.cleaned, 1, `mount {index} ({mount.branch}) cleaned up once in all`)
		end
	end)
end, {
	runs = 150,
	size = 14,
	exhaustive = { size = 2 },
})

sert.prop("presence · mounts on truthy, holds during exit, reverses on re-truthy, and unmounts on done", function(g)
	Model.isolated(function(owners)
		local visible = Flux.signal(g:bool())
		local input = if g:bool()
			then function()
				return visible:get()
			end
			else visible
		local mounts = {}
		local node
		local owner = Flux.scope(function()
			node = Flux.presence(input, function(exiting, done)
				local mount = { exiting = exiting, done = done, cleaned = 0 }
				table.insert(mounts, mount)
				Flux.cleanup(function()
					mount.cleaned += 1
				end)
				return mount
			end)
		end)
		table.insert(owners, owner)

		-- Model states: "unmounted", "mounted", "exiting"
		local state = "unmounted"
		local count = 0
		local pendingDone = false

		local function syncModel()
			Flux.flush()
			local cond = not not visible:peek()
			if cond then
				if state == "unmounted" then
					state = "mounted"
					count += 1
				elseif state == "exiting" then
					state = "mounted"
				end
				pendingDone = false
			else
				if pendingDone then
					if state == "exiting" then
						state = "unmounted"
					end
					pendingDone = false
				elseif state == "mounted" then
					state = "exiting"
				end
			end
			sert.eq(#mounts, count, "mount count matches reference")
			if state == "unmounted" then
				sert(node:peek() == nil, "output is nil when unmounted")
			else
				local active = mounts[#mounts]
				sert(node:peek() == active, "output is the active mount")
				sert.eq(active.exiting:peek(), state == "exiting", "exiting node matches state")
				sert.eq(active.cleaned, 0, "active mount not yet cleaned")
			end
			for i = 1, #mounts - (if state == "unmounted" then 0 else 1) do
				sert.eq(mounts[i].cleaned, 1, `retired mount {i} cleaned once`)
			end
		end

		syncModel()

		for _, op in Model.ops(g, { { 4, "set" }, { 3, "done" }, { 3, "flush" } }) do
			if op == "set" then
				local v = g:bool()
				g:note("visible = %s", tostring(v))
				visible:set(v)
			elseif op == "done" then
				g:note("done()")
				if #mounts > 0 then
					mounts[#mounts].done()
					if state == "exiting" and not visible:peek() then
						pendingDone = true
					end
				end
			else
				g:note("flush")
				syncModel()
			end
		end
		syncModel()

		node:Destroy()
		for i, mount in mounts do
			sert.eq(mount.cleaned, 1, `mount {i} cleaned once after Destroy`)
		end
	end)
end, {
	runs = 150,
	size = 16,
	exhaustive = { size = 2 },
})

sert.prop("pick/fallback · the value matches and a reader re-runs only when it changes", function(g)
	Model.isolated(function()
		local DOMAIN: { any } = { nil, false, "A", "B" }
		local function genValue(g): any
			return DOMAIN[g:int(1, 4)]
		end
		local isPick = g:bool()
		local omitFalse = isPick and g:bool()
		local signals = {}
		local evals = 0
		local function input(name: string): (any, () -> any)
			local initial = genValue(g)
			local form = g:pick({ "node", "getter", "plain" })
			g:note("%s = %s %s", name, form, tostring(initial))
			if form == "plain" then
				return initial, function()
					return initial
				end
			end
			local signal = Flux.signal(initial)
			table.insert(signals, { name = name, signal = signal })
			local current = function()
				return signal:peek()
			end
			if form == "getter" then
				local first = #signals == 1
				return function()
					if first then
						evals += 1
					end
					return signal:get()
				end, current
			end
			return signal, current
		end
		local node, expected, unused
		if isPick then
			local cond, condNow = input("condition")
			local whenTrue, trueNow = input("whenTrue")
			local whenFalse, falseNow = input("whenFalse")
			node = if omitFalse then Flux.pick(cond, whenTrue) else Flux.pick(cond, whenTrue, whenFalse)
			expected = function()
				return if condNow() then trueNow() elseif omitFalse then nil else falseNow()
			end
			unused = function(): any
				return if condNow() then "whenFalse" else "whenTrue"
			end
		else
			local value, valueNow = input("value")
			local default, defaultNow = input("default")
			node = Flux.fallback(value, default)
			expected = function()
				local current = valueNow()
				return if current == nil then defaultNow() else current
			end
			unused = function(): any
				return if valueNow() ~= nil then "default" else nil
			end
		end
		local runs = 0
		local reader = Flux.computed(function()
			runs += 1
			return node()
		end)
		local last = expected()
		sert(reader:get() == last and runs == 1, `{if isPick then "pick" else "fallback"} starts at {last}`)

		for _ = 1, g:int(0, g.size) do
			if #signals == 0 then
				break
			end
			local target = g:pick(signals)
			local value = genValue(g)
			g:note("%s := %s", target.name, tostring(value))
			local untouched = target.name == unused()
			local evalsBefore = evals
			target.signal:set(value)
			local before = runs
			local now = expected()
			sert(reader:get() == now, `the value is {now}`)
			sert.eq(runs - before, if now ~= last then 1 else 0, "the reader re-runs exactly when the value changed")
			if untouched then
				sert.eq(evals, evalsBefore, `writing the unused {target.name} does not re-evaluate`)
			end
			last = now
		end
		reader:Destroy()
	end)
end, {
	runs = 150,
	size = 16,
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
	sert.fails(function()
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

local function runMapper(g, map: any, genList: (g: any) -> { any }, keyOf: (list: { any }, i: number) -> any, check)
	Model.isolated(function(owners)
		local list = Flux.signal({})
		local noise = Flux.signal(0)
		local rows: { [any]: any } = {}
		local function row(key: any)
			local counts = rows[key]
			if counts == nil then
				counts = counters()
				rows[key] = counts
			end
			return counts
		end
		local source = if g:bool()
			then list
			else function()
				return list:get()
			end
		local mapper
		local owner = Flux.scope(function()
			mapper = map(source, function(a, b, key)
				local counts = row(key)
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
		table.insert(owners, owner)

		local live: { [any]: any } = {}
		local current = {}
		local lastResult = nil
		local function readAndCheck(listChanged: boolean)
			local result = mapper:get()
			if not listChanged then
				sert(result == lastResult, "no list change, no rebuild (mapper and teardown reads untracked)")
			end
			sert.eq(#result, #current, "one result per element")
			local nextLive = {}
			for i = 1, #current do
				local key = keyOf(current, i)
				local counts = row(key)
				local before = live[key]
				if before ~= nil then
					sert(result[i] == before, `the row for {key} keeps its result`)
					sert.eq(counts.maps, counts.disposed + 1, `a surviving row ({key}) is not re-mapped`)
				else
					sert.eq(counts.maps, counts.disposed + 1, `a new row ({key}) is mapped once`)
				end
				nextLive[key] = result[i]
			end
			check(result, current)
			for key, counts in rows do
				local alive = if nextLive[key] ~= nil then 1 else 0
				sert.eq(counts.disposed, counts.maps - alive, `{key}: each removed row's result disposed once`)
				sert.eq(counts.nodeDestroyed, counts.maps - alive, `{key}: and its node destroyed once`)
				sert.eq(counts.cleaned, counts.maps - alive, `{key}: and its cleanup run once`)
			end
			live, lastResult = nextLive, result
		end

		local changed = true
		for _, op in Model.ops(g, { { 3, "set" }, { 1, "noise" }, { 2, "read" } }) do
			if op == "set" then
				current = genList(g)
				g:note("list = { %s }", table.concat(table.clone(current) :: any, ", "))
				list:set(table.clone(current))
				changed = true
			elseif op == "noise" then
				g:note("noise")
				noise:set(noise:peek() + 1)
			else
				g:note("read")
				readAndCheck(changed)
				changed = false
			end
		end
		readAndCheck(changed)

		local direct = g:bool()
		g:note(if direct then "mapper:Destroy()" else "owner:Destroy()")
		if direct then
			mapper:Destroy()
		else
			owner:Destroy()
		end
		for key, counts in rows do
			sert.eq(counts.disposed, counts.maps, `{key}: destroying the mapper disposes every row once`)
			sert.eq(counts.nodeDestroyed, counts.maps, `{key}: and destroys every node once`)
			sert.eq(counts.cleaned, counts.maps, `{key}: and runs every cleanup once`)
		end
	end)
end

sert.prop("forValue · rows follow unique values: mapped once per new value, torn down once", function(g)
	local POOL = { "a", "b", "c", "d" }
	runMapper(g, function(source, mapFn)
		return Flux.forValue(source, function(indexNode, value)
			return mapFn(indexNode, value, value)
		end)
	end, function(g)
		local pool, out = table.clone(POOL), {}
		for _ = 1, g:int(0, math.min(#POOL, g.size + 1)) do
			table.insert(out, table.remove(pool, g:int(1, #pool)))
		end
		return out
	end, function(list, i)
		return list[i]
	end, function(result, list)
		for i, value in list do
			sert(result[i].b == value and result[i].a:peek() == i, `row {i} holds {value} with index {i}`)
		end
	end)
end, {
	runs = 150,
	size = 12,
	exhaustive = { size = 2 },
})

sert.prop("forIndex · rows follow positions: mapped once per new slot, torn down once", function(g)
	runMapper(g, function(source, mapFn)
		return Flux.forIndex(source, function(index, itemNode)
			return mapFn(index, itemNode, index)
		end)
	end, function(g)
		return g:list(function(g)
			return g:int(1, 3)
		end, 0, math.min(4, g.size + 1))
	end, function(_, i)
		return i
	end, function(result, list)
		for i, value in list do
			sert(result[i].a == i and result[i].b:peek() == value, `slot {i} holds {value}`)
		end
	end)
end, {
	runs = 150,
	size = 12,
	exhaustive = { size = 2 },
})

-- Selector ------------------------------------------------------------------------------------------------------------

test("selector · unobserved keys are swept once enough new keys are read", function()
	local active = new("kept")
	local sel = Flux.selector(active)
	local seenKept, seenMany, seenAgain
	local gone = Flux.effect(function()
		sel("gone")
	end)
	local kept = Flux.effect(function()
		seenKept = sel("kept")
	end)
	flush()
	gone:Destroy()

	local many = Flux.effect(function()
		local n = 0
		for k = 1, 100 do
			if not sel(k) then
				n += 1
			end
		end
		seenMany = n
	end)
	flush()
	expect(seenMany == 100, "every key read false")
	expect(sel._nodes.gone == nil, "the unobserved key was swept")
	expect(seenKept == true, "an observed key reads right after the sweep")

	active(7)
	flush()
	expect(seenMany == 99 and seenKept == false, "values flip correctly after a sweep")
	expect(sel:get("gone") == false, "an untracked read of a swept key is right")
	local again = Flux.effect(function()
		seenAgain = sel("gone")
	end)
	flush()
	expect(seenAgain == false, "a swept key is recreated when read again")
	active("gone")
	flush()
	expect(seenAgain == true, "and the new node flips")
	kept:Destroy()
	many:Destroy()
	again:Destroy()
	sel:Destroy()
end)

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

sert.prop("selector · per-key readers match the reference and only flipped keys re-run", function(g)
	Model.isolated(function(owners)
		local custom = g:bool()
		local function reference(value: number?, key: number): boolean
			if custom then
				return value ~= nil and value % 3 == key % 3
			end
			return value == key
		end
		local function genValue(g): number?
			local n = g:int(0, 5)
			return if n == 0 then nil else n
		end

		local source = Flux.signal(genValue(g))
		local noise = Flux.signal(0)
		local getterRuns = 0
		local useGetter = g:bool()
		local input = if useGetter
			then function()
				getterRuns += 1
				return source:get()
			end
			else source
		local sel
		local selScope = Flux.scope(function()
			sel = Flux.selector(input, if custom then reference else nil)
		end)
		table.insert(owners, selScope)
		Flux.flush()
		local readerScope = Flux.scope(function() end)
		table.insert(owners, readerScope)
		g:note(
			"selector(%s source = %s, custom: %s)",
			if useGetter then "getter" else "node",
			tostring(source:peek()),
			tostring(custom)
		)

		local readers = {}
		local earlyRun = false
		local function checkFlush(where: string)
			local getterBefore = getterRuns
			Flux.flush()
			local value = source:peek()
			for _, reader in readers do
				local expected = reference(value, reader.key)
				sert.eq(reader.value, expected, `{where}: reader of key {reader.key}`)
				if reader.checked ~= nil then
					local flipped = expected ~= reader.checked
					local reran = reader.runs - reader.checkedRuns
					sert(reran <= 1, `{where}: key {reader.key} re-ran at most once`)
					if not flipped and not earlyRun then
						sert(reran == 0, `{where}: key {reader.key} did not flip, so did not re-run`)
					end
				end
				reader.checked, reader.checkedRuns = expected, reader.runs
			end
			earlyRun = false
			return getterRuns - getterBefore
		end

		for _, op in
			Model.ops(g, {
				{ 4, "set" },
				{ 1, "noise" },
				{ 2, "peek" },
				{ 3, "reader" },
				{ 1, "drop" },
				{ 3, "flush" },
			})
		do
			if op == "set" then
				local value = genValue(g)
				g:note("source = %s", tostring(value))
				source:set(value)
			elseif op == "noise" then
				g:note("flush, noise, flush")
				checkFlush("before noise")
				noise:set(noise:peek() + 1)
				local before = getterRuns
				checkFlush("noise")
				if useGetter then
					sert.eq(getterRuns, before, "an unrelated write does not re-run the source getter")
				end
			elseif op == "peek" then
				local key = g:int(1, 5)
				local tracked = g:bool()
				local expected = reference(source:peek(), key)
				g:note("%s read of key %d", if tracked then "fresh tracked" else "untracked", key)
				if tracked then
					local probe = Flux.computed(function()
						return sel(key)
					end)
					sert.eq(probe:get(), expected, `a fresh tracked read of key {key} is current before the flush`)
					probe:Destroy()
				else
					sert.eq(sel:get(key), expected, `an untracked read of key {key} is current before the flush`)
				end
				earlyRun = true
			elseif op == "reader" then
				local key = g:int(1, 5)
				g:note("reader of key %d", key)
				local reader = Model.reader(readerScope, true, function()
					return sel(key)
				end)
				reader.key = key
				table.insert(readers, reader)
			elseif op == "drop" then
				if #readers > 0 then
					local index = g:int(1, #readers)
					g:note("drop reader %d", index)
					table.remove(readers, index).node:Destroy()
				end
			else
				g:note("flush")
				checkFlush("flush")
			end
		end
		checkFlush("end")

		local direct = g:bool()
		g:note(if direct then "sel:Destroy()" else "scope:Destroy()")
		if direct then
			sel:Destroy()
		else
			selScope:Destroy()
		end
		source:set((source:peek() or 0) + 1)
		Flux.flush()
		for _, reader in readers do
			sert.eq(reader.runs, reader.checkedRuns, `key {reader.key}: a destroyed selector re-runs no reader`)
		end
		sert(not pcall(sel, 1), "a read after Destroy errors")
		sel:Destroy()
	end)
end, {
	runs = 150,
	size = 16,
	exhaustive = { size = 2 },
})

test("selector · a key read only by an unobserved computed stays right across a sweep", function()
	local active = new("a")
	local sel = Flux.selector(active)
	local lazy = Flux.computed(function()
		return sel("x")
	end)
	expect(lazy() == false, "not selected")
	local many = Flux.effect(function()
		for k = 1, 100 do
			sel(k)
		end
	end)
	flush()
	expect(sel._nodes.x == nil, "the key read only by an unobserved computed was swept")
	active("x")
	flush()
	expect(lazy() == true, "the computed re-runs on its next read and sees the new selection")
	active("a")
	flush()
	expect(lazy() == false, "and keeps following it")
	many:Destroy()
	sel:Destroy()
end)

return {}
