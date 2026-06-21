extends SceneTree

## One-shot authoring tool (NOT shipped — run once, headless):
##   & "C:\Program Files\Godot\Godot.exe" --headless --path . -s res://tools/gen_levels.gd
## Writes the 30 campaign levels (levels/level_NN.tres), the branching world graph
## (world/world_graph.tres), and the 3 regions (regions/*.tres) from the hand-designed specs
## below. Every level's grid is authored by hand here (the `top` rows); the tool only stamps the
## resource header, pads descent headroom, and runs LevelResource.validate() so a malformed board
## can never reach disk — it aborts (exit 1) with the exact row/colour problem instead.

# Objective enum mirrors LevelResource.Objective (CLEAR, FREE_SOUL, CLEANSE).
const CLEAR := 0
const FREE_SOUL := 1
const CLEANSE := 2

# Per-region atmosphere [abyss_a, abyss_b, ember, fog].
const THEME := [
	[
		Color(0.14, 0.04, 0.05),
		Color(0.08, 0.05, 0.04),
		Color(1.0, 0.55, 0.30),
		Color(0.04, 0.02, 0.025)
	],
	[
		Color(0.04, 0.07, 0.12),
		Color(0.03, 0.10, 0.11),
		Color(0.45, 0.72, 0.92),
		Color(0.02, 0.03, 0.045)
	],
	[
		Color(0.11, 0.08, 0.07),
		Color(0.07, 0.06, 0.06),
		Color(1.0, 0.62, 0.30),
		Color(0.03, 0.025, 0.02)
	],
]

const REGIONS := [
	{
		"id": 0,
		"title": "The Ossuary",
		"boss": "The Tally-Keeper",
		"framing": "The shallow dead, near the mouth of the pit. You learn the work on them.",
		"accent": Color(0.74, 0.46, 0.33),
	},
	{
		"id": 1,
		"title": "The Drowned Cloister",
		"boss": "The Choirmistress",
		"framing": "Black water over old stone. The hymns never finished; they only sank.",
		"accent": Color(0.40, 0.62, 0.74),
	},
	{
		"id": 2,
		"title": "The Ashen Vigil",
		"boss": "The Last Warden",
		"framing":
		"The deepest floor, where the fires went out still watching. Nothing here forgives.",
		"accent": Color(0.72, 0.56, 0.46),
	},
]


func _initialize() -> void:
	var ok := _run()
	if not ok:
		push_error("gen_levels: FAILED")
	quit(0 if ok else 1)


func _run() -> bool:
	DirAccess.make_dir_recursive_absolute("res://world")
	var specs := _specs()
	if specs.size() != 30:
		push_error("expected 30 node specs, got %d" % specs.size())
		return false
	for s in specs:
		if not _save_level(s):
			return false
	if not _save_world(specs):
		return false
	if not _save_regions(specs):
		return false
	print("gen_levels: wrote 30 levels + world/world_graph.tres + 3 regions")
	return true


# --- level files --------------------------------------------------------------


func _save_level(s: Dictionary) -> bool:
	var lv := LevelResource.new()
	lv.id = s.id
	lv.title = s.t
	lv.lore_fragment = s.lo
	lv.width = s.w
	lv.num_colors = s.c
	lv.par_shots = s.get("par", 0)
	lv.objective_type = s.get("ob", CLEAR)
	lv.objective_color = s.get("oc", 0)
	lv.shot_budget = s.get("bud", 0)
	lv.tide_rows_per_shot = s.get("tide", 0)
	var theme: Array = THEME[s.rg]
	lv.abyss_color_a = theme[0]
	lv.abyss_color_b = theme[1]
	lv.ember_color = theme[2]
	lv.fog_color = theme[3]
	var top: Array = s.top
	var pad := 14 if s.get("tide", 0) > 0 else 10
	var rows := PackedStringArray()
	for r in top:
		rows.append(r)
	while rows.size() < top.size() + pad:
		rows.append(".".repeat(s.w))
	lv.layout = rows
	lv.danger_row = rows.size()
	var problems := lv.validate()
	if not problems.is_empty():
		push_error("level %02d invalid: %s" % [s.id, "; ".join(problems)])
		return false
	var path := "res://levels/level_%02d.tres" % s.id
	var err := ResourceSaver.save(lv, path)
	if err != OK:
		push_error("level %02d save failed (%d)" % [s.id, err])
		return false
	return true


