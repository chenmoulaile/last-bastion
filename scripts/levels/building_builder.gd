class_name BuildingBuilder
extends RefCounted
## P1-5 街区建筑：带外墙/门框/窗洞的 2 层建筑体，门嵌在门框里；
## 部分建筑可进入（独立房间实例 + 出口），窗洞用于绳降点。
## wp1：所有主题都生成——subway 为地铁站口/票房矮楼，military 为营房/工事，
## suburb / city / bridge 维持原临街楼参数（见 _theme_params）。

const TILE := 16

const FACADE_ROWS := 6          # 默认建筑高度（6 × 16 = 96px）
const BUILDING_W := 300.0


## 按主题取立面参数：
## facade_rows 建筑高度（tile 行数）；wall_row_hi/lo 上/下段墙体 tile 行；
## win_depths 开窗的 depth 层（0 = 最底层）。build() 骨架（4 幢、前 2 幢可进入）各主题一致。
static func _theme_params(theme: String) -> Dictionary:
	match theme:
		"subway":
			# 地铁站口/票房矮楼：4 层高，上下两层开窗
			return {"facade_rows": 4, "wall_row_hi": 1, "wall_row_lo": 5, "win_depths": [1, 3]}
		"military":
			# 营房/沙袋工事：5 层高，上下两层开窗
			return {"facade_rows": 5, "wall_row_hi": 1, "wall_row_lo": 5, "win_depths": [1, 3]}
		_:
			# 临街楼：6 层高，depth 2/4 两层开窗（原参数）
			return {"facade_rows": FACADE_ROWS, "wall_row_hi": 1, "wall_row_lo": 5, "win_depths": [2, 4]}


## 无碰撞 tileset：立面是"贴在街道后景上的建筑体"，玩家从前景走过。
## wp2：优先用专用立面图集 facade_{theme}.png（砖墙/抹灰/檐口/地板），
## 缺失时回退 facade_suburb.png，再回退旧的道路图集。
static func _make_visual_tileset(theme: String) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	var path := "res://assets/sprites/environment/facade_%s.png" % theme
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/environment/facade_suburb.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/environment/tiles_%s.png" % theme
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/environment/tiles_suburb.png"
	source.texture = load(path)
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	for row in 6:
		for col in 16:
			source.create_tile(Vector2i(col, row))
	return tile_set


