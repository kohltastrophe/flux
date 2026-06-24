---
title: Developer Tools
description: Recommended tools for developing with Flux in Roblox.
outline: deep
---

# Developer Tools

You can use Flux entirely within Roblox Studio, but external tools can improve code quality, workflow speed, and project maintainability.

Here are some community tools to pair with your Flux projects.

## Project Synchronization

### Rojo

[Rojo](https://rojo.space/) lets you write code in external editors and sync those files into Roblox Studio. It is a good fit when building complex Flux interfaces, since it lets you use external version control, linters, and formatters.

## Code Quality

### Luau Language Server (luau-lsp)

[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) is the language server that powers autocomplete, go-to-definition, and inline type errors in editors like VS Code and Neovim. It is the tool that makes Flux's strict typing pay off: because the library is written `--!strict`{luau} with fully-typed constructors and `Node<T>`{luau} inference, luau-lsp gives you real property autocomplete inside `Flux.new`{luau}, type-checked reactive bindings, and errors caught before you ever run the game: the "uncompromising IntelliSense" Flux is built around. Generate a [Rojo](https://rojo.space/) sourcemap (`rojo sourcemap --output sourcemap.json`) so it can resolve `require` paths across your project.

### Selene

[Selene](https://kampfkarren.github.io/selene/) is a linter for Luau. It catches common syntax errors, bad practices, and scoping issues before you run your game.

### StyLua

[StyLua](https://github.com/JohnnyMorganz/StyLua) is an opinionated code formatter for Luau. It keeps your Flux components, reactive bindings, and state logic in a consistent style across the codebase, which helps when collaborating with a team.

Beyond these external tools, Flux also ships a development-only [strict mode](/guide/tips/strict) that flags impure reactive bodies.

## Testing

Flux's reactive core is engine-agnostic, so it runs under the vanilla [`luau` CLI](https://github.com/luau-lang/luau) outside Roblox Studio: ideal for fast, headless unit tests of your state and computed logic in CI. Signals, Computeds, Effects, Stores, and the graph all work standalone; only Instance creation and non-number datatype motion still need Studio. See [Testing](/guide/tips/testing) for the harness, virtual-time stepping, and what to run where.

## UI Previewing (Storybooks)

Storybooks let you view, test, and iterate on UI components in isolation, without playtesting the whole game.

Flux ships no native storybook plugin, but every popular Roblox storybook follows the same contract: your story receives a **target** frame to mount into and returns a **cleanup** function that runs when the story is closed. That maps directly onto a Flux [Scope](/guide/concepts/scopes). `Flux.scope(fn)`{luau} returns the scope node plus whatever `fn` returns, so you run your component inside it, parent the result to the target, and return a teardown that calls `scope:Destroy()`{luau}, disposing every node, effect, and instance the component created.

Each example below previews this component, saved as a sibling `Counter.luau`{luau} ModuleScript:

```luau
-- Counter.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local function Counter()
    local count = Flux(0)
    return Flux.new "TextButton" {
        Size = UDim2.fromOffset(200, 50),
        Text = function() return `Clicks: {count}` end,
        Activated = function() count(count + 1) end,
    }
end

return Counter
```

### UI Labs

[UI Labs](https://github.com/PepeElToro41/ui-labs) is a modern previewer with live hot-reloading and a typed **controls** panel for tweaking props while the component runs. A story is a `.story.luau`{luau} ModuleScript; its `story`{luau} function mounts into `props.target`{luau} and returns the cleanup:

```luau
-- Counter.story.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return {
    summary = "A reactive counter",
    story = function(props)
        local scope, root = Flux.scope(Counter)
        root.Parent = props.target
        return function()
            scope:Destroy()
        end
    end,
}
```

### Flipbook

[Flipbook](https://github.com/flipbook-labs/flipbook) is an actively maintained storybook with controls and native support for React, Fusion, and Roact. The story table is the same shape; its mount target is `props.container`{luau}:

```luau
-- Counter.story.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return {
    summary = "A reactive counter",
    story = function(props)
        local scope, root = Flux.scope(Counter)
        root.Parent = props.container
        return function()
            scope:Destroy()
        end
    end,
}
```

### Hoarcekat

[Hoarcekat](https://github.com/Kampfkarren/hoarcekat) is the original, minimal previewer. A `.story.luau`{luau} ModuleScript returns a single function: it receives the preview frame and returns a destructor.

```luau
-- Counter.story.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local Counter = require(script.Parent.Counter)

return function(target)
    local scope, root = Flux.scope(Counter)
    root.Parent = target
    return function()
        scope:Destroy()
    end
end
```

Because this format is the simplest and predates the others, both UI Labs and Flipbook read Hoarcekat stories too, making a bare `function(target)`{luau} story the most portable option.
