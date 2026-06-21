# Spheres of Pain

A dark-fantasy **cluster bubble-shooter** for desktop, built in **Godot 4.7** (GDScript).
Mechanically faithful to *Clusterz!*, with our own grimdark levels and art.

The game ships as a single **3D presentation** (`scripts/play3d/`, `scenes/level_3d.tscn`),
but the simulation runs in pure **logical 2D pixel space** (`GridModel` + `ShotSimulator`,
unit-tested under `tests/`). The 3D views only reflect the model — they never mutate game state.

---

## Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| **Godot** | **4.7** (standard build) | The GDScript/standard editor — **not** the .NET/mono build. |
| **Git** | any | To clone the repo. |
| **Python** | 3.8+ | Only needed for the lint/format tooling (`gdtoolkit`). Optional but recommended. |

---

## First-time setup

> [!IMPORTANT]
> `addons/` is **gitignored**, so a fresh clone ships **without GUT**. `project.godot` references it
> as an enabled editor plugin, so install it before running the test suite. The game itself has **no
> addon dependencies** — it runs and exports without anything in `addons/`.

### 1. Clone

```bash
git clone <repo-url> spheres-of-pain
cd spheres-of-pain
```

### 2. Install GUT (only needed for the tests)

GUT is the project's **only** addon. Install it at the **exact version** below — easiest via the
in-editor **AssetLib** tab (search the name, Download, Install). It must land at the listed path. If
you only want to play or export the game, you can skip this step.

| Addon | Version | AssetLib search | Source | Install path | Needed for |
| --- | --- | --- | --- | --- | --- |
| **GUT** (Godot Unit Test) | 9.6.0 | `Gut` | [bitwes/Gut](https://github.com/bitwes/Gut) | `addons/gut/` | Running the unit tests |

> [!NOTE]
> **GUT** is an enabled editor plugin used only by the test suite — the game itself has no addon
> dependencies. Installing it fresh from the AssetLib lands it at `addons/gut/` with correct internal
> references.

### 3. Install the lint/format tooling (recommended)

We keep GDScript consistent with [`gdtoolkit`](https://github.com/Scony/godot-gdscript-toolkit)
(`gdformat` + `gdlint`):

```bash
pip install gdtoolkit
```

This gives you the `gdformat`, `gdlint`, and `gdparse` CLIs (see [Code quality](#code-quality-gdtoolkit)).

### 4. Open the project

Open `project.godot` in Godot 4.7. The editor should load with no errors. If you installed GUT and
see a plugin error, re-check that it exists at `addons/gut/` and is enabled under
*Project Settings → Plugins*.

---

## Running the game

- **In the editor:** press **F5** (or the Play button). `main_menu.tscn` is the main scene.
- The window runs **fullscreen**; press **Esc** (`ui_cancel`) in a level to quit.
- **Fire** is the `fire` input action (left mouse button).

Headless launch (substitute your Godot binary; on Windows it's `C:\Program Files\Godot\Godot.exe`):

```bash
godot --path .
```

---

## Running the tests

Unit tests live in `tests/` as `test_*.gd` (GUT, `class_name GutTest`). Run them headless:

```bash
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```

This prints a pass/fail summary. Config (`dirs`, `prefix`, `should_exit`) lives in `.gutconfig.json`.

> [!TIP]
> After adding or renaming a `class_name` type, **reimport first** so the global class cache is
> current: `godot --headless --import`.

---

## Code quality (gdtoolkit + pre-commit)

GDScript is kept consistent with `gdformat` + `gdlint` (rules in `.gdlintrc`), run automatically on
commit via [pre-commit](https://pre-commit.com). Set it up once per clone:

```bash
pip install pre-commit      # if you don't have it
pre-commit install          # installs the git hook
```

After that, `gdformat` (auto-format) and `gdlint` (lint) run on your staged `.gd` files at every
commit. Run them manually anytime:

```bash
pre-commit run --all-files  # format + lint the whole tree
gdformat .                  # auto-format in place
gdformat --check .          # check only, no writes (CI-friendly)
gdlint .                    # lint only
```

> [!NOTE]
> `pip install gdtoolkit` installs `gdformat`/`gdlint` into your Python **Scripts** directory — add
> that to your `PATH` to call them directly (on Windows it's e.g. `…\Python\…\Scripts`). The
> pre-commit hook fetches its own pinned gdtoolkit, so the hook works even if they aren't on `PATH`.

`.gdlintrc` follows our conventions: static typing, tabs, `snake_case` files, `PascalCase`
`class_name`s, `CONSTANT_CASE` consts, `_private` prefix for internals, past-tense signals;
`addons/`, `.godot/`, and `temp/` are excluded.

---

## Project layout

```
scripts/core/      Pure game logic (RefCounted, Log-free) — GridModel, ShotSimulator, Hex
scripts/play3d/    3D node behavior (board view, level controller, shooter, projectile)
scripts/           Autoloads — log.gd, game_state.gd, sound_manager.gd, settings.gd
scenes/            main_menu, level_select, settings, level_3d, ui/
levels/            Level data (.tres)
tests/             GUT unit tests (test_*.gd)
art/ audio/ shaders/ themes/   Assets
addons/            Third-party plugins (gitignored — see setup above)
temp/              Scratch dir for logs/screenshots (gitignored)
```

**Architecture:** strict model/view split — rules live in the pure-logic `GridModel` (unit-tested);
views reflect the model and never mutate game state. The model/sim stays dimension-agnostic; only
`scripts/play3d/` knows about 3D, mapping the logical plane to world space (one cell ≈ 1 m).

---

## AI-assisted development (optional)

This repo is set up for AI-assisted work with Claude Code. See [`CLAUDE.md`](CLAUDE.md) for the
working conventions, the Godot MCP config (`.mcp.json`), the observability/log workflow
(`temp/session.log`), and the headless verification commands.
