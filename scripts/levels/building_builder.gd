class_name BuildingBuilder
extends RefCounted
## P1-5 街区建筑：带外墙/门框/窗洞的 2 层建筑体，门嵌在门框里；
## 部分建筑可进入（独立房间实例 + 出口），窗洞用于绳降点。
## 仅在 suburb / city / bridge 主题生成，其余主题保持原样。

const TILE := 16

const FACADE_ROWS := 6          # 建筑高度（6 × 16 = 96px）
const BUILDING_W := 300.0


## 返回 [{"x0","x1","door_x","windows":[x...],"enterable":bool}]
static func build(parent: Node2D, theme: String, width: float, rng: RandomNumberGenerator) -> Array:
	if theme not in ["suburb", "city", "bridge"]:
		return []
	var out: Array = []
	var tile_set := TerrainBuilder._make_tileset(theme)
	var layer := TileMapLayer.new()
	layer.name = "Buildings"
	layer.tile_set = tile_set
	layer.z_index = 0
	parent.add_child(layer)
	var front := TileMapLayer.new()
	front.name = "BuildingFronts"
	front.tile_set = tile_set
	front.z_index = 4  # 前景遮挡（屋顶/墙体压在角色前）
	parent.add_child(front)

	var fractions := [0.17, 0.36, 0.57, 0.77]
	var enterable_left := 2
	for i in fractions.size():
		var cx: float = width * float(fractions[i])
		var x0: float = clampf(cx - BUILDING_W * 0.5, 80.0, width - BUILDING_W - 80.0)
		var x1: float = x0 + BUILDING_W
		var ground_y := 288.0
		var enterable := enterable_left > 0
		if enterable:
			enterable_left -= 1
		var windows := _paint_facade(layer, front, x0, x1, ground_y, rng)
		var door_x := x0 + BUILDING_W * 0.5
		# 门框：左右立柱 + 门楣（压在前景层，形成"嵌在墙里"的观感）
		_paint_door_frame(front, door_x, ground_y)
		out.append({
			"x0": x0, "x1": x1, "door_x": door_x,
			"windows": windows, "enterable": enterable, "ground_y": ground_y,
		})
	return out


static func _paint_facade(layer: TileMapLayer, front: TileMapLayer, x0: float, x1: float,
		ground_y: float, rng: RandomNumberGenerator) -> Array:
	var start_col := int(x0 / TILE)
	var end_col := int(ceil(x1 / TILE))
	var base_row := int(ground_y / TILE)   # 18
	var windows: Array = []
	for col in range(start_col, end_col):
		for depth in range(0, FACADE_ROWS):
			var row := base_row - depth
			# 窗洞：上两层每隔 5 列留 2 格空
			var is_window_row := depth == 2 or depth == 4
			var col_off := (col - start_col) % 6
			if is_window_row and col_off in [2, 3] and depth == 3:
				continue
			if is_window_row and col_off in [2, 3]:
				continue
			var tile_row := 1 if depth >= 3 else 5
			var variant := rng.randi_range(0, 15)
			layer.set_cell(Vector2i(col, row), 0, Vector2i(variant, tile_row))
	# 窗洞内芯（深色）+ 窗台
	for depth in [2, 4]:
		for col in range(start_col, end_col):
			var col_off := (col - start_col) % 6
			if col_off in [2, 3]:
				var hole := ColorRect.new()
				hole.color = Color(0.05, 0.06, 0.08, 1.0)
				hole.position = Vector2(col * TILE, (base_row - depth) * TILE)
				hole.size = Vector2(TILE, TILE)
				hole.z_index = 1
				front.add_child(hole)
				if depth == 2 and col_off == 2:
					windows.append(Vector2(col * TILE + TILE, (base_row - depth) * TILE))
	# 屋顶（前景）
	for col in range(start_col - 1, end_col + 1):
		front.set_cell(Vector2i(col, base_row - FACADE_ROWS), 0, Vector2i(rng.randi_range(0, 15), 3))
		front.set_cell(Vector2i(col, base_row - FACADE_ROWS - 1), 0, Vector2i(rng.randi_range(0, 15), 3))
	return windows


static func _paint_door_frame(front: TileMapLayer, door_x: float, ground_y: float) -> void:
	var base_row := int(ground_y / TILE)
	var col := int(door_x / TILE)
	# 门楣
	for c in range(col - 2, col + 2):
		front.set_cell(Vector2i(c, base_row - 3), 0, Vector2i(3, 1))
	# 门框立柱（左右各 1 列，从地面到门楣）
	for row in range(base_row - 2, base_row):
		front.set_cell(Vector2i(col - 2, row), 0, Vector2i(5, 5))
		front.set_cell(Vector2i(col + 1, row), 0, Vector2i(5, 5))


## 可进入房间：独立区域（远离关卡主路径），有地板/墙/平台/掩体/补给/出口。
## 返回 {"entry": Vector2, "exit": Vector2}
static func build_interior(parent: Node2D, theme: String, origin: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var tile_set := TerrainBuilder._make_tileset(theme)
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.z_index = 0
	layer.modulate = Color(0.82, 0.82, 0.9)
	parent.add_child(layer)
	var room_w := 22
	var room_h := 9
	var base_col := int(origin.x / TILE)
	var base_row := int(origin.y / TILE)
	for col in range(base_col, base_col + room_w):
		for depth in range(1, 5):
			layer.set_cell(Vector2i(col, base_row + depth), 0, Vector2i(rng.randi_range(0, 15), 5))
		layer.set_cell(Vector2i(col, base_row), 0, Vector2i(rng.randi_range(0, 15), 0))
	for row in range(base_row - room_h, base_row):
		layer.set_cell(Vector2i(base_col, row), 0, Vector2i(4, 5))
		layer.set_cell(Vector2i(base_col + room_w - 1, row), 0, Vector2i(4, 5))
	for col in range(base_col, base_col + room_w):
		layer.set_cell(Vector2i(col, base_row - room_h), 0, Vector2i(rng.randi_range(0, 15), 3))
	# 二层平台
	for col in range(base_col + 4, base_col + room_w - 4):
		layer.set_cell(Vector2i(col, base_row - 4), 0, Vector2i(rng.randi_range(0, 7), 3))
	return {
		"entry": Vector2(base_col * TILE + 4 * TILE, base_row * TILE - 4),
		"exit": Vector2(base_col * TILE + 2 * TILE, base_row * TILE - 4),
		"rect": Rect2(base_col * TILE, (base_row - room_h) * TILE, room_w * TILE, room_h * TILE),
	}