## 返回 [{"x0","x1","door_x","windows":[x...],"enterable":bool}]
static func build(parent: Node2D, theme: String, width: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var params := _theme_params(theme)
	var tile_set := _make_visual_tileset(theme)
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
		var windows := _paint_facade(layer, front, x0, x1, ground_y, rng, params)
		var door_x := x0 + BUILDING_W * 0.5
		# 门框：左右立柱 + 门楣（压在前景层，形成"嵌在墙里"的观感）
		_paint_door_frame(front, door_x, ground_y)
		# wp2：门旁挂 sign 门牌（临街店铺观感）
		_paint_door_sign(front, door_x, ground_y)
		out.append({
			"x0": x0, "x1": x1, "door_x": door_x,
			"windows": windows, "enterable": enterable, "ground_y": ground_y,
		})
	return out


static func _paint_facade(layer: TileMapLayer, front: TileMapLayer, x0: float, x1: float,
		ground_y: float, rng: RandomNumberGenerator, params: Dictionary) -> Array:
	var facade_rows := int(params["facade_rows"])
	var row_hi := int(params["wall_row_hi"])
	var row_lo := int(params["wall_row_lo"])
	var win_depths: Array = params["win_depths"]
	var split_depth := int(ceil(facade_rows / 2.0))   # 此 depth 以上用上段行，以下用下段行
	var start_col := int(x0 / TILE)
	var end_col := int(ceil(x1 / TILE))
	var base_row := int(ground_y / TILE)   # 18
	var windows: Array = []
	for col in range(start_col, end_col):
		for depth in range(0, facade_rows):
			var row := base_row - depth
			# 窗洞：窗行（win_depths）每隔 5 列留 2 格空；两窗层都正确开窗
			var is_window_row := depth in win_depths
			var col_off := (col - start_col) % 6
			if is_window_row and col_off in [2, 3]:
				continue
			var tile_row := row_hi if depth >= split_depth else row_lo
			var variant := rng.randi_range(0, 15)
			layer.set_cell(Vector2i(col, row), 0, Vector2i(variant, tile_row))
	# 窗洞内芯（深色/亮窗）+ 窗框叠加 + 窗台
	var frame_tex := SpriteLibrary.prop_texture("window_frame")
	for wdepth in win_depths:
		for col in range(start_col, end_col):
			var col_off := (col - start_col) % 6
			if col_off in [2, 3]:
				var hole := ColorRect.new()
				# wp2：约 1/3 的窗为"亮窗"（室内透出暖光），其余盲窗深色
				hole.color = Color(0.86, 0.68, 0.36, 1.0) if rng.randf() < 0.33 \
						else Color(0.05, 0.06, 0.08, 1.0)
				hole.position = Vector2(col * TILE, (base_row - wdepth) * TILE)
				hole.size = Vector2(TILE, TILE)
				hole.z_index = 1
				front.add_child(hole)
				# wp2：窗芯处叠加专用窗框贴图（32x31 缩到 16px，盖住窗洞四缘）
				if frame_tex != null:
					var frame := Sprite2D.new()
					frame.texture = frame_tex
					frame.centered = false
					frame.scale = Vector2(0.5, 0.5)
					frame.position = hole.position
					frame.z_index = 2
					front.add_child(frame)
				if wdepth == int(win_depths[0]) and col_off == 2:
					windows.append(Vector2(col * TILE + TILE, (base_row - wdepth) * TILE))
	# 屋顶（前景）
	for col in range(start_col - 1, end_col + 1):
		front.set_cell(Vector2i(col, base_row - facade_rows), 0, Vector2i(rng.randi_range(0, 15), 3))
		front.set_cell(Vector2i(col, base_row - facade_rows - 1), 0, Vector2i(rng.randi_range(0, 15), 3))
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


## wp2：门旁挂 sign 门牌（右立柱外侧，悬在门楣下方）
static func _paint_door_sign(front: TileMapLayer, door_x: float, ground_y: float) -> void:
	var tex := SpriteLibrary.prop_texture("sign")
	if tex == null:
		return
	var base_row := int(ground_y / TILE)
	var col := int(door_x / TILE)
	var sign := Sprite2D.new()
	sign.texture = tex
	sign.centered = false
	sign.position = Vector2((col + 2) * TILE + 1.0, (base_row - 3) * TILE + 12.0)
	sign.z_index = 2
	front.add_child(sign)


## 可进入房间：独立区域（远离关卡主路径），有地板/墙/平台/掩体/补给/出口。
## 返回 {"entry": Vector2, "exit": Vector2}
static func build_interior(parent: Node2D, theme: String, origin: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var tile_set := _make_visual_tileset(theme)
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	layer.z_index = 0
	layer.modulate = Color(0.82, 0.82, 0.9)
	parent.add_child(layer)
	var room_w := 22
	var room_h := 9
	var base_col := int(origin.x / TILE)
	var base_row := int(origin.y / TILE)
	# 房间实体：地板/左右墙/顶板（内部空间必须有碰撞）
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(base_col * TILE + room_w * TILE * 0.5, base_row * TILE + 2.5 * TILE)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(room_w * TILE, 5 * TILE)
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	var left_wall := StaticBody2D.new()
	left_wall.collision_layer = 1
	left_wall.collision_mask = 0
	left_wall.position = Vector2(base_col * TILE + 4.0, base_row * TILE - room_h * TILE * 0.5)
	var lshape := CollisionShape2D.new()
	var lrect := RectangleShape2D.new()
	lrect.size = Vector2(8, room_h * TILE)
	lshape.shape = lrect
	left_wall.add_child(lshape)
	parent.add_child(left_wall)
	var right_wall := StaticBody2D.new()
	right_wall.collision_layer = 1
	right_wall.collision_mask = 0
	right_wall.position = Vector2(base_col * TILE + room_w * TILE - 4.0, base_row * TILE - room_h * TILE * 0.5)
	var rshape := CollisionShape2D.new()
	var rrect := RectangleShape2D.new()
	rrect.size = Vector2(8, room_h * TILE)
	rshape.shape = rrect
	right_wall.add_child(rshape)
	parent.add_child(right_wall)
	var plat := StaticBody2D.new()
	plat.collision_layer = 1
	plat.collision_mask = 0
	plat.position = Vector2(base_col * TILE + room_w * TILE * 0.5, (base_row - 4) * TILE)
	var pshape := CollisionShape2D.new()
	var prect := RectangleShape2D.new()
	prect.size = Vector2((room_w - 8) * TILE, 6)
	pshape.shape = prect
	pshape.one_way_collision = true
	plat.add_child(pshape)
	parent.add_child(plat)
	for col in range(base_col, base_col + room_w):
		for depth in range(1, 5):
			# wp2：立面图集 row 2 = 楼板填充（原 row 5 现在是外墙砖）
			layer.set_cell(Vector2i(col, base_row + depth), 0, Vector2i(rng.randi_range(0, 15), 2))
		layer.set_cell(Vector2i(col, base_row), 0, Vector2i(rng.randi_range(0, 15), 0))
	for row in range(base_row - room_h, base_row):
		# wp2：立面图集 (4,4) = 内部侧墙深砖（原 (4,5) 现在是外墙砖/立柱）
		layer.set_cell(Vector2i(base_col, row), 0, Vector2i(4, 4))
		layer.set_cell(Vector2i(base_col + room_w - 1, row), 0, Vector2i(4, 4))
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
