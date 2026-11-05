class_name BuildingBuilder
extends RefCounted
## P1-5 街区建筑：带外墙/门框/窗洞的 2 层建筑体，门嵌在门框里；
## 部分建筑可进入（室内实例 + 出口），窗洞用于绳降点。
## wp1：所有主题都生成——subway 为地铁站口/票房矮楼，military 为营房/工事，
## suburb / city / bridge 维持原临街楼参数（见 _theme_params）。
## wp4-interior-complex：室内从单间矩形升级为 2-4 个功能房间 + 地面走廊 +
## 抬高层 + one-way 台阶堆 + 墙上门洞（剧情化房间表见 _LAYOUTS）。

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


## =============================================================================
## wp4-interior-complex：多房间复杂室内（对标破门而入：行动小组的室内走位）
## =============================================================================
## 每个可进入建筑按主题生成 2-4 个剧情化功能房间 + 地面走廊连接（房间表
## _LAYOUTS）：抬高层房间（floor=RAISED_ROW，高出地面 4 tile=64px）两端各设
## 「one-way 台阶堆」（4 级 × 16px）——上楼在台阶列原地起跳、下落时被最高一级
## 接住，下楼走出楼板边缘踩台阶平台逐级回落，双向皆可通行；行走路径为
## 「地面房 → 抬升 → 地面房」带上下转折，不直通。房间之间连接是墙列上挖出的
## 4 tile 高门洞（直接走过，非 enterable 门传送逻辑）；家具/掩体按房间表摆放
## 形成战术走位；弹药/医疗补给分布在不同房间、出口在最后一个房间远端，
## 迫使玩家走遍整栋建筑。
## 兼容 v3.4.5 契约：仍返回 {"entry","exit","rect"}（rect=整栋包围盒，供
## level_runner 相机右界 / InteriorAmbience / 补给回退使用），新增
## {"rooms"(房间矩形表), "path"(走位路标), "supply_spots"(补给点位)} 供验收。

const GROUND_ROW := 18   # 地面层地表 tile 行（y=288，与街道地坪同高）
const RAISED_ROW := 14   # 抬高层地表 tile 行（高出地面 4 tile = 64px）
const STEP_COLS := 2     # 台阶堆占 2 列（32px 宽）
const DOOR_GAP_H := 4    # 门洞高度 4 tile = 64px（玩家碰撞体 12×28 富余通过）

