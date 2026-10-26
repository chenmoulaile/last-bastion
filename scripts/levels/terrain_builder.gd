class_name TerrainBuilder
extends RefCounted
## Procedural side-scrolling terrain. Ground is drawn with a generated TileSet
## (physics layer 1) and upper tiers are one-way platforms. The level runner
## keeps the segment list for AI ground queries.

const GROUND_Y := 288.0
const TILE := 16


static func build(parent: Node2D, theme: String, width: float, rng: RandomNumberGenerator,
		dark: bool) -> Dictionary:
	var segments: Array[Dictionary] = []
	var platforms: Array[Dictionary] = []
	var tile_set := _make_tileset(theme)
	var ground_layer := TileMapLayer.new()
	ground_layer.name = "GroundTiles"
	ground_layer.tile_set = tile_set
	ground_layer.z_index = 0
	ground_layer.modulate = Color(0.62, 0.68, 0.78) if dark else Color.WHITE
	parent.add_child(ground_layer)
	var platform_layer := TileMapLayer.new()
	platform_layer.name = "PlatformTiles"
	platform_layer.tile_set = tile_set
	platform_layer.z_index = 1
	platform_layer.modulate = Color(0.62, 0.68, 0.78) if dark else Color.WHITE
	parent.add_child(platform_layer)

	var x := 0.0
	var seg_index := 0
	while x < width:
		var seg_len := rng.randi_range(430, 760)
		if seg_index == 0:
			seg_len = 720.0
		if x + seg_len > width:
			seg_len = width - x
		var gap := false
		if x > 950.0 and x < width - 1300.0 and rng.randf() < 0.20:
			var gap_len := float(rng.randi_range(64, 100))
			# Do not create a gap right before a segment shorter than a jump.
			if x + gap_len < width - 500.0:
				x += gap_len
				gap = true
		if x >= width:
			break
		seg_len = minf(seg_len, width - x)
		if seg_len < 100.0:
			break
		segments.append({"x0": x, "x1": x + seg_len, "y": GROUND_Y})
		_paint_ground(ground_layer, x, x + seg_len, GROUND_Y, rng)
		if seg_len > 470.0:
			_add_platforms(platform_layer, platforms, x, x + seg_len, rng, dark)
		x += seg_len
		seg_index += 1
		if gap:
			# Leave the gap empty; the next loop paints the far bank.
			pass
	return {"segments": segments, "platforms": platforms}


static func _paint_ground(layer: TileMapLayer, x0: float, x1: float, y: float,
		rng: RandomNumberGenerator) -> void:
	var cell_y := int(int(y) / TILE)
	var start_col := int(int(x0) / TILE)
	var end_col := int(ceil(x1 / float(TILE)))
	for col in range(start_col, end_col):
		var top_variant := rng.randi_range(0, 15)
		layer.set_cell(Vector2i(col, cell_y), 0, Vector2i(top_variant, 0))
		for depth in range(1, 6):
			var row := 1
			if depth >= 3:
				row = 5
			elif rng.randf() < 0.18:
				row = 2
			var variant := rng.randi_range(0, 15)
			layer.set_cell(Vector2i(col, cell_y + depth), 0, Vector2i(variant, row))


static func _add_platforms(layer: TileMapLayer, platforms: Array[Dictionary], x0: float,
		x1: float, rng: RandomNumberGenerator, dark: bool) -> void:
	var count := rng.randi_range(1, 2)
	for i in count:
		var span := rng.randi_range(3, 5)
		var px := rng.randi_range(int(x0 + 80.0), maxi(int(x0 + 80.0), int(x1 - 100.0)))
		var py := 176.0
		if i == 1 and rng.randf() < 0.35:
			py = 104.0
		var pw := float(span * TILE)
		if px + pw > x1 - 30.0:
			continue
		for col in range(int(px / float(TILE)), int((px + pw) / float(TILE))):
			var variant := rng.randi_range(0, 7)
			layer.set_cell(Vector2i(col, int(int(py) / TILE)), 0, Vector2i(variant, 3))
		platforms.append({"x0": float(px), "x1": px + pw, "y": py, "dark": dark})


static func _make_tileset(theme: String) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 0)
	var source := TileSetAtlasSource.new()
	var path := "res://assets/sprites/environment/tiles_%s.png" % theme
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/environment/tiles_suburb.png"
	source.texture = load(path)
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	for row in [0, 1, 2, 3, 5]:
		for col in 16:
			var coords := Vector2i(col, row)
			source.create_tile(coords)
			var data := source.get_tile_data(coords, 0)
			data.add_collision_polygon(0)
			var points := PackedVector2Array([
				Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)
			])
			data.set_collision_polygon_points(0, 0, points)
			if row == 3:
				data.set_collision_polygon_one_way(0, 0, true)
	return tile_set