---
title: Developer Tools
description: Recommended tools for developing with Flux in Roblox.
outline: deep
sidebar_position: 3
---

# Developer Tools

Flux runs directly in Roblox Studio with zero extra tooling and pairs cleanly with external Luau tools for type checking, linting, headless testing, and UI storybooks.

## Editor & Static Analysis

### Luau Language Server (`luau-lsp`)

[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) powers autocomplete, go-to-definition, and inline type diagnostics in VS Code, Cursor, and Neovim. Flux uses Luau type functions (`Flux.new`, `Flux.edit`, `Flux.Props`, `Flux.split`, `Flux.Unwrap`), so enable Luau's **New Type Solver** (`"luau-lsp.types.newSolver": true` in editor settings, `--flag:LuauSolverV2=true` on the CLI, and the New Luau Type Solver in Roblox Studio) for full `--!strict` inference.

Generate a [Rojo](https://rojo.space/) sourcemap so the language server can resolve module paths:

```bash
rojo sourcemap --output sourcemap.json
```

### Rojo, Selene & StyLua

- **[Rojo](https://rojo.space/)** syncs external `.luau` files into Roblox Studio so you can use Git and external editors.
- **[Selene](https://kampfkarren.github.io/selene/)** catches shadowed variables, unused locals, and suspicious Luau constructs.
- **[StyLua](https://github.com/JohnnyMorganz/StyLua)** formats declarative `Flux.new` trees and reactive bindings consistently across your team.

## Headless & Virtual-Time Testing

The `Flux` package loads directly under the standalone [`luau` CLI](https://github.com/luau-lang/luau) with zero setup, so reactive signals, stores, control flow, `Flux.Color.Oklab` vector helpers, `Flux.Responsive`, `Flux.Clock`, and `number` or `vector` animations (`Flux.spring`, `Flux.tween`) run without Roblox globals. Install [`sert`](https://github.com/kohltastrophe/sert)'s headless environment before `require(Flux)` when testing `Instance` trees, `Color3` helpers, layout or interaction helpers, or full Roblox datatypes without launching Studio. See **[Testing](/guide/tips/testing)** for details.

## UI Previewing (Storybooks)

Roblox storybook plugins mount a component into a `target` container and return a cleanup callback. Wrap the component in [`Flux.scope`](/guide/concepts/scopes) and return a cleanup function that calls `scope:Destroy()`. [`Flux.Responsive`](/guide/utilities/responsive) and [`Flux.Interact`](/guide/utilities/interact) stay live in Studio edit mode and inside `PluginGui` docks, so breakpoints, UI scaling, and hover or press states work directly inside storybooks and Studio plugins without pressing Play.

Given a reusable `Counter` component:

```luau
--!strict
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
--!strict
-- Counter.story.luau
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return function(target: Instance)
	local scope, root = Flux.scope(function()
		return Counter()
	end)
	root.Parent = target
	return function()
		scope:Destroy()
	end
end
```

### UI Labs (With Live Controls)

[UI Labs](https://ui-labs.luau.page/docs/stories/advanced/generic) mounts once and streams control edits through `props.subscribe`, which you can forward into a Flux signal:

```luau
--!strict
-- Counter.story.luau
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

type StoryProps = {
	target: Instance,
	controls: { step: number },
	subscribe: (listener: (values: { step: number }) -> ()) -> (),
}

return {
	controls = { step = 1 },
	render = function(props: StoryProps)
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
--!strict
-- Counter.story.luau
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return {
	summary = "A reactive counter",
	controls = { step = 1 },
	story = function(props: { container: Instance, controls: { step: number } })
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
