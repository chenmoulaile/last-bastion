extends Node
## RogueliteMapGenerator - 基于种子的程序化房间拼接生成器。
##
## 生成 10x10 房间网格，每个房间有类型（起点/战斗/补给/精英/Boss/秘密）。
## 使用种子确保同一设备上生成完全相同的地图。
## 保证所有房间可达（无死路）。

const ROOM_SIZE := 420.0  # 房间间距，包含墙壁

var seed: int = 0
var rng: RandomNumberGenerator = null
var grid_width: int = 10
var grid_height: int = 10
var rooms: Dictionary = {}  # "x,y" -> {type, x, y, room_scene, connections}

var room_scenes: Dictionary = {
	&"start": preload("res://scenes/rooms/start_room.tscn"),
	&"combat": preload("res://scenes/rooms/combat_room.tscn"),
	&"supply": preload("res://scenes/rooms/supply_room.tscn"),
	&"boss": preload("res://scenes/rooms/boss_room.tscn"),
}

func _ready() -> void:
	rng = RandomNumberGenerator.new()

## 使用给定种子生成地图。
func generate(seed_val: int, width: int = 10, height: int = 10) -> Dictionary:
	seed = seed_val
	grid_width = width
	grid_height = height
	rng.seed = seed_val
	rooms.clear()

	# 第一步：随机放置房间类型
	var room_map: Dictionary = {}
	for y in height:
		for x in width:
			var key := str(x) + "," + str(y)
			var r := rng.randi_range(0, 100)
			var t: int
			if x == 0 and y == int(height / 2):
				t = 0  # START
			elif x == width - 1 and y == int(height / 2):
				t = 4  # BOSS
			elif r < 10:
				t = 5  # SECRET
			elif r < 25:
				t = 3  # ELITE
			elif r < 40:
				t = 2  # SUPPLY
			else:
				t = 1  # COMBAT
			room_map[key] = {"type": t, "x": x, "y": y}

	# 第二步：使用 DFS 确保所有房间可达（从起点出发，打通路径）
	var visited: Dictionary = {}
	var stack: Array = [Vector2(0, int(height / 2))]
	visited[str(0) + "," + str(int(height / 2))] = true

	while stack.size() > 0:
		var current: Vector2 = stack.pop_back()
		var cx := int(current.x)
		var cy := int(current.y)
		var ckey := str(cx) + "," + str(cy)

		# 随机打乱方向
		var dirs: Array = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		dirs = shuffle_array(dirs)

		for dir in dirs:
			var nx := cx + int(dir.x)
			var ny := cy + int(dir.y)
			var nkey := str(nx) + "," + str(ny)
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				if not visited.has(nkey):
					visited[nkey] = true
					# 打通当前房间和下一个房间之间的连接
					_connect_rooms(room_map, ckey, nkey)
					stack.append(Vector2(nx, ny))

	# 第三步：建立房间字典
	for y in height:
		for x in width:
			var key := str(x) + "," + str(y)
			var info: Variant = room_map.get(key, null)
			if info != null:
				var t := int(info["type"])
				if t == -1:
					continue
				var scene := _get_scene_for_type(t)
				rooms[key] = {
					"type": t,
					"x": x,
					"y": y,
					"scene": scene,
					"world_x": x * ROOM_SIZE,
					"world_y": y * ROOM_SIZE
				}

	return _build_output_dict()


func _get_scene_for_type(t: int) -> PackedScene:
	match t:
		0: return room_scenes.get(&"start", null)
		1: return room_scenes.get(&"combat", null)
		2: return room_scenes.get(&"supply", null)
		3: return room_scenes.get(&"combat", null)  # 精英房用战斗房场景
		4: return room_scenes.get(&"boss", null)
		5: return room_scenes.get(&"supply", null)  # 密室用补给房场景
		_: return null


func _connect_rooms(room_map: Dictionary, key1: String, key2: String) -> void:
	# 记录两个房间之间的连接（用于生成走廊/门）
	var info1: Variant = room_map.get(key1, null)
	var info2: Variant = room_map.get(key2, null)
	if info1 == null or info2 == null:
		return
	# 连接信息存储在房间中
	if not info1.has("connections"):
		info1["connections"] = []
	if not info2.has("connections"):
		info2["connections"] = []
	info1["connections"].append(key2)
	info2["connections"].append(key1)


func shuffle_array(arr: Array) -> Array:
	var result := arr.duplicate()
	for i in result.size() - 1:
		var j := rng.randi_range(0, i)
		var tmp: Variant = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result


func _build_output_dict() -> Dictionary:
	var output: Dictionary = {}
	output["seed"] = seed
	output["width"] = grid_width
	output["height"] = grid_height
	output["room_size"] = ROOM_SIZE
	var rooms_array: Array = []
	for key in rooms.keys():
		var info: Variant = rooms[key]
		rooms_array.append(info)
	output["rooms"] = rooms_array
	return output


## 获取指定网格位置的房间信息。
func get_room(x: int, y: int) -> Dictionary:
	var key := str(x) + "," + str(y)
	return rooms.get(key, null)


## 获取起点房间。
func get_start_room() -> Dictionary:
	for key in rooms.keys():
		var info: Variant = rooms[key]
		if int(info.get("type", -1)) == 0:
			return info
	return {}


## 获取 Boss 房间。
func get_boss_room() -> Dictionary:
	for key in rooms.keys():
		var info: Variant = rooms[key]
		if int(info.get("type", -1)) == 4:
			return info
	return {}
