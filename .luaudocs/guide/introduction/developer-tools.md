---
title: Developer Tools
description: Recommended tools for developing with Flux in Roblox.
outline: deep
sidebar_position: 3
---

# Developer Tools

Flux works out of the box in Roblox Studio, and pairs cleanly with external Luau tooling for typechecking, linting, headless testing, and UI storybooks.

## Editor & Static Analysis

### Luau Language Server (`luau-lsp`)

[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) powers autocomplete, go-to-definition, and inline type diagnostics in VS Code, Cursor, and Neovim. Because Flux is written in `--!strict` mode with typed class constructors and `State<T>` / `Node<T>` inference, `luau-lsp` gives you exact property and event autocomplete inside `Flux.new` and `Flux.edit`.

Generate a [Rojo](https://rojo.space/) sourcemap so the language server can resolve module paths:

```bash
rojo sourcemap --output sourcemap.json
```

### Rojo, Selene & StyLua

- **[Rojo](https://rojo.space/)** syncs external `.luau` files into Roblox Studio so you can use Git and external editors.
- **[Selene](https://kampfkarren.github.io/selene/)** catches shadowed variables, unused locals, and suspicious Luau constructs.
- **[StyLua](https://github.com/JohnnyMorganz/StyLua)** formats declarative `Flux.new` trees and reactive bindings consistently across your team.

## Headless & Virtual-Time Testing

Flux's reactive graph and [`Flux.Clock`](/guide/tips/testing) run under the standalone [`luau` CLI](https://github.com/luau-lang/luau) with zero Roblox dependencies. You can step timers, springs, tweens, and frame flushes deterministically in unit tests without launching Studio. See **[Testing](/guide/tips/testing)** for details.

## UI Previewing (Storybooks)

Roblox storybook plugins mount a component into a `target` container and return a cleanup callback, a direct match for [`Flux.scope`](/guide/concepts/scopes).

Given a reusable `Counter` component:

```luau
-- Counter.luau
local Flux = require(ReplicatedStorage.Flux)

local function Counter(step: Flux.Reactive<number>?)
	local count = Flux.signal(0)
	return Flux.new "TextButton" {
		Size = UDim2.fromOffset(200, 50),
		Text = function()
			return `Clicks: {count()}`
		end,
		Activated = function()
			count(count() + (Flux.read(step) or 1))
		end,
	}
end

return Counter
```

### Hoarcekat (Universal Function Format)

A bare `function(target)` story works in [Hoarcekat](https://github.com/Kampfkarren/hoarcekat), [UI Labs](https://github.com/PepeElToro41/ui-labs), and [Flipbook](https://github.com/flipbook-labs/flipbook):

```luau
-- Counter.story.luau
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return function(target: Instance)
	local scope, root = Flux.scope(Counter)
	root.Parent = target
	return function()
		scope:Destroy()
	end
end
```

### UI Labs (With Live Controls)

[UI Labs](https://ui-labs.luau.page/docs/stories/advanced/generic) mounts once and streams control edits through `props.subscribe`, which you can forward into a Flux signal:

```luau
-- Counter.story.luau
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return {
	controls = { step = 1 },
	render = function(props)
		local step = Flux.signal(props.controls.step)
		props.subscribe(function(values)
			step(values.step)
		end)
		local scope, root = Flux.scope(function()
			return Counter(step)
		end)
		root.Parent = props.target
		return function()
			scope:Destroy()
		end
	end,
}
```

### Flipbook (With Controls)

[Flipbook](https://github.com/flipbook-labs/flipbook) re-runs `story` when a control changes:

```luau
-- Counter.story.luau
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return {
	summary = "A reactive counter",
	controls = { step = 1 },
	story = function(props)
		local scope, root = Flux.scope(function()
			return Counter(props.controls.step)
		end)
		root.Parent = props.container
		return function()
			scope:Destroy()
		end
	end,
}
```