## 每主题剧情化房间表：
##   rooms: 按走位顺序排列的 {name, c0 左墙列, c1 右墙列, floor 地表行, h 净高(tile)}；
##   房间之间的地面走廊 = 前一房右墙列与后一房左墙列之间的列段（恒为 GROUND_ROW）。
##   furniture: {kind, room 房间序号, col 房内列}——槽位人工校核过：与门洞列/
##   台阶列/补给点位/出生点(±40px)/出口互不重叠，且相邻家具间隙不夹死 12px 宽通路。
##   supplies: 弹药/医疗两个点位 {room, col}，分布在不同房间（2 房主题都放在
##   入口房间远端），出口在最后一个房间远端 → 探索动线覆盖全部房间。
const _LAYOUTS := {
	"suburb": {  # 民居：客厅（入户）→ 卧室（抬高层）→ 厨房（出口）
		"rooms": [
			{"name": "客厅", "c0": 0, "c1": 13, "floor": GROUND_ROW, "h": 7},
			{"name": "卧室", "c0": 18, "c1": 29, "floor": RAISED_ROW, "h": 6},
			{"name": "厨房", "c0": 34, "c1": 45, "floor": GROUND_ROW, "h": 7},
		],
		"furniture": [
			{"kind": "table", "room": 0, "col": 7},
			{"kind": "shelf", "room": 0, "col": 11},
			{"kind": "mattress", "room": 1, "col": 21},
			{"kind": "crate", "room": 1, "col": 26},
			{"kind": "table", "room": 2, "col": 38},
			{"kind": "shelf", "room": 2, "col": 41},
		],
		"supplies": [{"room": 1, "col": 24}, {"room": 0, "col": 9}],
	},
	"city": {  # 办公楼：办公隔间（入户，工位桌阵）→ 档案室（抬高层，出口）
		"rooms": [
			{"name": "办公隔间", "c0": 0, "c1": 19, "floor": GROUND_ROW, "h": 7},
			{"name": "档案室", "c0": 24, "c1": 35, "floor": RAISED_ROW, "h": 6},
		],
		"furniture": [
			{"kind": "table", "room": 0, "col": 6},
			{"kind": "table", "room": 0, "col": 10},
			{"kind": "table", "room": 0, "col": 14},
			{"kind": "shelf", "room": 0, "col": 16},
			{"kind": "shelf", "room": 1, "col": 27},
			{"kind": "shelf", "room": 1, "col": 30},
			{"kind": "crate", "room": 1, "col": 32},
		],
		"supplies": [{"room": 0, "col": 18}, {"room": 0, "col": 8}],
	},
	"subway": {  # 地铁站：站厅（入户）→ 票房（抬高层）→ 检修通道（净高 2 tile 爬行段，出口）
		"rooms": [
			{"name": "站厅", "c0": 0, "c1": 15, "floor": GROUND_ROW, "h": 8},
			{"name": "票房", "c0": 20, "c1": 27, "floor": RAISED_ROW, "h": 5},
			{"name": "检修通道", "c0": 32, "c1": 43, "floor": GROUND_ROW, "h": 3},
		],
		"furniture": [
			{"kind": "crate", "room": 0, "col": 6},
			{"kind": "shelf", "room": 0, "col": 9},
			{"kind": "table", "room": 0, "col": 11},
			{"kind": "shelf", "room": 1, "col": 23},
		],
		"supplies": [{"room": 0, "col": 13}, {"room": 1, "col": 25}],
	},
	"military": {  # 军营：营房（入户，铺位排）→ 军械库（抬高层，弹药架）→ 电台室（出口）
		"rooms": [
			{"name": "营房", "c0": 0, "c1": 15, "floor": GROUND_ROW, "h": 7},
			{"name": "军械库", "c0": 20, "c1": 31, "floor": RAISED_ROW, "h": 6},
			{"name": "电台室", "c0": 36, "c1": 47, "floor": GROUND_ROW, "h": 6},
		],
		"furniture": [
			{"kind": "mattress", "room": 0, "col": 6},
			{"kind": "mattress", "room": 0, "col": 10},
			{"kind": "mattress", "room": 0, "col": 13},
			{"kind": "shelf", "room": 1, "col": 23},
			{"kind": "shelf", "room": 1, "col": 28},
			{"kind": "table", "room": 2, "col": 40},
			{"kind": "crate", "room": 2, "col": 43},
		],
		"supplies": [{"room": 1, "col": 25}, {"room": 0, "col": 8}],
	},
	"bridge": {  # 桥头设施：岗亭（入户）→ 设备间（抬高层，出口）
		"rooms": [
			{"name": "岗亭", "c0": 0, "c1": 11, "floor": GROUND_ROW, "h": 6},
			{"name": "设备间", "c0": 16, "c1": 29, "floor": RAISED_ROW, "h": 7},
		],
		"furniture": [
			{"kind": "table", "room": 0, "col": 6},
			{"kind": "shelf", "room": 0, "col": 8},
			{"kind": "crate", "room": 1, "col": 19},
			{"kind": "shelf", "room": 1, "col": 22},
			{"kind": "crate", "room": 1, "col": 25},
		],
		"supplies": [{"room": 0, "col": 10}, {"room": 0, "col": 1}],
	},
}


static func _layout_for(theme: String) -> Dictionary:
	if _LAYOUTS.has(theme):
		return _LAYOUTS[theme]
	# 未知主题回退 suburb 布局（与 _theme_params 的 _ 分支同级兜底）
	return _LAYOUTS["suburb"]


static func _add_static_box(parent: Node2D, cx: float, cy: float, w: float, h: float,
		one_way := false) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(cx, cy)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	shape.shape = rect
	shape.one_way_collision = one_way
	body.add_child(shape)
	parent.add_child(body)
	return body


