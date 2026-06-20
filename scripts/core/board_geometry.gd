class_name BoardGeometry
extends RefCounted

## Pure derivation of the board's logical play geometry from the field size — the muzzle, board
## origin, and bounce/exit bounds. Extracted from the controller so the derivation is in one
## place and unit-testable on its own. Static-only — never instantiated; no nodes, no logging.
##
## The field is centred horizontally on FIELD_CENTER_X; the danger (lose) line sits
## danger_row rows below the top wall; the muzzle hangs MUZZLE_GAP_ROWS below that line and
## the bottom miss-exit EXIT_GAP_ROWS below the muzzle. One cell spacing == `diameter`, and
## a row is diameter * Hex.ROW_RATIO tall (hex packing).

const FIELD_CENTER_X := 640.0  # logical x the field + muzzle are centred on
const TOP_Y := 80.0  # logical y of the row-0 sphere centres
# Vertical stack below the danger (lose) line, in row-steps: the gun sits this far below the
# line, then the red miss-exit bar sits this far below the gun. A smaller MUZZLE_GAP lifts the
# whole gun+bar unit toward the field, so they sit closer to the spheres at the moment those
# reach the line and consume them.
const MUZZLE_GAP_ROWS := 0.3  # gun below the danger line (hand-tuned)
const EXIT_GAP_ROWS := 0.6  # red miss-exit bar below the gun


## The derived logical coordinates for one field size. play_left/right/bottom are the
## surfaces the ball reflects off / exits through (sides + bottom miss-exit); origin2d is
## cell (0,0)'s centre; muzzle2d is where the gun fires from.
class Layout:
	var origin2d: Vector2
	var muzzle2d: Vector2
	var play_left: float
	var play_right: float
	var play_bottom: float


static func compute(columns: int, danger_row: int, diameter: float) -> Layout:
	var row_step := diameter * Hex.ROW_RATIO
	var layout := Layout.new()
	# Centre the field horizontally: with this origin, (play_left + play_right) / 2 lands on
	# FIELD_CENTER_X regardless of column count.
	layout.origin2d = Vector2(FIELD_CENTER_X - diameter * (columns * 0.5 - 0.25), TOP_Y)
	var danger_y := layout.origin2d.y + danger_row * row_step
	layout.muzzle2d = Vector2(FIELD_CENTER_X, danger_y + row_step * MUZZLE_GAP_ROWS)
	layout.play_bottom = layout.muzzle2d.y + row_step * EXIT_GAP_ROWS
	layout.play_left = layout.origin2d.x - diameter * 0.5
	layout.play_right = layout.origin2d.x + (columns - 1) * diameter + diameter
	return layout