# --- world graph --------------------------------------------------------------


func _save_world(specs: Array) -> bool:
	var graph := WorldGraphResource.new()
	graph.start_node_id = 1
	var nodes: Array[MapNodeResource] = []
	for s in specs:
		var n := MapNodeResource.new()
		n.id = s.id
		n.region_id = s.rg
		n.node_kind = s.k
		n.map_position = s.pos
		n.prerequisites = PackedInt32Array(s.get("pre", []))
		n.gate_mode = s.get("g", MapNodeResource.Gate.ANY)
		n.successors = PackedInt32Array(s.get("suc", []))
		n.summary = s.get("sm", "")
		nodes.append(n)
	graph.nodes = nodes
	var problems := graph.validate()
	if not problems.is_empty():
		push_error("world graph invalid: %s" % "; ".join(problems))
		return false
	var err := ResourceSaver.save(graph, "res://world/world_graph.tres")
	if err != OK:
		push_error("world graph save failed (%d)" % err)
		return false
	return true


# --- regions ------------------------------------------------------------------


func _save_regions(specs: Array) -> bool:
	for meta in REGIONS:
		var r := RegionResource.new()
		r.id = meta.id
		r.title = meta.title
		r.framing_line = meta.framing
		r.boss_name = meta.boss
		r.accent = meta.accent
		var theme: Array = THEME[meta.id]
		r.ember_color = theme[2]
		r.fog_color = theme[3]
		var ids := PackedInt32Array()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for s in specs:
			if s.rg != meta.id:
				continue
			ids.append(s.id)
			lo = Vector2(minf(lo.x, s.pos.x), minf(lo.y, s.pos.y))
			hi = Vector2(maxf(hi.x, s.pos.x), maxf(hi.y, s.pos.y))
			if s.k == MapNodeResource.Kind.ENTRY:
				r.entry_node_id = s.id
			elif s.k == MapNodeResource.Kind.BOSS:
				r.boss_node_id = s.id
		r.node_ids = ids
		r.map_center = (lo + hi) * 0.5
		var pad := Vector2(120, 120)
		r.map_bounds = Rect2(lo - pad, (hi - lo) + pad * 2.0)
		var names := ["region_1_ossuary", "region_2_cloister", "region_3_vigil"]
		var fname: String = names[meta.id]
		var err := ResourceSaver.save(r, "res://regions/%s.tres" % fname)
		if err != OK:
			push_error("region %d save failed (%d)" % [meta.id, err])
			return false
	return true


# --- the hand-designed campaign ----------------------------------------------
# Kind: ENTRY/SPINE/BRANCH/CROSSROAD/DEAD_END/BOSS. Gate ANY unless noted. Spine = entry->...->boss;
# branches/crossroads/dead-ends hang off it and are harder (more indestructibles / colours / width).


