# Spheres of Pain — Design Backlog (Epics & Subtasks)

> A multi-cycle design backlog distilled from a deep analysis of the current build
> plus three research threads (genre/replayability design, game-feel/"juice", and
> dark-fantasy tone fusion). **This is a roadmap, not a single sprint.** It captures
> everything deemed worthy — including directions not yet chosen for development —
> so future cycles can pull from it.
>
> **How to read this.** Each EPIC is a theme with a design rationale, what exists
> today, and a priority. Each subtask is design-first: *what & why*, a light
> *Where to look* pointer (so a future Claude knows the system to touch — not a code
> spec), an effort guess (S/M/L), and a *Precedent* where one informed the idea.
> **Tone test** appears where an idea risks fighting the "earned despair" pillar.
>
> **The core insight that runs through all of it:** the architecture already
> *computes* most of this value — we mostly need to *express* it. The orphan-sweep
> is already returned (`AttachResult.orphaned`) but never scored; the RNG is already
> seeded (`GridModel.rng`) so a daily challenge is nearly free; the event spine
> (`_on_landed`, `_check_end`, `_end`, danger tiers) is already where a narrator and
> juice hang. Cheapness is the recurring theme.

---

## Where the game stands today (baseline)

- **Core (excellent, done):** pure `GridModel` + `ShotSimulator` + `Hex` + `ShotBag`,
  103 GUT tests. Rules: cluster match-3, orphan sweep, growth-on-dud,
  randomize-on-miss, three indestructible types (black/spin/bounce), win/lose, danger
  proximity. Model/view split is strict and Log-free.
- **Content:** 15 hand-authored `LevelResource` levels (ASCII layout + per-level theme
  colors), sequential unlock, paged level-select.
- **Presentation:** 3D sphere meshes, perspective camera, dark `WorldEnvironment`
  (fog/glow/grading), abyss backdrop, ember particles, frame veins, pulsing danger
  line, danger vignette + heartbeat audio escalation, ~12 shaders, ambient bed + 8
  pop SFX + UI sfx, gothic fonts/theme, glitch/shiver text shaders.
- **Shell:** `GameState`/`Settings`/`Sound`/`Log` autoloads, settings (video/graphics/
  audio/gameplay) with live-apply, progress + settings persistence, Windows + Web CI.
- **The honest gaps (what this backlog addresses):** no scoring/combo/objective
  variety; thin action feedback (no shake/particles/stings); the toy-vs-trial
  premise is stated, never *spoken*; no replay modes; no pause/records/endgame/
  tutorial/meta-progression; sphere colours have no colorblind-safe sigil yet
  (flagged "critical" in the GDD but unbuilt).

---

## Recommended first iteration — "The Ossuary" vertical slice
*(Chosen by the user: pillars E1 + E2 + E3, scoped to one region. Listed here as the
suggested entry point; the epics below are the full backlog it draws from.)*

Take the existing 5 Ossuary levels (L1–L5) and make them a complete proof of the
realized game by pulling the **cheap, high-leverage** subtasks from three epics:
E1.1 (lock fiction) · E1.2 (narrator) · E1.4 (region framing) · E2.1 (fx slider) ·
E2.2 (camera shake) · E2.3 (pop particles) · E2.4 (crescendo) · E2.7 (win/lose
stings) · E3.1 (isolation scoring) · E3.3 (par + winnability) · one of E3.4
(free-the-soul objective). Juice + scoring ship as game-wide systems; fiction +
region + par are authored on the Ossuary, then scaled. Prove it, then widen.

---

# EPIC 1 — The Voice & the Fiction
**Pillar:** Identity / light narrative. **Priority: HIGHEST (cheapest, most unique).**

