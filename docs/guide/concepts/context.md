---
title: Context
description: Passing dependencies down a component tree with dynamically-scoped values, à la SolidJS createContext.
outline: deep
---

# Context

As your UI grows, you often need to make a value (a theme, the active player, a service handle) available to a deeply nested component without threading it through every intermediate function as an argument. This is **dependency injection**, and `Flux.context`{lua} is Flux's answer to it.

If you are coming from SolidJS, this is similar to [`createContext`](https://docs.solidjs.com/reference/component-apis/create-context).

There is one important difference from React or SolidJS, and it shapes everything below. Those libraries inject context through the **component tree**: a child reads whatever its nearest provider ancestor set. Flux has no such tree: components are plain factory functions that run **once** and return Instances, with no retained ownership graph to walk. So Flux context is **dynamically scoped** instead: it is a value that lives on a stack for the synchronous duration of a `provide` call, exactly like a dynamic variable.

## Creating a Context

Call `Flux.context`{lua} with a default value. The default is what reads return when no `provide` is currently active.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)

-- A theme context, defaulting to a dark palette
local ThemeContext = Flux.context({
    background = Color3.fromRGB(20, 20, 24),
    text = Color3.fromRGB(235, 235, 235),
    accent = Color3.fromRGB(120, 170, 255),
})
```

The stored value is **opaque**. Flux never reads or unwraps it, so it can be anything: a plain table as above, a [Signal](/guide/concepts/signals), a [Store](/guide/concepts/stores), a function, or a single primitive. What you put in is exactly what comes back out.

## Providing and Reading

A context has two operations:

- **`context:provide(value, fn)`{luau}** runs `fn` with the context set to `value`, then restores the previous value when `fn` returns. It returns whatever `fn` returns.
- **`context:get()`{luau}** returns the innermost active provided value, or the default if nothing is currently providing.

```luau
print(ThemeContext:get().accent) -- the default accent

ThemeContext:provide({ accent = Color3.fromRGB(255, 120, 120) }, function()
    print(ThemeContext:get().accent) -- the provided accent
end)

print(ThemeContext:get().accent) -- back to the default
```

The scope is strictly **synchronous and dynamic** (not lexical): the provided value is visible to any code that runs while `fn` is on the stack, wherever that code is defined. Nesting works as you would expect: the innermost `provide` wins, and each one restores the value beneath it as it unwinds. The restore is exception-safe: if `fn` throws, the value is still popped before the error propagates.

`nil`{luau} and `false`{luau} are perfectly valid provided values: they shadow the default rather than falling back to it. Independent contexts each keep their own stack, so providing one never disturbs another.

### Call sugar

Calling the context directly is shorthand for these two methods:

```luau
ThemeContext()              -- same as ThemeContext:get()
ThemeContext(value, fn)     -- same as ThemeContext:provide(value, fn)
```

## The Run-Once Caveat

This is the most important thing to understand about Flux context, and it follows from how Flux components work.

> [!CAUTION] Read context at construction, never later
> `context:get()` returns whatever value is on the stack **at the moment it is called**, and once `provide` returns, that is the default again. The component body runs synchronously inside `provide`, so reading there is safe. Code that runs **later** is not: [effects](/guide/concepts/effects), [`async`](/guide/concepts/async) fetchers, and [`forValue`](/guide/concepts/mapping) map bodies are drained on flush, after `provide` has popped, so a `context:get()` inside one reads the **default**. Property bindings are subtler; their initial value is applied synchronously (a context read there is correct), but a binding **re-runs** whenever a reactive dependency changes, and that re-run happens after `provide`, silently switching to the default.

The fix is to **read at construction time** and close over the result. Capture the value into a local while you are still synchronously inside the body, then reference that local from your deferred bindings:

```luau
local new = Flux.new

