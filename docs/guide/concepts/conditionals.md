---
title: Conditional rendering
description: Mounting and swapping UI branches reactively with Flux.show and Flux.switch.
outline: deep
---

# Conditional rendering

`Flux.show`{lua} picks between two UI subtrees; `Flux.switch`{lua} picks among many. Each runs the chosen branch once, keeps the reactive bindings inside it updating, and rebuilds only when the condition flips.

This is needed because components in Flux are factory functions: they run **once** when they mount, and only the property bindings inside them re-evaluate afterwards. So "show this UI when X, otherwise show that" is a question of _structure_, not one you can answer by toggling a property: you need to actually build one subtree, tear it down, and build another when the condition flips. (If you are coming from SolidJS, `Flux.show`{lua} and `Flux.switch`{lua} are the equivalents of [`<Show>`](https://docs.solidjs.com/reference/components/show) and [`<Switch>`](https://docs.solidjs.com/reference/components/switch-and-match).)

## Showing one of two branches

`Flux.show`{lua} takes a condition, a component factory, and an optional fallback factory:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local loggedIn = Flux(false)

local view = Flux.show(
    -- CONDITION: a Node, a `() -> any` getter, or a plain value (truthiness decides)
    loggedIn,

    -- COMPONENT: runs once when this branch mounts, inside its own child Scope
    function()
        return new "TextLabel" {
            Text = "Welcome back!",
        }
    end,

    -- FALLBACK (optional): runs once when the condition is falsy
    function()
        return new "TextButton" {
            Text = "Log in",
        }
    end
)
```

Each branch factory receives one argument: a `value` accessor (a `() -> any`{luau} getter for the condition's current value, the equivalent of the value SolidJS's `<Show>` hands its callback children). Read `value()`{luau} inside a binding or effect to track the live value (it updates without remounting); read it once in the factory body for a snapshot. The factory runs inside its own child [Scope](/guide/concepts/scopes) (covered in [Branch scopes and cleanup](#branch-scopes-and-cleanup) below), so anything it builds with `new`{luau}, `Flux(...)`{luau}, or `Flux.cleanup`{lua} is owned by that branch. The examples above ignore the argument, which is fine.

The condition can be any of three things, and truthiness alone decides the branch:

- a **Node** (a Signal, Computed, or any reactive node), tracked, so flipping it swaps branches,
- a **`() -> any`{luau} getter**, invoked inside a tracked context, so any reactive state it reads becomes a dependency (use this when the condition is derived, e.g. `function() return health() <= 0 end`{luau}),
- a **plain value**, evaluated once; useful for a branch that is decided at build time and never changes.

`Flux.show`{lua} returns a **Node** whose value is the current branch's output. The factory may return an [`Instance`](https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance), an array of Instances, or anything else: whatever it returns becomes the Node's value.

### Only truthiness changes trigger a rebuild

The branch is keyed on the condition's **truthiness**, not its value. Toggling between two truthy values does **not** rebuild; the existing branch stays mounted, and any reactive bindings inside it update as normal.

```luau
local user = Flux(nil)

local card = Flux.show(user, function(value)
    return new "TextLabel" {
        -- `value()` tracks the live condition value, so this binding stays
        -- correct across truthy -> truthy changes without remounting
        Text = function()
            return "Signed in as " .. value().name
        end,
    }
end)

user({ name = "Ada" })  -- nil -> truthy: builds the branch
user({ name = "Grace" }) -- truthy -> truthy: NO rebuild, the Text binding just updates
user(nil)               -- truthy -> falsy: destroys the branch (no fallback -> value is nil)
```

This mirrors SolidJS, where `<Show>` does not re-render its children just because the value it carries changed, only because it crossed the visible/hidden boundary.

### Remounting on identity change {#keyed-show}

Sometimes you want the opposite: a full teardown and rebuild whenever the value changes, not just when it crosses the truthy/falsy line, to reset a branch's internal state when the thing it represents changes. `Flux.showKeyed`{lua} keys on the value's **identity** instead of its truthiness:

```luau
local selected = Flux(firstUser)

local panel = Flux.showKeyed(selected, function(value)
    local user = value() -- fixed for this branch's lifetime: read it directly, no tracking
    local draft = Flux(user.name) -- per-user editing state, fresh on every switch

    return new "TextBox" {
        Text = draft,
        FocusLost = function()
            save(user.id, draft:get())
        end,
    }
end)

selected(secondUser) -- truthy -> truthy: REMOUNTS, so `draft` resets to secondUser.name
```

Because the branch is rebuilt on every identity change, the value handed to the factory is fixed for that branch's lifetime; read it directly with `value()` rather than tracking it. This is the equivalent of SolidJS's [`<Show keyed>`](https://docs.solidjs.com/reference/components/show): plain `Flux.show`{lua} keeps the subtree and lets its bindings update (SolidJS `equals: !a == !b`), while `Flux.showKeyed`{lua} discards and rebuilds it (SolidJS `equals: a == b`). Reach for it when a branch caches per-value state that a live binding cannot cleanly reset; reach for plain `Flux.show`{lua} otherwise, since keeping the subtree is cheaper.

## Using the result as a child

The Node returned by `Flux.show`{lua} (and `Flux.switch`{lua}) is built to drop straight into a numeric index of `Flux.new`{lua} or `Flux.edit`{lua}, exactly like a list of children. Flux binds it as children: when the branch swaps, the old instances are parented out (and destroyed with their branch scope) and the new ones take their place.

```luau
local new = Flux.new

local screen = new "Frame" {
    Name = "Root",
    Size = UDim2.fromScale(1, 1),

    new "UIListLayout" {},

    -- The show-node sits at a numeric index, just like any other child
    Flux.show(loggedIn, ProfilePanel, LoginPanel),
}
```

A common shape is a three-state page (loading, error, content) driven by an [Async](/guide/concepts/async) node:

```luau
local profile = Flux.async(currentUserId, fetchProfile)

local page = new "Frame" {
    Size = UDim2.fromOffset(320, 160),

    Flux.show(
        profile.loading,
        Spinner, -- shown while the fetcher is yielding
        function()
            -- The fallback handles "not loading": error or data
            return Flux.show(profile.error, ErrorBanner, function()
                return ProfileCard(profile.data)
            end)
        end
    ),
}
```

## Switching between many branches

When you have more than two cases, `Flux.switch`{lua} keys on a source's current value instead of a boolean. It is a curried call: `Flux.switch(source)(map)`{luau}, where `source` is a Node, a getter, or a plain value, and `map` is a table from key to factory.

```luau
local activeTab = Flux("home")

local content = Flux.switch(activeTab)({
    home = function()
        return new "TextLabel" { Text = "Home" }
    end,

    settings = function()
        return SettingsPanel()
    end,

    profile = function()
        return ProfilePanel()
    end,
})
```

`Flux.switch`{lua} mounts the factory for the source's **current value** and swaps (destroying the old branch's scope) whenever the key changes. Selecting the **same** key again is a no-op; like `Flux.show`{lua}, it only rebuilds when the key actually changes.

### A default branch

If the source's value has no matching key, the branch is empty and the Node's value is `nil`{luau}. Add a `Flux.default`{lua} entry to mount a fallback factory for any unmatched value:

```luau
local content = Flux.switch(activeTab)({
    home = HomePanel,
    settings = SettingsPanel,

    -- Mounts whenever activeTab matches no other key
    [Flux.default] = function(value)
        return new "TextLabel" {
            Text = function()
                return `Unknown tab: {value()}`
            end,
        }
    end,
})
```

All unmatched values share the **one** default mount: switching between two different unmatched keys keeps the default branch in place rather than rebuilding it. Like `Flux.show`{lua}, each `switch` factory also receives a `value` accessor as its second argument. A keyed factory's `value()` returns its own matching key; the default factory's tracks whichever value is currently unmatched, so reading `value()` inside a binding or effect (as above) renders the live unmatched value even though the mount is reused.

## Branch scopes and cleanup

Each branch factory runs inside its **own child [Scope](/guide/concepts/scopes)**. Anything it creates (effects, computeds, nested instances, async resources, event connections) is destroyed automatically when the branch unmounts. This is the cleanup guarantee that makes conditional rendering safe: you never have to manually disconnect a branch's reactivity.

```luau
local content = Flux.switch(activeTab)({
    live = function()
        -- This effect belongs to the branch scope, so it is torn down
        -- the moment the user switches away from the "live" tab.
        Flux(function()
            print("polling for live updates...")
        end, true) -- the `true` makes this an Effect (see [Effects](/guide/concepts/effects))

        return LiveFeed()
    end,

    archive = function()
        return ArchiveList()
    end,
})
```

> [!CAUTION]
> Whatever the factory creates _while it runs_ is bound to that branch; its effects and cleanups are torn down (and any plain signals dropped for the GC) on the next swap. State created **outside** the factory (in an enclosing scope or at module load) belongs to that other owner, so it survives remounts and you manage its lifetime there.

### Tying a branch to a parent scope

Created inside a [`Flux.scope`](/guide/concepts/scopes), a show or switch is tied to that scope: destroying the scope cascades down through the driver and whatever branch is currently mounted, tearing them down.

```luau
local app, view = Flux.scope(function()
    return Flux.show(loggedIn, ProfilePanel, LoginPanel)
end)

-- `view` drops into the UI tree; later, tear it all down at once:
app:Destroy()
```

Reach for a standalone `Flux.show`{lua} / `Flux.switch`{lua} when the conditional's lifetime is governed by the instance tree it is parented into; wrap it in a `Flux.scope`{lua} when you want an explicit scope to own it.

> [!NOTE] No built-in exit animations
> A branch is destroyed **synchronously** the instant its condition flips, so `Flux.show`{lua} and `Flux.switch`{lua} can't tween the outgoing subtree out on their own. To fade or slide content out, animate a **property** of a permanently-mounted instance (`Visible`, `Position`, transparency) from the condition with a [spring](/guide/motion/spring) or [tween](/guide/motion/tween), instead of swapping structurally. For a structural swap that still needs an exit transition, keep the outgoing instance owned by an enclosing scope (so the swap doesn't destroy it) and `:Destroy()`{luau} it yourself once the tween finishes.
