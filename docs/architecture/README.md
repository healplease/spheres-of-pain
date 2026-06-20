# Architecture notes

Long-form rationale for design decisions that have settled into staples. The code keeps a
one-line summary at each site and points here, so the source stays scannable while the "why"
stays close.

| Topic | Code site | Note |
|---|---|---|
| Spin rotation | [`GridModel.spin_step`](../../scripts/core/grid_model.gd) | [spin.md](spin.md) |
| Shot tuning constants | [`ShotSimulator`](../../scripts/core/shot_simulator.gd) | [shot-simulation.md](shot-simulation.md) |
| Post-shot level flow | [`LevelController3D`](../../scripts/play3d/level_controller_3d.gd) | [level-flow.md](level-flow.md) |

See also `CLAUDE.md` (conventions, model/view split) and the GDD for game design.
