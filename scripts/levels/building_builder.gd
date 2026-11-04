class_name BuildingBuilder
extends RefCounted
## P1-5 街区建筑：带外墙/门框/窗洞的 2 层建筑体，门嵌在门框里；
## 部分建筑可进入（独立房间实例 + 出口），窗洞用于绳降点。
## wp1：所有主题都生成——subway 为地铁站口/票房矮楼，military 为营房/工事，
## suburb / city / bridge 维持原临街楼参数（见 _theme_params）。

const TILE := 16

const FACADE_ROWS := 6          # 默认建筑高度（6 × 16 = 96px）
const BUILDING_W := 300.0

## wp3：室内氛围挂件（preload 而非 class_name，避免全局类缓存未刷新时解析失败）
const InteriorAmbienceScript := preload("res://scripts/levels/interior_ambience.gd")


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


## wp3：室内专用 tileset——不复用街道立面/路面砖。
## interior_{theme}.png（256x96，6 行）：row0 木地板横纹 / row1 墙纸墙面 /
## row2 踢脚线行 / row3 天花板 / row4 地板下填充 / row5 平台木缘。
## 缺失时回退 interior_suburb.png，再回退街道 facade 图集（兜底，不崩）。
static func _make_interior_tileset(theme: String) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	var path := "res://assets/sprites/environment/interior_%s.png" % theme
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/environment/interior_suburb.png"
	if not ResourceLoader.exists(path):
		return _make_visual_tileset(theme)
	source.texture = load(path)
	source.texture_region_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	for row in 6:
		for col in 16:
			source.create_tile(Vector2i(col, row))
	return tile_set


## 家具类型 -> [interior_furniture.png 格号, 碰撞宽, 碰撞高]（32x32 贴片，底边落地）
const FURNITURE := {
	"table": [0, 30, 16],
	"shelf": [1, 26, 30],
	"crate": [2, 26, 24],
	"mattress": [3, 30, 12],
}


## wp3：室内摆一件家具（StaticBody2D 碰撞 + 32x32 贴片精灵），返回碰撞体。
static func _spawn_furniture(room_root: Node2D, kind: String, cx: float, ground_y: float) -> StaticBody2D:
	var info: Array = FURNITURE[kind]
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(cx, ground_y - float(info[2]) * 0.5)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(float(info[1]), float(info[2]))
	shape.shape = rect
	body.add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/sprites/environment/interior_furniture.png")
	sprite.region_enabled = true
	sprite.region_rect = Rect2(int(info[0]) * 32, 0, 32, 32)
	sprite.centered = false
	sprite.position = Vector2(-16.0, -32.0)
	sprite.z_index = 2
	body.add_child(sprite)
	room_root.add_child(body)
	return body