**Why it matters.** Every precedent that punches above its budget (Darkest Dungeon,
Bastion, Hades, Dark Souls, Cultist Simulator) earns atmosphere by *layering theme
onto a shared mechanical chassis*, not authoring bespoke content. We already fire
events; hanging a voice and a coherent fiction on them makes the whole game read as
"authored" for roughly the cost of a text file. This is also the direct answer to
"how do we expand the odd grim-dark × bubble-shooter combination?" — **make the
clash deliberate.** Studied genre: "dark cozy" — keep the *form* comfortingly
familiar (a gentle toy), detonate the *meaning* underneath.

**Status today.** Per-level `lore_fragment` lines exist (grim, good) but are isolated;
regions/hub/bosses from the GDD are unbuilt; no narrator; verdicts say "THE SPHERES
CONSUME YOU" but the fiction is never explained.

### E1.1 Lock the core fiction ("The Unmaking")  `effort: S`
Write a one-paragraph bible and propagate it. **The fiction:** the etched orbs are
**trapped souls held in the wall of the pit**; matching like-to-like does not destroy
them, it **releases / unmakes** them (the game never resolves mercy vs. annihilation —
"they will not thank you"). You are a **gravedigger/psychopomp**, not a hero, working
a wall that never empties. Growth-on-dud = the dead crowding back; crossing the danger
line = the dead reclaiming you. This makes *every existing mechanic diegetic for free.*
*Where to look:* GDD `before-we-start-i-swirling-crayon.md` (new §2.10) + status memory.
*Precedent:* Inscryption/DDLC (master a mechanic, then darken its meaning); Miyazaki on gaps.

### E1.2 Reactive grim narrator system (text-only)  `effort: M`
A second-person, liturgical, **never-repeating** line fired on real events — the single
highest atmosphere-per-effort device. Short (one breath), cold courtesy, no jokes/hype.
*Design:* event-keyed line pools with "recently said" memory (reshuffle on exhaustion),
optional per-region sub-pools. Lines are **data not code** (a `NarratorLines` resource,
mirroring the "levels are data" philosophy). Surface as a fading subtitle on the play
HUD (reuse the lore-line fade choreography). Sample lines:
- start: *"You descend again. The dead do not mind the company."*
- big clear: *"So many, freed at once. They will not thank you."*
- lucky chain: *"How easily it comes apart. Mind it does not teach you confidence."*
- danger rising: *"The wall remembers every face it has swallowed."*
- defeat: *"And so you join the pattern you came to break."*
*Where to look:* new `Narrator` autoload (mirror the `Sound` autoload shape); hook
`level_controller_3d.gd` events (`_ready` intro, `_on_landed`, `_update_heartbeat`,
`_end`); surface via `CenterBanner`-style fades. *Precedent:* Bastion (short + never
repeat), Hades (event-conditional barks), Darkest Dungeon narrator.

### E1.3 Lore fragments → region micro-arcs  `effort: S`
Re-author the existing one-liners into per-region 5-beat arcs that *imply, don't
narrate* (*"They ran out of ground here. So they began to stack."*). Let some hint at
mechanics (breadcrumbs). Keep one breath each.
*Where to look:* `levels/level_*.tres` `lore_fragment`. *Precedent:* Cultist Simulator
(obscurity as feature), Dark Souls item descriptions.

### E1.4 Regions + vertical descent hub map  `effort: M`
Group the 15 levels into **named regions** (5 each) — *The Ossuary, The Drowned
Cloister, The Ashen Vigil* — each costing only a palette + motif + ambient key +
framing line + fragment arc + a named boss landmark. Build a **vertical descent map**
(a single column going *down* — "there is only ever down"). The hub gives the *return*
meaning. (Slice version: region headers in level-select; full map scene later.)
*Where to look:* new `RegionResource` or region metadata in `GameState`; level-select
grouping; a new `descent_map.tscn` for the full version. *Precedent:* Darkest Dungeon
Hamlet (place from ~5 nodes), Slay the Spire map legibility, FTL visible-exit journey.

