# CLAUDE.md — Spheres of Pain

Working notes for Claude. Read this first every session.

**Spheres of Pain** is an original **dark-fantasy cluster bubble-shooter** for desktop,
built in **Godot 4.6** (mechanics faithful to *Clusterz!*, our own grimdark levels/art).

- **Game design + roadmap:** `C:\Users\olhav\.claude\plans\before-we-start-i-swirling-crayon.md` (the GDD).
- **Build status & how to run/test:** see the project memory files (`spheres-of-pain-status`, `godot-verification-workflow`).

---

## Tooling & workflow

**Prefer the Godot MCP** for anything involving the running engine — launch the game,
read logs/`print()`/errors, scaffold scenes, screenshot, run tests. It's the primary
run+debug loop. The MCP server is **`godot-mcp-enhanced`** (configured in `.mcp.json`,
prefix `mcp__godot__*`) — a large toolset (140+ tools). Discover exact tool names with
`ToolSearch` (e.g. "godot run project", "godot screenshot", "godot run tests") rather than
assuming; names differ from the basic server. Hand-author `.tscn` when you need exact control.
- Godot executable: `C:\Program Files\Godot\Godot.exe` (also in `.mcp.json` env `GODOT_PATH`).
- Enhanced features (live editor edits, editor screenshots) need the in-editor plugin
  **MCP Server** enabled (it is, in `project.godot [editor_plugins]`) and the editor running;
  otherwise it falls back to headless mode. The plugin runs a localhost WebSocket (port 9090)
  and writes an auth key to `.godot/mcp_editor.key`.

**Unit tests use GUT** (`addons/gut/`, `class_name GutTest`). Tests live in `tests/` as
`test_*.gd`; run headless:
```
& "C:\Program Files\Godot\Godot.exe" --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```
Prints a pass/fail summary; config (`dirs`, `prefix`, `should_exit`) is in `.gutconfig.json`.
**Reimport first** (`--headless --import`) after adding/renaming `class_name` types so the
global class cache is current. Keep the rules core (`GridModel`) covered.

**Live gameplay verification:** synthetic *mouse* clicks do NOT reach the Godot window
(keyboard does). To exercise the fire→land→attach pipeline, set env `SOP_AUTOPLAY=1` and
run via PowerShell with `-RedirectStandardOutput`; the controller fires scripted shots and
prints `[FIRE]/[LAND]/[DROP]` events (gated behind `_debug`). A real mouse works in normal play.

**Screenshots:** no MCP screenshot tool — capture the running window via PowerShell
`System.Drawing` + `GetWindowRect`/`CopyFromScreen` (window title "Spheres of Pain").
Always *look* at the screenshot; a blank frame is a failed launch.

**When unsure about a Godot API/component, consult the docs — don't guess:**
- Docs index: <https://docs.godotengine.org/en/stable/index.html>
- Best-practices index: <https://docs.godotengine.org/en/stable/tutorials/best_practices/>
- Use `WebFetch` on the specific page rather than relying on memory.

---

## Godot best practices (compressed — follow these)

**Scenes vs scripts (the core mental model)**
- A **scene is a class**; it *is* an extension of the script on its root node. Scripts add
  behavior (imperative); scenes declare composition (declarative). They pair 1:1 on the root.
- **Scenes are the primary unit of composition.** Build node hierarchies in `.tscn`, not in
  `_ready()` with `add_child()`. Compose in the editor; script the behavior.
- Split a subsystem into its own scene when it has internal coherence or is reused.
  Runtime-spawned things (projectiles, effects) are **their own scene**, instanced via a
  `preload`ed `PackedScene` → `.instantiate()` (faster, batched, idiomatic).
- Apply OOP to scenes: single responsibility, encapsulation.

