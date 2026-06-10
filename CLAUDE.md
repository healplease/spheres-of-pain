# CLAUDE.md — Spheres of Pain

Working notes for Claude. Read this first every session.

**Spheres of Pain** is an original **dark-fantasy cluster bubble-shooter** for desktop,
built in **Godot 4.6** (mechanics faithful to *Clusterz!*, our own grimdark levels/art).

- **Game design + roadmap:** `C:\Users\olhav\.claude\plans\before-we-start-i-swirling-crayon.md` (the GDD).
- **Build status & how to run/test:** see the project memory files (`spheres-of-pain-status`, `godot-verification-workflow`).

---

## Tooling & workflow

**Default to the Godot MCP — it is the primary run+debug loop, not a last resort.**
For *anything* involving the running engine — launching the game, reading
logs/`print()`/errors, inspecting the scene tree or node properties, scaffolding scenes,
screenshotting, running tests — **reach for `mcp__godot__*` FIRST.** Only fall back to a
shell command (PowerShell/Bash `Start-Process`, `--headless`, `System.Drawing`, etc.) when
no MCP tool fits or the MCP path has actually failed — and when you do, say *why* in one line.
If you're about to shell out to drive the engine, stop and `ToolSearch` for the MCP tool first.

The MCP server is **`godot-mcp-enhanced`** (configured in `.mcp.json`, prefix `mcp__godot__*`)
— a large toolset (140+ tools). Discover exact tool names with `ToolSearch` (e.g. "godot run
project", "godot screenshot", "godot game query", "godot run tests") rather than assuming;
names differ from the basic server. Rough map of what to reach for:
- **Run / inspect a live game:** `mcp__godot__game` (`game_bridge_install`, then `game_query`
  for `get_tree`/`find_nodes`/`get_node_properties`/`take_screenshot`, `game_input` to drive it).
- **Headless scene render + AI look:** `mcp__godot__screenshot` (`capture` then `analyze`).
- **Runtime state / logs:** `mcp__godot__runtime`, `mcp__godot__game` queries.
- **Scenes / scripts / tests:** `mcp__godot__scene`, `mcp__godot__script`, `mcp__godot__test`.

Hand-author `.tscn` when you need exact control.
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

**Scratch files go in `temp/`.** Every intermediate/throwaway file a session generates —
screenshots, redirected stdout/stderr logs, cropped frames, scratch inputs/outputs — **must**
be written under `temp/` (gitignored). Never scatter `_run.log`/`_anim_*.png`-style files in
the project root. Clean up when done, but `temp/` keeps stray artifacts out of `git status`
regardless.

**Live gameplay verification:** synthetic *mouse* clicks do NOT reach the Godot window
(keyboard does). To exercise the fire→land→attach pipeline, set env `SOP_AUTOPLAY=1`; the
controller fires scripted shots and prints `[FIRE]/[LAND]/[DROP]` events (gated behind
`_debug`). Prefer driving + reading this via the Godot MCP (`mcp__godot__game`); if you must
shell out, redirect output into `temp/`. A real mouse works in normal play.

**Screenshots:** prefer the MCP — `mcp__godot__screenshot` (headless scene `capture`, then
`analyze`) or `mcp__godot__game` `take_screenshot` for the *running* game (needs
`game_bridge_install`). PowerShell `System.Drawing` + `GetWindowRect`/`CopyFromScreen` (window
title "Spheres of Pain") is the **fallback** for grabbing the actual OS window — e.g. a real
fullscreen play session — and it must save into `temp/`. Always *look* at the result; a blank
frame is a failed launch.

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
- **3D only.** The game ships as a single 3D presentation (`scripts/play3d/`, `scenes/level_3d.tscn`).
  The old 2D presentation has been removed. The simulation still runs in **logical 2D pixel space**
  (`GridModel` + `ShotSimulator`); the 3D views map that plane to/from world space via `to3d`/`to2d`
  (one cell ≈ 1 m). Keep that model/sim dimension-agnostic — only `scripts/play3d/` knows about 3D.
- **Layout:** `scripts/core/` (pure logic), `scripts/play3d/` (3D node behavior), `scenes/`,
  `levels/` (level `.tres`), `tests/`, `art/ audio/ shaders/ themes/`.
- **Levels are data, not code** (`LevelResource` `.tres`) once M2 lands.
- **Input via the named InputMap action `fire`** (LMB), checked with `event.is_action_pressed(...)`.
  The window runs **fullscreen** (`display/window/size/mode=3`); `LevelController3D._input` quits on
  `ui_cancel` (Esc) so there's a way out.
- Keep every rule (match, isolation, growth, randomize) isolated and swappable — the exact
  Clusterz fidelity of a few rules is still being verified against the original.