### E1.5 Boss framing per region  `effort: M (per boss)`
An oversized hand-crafted board with a unique cruel gimmick and a name (The
Tally-Keeper, The Choirmistress, The Last Warden). Frame each as "this one was a
person, once."
*Where to look:* a `LevelResource` with a `boss` flag + bespoke layout; narrator
hooks. *Precedent:* Inscryption bosses, DD region bosses.

### E1.6 Failure-as-fiction: epitaph & victory screens  `effort: S`
Reword end states into the fiction, not "Game Over": defeat = *"And so you join the
pattern…"*; victory = exhausted relief (*"The wall is quiet. For now you are not in
it."*), never a fanfare. An optional grim epitaph tally (*"Forty-one freed. None
thanked you."*).
*Where to look:* `_check_end`/`_end` + `CenterBanner.show_end`. *Precedent:* DD death,
Spelunky death summaries.

### E1.7 Naming grammar & all-15-cleared epilogue  `effort: S`
A consistent *[The] + [grim rite/place noun]* naming grammar everywhere (avoid
fantasy-generic); a short epilogue/credits when the whole descent is complete (today
the last level just shows a generic win).
*Where to look:* titles across `levels/`, menus; a new end-of-game screen.

### E1.8 Marketing identity (the hook, externalized)  `effort: S`
Lock the tagline **"It looks like a toy. It is a trial."**; design a capsule/first
screenshot that carries *both* signals at once (friendly toy-arrangement of orbs +
ink-black gothic frame — the orb double-read). Positioning line: *[grimdark]
[bubble-shooter]* — clashing nouns ARE the pitch. Stage the in-game reveal as a slow
burn (near-pleasant first level; narrator sharpens by level 3–4).
*Where to look:* store page assets, `main_menu.tscn` first-run framing. *Precedent:*
Akupara hook+anchor, Zukowski (clarity > cleverness; dark tone is a solo-dev advantage).

---

# EPIC 2 — Weight & Dread (Game Feel / Juice)
**Pillar:** Oppressive presentation. **Priority: HIGH.**

**Why it matters.** Big clears currently land with no *impact* — feedback is audio +
state-change, not physical. The juice canon (Jonasson/Purho "Juice it or lose it",
Nijman "Art of Screenshake", Swink "Game Feel") and the horror canon are the **same
parameters pointed in opposite directions.** Keep the structure, **invert the
envelope:** fast attack / slow asymmetric decay, low-frequency lurch not buzz, **cubic
response** (routine pops barely register; only catastrophe slams), dim desaturated red
not white, particles that **fall and die** not confetti, **descending** pitch not
ascending. Discipline is the brand: a light-show on every match reads arcade, not grim.

**Status today.** Spheres scale-spawn and scale+fade-pop (staggered by hex distance);
pulsing danger line; danger vignette + heartbeat escalation; ambient + pop SFX. **No**
screen shake, particle burst, projectile trail, impact flash, slow-mo, or win/lose
sting.

### E2.1 Master "Effects Intensity" slider (build FIRST)  `effort: S`
A single persisted `fx_intensity` (0..1) that *every* juice effect multiplies by —
accessibility backbone and the gate for everything below. At 0 the game stays fully
playable and grim (dread survives on fog/ambience/environment). Default **1.0** so the
intended feel ships. Label "Effects Intensity / Reduce motion & flashing" — **never**
"epilepsy mode".
*Where to look:* mirror the existing `text_glitch` pattern 1:1 — `SettingsStore` get/set,
`Settings` global-shader-uniform + read-through getter, Graphics tab slider.
*Precedent:* GAccG, WCAG 2.3.1; Vlambeer's real lesson = many small tasteful tricks.