func _specs() -> Array:
	var kind := MapNodeResource.Kind
	return [
		# ===== Region 0 — The Ossuary (ids 1-10), boss 5 ============================
		{
			"id": 1,
			"rg": 0,
			"k": kind.ENTRY,
			"pre": [],
			"suc": [2, 9],
			"pos": Vector2(400, 100),
			"t": "The Shallow Vein",
			"w": 9,
			"c": 3,
			"par": 8,
			"lo": "You come down into the Ossuary. Here the dead lie shallow — begin with them.",
			"top": ["012201120", "120012201", "201120012", "021210102"],
		},
		{
			"id": 2,
			"rg": 0,
			"k": kind.SPINE,
			"pre": [1],
			"suc": [3, 6],
			"pos": Vector2(400, 300),
			"t": "Knucklebone Run",
			"w": 9,
			"c": 3,
			"par": 9,
			"lo": "A scattering of small bones. They click as they fall, like counting.",
			"top": ["112002211", "021120210", "210201021", "002112200"],
		},
		{
			"id": 3,
			"rg": 0,
			"k": kind.SPINE,
			"pre": [2],
			"suc": [4, 10],
			"pos": Vector2(430, 500),
			"t": "The Counting House",
			"w": 10,
			"c": 4,
			"par": 10,
			"lo": "Someone tallied the dead here, once. The ledgers rotted; the dead did not.",
			"top": ["0123012301", "1230123012", "2301230123", "3012301230"],
		},
		{
			"id": 4,
			"rg": 0,
			"k": kind.SPINE,
			"pre": [3, 8],
			"g": 0,
			"suc": [5],
			"pos": Vector2(400, 700),
			"t": "Where Roads Rejoin",
			"w": 11,
			"c": 4,
			"par": 11,
			"lo":
			"Two ways down meet again at the foot of the stair. The work is the same either way.",
			"top": ["01230123012", "12301230123", "23012301230", "30123012301"],
		},
		{
			"id": 5,
			"rg": 0,
			"k": kind.BOSS,
			"pre": [4],
			"suc": [11],
			"pos": Vector2(400, 900),
			"t": "The Tally-Keeper",
			"w": 12,
			"c": 4,
			"par": 12,
			"sm": "The first warden. Stone spin-wheels turn the count against you.",
			"lo": "It keeps the count of everyone who came down. It would like to add you.",
			"top": ["012301230123", "X23012301X30", "012S01230S23", "3012X01230X1", "230123012301"],
		},
		{
			"id": 6,
			"rg": 0,
			"k": kind.CROSSROAD,
			"pre": [2],
			"suc": [7, 8],
			"pos": Vector2(600, 380),
			"t": "The Forking Crypt",
			"w": 11,
			"c": 4,
			"par": 13,
			"sm": "A harder side-crypt. One way ends; the other rejoins the descent.",
			"lo":
			"The passage splits. One arm is a dead grave; the other circles back to the stair.",
			"top": ["0123012X012", "X2301X23012", "01230123012", "230X1230X30"],
		},
		{
			"id": 7,
			"rg": 0,
			"k": kind.DEAD_END,
			"pre": [6],
			"suc": [],
			"pos": Vector2(760, 320),
			"t": "A Child's Cairn",
			"w": 10,
			"c": 4,
			"ob": FREE_SOUL,
			"oc": 2,
			"sm": "Dead end. Free the small soul caged in the stones — the path ends here.",
			"lo":
			"Small stones, stacked with care no one came back for. Something waits inside to be let out.",
			"top": ["01@3012X30", "3012@01230", "X230123X01", "0123012301"],
		},
		{
			"id": 8,
			"rg": 0,
			"k": kind.BRANCH,
			"pre": [6],
			"suc": [4],
			"pos": Vector2(620, 600),
			"t": "The Long Way Down",
			"w": 11,
			"c": 4,
			"par": 12,
			"sm": "A harder branch that merges back into the spine below.",
			"lo": "The crooked path. Longer, meaner, and it rejoins the stair all the same.",
			"top": ["0123X012301", "X23012301X0", "01230123012", "230123X0123"],
		},
		{
			"id": 9,
			"rg": 0,
			"k": kind.DEAD_END,
			"pre": [1],
			"suc": [],
			"pos": Vector2(200, 180),
			"t": "The First Wrong Turn",
			"w": 9,
			"c": 3,
			"ob": FREE_SOUL,
			"oc": 1,
			"sm": "Dead end. A soul to free, and no way onward — only back.",
			"lo": "You turned aside almost at once. There is a soul here, and nothing else.",
			"top": ["01@201X20", "20102@012", "1X0210210"],
		},
		{
			"id": 10,
			"rg": 0,
			"k": kind.DEAD_END,
			"pre": [3],
			"suc": [],
			"pos": Vector2(250, 560),
			"t": "Mismarked Grave",
			"w": 10,
			"c": 4,
			"ob": CLEANSE,
			"oc": 3,
			"sm": "Dead end. Cleanse the cursed cell. The lore is the only reward.",
			"lo":
			"The ledger named this grave wrong. Whatever lies in it has been angry a long time.",
			"top": ["01*3012*30", "X230123X01", "012301230X"],
		},
		# ===== Region 1 — The Drowned Cloister (ids 11-20), boss 15 =================
		{
			"id": 11,
			"rg": 1,
			"k": kind.ENTRY,
			"pre": [5],
			"suc": [12, 16],
			"pos": Vector2(400, 1100),
			"t": "The Flooded Nave",
			"w": 11,
			"c": 4,
			"par": 11,
			"lo":
			"Past the Tally-Keeper the water begins. The cloister drowned with its singers inside.",
			"top": ["01230123012", "12301230123", "2301X230123", "30123012301"],
		},
		{
			"id": 12,
			"rg": 1,
			"k": kind.SPINE,
			"pre": [11],
			"suc": [13, 17],
			"pos": Vector2(380, 1300),
			"t": "Hymnal Silt",
			"w": 12,
			"c": 4,
			"par": 13,
			"lo": "Pages of waterlogged song, settled into the floor. They still know the tune.",
			"top": ["012301230123", "X23012301230", "012301X30123", "230123012X01"],
		},
		{
			"id": 13,
			"rg": 1,
			"k": kind.SPINE,
			"pre": [12, 17],
			"g": 0,
			"suc": [14, 18],
			"pos": Vector2(400, 1500),
			"t": "The Sunken Choir",
			"w": 13,
			"c": 5,
			"par": 14,
			"lo": "Rows of stalls under black water, each still facing the altar. Each still full.",
			"top":
			["0123401234012", "X234012340123", "01234X1234012", "3401234X12340", "1234012340X23"],
		},
		{
			"id": 14,
			"rg": 1,
			"k": kind.SPINE,
			"pre": [13, 20],
			"g": 0,
			"suc": [15],
			"pos": Vector2(400, 1700),
			"t": "Antechamber of the Descant",
			"w": 14,
			"c": 5,
			"par": 16,
			"lo": "The last dry step before her. The water here hums on its own.",
			"top": ["01234012340123", "X2340X2340X234", "01234012340123", "X2340X2340X234"],
		},
		{
			"id": 15,
			"rg": 1,
			"k": kind.BOSS,
			"pre": [14],
			"suc": [21],
			"pos": Vector2(400, 1900),
			"t": "The Choirmistress",
			"w": 14,
			"c": 5,
			"tide": 2,
			"sm": "The drowned conductor. The water rises a little with every shot.",
			"lo":
			"She conducts the drowned. While she sings, the flood climbs the walls toward you.",
			"top": ["01234012340123", "X234S012340X23", "01234B12340123", "X2340123X0X234"],
		},
		{
			"id": 16,
			"rg": 1,
			"k": kind.DEAD_END,
			"pre": [11],
			"suc": [],
			"pos": Vector2(200, 1180),
			"t": "The Drowned Vow",
			"w": 12,
			"c": 5,
			"ob": CLEANSE,
			"oc": 4,
			"sm": "Dead end. Cleanse the cursed cell; read what was sworn here.",
			"lo": "A vow was made at this font and broken. The water remembers the breaking.",
			"top": ["0123*01234*1", "X2340123401X", "012340123401", "X23401234X12"],
		},
		{
			"id": 17,
			"rg": 1,
			"k": kind.BRANCH,
			"pre": [12],
			"suc": [13],
			"pos": Vector2(600, 1380),
			"t": "Side Chapel, Flooded",
			"w": 14,
			"c": 5,
			"par": 16,
			"sm": "A harder branch that rejoins the choir.",
			"lo": "A smaller room off the nave, fuller and darker. It lets back into the choir.",
			"top": ["01234012340123", "X23401234X1234", "01234012340123", "X2340X2340X234"],
		},
		{
			"id": 18,
			"rg": 1,
			"k": kind.CROSSROAD,
			"pre": [13],
			"suc": [19, 20],
			"pos": Vector2(610, 1560),
			"t": "The Split Transept",
			"w": 14,
			"c": 5,
			"par": 16,
			"sm": "A hard fork: one arm is a dead chapel, one rejoins the spine.",
			"lo": "The cross of the cloister, snapped in two. Choose an arm; only one leads on.",
			"top": ["01234012340123", "X234X1234X1234", "01234012340123", "X234X1234X1234"],
		},
		{
			"id": 19,
			"rg": 1,
			"k": kind.DEAD_END,
			"pre": [18],
			"suc": [],
			"pos": Vector2(780, 1520),
			"t": "The Bricked Confessional",
			"w": 13,
			"c": 5,
			"ob": FREE_SOUL,
			"oc": 0,
			"sm": "Dead end. Free the soul sealed behind the wall.",
			"lo": "Someone was sealed in to keep confessing forever. The mortar is still wet.",
			"top": ["0@234012340@2", "X2340X23401X3", "0123401234012", "X234012340X23"],
		},
		{
			"id": 20,
			"rg": 1,
			"k": kind.BRANCH,
			"pre": [18],
			"suc": [14],
			"pos": Vector2(620, 1720),
			"t": "The Rising Undercroft",
			"w": 14,
			"c": 5,
			"par": 16,
			"tide": 2,
			"sm": "A flooding branch (the tide rises) that merges back to the spine.",
			"lo": "The lowest vault, filling fast. Cross it before it closes over your head.",
			"top": ["01234012340123", "X2340X2340X234", "01234012340123", "X234012340X234"],
		},
		# ===== Region 2 — The Ashen Vigil (ids 21-30), boss 25 (FINAL) =============
		{
			"id": 21,
			"rg": 2,
			"k": kind.ENTRY,
			"pre": [15],
			"suc": [22, 27],
			"pos": Vector2(400, 2100),
			"t": "First Ash",
			"w": 12,
			"c": 4,
			"par": 13,
			"lo": "Below the water, only ash. The deepest floor kept its fires until it didn't.",
			"top": ["012301230123", "123S01230123", "230123012301", "301230123012"],
		},
		{
			"id": 22,
			"rg": 2,
			"k": kind.SPINE,
			"pre": [21],
			"suc": [23, 26],
			"pos": Vector2(400, 2300),
			"t": "The Turning Eye",
			"w": 14,
			"c": 5,
			"par": 16,
			"lo": "A great burnt iris set in the floor, still tracking whatever moves.",
			"top": ["01234012340123", "X234S012340X23", "01234012340123", "X23401234X1234"],
		},
		{
			"id": 23,
			"rg": 2,
			"k": kind.SPINE,
			"pre": [22, 26],
			"g": 0,
			"suc": [24],
			"pos": Vector2(400, 2500),
			"t": "The Sealed Diamond",
			"w": 15,
			"c": 5,
			"par": 18,
			"lo":
			"Two paths around a furnace, closing to one. The fire between them never went cold.",
			"top": ["X12340123401234", "X2340X234S01234", "012340123401234", "X2340X2340X2340"],
		},
		{
			"id": 24,
			"rg": 2,
			"k": kind.SPINE,
			"pre": [23],
			"suc": [25, 28],
			"pos": Vector2(400, 2700),
			"t": "The Warden's Threshold",
			"w": 16,
			"c": 6,
			"par": 20,
			"lo": "The last gate before the last guard. Everything here is iron and cinder.",
			"top":
			[
				"X123450123450123",
				"X23450X23450S234",
				"012345012345012X",
				"X23450X2345S2345",
				"X234501234X01234"
			],
		},
		{
			"id": 25,
			"rg": 2,
			"k": kind.BOSS,
			"pre": [24],
			"suc": [],
			"pos": Vector2(400, 2900),
			"t": "The Last Warden",
			"w": 16,
			"c": 6,
			"bud": 14,
			"tide": 2,
			"sm":
			"The final guard. Few shots, spin and bounce against you, and a rising tide of ash.",
			"lo":
			"It has kept the bottom of the pit since before there was a pit. Make every shot a verdict.",
			"top":
			[
				"0123450123450123",
				"X234S012345B0X23",
				"012345012345012X",
				"X2345B01234S0123",
				"X2340123450X2345"
			],
		},
		{
			"id": 26,
			"rg": 2,
			"k": kind.BRANCH,
			"pre": [22],
			"suc": [23],
			"pos": Vector2(600, 2400),
			"t": "Around the Furnace",
			"w": 16,
			"c": 6,
			"par": 18,
			"sm": "A hard branch around the furnace; it closes the diamond back onto the spine.",
			"lo":
			"The long way round the fire. Hotter, harder, and it seals shut behind you onto the path.",
			"top": ["0123450123450123", "X2345X012345S0X3", "01234B012345012X", "X23450X23450X234"],
		},
		{
			"id": 27,
			"rg": 2,
			"k": kind.DEAD_END,
			"pre": [21],
			"suc": [],
			"pos": Vector2(190, 2180),
			"t": "The Last Soul Before the Wall",
			"w": 16,
			"c": 7,
			"ob": FREE_SOUL,
			"oc": 3,
			"sm": "Dead end. The hardest rescue in the pit — seven colours, deep ash, no way on.",
			"lo":
			"The deepest caged thing, almost at the wall of the world. Free it. Then turn back.",
			"top": ["0@2345601234560@", "X23456S0123456X2", "X123456012345601", "X23456X023456X23"],
		},
		{
			"id": 28,
			"rg": 2,
			"k": kind.CROSSROAD,
			"pre": [24],
			"suc": [29, 30],
			"pos": Vector2(610, 2760),
			"t": "The Cinder Fork",
			"w": 16,
			"c": 6,
			"par": 18,
			"sm": "A hard fork onto two dead vaults — lore only, both ways.",
			"lo": "The path frays into the ash. Two ways, both ending; pick which story you want.",
			"top": ["0123450123450123", "X2345X012345B0X3", "012345012345012X", "X2345X02345X0234"],
		},
		{
			"id": 29,
			"rg": 2,
			"k": kind.DEAD_END,
			"pre": [28],
			"suc": [],
			"pos": Vector2(780, 2720),
			"t": "Ash That Remembers",
			"w": 15,
			"c": 6,
			"ob": CLEANSE,
			"oc": 5,
			"sm": "Dead end. Cleanse the cursed cell to read the ash's memory.",
			"lo":
			"Press a hand to this ash and it shows you a face. Cleanse it, and the face can rest.",
			"top": ["0*234501234*012", "X23450X2345X012", "X12345012345012", "X23450X23450123"],
		},
		{
			"id": 30,
			"rg": 2,
			"k": kind.DEAD_END,
			"pre": [28],
			"suc": [],
			"pos": Vector2(700, 2880),
			"t": "The Warden's Wards",
			"w": 16,
			"c": 7,
			"ob": FREE_SOUL,
			"oc": 6,
			"sm": "Dead end. Nine wards of iron guard one soul — the meanest board down here.",
			"lo":
			"The Warden left wards even in a grave it never visits. Break them; free what they kept.",
			"top": ["0@234560123456@0", "X2345X0S23456X02", "X123456X12345X12", "X2345X02345X0123"],
		},
	]
