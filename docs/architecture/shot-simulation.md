# Shot tuning constants (`ShotSimulator`)

The ball flight is a pure-logic simulation on the logical 2D play plane, shared verbatim by the
aim preview and the live shot so they stay identical. Two constants carry the feel and the safety
caps.

## `HIT_DISTANCE_SCALE` (0.78)

How close — as a fraction of the cell spacing `diameter` — the moving sphere's centre must come to
a settled sphere's centre to count as a hit.

- At **0.92** the two rendered spheres just touch (each has radius `0.46 · diameter`).
- Using **less** than that gives the *moving* sphere a smaller hitbox than it looks, so a precise
  shot can be threaded through a narrow gap between two field spheres — a deliberate skill play.
- Kept **above ~0.5** so a shot can't pass straight through two touching spheres.

Both the aim preview and the live shot run the same `simulate()`, so this threshold applies to
both identically.

## `MAX_BOUNCES` (12)

A fired sphere reflects off a BOUNCE sphere like a wall instead of attaching. The reflections per
shot are capped so a ball trapped between two bouncers can't burn the whole per-step budget — past
the cap it falls through to a normal miss-exit.
