---
title: Sync
description: Sharing reactive state between the server and every client.
outline: deep
sidebar_position: 9
---

# Sync

`Flux.Sync` gives you a signal that has the same value on the server and every client. The server owns the value. When you write it on the server, Sync batches the change at the end of the frame and updates every client when the packet arrives.

```luau
-- Shared (ReplicatedStorage)
local round = Flux.Sync("Round", "Lobby")
local coins = Flux.Sync("Coins", 0)

-- Server
round("Fighting")        -- every client sees "Fighting"
coins:of(player)(250)    -- only this player sees 250

-- Client
Flux.new "TextLabel" {
	Text = function()
		return `{round()}: {coins()} coins`
	end,
}
```

## Creating a Synced Signal

Call `Flux.Sync(key, initial, validate?)` from code that runs on both sides, usually a shared module. Every call with the same `key` returns the same signal, typed from `initial` like `Flux.signal`:

```luau
local round = Flux.Sync("Round", "Lobby") -- SyncSignal<string>
print(Flux.Sync.Round == round) --> true
```

`Flux.Sync.Key` looks up a signal by name (`"ready"` and `"flush"` are reserved methods on `Flux.Sync`) and creates it if it doesn't exist yet, starting at `nil`. A later `Flux.Sync(key, initial)` fills in the initial value as long as nothing has written the signal yet. A client can index a key before the server has created it. The client's signal links up and takes the server's value once the server announces it.

> [!WARNING] Typos Create New Signals
> `Flux.Sync.Cions` quietly creates a separate signal named `"Cions"`. Declare each signal once in a shared module with `Flux.Sync(key, initial)` and require that module, rather than indexing by name across files.

A synced signal is a normal `Flux.State<T>`. Read it with `sig()`, `sig:get()`, or `sig:peek()`, update it functionally with `sig:update(fn)` (returning the signal), and use it in computeds, effects, and bound properties. On the server, `coins:of(player):update(fn)` applies a functional update to a single player's override without subscribing the caller.

## How Changes Travel

Writes don't go out right away. Sync collects them and sends one batch per frame, after the reactive graph flushes. If a signal changes three times in a frame, only the last value goes out. Call `Flux.Sync.flush()` to send pending changes right now.

When a player joins, their client asks the server for every current value, so a client never has to wait for remotes with `WaitForChild` (make sure a server script also requires `Flux` so the server creates its remotes and answers the handshake). Until the handshake arrives, a client reads the `initial` it passed. `Flux.Sync.ready` tells you when the handshake has arrived. It's always `true` on the server:

```luau
Flux.new "Frame" {
	Visible = function()
		return not Flux.Sync.ready() -- the loading screen hides once values arrive
	end,
}
```

Each signal is sent with a 1-byte ID (2 bytes after the first 256 signals), so batches stay small. Sync supports up to 65,536 signals.

## Per-Player Values

On the server, `sig:of(player)` returns a signal holding the value that one player sees. Writing it replicates only to that player. It starts from the shared value, and the player keeps their own value until you call `sig:clear(player)`:

```luau
local coins = Flux.Sync("Coins", 0)

Players.PlayerAdded:Connect(function(player)
	coins:of(player)(loadCoins(player))
end)

Players.PlayerRemoving:Connect(function(player)
	saveCoins(player, coins:of(player)()) -- still readable here
end)
```

When a player has their own value, writing the shared value no longer reaches them. Per-player signals are dropped just after the player leaves, so `PlayerRemoving` handlers can still read them. After that, calling `:of` for that player errors. On a client, `:of` returns the signal itself and `:clear` does nothing, so shared code can call both.

## Client Writes

Synced signals are server-only by default. If a client writes one, the write shows locally right away and then rolls back to the server's value. To let clients write a signal, give it a validator. The validator runs on the server for each client write:

```luau
local theme = Flux.Sync("Theme", "Dark", function(player, value)
	return value == "Dark" or value == "Light"
end)

-- Client
theme("Light") -- shows right away, rolled back if the server rejects it
```

Return `true` to accept the value, or `false` (or nothing) to reject it. Return `true, other` to store a different value, such as a clamped number. The sender is corrected whenever the stored value differs from what they sent:

```luau
local volume = Flux.Sync("Volume", 5):validate(function(player, value)
	if type(value) ~= "number" or value ~= value then
		return false
	end
	return true, math.clamp(value, 0, 10)
end)
```

An accepted write goes to the shared value. Once you've called `:of` on the signal, accepted writes go to the sender's own value instead. A validator can also write the signal itself (`sig(v)` or `sig:of(player)(v)`). In that case its return value is ignored.

Call `sig:validate(fn)` at any time to attach or replace a validator, or pass `nil` to make the signal server-only again. Clients ignore `:validate`, so you can call it in shared code.

> [!CAUTION] Validators Must Not Yield
> A validator runs while the server processes a client's message, so it can't wait on a `DataStore` call or `task.wait`. If a validator yields, Sync warns once for that signal and rejects the write. Even though `Validator<T>` types `value` as `T`, network payloads are untrusted: always verify `type(value)` / `typeof(value)` and guard against `NaN` (`value == value`) at runtime.

A client's optimistic value wins until the server has answered that write. A stale correction never overwrites a newer write from the same client.

## Unreliable Signals

`sig:unreliable()` sends a signal's server-to-client changes over an `UnreliableRemoteEvent`. Use it for values that change every frame, like positions or timers, where a dropped update is replaced by the next one:

```luau
local timer = Flux.Sync("Timer", 0):unreliable()
```

Unreliable messages can drop or arrive out of order, and the last value in a burst may never arrive. All `:unreliable()` signals updated in the same server frame share one `UnreliableRemoteEvent` packet (capped around ~900-1,000 bytes by the engine), so keep unreliable payloads small, and pass `false` to switch back. Client writes always travel reliably.

## Limitations

- Sync replicates values, not events. Use a `RemoteEvent` for one-off actions like "play this sound".
- `Flux.setter(sig)` writes the node directly and doesn't replicate. Call the signal or `:set` instead.
- Values must be serializable over a `RemoteEvent` (plain values or tables with string or array keys, without functions or metatables).
- A table changed in place isn't seen as a change. Write a new table, or call `sig:update()` (or `sig:set(value, true)`) to replicate an in-place change.