## 可进入房间：独立区域（远离关卡主路径），有地板/墙/平台/掩体/补给/出口。
## wp3-interior-visuals：室内专用调色板 + 不透明深色底板（挡街道视差）+
## 随机家具（带碰撞）+ 出口下行楼梯贴片与「返回街道」浮动提示 + 进屋暖色氛围。
## 返回 {"entry": Vector2, "exit": Vector2}
static func build_interior(parent: Node2D, theme: String, origin: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var room_root := Node2D.new()
	# 唯一命名：同名 add_child 会被 Godot 改成 "@Node2D@N"，外部工具按名找不到第二个房间
	var room_idx := 0
	for c in parent.get_children():
		if String(c.name).begins_with("InteriorRoot"):
			room_idx += 1
	room_root.name = "InteriorRoot%d" % (room_idx + 1)
	room_root.modulate = Color(1.0, 0.92, 0.82)  # wp3：室内固定轻暖色调
	parent.add_child(room_root)
	var room_w := 22
	var room_h := 9
	var base_col := int(origin.x / TILE)
	var base_row := int(origin.y / TILE)
	var room_rect := Rect2(base_col * TILE, (base_row - room_h) * TILE, room_w * TILE, room_h * TILE)
	# wp3：不透明深色底板——室内 tile 层之下、街道视差之上，
	# 覆盖房间 rect 外扩 240px，彻底挡住房子/路灯/天空。
	var backdrop := Polygon2D.new()
	var pad := 240.0
	var bd := room_rect.grow(pad)
	backdrop.polygon = PackedVector2Array([
		bd.position, Vector2(bd.end.x, bd.position.y),
		bd.end, Vector2(bd.position.x, bd.end.y),
	])
	backdrop.color = Color(0.07, 0.06, 0.08)
	backdrop.z_index = -6
	room_root.add_child(backdrop)
	var layer := TileMapLayer.new()
	layer.tile_set = _make_interior_tileset(theme)
	layer.z_index = 0
	room_root.add_child(layer)
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
			# wp3：interior 图集 row 4 = 地板下填充（暗色地基）
			layer.set_cell(Vector2i(col, base_row + depth), 0, Vector2i(rng.randi_range(0, 15), 4))
		# wp3：interior 图集 row 0 = 木地板（暖棕横纹）
		layer.set_cell(Vector2i(col, base_row), 0, Vector2i(rng.randi_range(0, 15), 0))
	for row in range(base_row - room_h, base_row):
		# wp3：室内侧墙 = row 1 墙纸；贴地一行用 row 2 踢脚线
		var wall_row := 2 if row == base_row - 1 else 1
		layer.set_cell(Vector2i(base_col, row), 0, Vector2i(rng.randi_range(0, 15), wall_row))
		layer.set_cell(Vector2i(base_col + room_w - 1, row), 0, Vector2i(rng.randi_range(0, 15), wall_row))
	for col in range(base_col, base_col + room_w):
		# wp3：interior 图集 row 3 = 天花板
		layer.set_cell(Vector2i(col, base_row - room_h), 0, Vector2i(rng.randi_range(0, 15), 3))
	# 二层平台（wp3：row 5 = 平台木缘）
	for col in range(base_col + 4, base_col + room_w - 4):
		layer.set_cell(Vector2i(col, base_row - 4), 0, Vector2i(rng.randi_range(0, 15), 5))
	# ---- wp3：家具 3-5 件（带 StaticBody 碰撞，类型从桌/货架/木箱/床垫随机）----
	# 补给由 level_runner 固定刷在 room_x+120（弹药）/ room_x+200（医疗）：
	# 固定两件紧贴补给（槽@152、@232），再从右侧空档/二层平台随机补 1-3 件，
	# 全部槽位与两件补给中心距 ≥32px，不压补给、不堵入口（entry@64）与出口（exit@32）。
	var ground_y := base_row * TILE
	var room_x := base_col * TILE
	var slots: Array = [[152.0, ground_y], [232.0, ground_y]]
	var extra_slots: Array = [264.0, 308.0, 176.0]
	var kinds_pool: Array = ["table", "shelf", "crate", "mattress"]
	var extra_count := rng.randi_range(1, 3)
	for i in extra_count:
		var kind: String = kinds_pool[rng.randi_range(0, kinds_pool.size() - 1)]
		if i < 2:
			slots.append([extra_slots[i], ground_y])
		else:
			slots.append([176.0, (base_row - 4) * TILE])  # 第 5 件上二层平台
	for s in slots:
		var kind: String = kinds_pool[rng.randi_range(0, kinds_pool.size() - 1)]
		_spawn_furniture(room_root, kind, room_x + float(s[0]), float(s[1]))
	# ---- wp3：出口下行楼梯贴片 + 「返回街道」浮动提示 ----
	var exit_pos := Vector2(room_x + 2 * TILE, base_row * TILE - 4)
	var furn_tex: Texture2D = load("res://assets/sprites/environment/interior_furniture.png")
	if furn_tex != null:
		var stairs := Sprite2D.new()
		stairs.texture = furn_tex
		stairs.region_enabled = true
		stairs.region_rect = Rect2(4 * 32, 0, 32, 32)  # stairs_down 格
		stairs.centered = false
		stairs.position = Vector2(exit_pos.x - 16.0, ground_y - 32.0)
		room_root.add_child(stairs)
	# 浮动提示：复用 HUD interact prompt 样式（UIKit 深底 AMBER 边 + INK 字，hud.gd:640-650）
	var prompt_root := Node2D.new()
	prompt_root.position = exit_pos + Vector2(0.0, -52.0)
	prompt_root.z_index = 7  # 高于玩家（Actors z=5），保证提示可见
	var prompt_panel := UIKit.panel(Color(0.04, 0.05, 0.06, 0.92), UIKit.AMBER)
	prompt_panel.position = Vector2(-34.0, -10.0)
	prompt_panel.size = Vector2(68, 20)
	prompt_root.add_child(prompt_panel)
	var prompt_label := UIKit.label("返回街道", 9, UIKit.INK, UIKit.font_cjk())
	prompt_label.position = Vector2(2.0, 3.0)
	prompt_label.size = Vector2(64, 12)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	room_root.add_child(prompt_root)
	# ---- wp3：室内氛围挂件——玩家/队友/室内掉落物进屋染暖、回街恢复 ----
	var ambience := InteriorAmbienceScript.new()
	ambience.name = "InteriorAmbience"
	ambience.room_rect = room_rect
	room_root.add_child(ambience)
	return {
		"entry": Vector2(base_col * TILE + 4 * TILE, base_row * TILE - 4),
		"exit": exit_pos,
		"rect": room_rect,
	}
