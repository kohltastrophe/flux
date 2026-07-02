---
title: API Reference
description: A one-page reference of Flux's public API, grouped by task, with links into the guide.
outline: deep
---

# API Reference

A quick map of Flux's public surface, grouped by what you're trying to do. Signatures are **simplified for readability**; the exhaustive, always-current reference is the strict typing itself, surfaced in your editor by [luau-lsp](/guide/developer-tools#luau-language-server-luau-lsp). Click any row to jump to the guide section that teaches it.

`T`/`U` denote generic types; `Node<T>` is a reactive node; `?` marks an optional argument. A leading `node:`/`selector:`/`context:`/`motion:`/`async:` is a method on that object.

## Reactivity

| Signature                                        | Summary                                                                                             | Guide                                                                                  |
| :----------------------------------------------- | :-------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------- |
| `Flux.signal(init: T, equals?) -> Node<T>`       | Create a writable reactive node.                                                                    | [Signals](/guide/concepts/signals#creating-a-signal)                                   |
| `Flux.computed(fn: () -> T, equals?) -> Node<T>` | Lazily-cached derived node.                                                                         | [Computeds](/guide/concepts/computeds#creating-a-computed)                             |
| `Flux.effect(fn: (prev?) -> ()) -> Node<T>`      | Deferred side-effecting node; re-runs when its deps change.                                         | [Effects](/guide/concepts/effects#creating-an-effect)                                  |
| `Flux(obj, effectOrProperty?) -> Node<T>`        | Call shorthand: signal / computed / effect (or bind-from-Instance).                                 | [Signals](/guide/concepts/signals#creating-a-signal)                                   |
| `Flux.cleanup(obj)`                              | Defer teardown to the current owner: before the enclosing computation re-runs, or on scope destroy. | [Effects](/guide/concepts/effects#cleanup-with-flux-cleanup)                           |
| `Flux.untrack(fn?) -> ...`                       | Read without tracking deps (or suspend tracking if called bare).                                    | [Tracking](/guide/concepts/tracking#flux-untrack)                                      |
| `Flux.retrack()`                                 | Re-enable tracking after a bare `untrack()`.                                                        | [Tracking](/guide/concepts/tracking#imperative-pairing-flux-untrack-flux-retrack)      |
| `Flux.on(deps, fn, defer?) -> (prev?) -> R?`     | Explicit-dependency reaction; runs `fn` untracked on change.                                        | [Tracking](/guide/concepts/tracking#flux-on)                                           |
| `Flux.raw(obj) -> any`                           | Read a node's value **without** tracking.                                                           | [Tracking](/guide/concepts/tracking#flux-raw)                                          |
| `Flux.read(obj) -> any`                          | Read a node's value **with** tracking (passthrough for non-nodes).                                  | [Tracking](/guide/concepts/tracking#flux-read)                                         |
| `Flux.listen(node, fn) -> () -> ()`              | Subscribe to updates (Connect-like, own thread); returns an unsubscribe.                            | [Effects](/guide/concepts/effects#effects-vs-flux-listen)                              |
| `Flux.strict(on?) -> boolean`                    | Toggle/read dev-mode strict graph checks.                                                           | [Strict mode](/guide/tips/strict#enabling-strict-mode)                                 |
| `Flux.isNode(obj) -> boolean`                    | True if `obj` is a reactive node.                                                                   | [Components](/guide/concepts/components#_3-reading-node-or-value-props-with-flux-read) |
| `Flux.isReactive() -> boolean`                   | True when called inside a tracking computed/effect body.                                            | [Tracking](/guide/concepts/tracking)                                                   |
| `node:get() -> T` · `node()`                     | Tracked read of a node.                                                                             | [Signals](/guide/concepts/signals#reading-a-signal)                                    |
| `node:peek() -> T`                               | Untracked read of a node (current value, no subscribe).                                             | [Tracking](/guide/concepts/tracking#flux-raw)                                          |
| `node:set(value, force?)` · `node(value)`        | Write a node (`force` re-fires dependents even when the value is unchanged).                        | [Signals](/guide/concepts/signals#updating-a-signal)                                   |
| `node:Destroy()` · `node:onDestroy(fn)`          | Tear down a node / register a teardown callback.                                                    | [Signals](/guide/concepts/signals#destroying-a-signal)                                 |

## UI Construction

| Signature                                    | Summary                                                                                            | Guide                                                                    |
| :------------------------------------------- | :------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------- |
| `Flux.new(className) -> (props) -> Instance` | Create an Instance with defaults + reactive props.                                                 | [Creation](/guide/roblox/creation#the-flux-new-function)                 |
| `Flux.edit(instance) -> (props) -> Instance` | Hydrate an existing Instance with reactive bindings.                                               | [Hydration](/guide/roblox/hydration#the-flux-edit-function)              |
| `Flux.model(node) -> T`                      | Wrap a node for two-way property/attribute binding.                                                | [Creation](/guide/roblox/creation#flux-model-two-way-binding-in-one-key) |
| `_EVENT = { [signal] = fn }`                 | Directive: `:Connect` handlers & property-change listeners (nested `_ATTR` for attribute changes). | [Hydration](/guide/roblox/hydration#event-two-way-binding-listeners)     |
| `_ATTR = { [name] = value \| node }`         | Directive: set or bind Roblox attributes.                                                          | [Hydration](/guide/roblox/hydration#attr-attributes)                     |
| `_TAG = tag \| node \| { tag \| node }`      | Directive: static or reactive CollectionService tags (diffed: adds new, removes dropped).          | [Hydration](/guide/roblox/hydration#tag-collectionservice-tags)          |
| `_REF = (instance) -> cleanup?` · `Node`     | Directive: receive the built Instance.                                                             | [Hydration](/guide/roblox/hydration#ref-reference)                       |
| `_CLEAN = { Cleanable }`                     | Directive: extra teardown tied to `Destroying`.                                                    | [Hydration](/guide/roblox/hydration#clean-lifecycle-cleanup)             |
| `Flux.attr(name, value)` · `Flux.attr(map)`  | One-off `_ATTR` for the array portion; repeatable.                                                 | [Hydration](/guide/roblox/hydration#one-off-directives)                  |
| `Flux.event(name, fn)` · `Flux.event(map)`   | One-off `_EVENT` for the array portion; repeatable.                                                | [Hydration](/guide/roblox/hydration#one-off-directives)                  |
| `Flux.tag(...tags)`                          | One-off `_TAG` for the array portion; repeatable.                                                  | [Hydration](/guide/roblox/hydration#one-off-directives)                  |
| `Flux.ref(fn \| node)`                       | One-off `_REF` for the array portion.                                                              | [Hydration](/guide/roblox/hydration#one-off-directives)                  |
| `Flux.onDestroy(...items)`                   | One-off `_CLEAN` for the array portion; repeatable.                                                | [Hydration](/guide/roblox/hydration#one-off-directives)                  |
| `Flux.Defaults`                              | Mutable per-class default props auto-applied by `Flux.new` (e.g. `Frame.BorderSizePixel = 0`).     | [Defaults](/guide/roblox/defaults#customizing-defaults)                  |
| `Flux.Flags.defaults`                        | Global on/off for the auto-defaults system (default `true`; `false` builds raw instances).         | [Defaults](/guide/roblox/defaults#disabling-defaults)                    |

## Lifecycle

| Signature                       | Summary                                                                                  | Guide                                                           |
| :------------------------------ | :--------------------------------------------------------------------------------------- | :-------------------------------------------------------------- |
| `Flux.scope(fn) -> (scope, R)`  | Run `fn` in a fresh owner; nodes, instances, and effects created inside are owned by it. | [Scopes](/guide/concepts/scopes#creating-a-scope)               |
| `scope:Destroy()`               | Tear down a scope and everything it owns.                                                | [Scopes](/guide/concepts/scopes#creating-a-scope)               |
| `Flux.getOwner() -> Node?`      | The owner scope currently evaluating (`nil` at the root).                                | [Scopes](/guide/concepts/scopes#capturing-the-active-scope)     |
| `Flux.withOwner(node, fn) -> R` | Run `fn` with `node` as the active owner; new nodes and cleanups attach there.           | [Scopes](/guide/concepts/scopes#capturing-the-active-scope)     |
| `Flux.clean(obj: Cleanable)`    | Recursively dispose instances, connections, threads, functions, arrays, immediately.     | [Scopes](/guide/concepts/scopes#manual-cleanup-with-flux-clean) |

## Control Flow & Mapping

| Signature                                       | Summary                                                                      | Guide                                                                        |
| :---------------------------------------------- | :--------------------------------------------------------------------------- | :--------------------------------------------------------------------------- |
| `Flux.show(cond, comp, fallback?) -> Node`      | Mount `comp` while truthy, `fallback` when falsy; factories get `(value)`.   | [Conditionals](/guide/concepts/conditionals#showing-one-of-two-branches)     |
| `Flux.showKeyed(cond, comp, fallback?) -> Node` | Like `show`, but remounts on value identity change, not just truthiness.     | [Conditionals](/guide/concepts/conditionals#keyed-show)                      |
| `Flux.switch(source) -> (map) -> Node`          | Mount the branch keyed by `source`'s current value; factories get `(value)`. | [Conditionals](/guide/concepts/conditionals#switching-between-many-branches) |
| `Flux.default`                                  | Sentinel key for `switch`'s fallback branch.                                 | [Conditionals](/guide/concepts/conditionals#a-default-branch)                |
| `Flux.forIndex(list, mapFn) -> Node<{U}>`       | Map an array by index; updates item nodes in place.                          | [Mapping](/guide/concepts/mapping#flux-forindex-keyed-by-index)              |
| `Flux.forValue(list, mapFn) -> Node<{U}>`       | Map an array by value (keyed); stable across reorders.                       | [Mapping](/guide/concepts/mapping#flux-forvalue-keyed-by-value)              |

## State

| Signature                                                 | Summary                                                    | Guide                                                                                   |
| :-------------------------------------------------------- | :--------------------------------------------------------- | :-------------------------------------------------------------------------------------- |
| `Flux.store(init: T) -> T`                                | Deep reactive proxy over a plain table.                    | [Stores](/guide/concepts/stores#creating-a-store)                                       |
| `Flux.Store.reconcile(proxy, snapshot, key?) -> T`        | Diff a snapshot in; fire only the changed leaves.          | [Stores](/guide/concepts/stores#reconciling-snapshots)                                  |
| `Flux.Store.unwrap(proxy) -> T`                           | The raw, un-proxied underlying table.                      | [Stores](/guide/concepts/stores#unwrapping-a-store)                                     |
| `Flux.Store.insert(proxy, posOrValue, value?)`            | Reactive `table.insert` for store arrays.                  | [Stores](/guide/concepts/stores#arrays-and-iteration)                                   |
| `Flux.Store.remove(proxy, pos?) -> any`                   | Reactive `table.remove` for store arrays.                  | [Stores](/guide/concepts/stores#arrays-and-iteration)                                   |
| `Flux.Store.move(proxy, from, to)`                        | Reactive reorder of a store array element.                 | [Stores](/guide/concepts/stores#arrays-and-iteration)                                   |
| `Flux.Store.destroy(proxy)`                               | Tear down a store and its nested proxies.                  | [Stores](/guide/concepts/stores#destroying-a-store)                                     |
| `Flux.selector(source, equals?) -> Selector`              | O(1) keyed selection (one active key at a time).           | [Selectors](/guide/concepts/selectors#creating-a-selector)                              |
| `selector:get(key) -> boolean` · `selector(key)`          | Reactively read whether `key` is selected.                 | [Selectors](/guide/concepts/selectors#reading-a-selection)                              |
| `selector:destroy()`                                      | Tear down the selector and its per-key nodes.              | [Selectors](/guide/concepts/selectors#cleaning-up)                                      |
| `Flux.context(default: T) -> Context<T>`                  | Create a dynamically-scoped value.                         | [Context](/guide/concepts/context#creating-a-context)                                   |
| `context:get() -> T` · `context()`                        | Read the innermost provided value, else the default.       | [Context](/guide/concepts/context#providing-and-reading)                                |
| `context:provide(value, fn) -> R` · `context(value, fn)`  | Run `fn` with the context set to `value`.                  | [Context](/guide/concepts/context#providing-and-reading)                                |
| `Flux.wrap(tbl) -> { [any]: Node }`                       | Box a table's plain leaf values into nodes, in place.      | [Wrapping](/guide/concepts/wrapping#basic-usage)                                        |
| `Flux.async(source, fetcher?, initial?) -> Async<T>`      | Race-guarded fetch (`.data`/`.error`/`.loading`/`.state`). | [Async](/guide/concepts/async#creating-an-async-node)                                   |
| `async:refetch()` · `async:mutate(v)` · `async:Destroy()` | Re-run fetcher / optimistic `.data` write / tear down.     | [Async](/guide/concepts/async#refetching-and-mutating)                                  |
| `Flux.safe(tryFn, fallback, equals?) -> Node<T>`          | A Computed that falls back to `fallback` on error.         | [Error Handling](/guide/tips/errors#structured-error-handling-flux-safe-and-flux-catch) |
| `Flux.catch(fn, handler) -> T`                            | Synchronous, untracked try / recover.                      | [Error Handling](/guide/tips/errors#structured-error-handling-flux-safe-and-flux-catch) |

## Motion

| Signature                                              | Summary                                                                                          | Guide                                                                |
| :----------------------------------------------------- | :----------------------------------------------------------------------------------------------- | :------------------------------------------------------------------- |
| `Flux.spring(target, frequency?, damping?) -> Node<T>` | Spring toward `target` (reactive target & params).                                               | [Spring](/guide/motion/spring#basic-usage)                           |
| `Flux.tween(target, info?: TweenInfo) -> Node<T>`      | Tween toward `target`; `info` defaults to 0.3 s cubic.                                           | [Tween](/guide/motion/tween#basic-usage)                             |
| `Flux.Motion.step(now?)`                               | Advance active motions to clock time `now` (defaults to `os.clock()`; auto-called on Heartbeat). | [Testing](/guide/tips/testing#full-engine-tests-in-ci)               |
| `motion:set(value)` · `motion(value)`                  | Retarget the animation goal.                                                                     | [Spring](/guide/motion/spring#reactive-targets)                      |
| `motion:impulse(delta)` · `motion:setVelocity(v)`      | Add / set velocity (spring only).                                                                | [Spring](/guide/motion/spring#velocity-control-impulse-set-velocity) |
| `motion:Destroy()`                                     | Tear down the motion and its node.                                                               | [Spring](/guide/motion/spring)                                       |

The **`Flux.Color`** toolkit (Color3 in/out, gamut-clipped):

| Signature                                                                                             | Summary                                                                  | Guide                                                  |
| :---------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------- | :----------------------------------------------------- |
| `Color.lighten / darken / saturate / desaturate(c, amount) -> Color3`                                 | Adjust lightness or chroma in Oklab.                                     | [Manipulation](/guide/motion/color#manipulation)       |
| `Color.rotateHue(c, degrees) -> Color3` · `Color.grayscale(c) -> Color3`                              | Rotate hue (degrees) / strip chroma.                                     | [Manipulation](/guide/motion/color#manipulation)       |
| `Color.mix(a, b, t) -> Color3`                                                                        | Perceptual blend in Oklab.                                               | [Blending](/guide/motion/color#blending)               |
| `Color.fromTemperature(kelvin) -> Color3`                                                             | Blackbody color for a temperature.                                       | [Construction](/guide/motion/color#construction)       |
| `Color.luminance(c) -> number` · `contrast(a, b) -> number` · `readable(bg, dark?, light?) -> Color3` | WCAG luminance / contrast ratio / auto-readable foreground.              | [Accessibility](/guide/motion/color#accessibility)     |
| `Color.Oklab.*` · `Color.sRGB.*`                                                                      | Lower-level Oklab (Vector3, hue in degrees) and sRGB↔linear conversions. | [Oklab](/guide/motion/color#working-in-oklab-directly) |

## Utilities & Roblox

| Signature                                                                                         | Summary                                                   | Guide                                                                |
| :------------------------------------------------------------------------------------------------ | :-------------------------------------------------------- | :------------------------------------------------------------------- |
| `Flux.padding(value) -> UIPadding`                                                                | UIPadding from a length, per-side table, or node.         | [Layout](/guide/utilities/layout#padding)                            |
| `Flux.list(config?) -> UIListLayout`                                                              | UIListLayout (gap, direction, align, flex semantics).     | [Layout](/guide/utilities/layout#list)                               |
| `Flux.grid(config?) -> UIGridLayout`                                                              | UIGridLayout (cell, gap, fill, align).                    | [Layout](/guide/utilities/layout#grid)                               |
| `Flux.aspectRatio(ratio, type?, axis?) -> UIAspectRatioConstraint`                                | Aspect-ratio constraint (friendly strings or Enums).      | [Layout](/guide/utilities/layout#aspectratio)                        |
| `Flux.sizeConstraint(min?, max?) -> UISizeConstraint`                                             | Reactive pixel size bounds.                               | [Layout](/guide/utilities/layout#sizeconstraint)                     |
| `Flux.flex(mode) -> UIFlexItem`                                                                   | UIFlexItem (`fill`/`grow`/`shrink`/`none`).               | [Layout](/guide/utilities/layout#flex)                               |
| `Flux.viewport: Node<Vector2>`                                                                    | Shared camera viewport-size node.                         | [Responsive](/guide/utilities/responsive#viewport)                   |
| `Flux.scale: Node<number>`                                                                        | UIScale factor derived from the viewport.                 | [Responsive](/guide/utilities/responsive#scale)                      |
| `Flux.breakpoint: Node<Breakpoint>`                                                               | Size-class node derived from viewport width.              | [Responsive](/guide/utilities/responsive#breakpoint)                 |
| `Flux.safeArea: Node<Insets>`                                                                     | Topbar / GUI inset node (`top`/`bottom`/`left`/`right`).  | [Responsive](/guide/utilities/responsive#safe-area)                  |
| `Flux.Responsive.scaleOf(partial?) -> Node<number>` · `breakpointOf(partial?) -> Node`            | Per-surface scale / breakpoint nodes.                     | [Responsive](/guide/utilities/responsive#per-surface-overrides)      |
| `Flux.Responsive.scaleFor(w, h, partial?) -> number` · `breakpointFor(w, partial?) -> Breakpoint` | Pure scale / breakpoint math (no node).                   | [Responsive](/guide/utilities/responsive#pure-helpers)               |
| `Flux.Responsive.config`                                                                          | Mutable live default responsive config.                   | [Responsive](/guide/utilities/responsive#configuration)              |
| `Flux.Find.Child / Descendant / Parent / Query / QueryFirst(query)(props)`                        | Instance selectors: apply props to the match(es).         | [Hydration](/guide/roblox/hydration#instance-selectors-flux-find)    |
| `Flux.Find.Ancestor / AncestorClass / AncestorIsA / ChildClass / ChildIsA(query)(props)`          | Ancestor and class-filtered selectors.                    | [Hydration](/guide/roblox/hydration#available-selectors)             |
| `Flux.flush()`                                                                                    | Drain the pending-effect queue now (deterministic tests). | [Testing](/guide/tips/testing#deterministic-effects-with-flux-flush) |
