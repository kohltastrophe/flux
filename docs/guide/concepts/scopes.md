---
title: Scopes
description: Managing lifecycles and cleaning up reactive state in Flux.
outline: deep
---

# Scopes

In dynamic reactive systems, disposing of unused state, effects, and UI instances (disconnecting connections, destroying instances) prevents memory leaks. **Scopes** manage the lifecycles of groups of reactive objects without boilerplate.

If you are coming from other libraries, a Scope is a reactive root (like SolidJS's [`createRoot`](https://docs.solidjs.com/reference/reactive-utilities/create-root)) combined with a cleanup tracker (similar to the Maid and Trove patterns common in Roblox development).

## Creating a Scope

`Flux.scope(fn)`{luau} runs `fn` in a fresh **owner** and returns two values: the scope node and whatever `fn` returned. The reactions, instances, and cleanups created inside `fn` are owned by that scope, so a single `scope:Destroy()`{luau} tears them all down. (Plain signals are the exception; see [What a Scope Owns](#what-a-scope-owns).)

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

local scope, label = Flux.scope(function()
    local name = Flux("Guest")

    -- This Effect is owned by the scope
    Flux(function()
        print("Hello, " .. name)
    end, true)

    -- This instance is owned by the scope
    return Flux.new "TextLabel" {
        Text = function() return "Welcome, " .. name() end,
        Parent = playerGui,
    }
end)

-- When this system is no longer needed:
scope:Destroy()
-- The Effect and `label` are disconnected and destroyed; `name`, a plain signal, is left for the GC.
```

There is no separate "scoped" constructor. Inside a scope you build state and UI with the **same** `Flux(...)`{luau}, `Flux.new`{lua}, and helpers you use everywhere else; ownership is tracked implicitly.

> [!NOTE]
> `fn` also receives the scope node as its argument: `Flux.scope(function(scope) ... end)`{luau}. Capture it when a nested callback needs to destroy the scope or re-enter it (see [Capturing the Active Scope](#capturing-the-active-scope)).

## What a Scope Owns

Anything created while a scope is active that holds a subscription, a resource, or needs deterministic teardown attaches to it automatically:

- Computeds and Effects (`Flux.computed`{lua}, `Flux.effect`{lua}, `Flux(fn)`{luau})
- Instances from `Flux.new`{lua} and bindings applied with `Flux.edit`{lua}
- [Stores](/guide/concepts/stores), [Async](/guide/concepts/async) tasks, [Selectors](/guide/concepts/selectors), and [mapping](/guide/concepts/mapping) helpers
- [Conditional](/guide/concepts/conditionals) branches from `Flux.show`{lua} and `Flux.switch`{lua}

Destroying the scope tears all of them down. Nothing has to be registered by hand.

> [!NOTE]
> Plain **signals** (`Flux(value)`{luau}, `Flux.signal`{lua}) are the one exception: they hold no subscriptions or resources, so a scope does not own them. A signal is reclaimed by the [garbage collector](/guide/concepts/signals#destroying-a-signal) once you stop referencing it (not torn down on `scope:Destroy()`), which also means its [`onDestroy`](/guide/concepts/signals#destroying-a-signal) fires only on an explicit `:Destroy()`{luau}.

## Nesting Scopes

Scopes nest. Call `Flux.scope`{lua} inside another scope and the inner one becomes a child: destroying the parent destroys the child (and everything in it), while the child stays independently `:Destroy()`{luau}-able. Destroying a child first unlinks it from the parent, so a later parent destroy never double-frees it.

```luau
local session = Flux.scope(function()
    -- A child scope for one screen within the session
    local screen = Flux.scope(function()
        return Flux.new "TextLabel" { Text = "Hello", Parent = playerGui }
    end)

    -- Tear down just this screen...
    screen:Destroy() -- the label is gone; `session` is untouched
end)

-- ...or tear down everything at once
session:Destroy() -- destroys any remaining child scopes too
```

Child scopes are the building block behind [conditional rendering](/guide/concepts/conditionals): each mounted branch lives in its own child scope so it can be swapped out.

> [!TIP]
> Reach for a child scope when a long-lived scope owns sub-regions that come and go independently: tabs, list rows, modals within a session. It keeps cleanup precise without juggling separate top-level scopes.

## Registering Cleanup

For resources Flux does not create itself (manual connections, threads, third-party objects), `Flux.cleanup`{lua} attaches teardown to the current scope. It accepts anything cleanable: a function, an Instance, a connection, a thread, a node, or any object with a `:Destroy()`{luau}/`:destroy()`{luau} method.

```luau
Flux.scope(function()
    Flux.cleanup(workspace.Marker) -- destroyed with the scope
    Flux.cleanup(someSignal:Connect(handler)) -- disconnected with the scope
    Flux.cleanup(function() print("bye") end) -- run on teardown
end)
```

Inside a [Computed](/guide/concepts/computeds) or [Effect](/guide/concepts/effects), `Flux.cleanup`{lua} runs **before each re-run** as well as on destroy, which is how an effect tears down whatever it set up on its previous pass. See [Effects](/guide/concepts/effects#cleanup-with-flux-cleanup).

## Capturing the Active Scope

Inside any reactive body, Flux knows which scope owns the reactions and cleanups you create; that is how `Flux.cleanup`{lua} and implicit ownership find their target. Two low-level escape hatches let you read and re-establish that owner by hand, which matters when ownership would otherwise be lost across a boundary (a deferred callback, a coroutine, a manual helper):

- `Flux.getOwner()`{luau} returns the scope node currently evaluating, or `nil`{luau} at the root. Capture it while you still have it.
- `Flux.withOwner(node, fn)`{luau} runs `fn` with `node` reinstalled as the active scope, so anything it creates (computeds, effects, `Flux.cleanup`{lua} callbacks, instances) attaches to that scope's lifetime. It re-establishes **only the owner**, not dependency tracking; so reads inside `fn` still subscribe the computation that is currently running. Combine it with [`Flux.untrack`](/guide/concepts/tracking) when those reads should not become dependencies (the built-in helpers pair the two).

```luau
local owner = Flux.getOwner() -- grab the active scope before we defer

task.defer(function()
    -- Re-enter `owner` so the cleanup below attaches to it, tearing `late` down on teardown
    Flux.withOwner(owner, function()
        local late = Flux(buildExpensiveThing())
        Flux.cleanup(function() late:Destroy() end)
    end)
end)
```

These are the primitives the built-in helpers (mapping, conditionals, instance binding) use internally to keep ownership correct; most application code only needs `Flux.scope`{lua}.

## Manual Cleanup with `Flux.clean`{lua}

`Flux.clean`{lua} is the cleanup engine behind Scopes and the `__CLEAN` directive, exposed for manual use. It accepts a function, Instance, connection, thread, node, any object with a `:Destroy()`{luau}/`:destroy()`{luau} method, or an array of any of these (recursively), and disposes of it immediately. Individual failures are isolated, so one bad cleanup never aborts the rest:

```luau
Flux.clean({
    connection,
    someInstance,
    function() print("bye") end,
})
```

`Flux.clean`{lua} disposes **now**; `Flux.cleanup`{lua} _defers_ disposal to the current scope's teardown.

## When to Use Scopes

- **UI components** - Wrap each component in a scope. Destroy it when the component unmounts.
- **Minigames or rounds** - Create one scope per round. When the round ends, call `:Destroy()`{luau} to wipe all round-specific UI, state, and effects instantly.
- **Player sessions** - Tie a scope to `Players.PlayerAdded`{lua}. Destroy it in `Players.PlayerRemoving`{lua}.
- **Modal windows** - Create a scope when the window opens; destroy it when it closes.

## Connecting a Scope to an Instance Lifetime

A common pattern ties a scope's lifetime to a Roblox instance with the `__CLEAN` directive, so destroying the instance destroys the scope:

```luau
local function Toast(message)
    local scope, frame = Flux.scope(function(scope)
        local alpha = Flux(1)

        return Flux.new "Frame" {
            BackgroundTransparency = function() return 1 - alpha() end,
            Size = UDim2.fromOffset(300, 60),

            -- Destroy the scope when the frame is destroyed
            __CLEAN = { scope },
        }
    end)

    -- Animate out and destroy after 3 seconds
    task.delay(3, function()
        frame:Destroy() -- triggers __CLEAN, which destroys the scope
    end)

    return frame
end
```

The `Frame` is owned by the scope, and `__CLEAN = { scope }`{luau} closes the loop the other way: if anything destroys the `Frame` (its parent `ScreenGui` going away, for example), the scope and all the state inside it go with it. Destroying either side tears the whole unit down exactly once.