### E2.2 Trauma-based ROTATIONAL camera shake (the backbone)  `effort: M`
One `trauma` scalar; events add, it decays; shake = `trauma²·max_angle` via noise,
applied as **camera rotation, never translation** (translational shake in perspective =
nausea). Dread tuning: low noise speed (lurch), max ~1–3°, slow decay so it lingers.
One `add_trauma(x)` API drives all tiers (land ~0.15 / small pop ~0.3 / big clear
~0.5–0.7 / catastrophe ~0.95).
*Where to look:* `StageView` (owns `_camera`); offset around the rest orientation set in
`_place_camera`; restore each `_process`. *Precedent:* Squirrel Eiserloh "Juicing Your
Cameras" (cubic trauma; rotational only).

### E2.3 Pooled pop-burst particles — death, not confetti  `effort: M`
A pooled one-shot burst per popped cluster, scaled by magnitude, layering: **embers**
(few, dim, the only emissive layer, gravity DOWN), **ash/smoke** (desaturated, no
emission, downward drift — the visual mass), **bone shards** (heavy, tumbling), and a
few **soul-wisps** (cold, low-alpha, the *only upward* layer — a freed soul rising; it
reads as meaningful because everything else falls). Never white-cored; don't touch env
glow.
*Where to look:* new `pop_burst.tscn` (GPUParticles3D, `restart()` to fire, pool on
`finished`); trigger from `_on_landed`/`BoardView3D`. *Precedent:* horror color theory
(drained/desaturated/low-value); Godot ParticleProcessMaterial.

### E2.4 Big-chain crescendo (slow-mo + pitch ladder + drone)  `effort: M`
Make a large chain a building dread crescendo: pops **descend** ~1 semitone per step
(invert the happy ascending combo); a sub-bass **drone** swells with magnitude and
tails out slowly; on the final pop, dip `Engine.time_scale`≈0.35 for ~300ms **matched
by** `AudioServer.playback_speed_scale` (drags all audio down in pitch for free).
Sequence build → peak (shake+slow-mo+pulse together) → aftermath (drone tail). Gate
hard on magnitude; scale by `fx_intensity`.
*Where to look:* `_on_landed` (magnitude already computed); `Sound` buses; restore tween
must `set_ignore_time_scale(true)`. *Precedent:* horror sound design (downward
transposition, sub-bass), Vlambeer hit-stop.

### E2.5 Hit-stop, impact flash, heavy squash  `effort: S–M`
Reserve a short freeze-frame for big clears only; a per-sphere **emission** flash
(glow from within, more sinister than albedo) with asymmetric envelope (fast rise ~50ms,
slow ebb ~400ms, dim blood-red, peak alpha ≤0.25); *heavy* squash (deform little,
settle slowly — weight, not bounce).
*Where to look:* `_on_landed`; `BoardView3D` pop anim; scale child mesh not logical node.
*Precedent:* Vlambeer hit-stop; Disney 12 principles (squash for weight).

### E2.6 Projectile weight, trail, recoil  `effort: M`
Slow flight (~18→~12 m/s) so the orb reads heavy; a dim desaturated contrail (child
particles in world space — avoid built-in `trail_enabled` bugs); make the flying orb
the brightest thing on screen (slight emission); a small launcher recoil + tiny camera
pitch-kick on fire (restraint — fires every shot); optional brief anticipation wind-up
on aim-hold.
*Where to look:* `projectile_3d.gd`, `shooter_3d.gd`, `_on_fired`. *Precedent:* Nijman
named tricks; classic animation anticipation/follow-through.