**Node alternatives — don't make everything a Node**
- **RefCounted** for custom data/logic classes (auto memory mgmt) — e.g. our `GridModel`.
- **Resource** when you need to save/load or edit in the Inspector — e.g. future `LevelResource` (`.tres`).
- **`static func` / `static var`** for stateless helper libraries — e.g. our `Hex`.
- Nodes are the heaviest; many complex nodes hurt performance. Use the lightest type that fits.

**Scene organization & decoupling**
- Design scenes with **no external dependencies** ("call down, signal up").
- Parent → child: direct method calls or set properties/`@export` references.
- Child → parent / siblings: **signals** (past-tense names: `fired`, `landed`, `item_collected`).
  Mediate sibling talk through the parent. Prefer `Callable`/exported refs over hard `get_node` paths.
- Self-document node requirements with `_get_configuration_warnings()` instead of external notes.

**Autoloads (singletons)**
- Use **only** for broad, self-contained systems that own their own state (save manager,
  audio bus, event bus) and don't mutate others' data. Avoid them for localized logic.
- Alternatives: `class_name` node types, `Resource` for shared data, `static` helpers.

**Acquiring references**
- `const Foo = preload("res://...")` for design-time constants (compile-time safe, autocompletes).
- `@onready var x = $Child` to cache a child once; `@export var x: Node` for inspector-assigned refs.
- `load()` for dynamic/overridable/runtime deps and memory you must free.
- Duck-type safely: `node.has_method(...)`, `node is Type`, or **groups** as implied interfaces.

**Lifecycle callbacks**
- `_init()` script-only setup → `_enter_tree()` → `_ready()` (after children ready; tree-dependent setup).
- `_process(delta)` framerate-dependent (visuals/UI); `_physics_process(delta)` for movement/kinematics.
- Handle input in `_input` / `_unhandled_input` (fire only on events) — **not** by polling in `_process`.
- Set node properties **before** `add_child` (cheaper); set `global_position` *after* entering the tree.
- `Timer` node for periodic work instead of counting in `_process`.

**Data & logic preferences**
- **Array** for ordered iteration/position access; **Dictionary** for key lookups/insert/erase.
  Avoid front-insertions on Arrays. Don't run linear scans over huge data each frame.
- Enums: int compares are fast (need a map for readable names); strings print readably but compare slower.
- `preload` static deps; `load` dynamic ones. Break large scenes into smaller reusable pieces.

**Project organization & VCS**
- `snake_case` for files and folders; `PascalCase` for node names and `class_name`s; `CONSTANT_CASE` for consts.
- Group assets near where they're used; `addons/` for third-party; `.gdignore` to hide a folder from import.
- gitignore `.godot/` and `*.translation`. Use `.gitattributes` for LF endings (+ Git LFS for binary assets).

**GDScript style**
- Static typing everywhere (`var x: int`, `func f() -> Vector2:`). Tabs for indentation.
- `class_name` for the project's own reusable/named types (discoverable globally).
- `_private` prefix for internal members; signals past-tense; one class per file.

---

## This project's conventions

- **Strict model/view split.** Rules live in pure-logic `GridModel` (RefCounted, unit-tested);
  views only reflect the model and never mutate game state.
- **Layout:** `scripts/core/` (pure logic), `scripts/play/` (node behavior), `scenes/`,
  `levels/` (level `.tres`), `tests/`, `art/ audio/ shaders/ themes/`.
- **Levels are data, not code** (`LevelResource` `.tres`) once M2 lands.
- **Input via the named InputMap action `fire`** (LMB), checked with `event.is_action_pressed(...)`.
- **Gotcha:** a full-screen `Control` (e.g. the Background `ColorRect`) defaults to `mouse_filter = STOP`
  and swallows every click before it reaches gameplay `_unhandled_input` — keyboard is unaffected, so
  it looks like "fire is broken but Space works". Set such Controls to `mouse_filter = 2` (Ignore).
- Keep every rule (match, isolation, growth, randomize) isolated and swappable — the exact
  Clusterz fidelity of a few rules is still being verified against the original.
