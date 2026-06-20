# Spin rotation (`GridModel.spin_step`)

After a shot lands, every SPIN sphere rotates the **contents** of its neighbouring "track" cells
one step counter-clockwise. The spheres physically **move** — they no longer just swap colours in
place. `spin_step()` brings the model to its final state and returns a moves list
(`{from, to, color}`), one per breakable sphere that ends up somewhere new, so the view
(`BoardView3D.animate_spin`) can animate the travel.

## Track cells

A *track cell* is an in-bounds, non-indestructible neighbour — breakable **or** empty. Empty slots
take part in the rotation too, so a sphere can travel into an empty slot, or an empty slot can
travel round and vacate a sphere's cell. Indestructible neighbours (BLACK/SPIN/BOUNCE) and
out-of-bounds positions are excluded, and the ring **compacts over them**: a sphere may "jump" the
gap to the next track slot. A spin with fewer than two track cells is a no-op. Empty slots produce
no move entry but are still vacated/filled by the rotation.

## One spin at a time, in reading order

Spins resolve **one at a time** in reading order (top-to-bottom row, then left-to-right column) —
deterministic, and the natural order a player scans the board. Each spin acts on the board the
previous spins left behind, so two nearby spins both take effect (the later one rotates the cells
the earlier one already moved) instead of one cancelling the other.

A single spin's own ring is **read in full before it writes**, so that one rotation stays
simultaneous within itself. Each sphere is tracked from its starting cell to its final cell (via
the `origin` map), and the returned moves are those *net hops* — always a clean permutation (each
origin once, each destination once). That lets the view re-key its sphere nodes safely even when a
sphere is carried through two rotations.

## Why `i -> i+1` over `Hex.DIRS` is counter-clockwise

`Hex.DIRS[parity]` is authored so the same index is the same compass direction for both row
parities, walking E → up-right → up-left → W → down-left → down-right — counter-clockwise on
screen. Reading the ring in `DIRS` order and shifting each slot's content to the next slot
(`i -> i+1`) is therefore a CCW rotation.
