# Post-shot level flow (`LevelController3D`)

## The post-shot resolution sequence (`_on_landed`)

`_on_landed` is a coroutine: the post-shot field animations play **in sequence**, and the gun
stays locked (`shooter.enabled` was set false at fire time) until the board has fully settled, so
the player can't fire into a still-animating field.

Order of operations, each waiting on the previous to read as a distinct beat:

1. **Attach.** `model.attach()` either pops a matched cluster (plus any spheres it orphans) or, on
   a dud, grows the field one step.
2. **Pop / grow animation.** `board.sync()` ripples the clear outward from the impact cell (a pop)
   or animates the grown spheres in (a dud). The gun stays locked through the settle time.
3. **Spin.** Only after pop/grow settles do SPIN spheres react to the settled board (see
   [spin.md](spin.md)). `spin_step()` brings the model to its final state; `animate_spin()`
   relocates the existing nodes.
4. **Read the final board once.** `count_colored()` / `max_row()` are read **after the spin** —
   the spin can carry a sphere into a deeper row — and the single scan is shared by the log, the
   HUD, the heartbeat, and the narrator instead of rescanning the board several times.
5. **Verdict.** Win/loss is checked **last**, after a short beat, because the spin can push a
   sphere across the danger line; the verdict must reflect the final state, not the pre-spin one.

Every `await` is guarded by `if not is_inside_tree() or game_over: return`, so leaving the level
(Esc, an end during a pause) cleanly aborts a resolution in flight.

## Verdicts speak the fiction (`_check_end`, GDD §2.10)

A win is exhausted relief, never a fanfare; a loss is the dead reclaiming you. Both verdict lines
stay short to fit the title-size banner — the longer grave-courtesy and the souls-freed tally ride
the *epitaph* beneath them (`_epitaph`). Beating the final campaign level ends the whole descent:
the controller holds the verdict a beat, lets the narrator's voice land, then moves to the
epilogue scene instead of the ordinary end panel.