## 可进入建筑：独立区域（远离关卡主路径）的复杂室内——多个功能房间 + 走廊 +
## 抬高层 + 台阶堆 + 门洞 + 家具掩体 + 分布式补给 + 出口（最后一个房间远端）。
## wp3-interior-visuals 观感保留：室内专用调色板 + 不透明深色底板（挡街道视差）+
## 家具（带碰撞）+ 出口下行楼梯贴片与「返回街道」浮动提示 + 进屋暖色氛围，
## 新增房间名吊牌（剧情化标识）。
## 返回 {"entry","exit","rect","rooms","path","supply_spots"}
static func build_interior(parent: Node2D, theme: String, origin: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var lay := _layout_for(theme)
	var rooms: Array = lay["rooms"]
	var room_root := Node2D.new()
	# 唯一命名：同名 add_child 会被 Godot 改成 "@Node2D@N"，外部工具按名找不到第二个房间
	var room_idx := 0
	for c in parent.get_children():
		if String(c.name).begins_with("InteriorRoot"):
			room_idx += 1
	room_root.name = "InteriorRoot%d" % (room_idx + 1)
	room_root.modulate = Color(1.0, 0.92, 0.82)  # wp3：室内固定轻暖色调
	parent.add_child(room_root)
	var base_col := int(origin.x / TILE)
	# 走廊推导：房间两两之间的列段（恒为地面层）；地面↔抬高层过渡端放台阶堆
	var corridors: Array = []
	for i in range(rooms.size() - 1):
		var cl: int = int(rooms[i]["c1"]) + 1
		var cr: int = int(rooms[i + 1]["c0"]) - 1
		var stack_cols: Array = []
		var stack_top_row := GROUND_ROW
		if int(rooms[i]["floor"]) < GROUND_ROW:
			stack_cols = [cl, cl + 1]           # 当前房抬高 → 下行台阶靠本房侧
			stack_top_row = int(rooms[i]["floor"])
		elif int(rooms[i + 1]["floor"]) < GROUND_ROW:
			stack_cols = [cr - 1, cr]           # 下一房抬高 → 上行台阶靠下一房侧
			stack_top_row = int(rooms[i + 1]["floor"])
		corridors.append({"cl": cl, "cr": cr, "stack_cols": stack_cols, "stack_top_row": stack_top_row})
	# 整栋包围盒：x 覆盖首房左墙列到末房右墙列，y 覆盖最高天花板行到地基底
	var top_row := GROUND_ROW
	for r in rooms:
		top_row = mini(top_row, int(r["floor"]) - int(r["h"]))
	var bx0: float = (base_col + int(rooms[0]["c0"])) * TILE
	var bx1: float = (base_col + int(rooms[rooms.size() - 1]["c1"]) + 1) * TILE
	var room_rect := Rect2(bx0, top_row * TILE, bx1 - bx0, (GROUND_ROW + 5) * TILE - top_row * TILE)
	# wp3：不透明深色底板——室内 tile 层之下、街道视差之上，
	# 覆盖建筑 rect 外扩 240px，彻底挡住房子/路灯/天空。
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
	_paint_complex(layer, base_col, rooms, corridors, top_row, rng)
	_build_complex_bodies(parent, base_col, rooms, corridors)
	# ---- wp4：家具/掩体（带 StaticBody 碰撞，槽位来自房间表）----
	var furn_list: Array = lay["furniture"]
	for f in furn_list:
		var fr: Dictionary = rooms[int(f["room"])]
		_spawn_furniture(room_root, String(f["kind"]),
				(base_col + int(f["col"])) * TILE + 8.0, int(fr["floor"]) * TILE)
	# ---- wp4：补给点位（弹药/医疗分布在不同房间，level_runner 按 spots 刷）----
	var supply_spots: Array = []
	for s in lay["supplies"]:
		var sr: Dictionary = rooms[int(s["room"])]
		supply_spots.append(Vector2((base_col + int(s["col"])) * TILE + 8.0,
				int(sr["floor"]) * TILE - 24.0))
	# ---- 入口（首房左墙内侧 4 tile）与出口（末房右墙内侧，最后房间远端）----
	var first: Dictionary = rooms[0]
	var last: Dictionary = rooms[rooms.size() - 1]
	var entry_pos := Vector2((base_col + int(first["c0"]) + 4) * TILE,
			int(first["floor"]) * TILE - 4)
	var exit_pos := Vector2((base_col + int(last["c1"]) - 1) * TILE + 8.0,
			int(last["floor"]) * TILE - 4)
	var last_ground_y := float(int(last["floor"]) * TILE)
	# ---- wp3：出口下行楼梯贴片 + 「返回街道」浮动提示 ----
	var furn_tex: Texture2D = load("res://assets/sprites/environment/interior_furniture.png")
	if furn_tex != null:
		var stairs := Sprite2D.new()
		stairs.texture = furn_tex
		stairs.region_enabled = true
		stairs.region_rect = Rect2(4 * 32, 0, 32, 32)  # stairs_down 格
		stairs.centered = false
		stairs.position = Vector2(exit_pos.x - 16.0, last_ground_y - 32.0)
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
	# ---- wp4：房间名吊牌（剧情化标识，验收截图可读出房间主题）----
	var label_root := Node2D.new()
	label_root.name = "RoomLabels"
	label_root.z_index = 1
	room_root.add_child(label_root)
	var room_infos: Array = []
	for r in rooms:
		var c0 := int(r["c0"])
		var c1 := int(r["c1"])
		var floor_row := int(r["floor"])
		var h := int(r["h"])
		var rc := Rect2((base_col + c0) * TILE, (floor_row - h) * TILE,
				(c1 - c0 + 1) * TILE, h * TILE + 8.0)
		room_infos.append({"name": String(r["name"]), "rect": rc, "floor_y": floor_row * TILE})
		var lb := UIKit.label(String(r["name"]), 9, Color(0.91, 0.83, 0.66, 0.85), UIKit.font_cjk())
		lb.position = Vector2(rc.position.x + rc.size.x * 0.5 - 48.0, rc.position.y + 6.0)
		lb.size = Vector2(96, 14)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_root.add_child(lb)
	# ---- wp4：走位路标（每房间中心 + 每次爬层的台阶列中心；末点为出口）----
	var path: Array = []
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		if i > 0 and int(r["floor"]) < GROUND_ROW:
			var cor: Dictionary = corridors[i - 1]
			var s0 := int(cor["stack_cols"][0])
			path.append(Vector2((base_col + s0) * TILE + STEP_COLS * TILE * 0.5,
					int(r["floor"]) * TILE - 4.0))
		var mid_col := (int(r["c0"]) + int(r["c1"]) + 1) / 2
		path.append(Vector2((base_col + mid_col) * TILE + 8.0, int(r["floor"]) * TILE - 4.0))
	path.append(exit_pos)
	# ---- wp3：室内氛围挂件——玩家/队友/室内掉落物进屋染暖、回街恢复 ----
	var ambience := InteriorAmbienceScript.new()
	ambience.name = "InteriorAmbience"
	ambience.room_rect = room_rect
	room_root.add_child(ambience)
	return {
		"entry": entry_pos,
		"exit": exit_pos,
		"rect": room_rect,
		"rooms": room_infos,
		"path": path,
		"supply_spots": supply_spots,
	}


## wp4：复杂室内贴片绘制。房间：地板/地基/天花板/天花板以上楼体质量/墙列
## （门洞段挖暗）；走廊：地板/地基/天花板/质量（台阶列留空作楼梯井）；
## 台阶堆：row 5 平台木缘逐级贴出楼梯观感。
static func _paint_complex(layer: TileMapLayer, base_col: int, rooms: Array,
		corridors: Array, top_row: int, rng: RandomNumberGenerator) -> void:
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var c0 := int(r["c0"])
		var c1 := int(r["c1"])
		var floor_row := int(r["floor"])
		var ceil_row := floor_row - int(r["h"])
		var minf := mini(floor_row, GROUND_ROW)  # 门洞服务较低一侧地面
		for col in range(c0, c1 + 1):
			var wc := base_col + col
			layer.set_cell(Vector2i(wc, floor_row), 0, Vector2i(rng.randi_range(0, 15), 0))
			for row in range(floor_row + 1, floor_row + 5):
				layer.set_cell(Vector2i(wc, row), 0, Vector2i(rng.randi_range(0, 15), 4))
			layer.set_cell(Vector2i(wc, ceil_row), 0, Vector2i(rng.randi_range(0, 15), 3))
			for row in range(top_row, ceil_row):
				layer.set_cell(Vector2i(wc, row), 0, Vector2i(rng.randi_range(0, 15), 1))
		# 墙列：外墙（首房左墙/末房右墙）整列实墙；走廊侧挖门洞（暗色开口）
		var side_cols := [[c0, i == 0], [c1, i == rooms.size() - 1]]
		for sc in side_cols:
			var col: int = sc[0]
			var exterior: bool = sc[1]
			var gap_rows := {}
			if not exterior:
				for row in range(minf - DOOR_GAP_H, minf):
					gap_rows[row] = true
			for row in range(ceil_row, floor_row):
				var tex_row := 1
				if gap_rows.has(row):
					tex_row = 4  # 门洞开口（暗）
				elif row == floor_row - 1:
					tex_row = 2  # 踢脚线
				layer.set_cell(Vector2i(base_col + col, row), 0, Vector2i(rng.randi_range(0, 15), tex_row))
	for cor in corridors:
		var stack_cols: Array = cor["stack_cols"]
		for col in range(int(cor["cl"]), int(cor["cr"]) + 1):
			var wc := base_col + col
			layer.set_cell(Vector2i(wc, GROUND_ROW), 0, Vector2i(rng.randi_range(0, 15), 0))
			for row in range(GROUND_ROW + 1, GROUND_ROW + 5):
				layer.set_cell(Vector2i(wc, row), 0, Vector2i(rng.randi_range(0, 15), 4))
			if not stack_cols.has(col):
				layer.set_cell(Vector2i(wc, GROUND_ROW - DOOR_GAP_H), 0, Vector2i(rng.randi_range(0, 15), 3))
				for row in range(top_row, GROUND_ROW - DOOR_GAP_H):
					layer.set_cell(Vector2i(wc, row), 0, Vector2i(rng.randi_range(0, 15), 1))
		if not stack_cols.is_empty():
			var top: int = cor["stack_top_row"]
			for col in stack_cols:
				for row in range(top, GROUND_ROW):
					layer.set_cell(Vector2i(base_col + int(col), row), 0,
							Vector2i(rng.randi_range(0, 15), 5))


## wp4：复杂室内碰撞体。每房楼板（含墙列正下方）+ 左右墙体（门洞段留空）+
## 地面↔抬高层过渡端的 one-way 台阶堆（上行穿过、下行承接，双向可通行）。
static func _build_complex_bodies(parent: Node2D, base_col: int, rooms: Array,
		corridors: Array) -> void:
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var c0 := int(r["c0"])
		var c1 := int(r["c1"])
		var floor_row := int(r["floor"])
		var ceil_row := floor_row - int(r["h"])
		var minf := mini(floor_row, GROUND_ROW)
		var x0 := (base_col + c0) * TILE
		var w := (c1 - c0 + 1) * TILE
		# 楼板：厚 5 tile（地表行 + 地基 4 行），跨房间全部列
		_add_static_box(parent, x0 + w * 0.5, floor_row * TILE + 40.0, w, 5.0 * TILE)
		# 侧墙：首房左墙 / 末房右墙为整列实墙；走廊侧墙在门洞段（minf-4..minf-1 行）留空
		var side_cols := [[c0, i == 0], [c1, i == rooms.size() - 1]]
		for sc in side_cols:
			var col: int = sc[0]
			var exterior: bool = sc[1]
			var y_top := ceil_row * TILE
			var y_bot := floor_row * TILE
			if not exterior:
				var gap_top_row := minf - DOOR_GAP_H
				if gap_top_row <= ceil_row:
					continue  # 门洞贯穿整面墙（如爬行段），无墙体
				y_bot = gap_top_row * TILE
			var wall_x := (base_col + col) * TILE + (0.0 if col == c0 else TILE - 8.0)
			_add_static_box(parent, wall_x + 4.0, (y_top + y_bot) * 0.5, 8.0, y_bot - y_top)
	for cor in corridors:
		# 走廊楼板（地面层，与两侧房间楼板同高衔接——走廊列段必须有实体地板，
		# 否则玩家在门洞→台阶之间踩空坠入远端虚空）
		var cl := int(cor["cl"])
		var cr := int(cor["cr"])
		var cx0 := (base_col + cl) * TILE
		var cw := (cr - cl + 1) * TILE
		_add_static_box(parent, cx0 + cw * 0.5, GROUND_ROW * TILE + 40.0, cw, 5.0 * TILE)
		var stack_cols: Array = cor["stack_cols"]
		if stack_cols.is_empty():
			continue
		var top: int = cor["stack_top_row"]
		var s0 := int(stack_cols[0])
		for row in range(top, GROUND_ROW):
			# one-way 台阶：顶面 row*TILE、厚 6px；从下方穿过、从上方承接
			_add_static_box(parent, (base_col + s0) * TILE + STEP_COLS * TILE * 0.5,
					row * TILE + 3.0, STEP_COLS * TILE, 6.0, true)
