<img align="left" src="docs/public/logo.svg" width="128" alt="Flux" />
<a href="https://github.com/kohltastrophe/Flux/releases"><img align="right" src=".github/img/link-download-dark.svg" alt="Download"></a>
<a href="http://kohltastrophe.github.io/flux"><img align="right" src=".github/img/link-docs-dark.svg" alt="Docs"></a>
<br/>
<br/>
<br/>
<br/>
<br/>

# Write less. Type better. Run faster.

_A next-generation reactive framework for Luau. Powered by a heavily optimized graph algorithm, strictly typed for uncompromising IntelliSense, and built with a terse syntax that makes building interfaces genuinely fun._

### Why Flux?

The Roblox open-source ecosystem has incredible UI frameworks. Flux was built by studying them, identifying their pain points, and engineering a solution that puts developer experience, type accuracy, and raw execution speed above all else.

#### Next-Generation Speed (Luau-Tuned)

Most reactive frameworks rely on topological sorting, dirty-checking, or heavy virtual-DOM architectures that carry significant overhead for the Luau VM.

Flux runs on a **modified graph coloring algorithm** tuned specifically for Luau's execution environment. Its four-state cache model (`CLEAN`, `CHECK`, `DIRTY`, `BUSY`) means:

- **Zero redundant recomputation** - `CLEAN` nodes are skipped instantly without inspecting their function.
- **Short-circuit propagation** - A `CHECK` node walks its dependency tree and bails out the moment it can prove nothing has changed.
- **Glitch-free evaluation** - The "diamond problem" is resolved without batching hacks; each node is evaluated at most once per flush cycle.
- **Cycle detection at zero cost** - The `BUSY` state catches cyclic writes immediately with a clear error rather than silently hanging.

Effects are batched and flushed in a single `Heartbeat` tick, keeping your UI perfectly in sync without unnecessary intermediate renders.

#### Uncompromising Type Safety

Luau's type checker struggles with deeply nested dictionary properties, often producing broken autocomplete or cryptic cascade errors. Flux was engineered from the ground up to conquer `--!strict` mode.

- **Smart Instance Suggestion:** Flux knows what you're building the moment you name the class.
- **Strict Property Autocomplete:** Every property, event, and attribute is typed at the point of use.
- **Relevant Type Errors:** When things go wrong, Flux surfaces accurate, readable errors, not a wall of inference failures.

#### Zero-Boilerplate Syntax

Boilerplate kills momentum. Flux minimizes code through `__call` metamethods and complete **operator overloading** on every reactive node.

Forget `count:get()` and `count:set(1)`. Just write `count()` and `count(1)`. Arithmetic, comparison, string concatenation, and unary operators all transparently evaluate and track dependencies; reactive expressions read exactly like plain Luau.

##

### License

This project is licensed under the [MIT License](LICENSE.txt).