### E2.7 Win/lose stings + lose vignette close  `effort: S–M`
**Win = relief not fanfare:** heartbeats fall out, duck ambience, one low sustained
tone/distant bell, vignette recedes, environment eases a few % toward calm ("a held
breath let out in a cold room"). **Lose = payoff hit:** hard-stop heartbeats, ~150ms
dead air (the silence makes it land), then a sub-bass drop/dissonant swell; vignette
closes past 1.0 + a black `ColorRect` fills + saturation→0. One smooth tween, never
strobe.
*Where to look:* `_end`; reuse `Sound` + `DangerView`/`danger_vignette.gdshader`. New
clips via the **find-assets** skill (user-approved). *Precedent:* stinger theory (attack
+ dissonance, not volume); "silence is scary".

### E2.8 Dark screen-wide pulse on big clears  `effort: S`
An *inward* red/black throb (tunnel-vision/injury constriction), not an outward bright
flash; a sub-bass thump. Reuse the danger vignette with a one-shot `pulse()`.
*Where to look:* `DangerView`. *Precedent:* injury/vignette feedback conventions.

> **Tone test for the whole epic:** anything firing every shot must be near-subliminal;
> only rare big events may be loud. Periodically strip all juice ("juice detox") — if
> the core only feels good *with* juice, the juice is masking a design hole.

---

# EPIC 3 — Skill & Despair (Scoring & Depth)
**Pillar:** Honest, readable, fair rules. **Priority: HIGH.**

**Why it matters.** Every level shares one goal (clear the board) and rewards nothing
beyond a single clear. The genre's skill-DNA is non-reflex and consistent: pay
super-linearly for **detachments** (our orphan sweep — already computed!), reward one
big trigger over many small, give a marquee **all-clear** bonus, reward **economy**
(unused shots), and gate top tiers behind a **solver-verified** threshold. All reinforce
"earned despair"; all are mostly latent value.

**Status today.** No score, combos, cascades, objectives, or par. Pure win/lose binary.

### E3.1 Exponential isolation scoring + clean-clear bonus  `effort: S`
Score the **orphan sweep** super-linearly by mass (the genre's marquee skill event),
modest for the matched pop, plus a flat **clean-clear ("perfect sweep")** bonus and an
unused-shots economy component. Keep `GridModel` pure — all inputs come from
`AttachResult.popped/orphaned` + shot count.
*Where to look:* new pure `Scoring` helper (unit-testable, Log-free); accumulate in
`_on_landed`. *Precedent:* Puzzle Bobble drops double 20→40→80…; Puyo all-clear; Tetris
perfect clear; Snood ~9× for dropping.

### E3.2 Diegetic surfacing (no arcade counter)  `effort: S`
Surface score *quietly, in fiction*: a HUD **"Souls freed N"** tally (understated, not
flashing) and an end-screen **verdict tier** ("Freed them cleanly / Freed them /
Barely"). Score is how cleanly you ended the suffering, not a celebratory number.
*Where to look:* `_update_status`, `_end`/`CenterBanner`. **Tone test:** reject anything
that rewards speed (no time bonuses).

### E3.3 Solver-verified par + efficiency tiers + winnability validator  `effort: M`
Add `par_shots` to `LevelResource`; tiers reward economy (clear / +1 to spare / +2).
Build a **headless winnability validator** (greedy/bounded search over the pure
`GridModel`+`ShotSimulator`) that proves each level is **clearable** in CI — making
brutality *provably fair* (the literal Miyazaki/Stephen's-Sausage-Roll thesis). Tune par
so the correct first move can look like a mistake until the board resolves.
*Where to look:* `LevelResource`; GUT test using the pure core; `_check_end` for the
tier. *Precedent:* JellySplit ("every level provably 3-starrable"), Hexcells solver.
(Full *optimal* par solver = deferred; ship winnability + hand-tuned par first.)

### E3.4 Secondary win-conditions (one verb, many goals)  `effort: M each`
Hold the verb constant, vary the *goal* to keep 15→40+ levels fresh. Deterministic,
spatial, on-tone options:
- **Free the trapped soul** — release a caged sphere (cage with black walls); win when
  it's cleared. Grimdark-native, the most fiction-aligned (start here). *No model change:
  tag objective cells in `LevelResource` (`@` char), controller checks they're empty.*
- **Cleanse cursed/marked cells** — win by clearing specific designated cells (points the
  player at a brutal corner).
- **Tight shot budget** ("Sniper") — the honest scarcity-pressure for a logic puzzle.
- **Shot-paced descending tide** — the dark tide drops one row *per shot* (never per
  second).
*Where to look:* `LevelResource` `objective_type` enum + params; a `_check_objective()`
in the controller alongside `is_won()`. **Tone test:** never real-time/timed goals —
King removed Candy Crush timed levels; clocks fight "spatial logic, not reflex".
*Precedent:* Candy Crush jelly/order/moves, Bubble Witch "save the ghost", GMTK
"versatile verbs".

### E3.5 "Fair brutality" design checklist (apply to all content)  `effort: ongoing`
A shipping checklist, not a feature: determinism = fair punishment (keep the core
RNG-free at decision time, or seeded-and-visible); a loss is fair only if the player
*sees why* (render the fatal board/move on defeat); menace must match real threat (the
scariest-looking state must be the genuinely most punishing); ramp via new spatial
rules/tighter margins, **not** "more spheres, faster"; mine unexplored consequences of
existing rules before adding mechanics; **the level is the tutorial** (teach safe →
recur → combine → brutalize; never stack three novel interactions at once); fast,
frictionless retry.
*Where to look:* level authoring guidance in the GDD; `_end` fatal-state render.
*Precedent:* Miyazaki interviews, Stephen's Sausage Roll, The Witness, Mario 1-1, flow theory.

---

# EPIC 4 — The Eternal Pit (Replayability & Modes)
**Pillar:** Replayability / retention. **Priority: MEDIUM (not chosen yet — high ROI later).**

**Why it matters.** Today it's a single-run campaign — "beat 15 levels once." The genre's
best retention play (seeded daily) is *nearly free here* because `GridModel.rng` is
already seeded and `fill_random()` builds deterministic boards. Deterministic = boards
are comparable, fair, and shareable.

**Status today.** Linear campaign + a free-play random board only.

### E4.1 Daily seeded challenge  `effort: S–M`
A date-derived seed → one board the whole world plays, **one attempt**, post a score.
The single best retention / on-tone fit: one life per day, no take-backs, shared
suffering, public ranking *is* earned despair.
*Where to look:* reuse the seeded `fill_random()` board-gen path; new "one attempt + score"
state. *Precedent:* Spelunky daily (one attempt makes a solo game social), Wordle.

### E4.2 Wordle-style shareable result glyph  `effort: S`
A spoiler-free emoji/glyph grid summarizing the daily result for social compare.
*Where to look:* result screen of E4.1. *Precedent:* Wordle.

### E4.3 Endless / survival on the growth engine  `effort: M`
We already own a **timer-free rising-pressure** engine (growth-on-dud). "How long until
the dead overrun you" is a better, on-tone endless than a descending ceiling — no clock,
the dread is the rising tide.
*Where to look:* a mode wrapper around `GridModel.grow()` + danger system; scoring from
E3. *Precedent:* Tetris marathon, Bubble Witch limited-shots endless.

### E4.4 Seeded generator + validator + seed sharing  `effort: M`
A seed → identical *solvable* puzzle (the validator from E3.3 guarantees winnability);
share by seed. Optional rotating **daily modifiers** on the shared seed ("no reflectors
today", "the tide drops two rows").
*Where to look:* board-gen + E3.3 validator. *Precedent:* Hexcells Infinite, Slay the
Spire Daily Climb.

### E4.5 Scored marathon / sprint over the 15 levels  `effort: S`
Reuse the existing campaign as a score-ranked run / fewest-shots sprint (borrow the
leaderboard structure, never a wall clock).
*Where to look:* `GameState` run wrapper + E3 scoring. **Tone test:** no real-time timers.

---

# EPIC 5 — New Bubble Vocabulary (Special Spheres)
**Pillar:** Designed difficulty via new spatial rules. **Priority: MEDIUM.**

**Why it matters.** We have black/spin/bounce. The genre has a rich readable vocabulary;
a *few* well-chosen additions extend tactical depth without inflating stats. Readable
archetypes encode effect in shape (lock, web, crack, frost). **Add few, chosen well**,
and only deterministic ones.

**Status today.** 3 indestructible types; adding one touches ~4–5 hard-coded sites (const,
sim/model branch, `LevelResource` char + validate, material) — no registry.

### E5.0 Special-type registry refactor  `effort: M (enabler)`
Before adding several types, consolidate the scattered per-type sites into one registry
(sentinel → {behavior flags, layout char, material}) so each new special is small and
safe.
*Where to look:* `GridModel` sentinels, `ShotSimulator`, `LevelResource` parse/validate,
`SphereAssets`/`BoardView3D.mat_for`.

### E5.1 Spider-web / anchor-trap  `effort: M`  **(do first)**
Webbed spheres *don't* vanish when isolated; kill the web's center to release them — a
deliberate **subversion of our single core rule** (isolation vanishes). The cruelest,
fairest twist available *specifically to us*, and on-tone (a web in the pit).
*Precedent:* Bubble Witch spider web.

### E5.2 Armored / multi-hit  `effort: M`
N visible shell layers; each adjacent match strips one. Pure plannable depth, readable.
*Precedent:* MobilityWare heavy armor.

### E5.3 Locked / chained  `effort: M`
Can't match/move until freed (e.g., two same-colour hits). Honest gating.
*Precedent:* Bubble Witch / Candy Crush liquorice lock.

### E5.4 Steel / drop-only  `effort: M`
Colorless, unmatchable, but **drops when unsupported** — beaten by isolation, not by
hitting it. The purest fit for an isolation game.
*Precedent:* Arkadium steel.

### E5.5 Ice / frozen reveal & E5.6 spreading/infecting  `effort: M each`
Frozen: melt by matching neighbours to reveal true colour. Spreading: converts one
neighbour per shot (deterministic target — punishes slow play).
*Precedent:* Bubble Witch crystal / infected.

> **Tone test:** **reject all random ones** (mystery payload, random-path lightning,
> tile-eaters). Agency comes from *plannable* specials; randomness fights the pillar.

---

# EPIC 6 — The Game Shell (Structure & Retention Plumbing)
**Pillar:** Make it feel like a complete game. **Priority: MEDIUM.**

**Why it matters.** Several "complete game" basics are missing. Most are low-effort,
high-UX, and unblock the modes/meta above.

**Status today.** Clean scene flow + progress/settings persistence + CI, but no pause,
no records, no endgame, no tutorial, no meta-progression, no stats.

### E6.1 Pause overlay  `effort: S`  (a code comment already anticipates it)
Mid-level pause with resume/settings/quit; lets the player breathe and screenshot.
*Where to look:* a pause `CanvasLayer` in the play scene; `ui_cancel` currently exits.

### E6.2 Per-level records (best score/time/shots)  `effort: M`
Persist best results alongside unlock state; surface on level-select + end screen as the
replay motivation.
*Where to look:* extend `ProgressStore`/`progress.cfg`; E3 scoring.

### E6.3 Endgame payoff: all-cleared epilogue + credits  `effort: S`
A special screen/epilogue when the whole descent is complete (today: nothing).
*Where to look:* `GameState` completion check; new screen. (Pairs with E1.7.)

### E6.4 First-time teaching (level-as-tutorial)  `effort: M`
No tutorial today (assumes genre literacy). Teach each interaction where misuse is free,
in fiction, via the narrator + early board design — not a separate tutorial mode.
*Where to look:* early `levels/` design + narrator (E1.2). *Precedent:* Mario 1-1, The
Witness (E3.5).

### E6.5 Meta-progression / cosmetic unlocks  `effort: M+`
One on-tone meta reward loop (e.g., unlock a palette/sigil-style/effect by completing a
region or the descent). Small, but it's the missing long-term hook.
*Where to look:* `ProgressStore` + a cosmetics system; ties to E7.
**Tone test:** unlocks must stay grim (no cheerful shop).

### E6.6 Statistics tracking  `effort: S`
Aggregate souls freed / clears / longest chain / deaths — both a player-facing "ledger"
(fiction!) and design telemetry. `Log` already records events locally.
*Where to look:* a stats store; surface as a grim "descent ledger".

---

# EPIC 7 — Art & Readability (the Gothic-Ink Identity + Colorblind-Safe Sigils)
**Pillar:** Oppressive presentation + accessibility-by-construction. **Priority: MEDIUM-HIGH for E7.1 (flagged critical in GDD).**

**Why it matters.** A colour-matching game in a desaturated grim palette is a
readability minefield; the GDD calls sigils "critical, not optional" — yet spheres are
still colour-only. And the hand-drawn gothic-ink direction (the orb double-read: toy at
distance, trapped soul up close) is *the pitch made visual*, but largely unbuilt
(everything is procedural shaders + one icon).

**Status today.** Cohesive procedural atmosphere; no per-colour sigils, no colorblind
palette, no bespoke art.

### E7.1 Engraved per-colour sigils  `effort: M`  **(accessibility-critical)**
Each colour carries a distinct engraved sigil/shape so matching never relies on hue —
colorblind-safe *by construction*, and it fits the occult aesthetic (a sigil = a soul's
mark).
*Where to look:* `SphereAssets` materials/decals; could be a shader overlay per colour.
*Precedent:* GDD §2.9.

### E7.2 Colorblind / high-contrast palette option  `effort: S–M`
A selectable palette; pairs with E7.1. *Where to look:* `BoardView3D.PALETTE` + a setting.

### E7.3 Hand-drawn gothic-ink art pass  `effort: L (scope carefully)`
The biggest content cost: bespoke sphere/board art, ornate UI frames (Darkest Dungeon
lineage). Scope first-region-first; the orb double-read is the single most identity-
defining art decision.
*Where to look:* `art/`, `themes/`, `SphereAssets`. **Tone test:** the only thing that
most cheaply *breaks* the brand is bright/rounded/emoji UI — keep typography liturgical.

### E7.4 Grain / vignette / effects sliders consolidation  `effort: S`
Expose grain/vignette intensity (partly exists) under the E2.1 effects umbrella for
players & hardware.
*Where to look:* `dread_overlay.gdshader` params + Settings.

---

## Cross-cutting principles (apply to every epic)
- **Express latent value before building new systems** — the orphan sweep, seeded RNG,
  and event spine already hold most of this.
- **Determinism is the fairness engine** — keep `GridModel` pure; randomness only
  seeded-and-visible.
- **Restraint is the brand** — over-juicing / celebration / jokes collapse the hook into
  "casual mobile game" faster than anything else.
- **Data not code** — narrator lines, regions, levels, palettes as resources.
- **Verify per CLAUDE.md** — keep the rules core GUT-covered; live-run + screenshot for
  feel (user eyeballs visuals); gdformat + gdlint every iteration; new audio via the
  find-assets skill (user-approved).

## Suggested epic sequencing (impact-per-effort)
1. **E1** Voice & Fiction (+ the Ossuary slice combining E1/E2/E3 cheap wins)
2. **E2** Weight & Dread, **E3** Skill & Despair (systems; tune on the slice)
3. **E7.1–E7.2** Sigils + colorblind palette (accessibility debt)
4. **E4** The Eternal Pit (daily first — nearly free)
5. **E6** Shell basics (pause, records, endgame)
6. **E5** New bubble vocabulary (registry refactor → spider-web first)
7. **E7.3** Full gothic-ink art pass (largest content cost; scope per region)

## Deferred / out of scope for now
Networked leaderboards, achievements/badges, VO narration, multiple campaigns, a
player-facing level editor, mobile/touch port, an automated *optimal*-par solver.