local function Panel()
    -- Read ONCE, synchronously, at construction. `theme` is a plain captured
    -- value from here on: the deferred bindings below close over it.
    local theme = ThemeContext:get()

    return new "Frame" {
        BackgroundColor3 = theme.background, -- ✅ closes over the captured value

        new "TextLabel" {
            TextColor3 = theme.text,
            Text = "Hello",
        },
    }
end

-- Provide the theme for the SYNCHRONOUS extent in which Panel is built.
local panel = ThemeContext:provide({
    background = Color3.fromRGB(40, 20, 60),
    text = Color3.fromRGB(255, 235, 245),
    accent = Color3.fromRGB(255, 120, 200),
}, Panel)
```

Here `Panel()`{luau} runs entirely inside the `provide` callback, so its `ThemeContext:get()`{luau} sees the provided palette. Because the build is synchronous, every nested component constructed during it sees the same value too; that is how the theme reaches the deep `TextLabel` without being passed as an argument.

Contrast that with the trap, a binding that reads the context alongside reactive state:

```luau
local active = Flux(false)

local function Broken()
    return new "Frame" {
        -- ❌ Reads `active` (reactive) AND the context. The first value, computed
        --    synchronously inside provide, is correct, but when `active` flips the
        --    binding re-runs AFTER provide has popped, so ThemeContext:get() then
        --    returns the DEFAULT palette.
        BackgroundColor3 = function()
            local theme = ThemeContext:get()
            return if active() then theme.accent else theme.background
        end,
    }
end
```

A binding that reads _only_ the context never re-runs, so it happens to keep the value captured at construction, but that is a trap in waiting: the moment it gains a reactive dependency, every re-run reads the default. Capturing into a local at construction sidesteps it entirely.

> [!NOTE] Why not just make context reactive?
> Because the value is read once at construction and captured, context is not a substitute for reactivity. If the thing being provided needs to change over time, provide a [Signal](/guide/concepts/signals) or [Store](/guide/concepts/stores) as the context value: capture the node at construction, then read it reactively in your bindings. The node identity is fixed for the component's lifetime, while its contents stay live.

## Reactive Signals Through Context

Putting a reactive node in the context gives you a stable handle injected at construction, with live contents. Here `Flux(...)`{luau} (shorthand for `Flux.signal(...)`{luau}) creates a [Signal](/guide/concepts/signals) node, and that node is what we store in the context:

```luau
-- The context holds a Signal, not a bare Color3
local AccentContext = Flux.context(Flux(Color3.fromRGB(120, 170, 255)))

local function Button()
    -- Capture the NODE at construction (this is allowed and correct)
    local accent = AccentContext:get()

    return new "TextButton" {
        -- Reading the captured node inside a binding IS reactive and tracked,
        -- so this updates whenever someone sets the accent signal.
        BackgroundColor3 = accent,
        Text = "Click me",
    }
end

local themedAccent = Flux(Color3.fromRGB(255, 120, 200))
local button = AccentContext:provide(themedAccent, Button)

-- Later: every Button built under this provide repaints.
themedAccent:set(Color3.fromRGB(120, 255, 170))
```

The `provide` call only had to be active long enough to hand `Button` the `themedAccent` node. After that, ordinary [tracking](/guide/concepts/tracking) takes over: the binding depends on the captured node, and updates flow normally.

## Summary

- `Flux.context(default)`{luau} creates a dynamically-scoped value with a fallback.
- `context:provide(value, fn)`{luau} sets it for the **synchronous** extent of `fn`, restoring afterward (even on error); `context:get()`{luau} reads the innermost active value, or the default.
- Call sugar: `context()`{luau} reads, `context(value, fn)`{luau} provides.
- The value is opaque; `nil`{luau}/`false`{luau} shadow the default; separate contexts are independent.
- **Read at construction, not in deferred code.** Capture `context:get()`{luau} into a local synchronously inside the `provide` body, then close over it; an effect, `async`/map body, or a binding that re-runs reads only the default. To stay reactive, make the captured value a [Signal](/guide/concepts/signals) or [Store](/guide/concepts/stores).
