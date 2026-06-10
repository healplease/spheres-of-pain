class_name Hex
extends RefCounted

## Offset-coordinate hex geometry for the sphere lattice. A stateless helper —
## all methods are static; never instantiated.
##
## We use "odd-r" offset coordinates: spheres live on integer (col, row) cells;
## ODD rows are shoved right by half a diameter. Row 0 is the top edge (the
## anchor). This is the natural layout for a bubble-shooter — rows stack downward
## and the danger line is simply a row index.
##
## Cells are Vector2i(col, row). World math takes the sphere DIAMETER `d` and an
## `origin` (world position of cell (0,0)'s centre).

## Neighbour deltas, indexed by row parity (row & 1). Each is [dcol, drow].
## Source: Red Blob Games "odd-r" offset neighbours.
const DIRS := [
	# even rows
	[Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1),
	 Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)],
	# odd rows
	[Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	 Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)],
]

## Vertical distance between rows, as a fraction of the diameter (hex packing).
const ROW_RATIO := 0.866025403784439  # sqrt(3) / 2


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for delta in DIRS[cell.y & 1]:
		out.append(cell + delta)
	return out


static func cell_to_world(cell: Vector2i, origin: Vector2, d: float) -> Vector2:
	var x_off := d * 0.5 if (cell.y & 1) == 1 else 0.0
	return Vector2(
		origin.x + cell.x * d + x_off,
		origin.y + cell.y * d * ROW_RATIO
	)


static func world_to_cell(pos: Vector2, origin: Vector2, d: float) -> Vector2i:
	var row := int(round((pos.y - origin.y) / (d * ROW_RATIO)))
	var x_off := d * 0.5 if (row & 1) == 1 else 0.0
	var col := int(round((pos.x - origin.x - x_off) / d))
	return Vector2i(col, row)
