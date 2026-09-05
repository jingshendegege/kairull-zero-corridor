extends SceneTree
## 真正 Player.step 连续走完整长关；图合同/BFS 不能替代这个物理测试。
## 主线只用 A/D，维护高路只加 W；不传送、不复活、不借用冲刺/翻滚穿墙。

const DATA := preload("res://generated/m04_chrono_freight_data.gd")
const DT := 1.0 / 60.0
const OPTIONAL := [[104, 130, 21], [201, 211, 29], [290, 321, 21], [424, 434, 24]]
var _pass := 0
var _fail := 0
var _level: CorridorLevel
var _player: KairullPlayer
var _db: AtlasDB
var _visited_entities: Dictionary = {}
var _visited_pickups: Dictionary = {}
var _touched_steps: Dictionary = {}
var _input_valid := true
var _simulated_frames := 0


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, " ", detail)


func _feet(column: int, surface: float) -> Vector2:
	return Vector2(float(column) * 32.0 + 16.0, surface * 32.0 - 0.1)


func _configure() -> void:
	CorridorLevel.active_map = DATA.MAP_TEXT
	CorridorLevel.active_rooms = []
	for source: Dictionary in DATA.ROOMS:
		var room := source.duplicate(true)
		var rect: Array = source["rect"]
		room["rect"] = Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
		room["name"] = source["display_name"]
		CorridorLevel.active_rooms.append(room)
	CorridorLevel.active_stairs = []
	for source: Dictionary in DATA.STAIRS:
		var bottom: Array = source["bottom_cell"]
		var top: Array = source["top_cell"]
		CorridorLevel.active_stairs.append({"left_c": mini(int(bottom[0]), int(top[0])),
			"bottom_row": int(bottom[1]), "steps": int(source["steps"]),
			"rise_dir": 1 if String(source["direction"]) == "right_up" else -1})
	_level = CorridorLevel.new()
	_level.build(false)
	_db = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json"])
	_player = KairullPlayer.new()
	_player.auto_input = false
	_player.level = _level
	_player.db = _db
	_player.spawn = _level.spawn
	get_root().add_child(_player)
	_player.on_ground = true
	_player.keys.clear()


func _surface(column: int) -> float:
	for stair: Dictionary in _level.stairs:
		var index := column - int(stair["left_c"])
		if index >= 0 and index < int(stair["steps"]):
			var rank := index + 1 if int(stair["rise_dir"]) > 0 else int(stair["steps"]) - index
			return float(stair["bottom_row"]) - float(rank) * 0.5
	# 主线只取最下方实心地面，不把可选单向步道误认成必走线。
	for row in range(DATA.MAP_HEIGHT - 2, 0, -1):
		if _level.tile_at(column, row) == "#":
			var top := row
			while top > 1 and _level.tile_at(column, top - 1) == "#":
				top -= 1
			if _level.tile_at(column, top - 1) == "=":
				top -= 1
			return float(top)
	return -1.0


func _track() -> void:
	for index in DATA.ENTITIES.size():
		var cell: Array = DATA.ENTITIES[index]["cell"]
		var target := _feet(int(cell[0]), float(cell[1]) + 1.0)
		if absf(_player.position.x - target.x) < 21.0 and absf(_player.position.y - target.y) < 21.0:
			_visited_entities[index] = true
	for index in DATA.TACTICAL_OBJECTS.size():
		var item: Dictionary = DATA.TACTICAL_OBJECTS[index]
		if item["type"] == "smoke_pickup":
			var pos: Array = item["pos"]
			if _player.position.distance_to(Vector2(pos[0], pos[1])) < 30.0:
				_visited_pickups[index] = true
	for index in _level.stairs.size():
		var stair: Dictionary = _level.stairs[index]
		var step := floori(_player.position.x / 32.0) - int(stair["left_c"])
		if step >= 0 and step < int(stair["steps"]):
			var rank := step + 1 if int(stair["rise_dir"]) > 0 else int(stair["steps"]) - step
			var expected := float(stair["bottom_row"]) * 32.0 - float(rank) * 16.0 - 0.1
			if _player.on_ground and absf(_player.position.y - expected) < 2.0:
				_touched_steps[index * 100 + step] = true


func _drive(route: Array[Dictionary], label: String) -> bool:
	for target_index in route.size():
		var waypoint: Dictionary = route[target_index]
		var target: Vector2 = waypoint["pos"]
		var allow_jump := bool(waypoint.get("jump", false))
		var reached := false
		var cooldown := 0
		for frame in 720:
			var delta := target - _player.position
			if absf(delta.x) <= 9.0 and absf(delta.y) <= 17.0:
				reached = true
				_track()
				break
			_player.keys.clear()
			if delta.x > 4.0:
				_player.keys[KEY_D] = true
			elif delta.x < -4.0:
				_player.keys[KEY_A] = true
			cooldown = maxi(0, cooldown - 1)
			if allow_jump and _player.on_ground and cooldown == 0 and delta.y < -20.0 and absf(delta.x) < 150.0:
				_player.keys[KEY_W] = true
				cooldown = 24
			for key: int in _player.keys:
				_input_valid = _input_valid and key in [KEY_A, KEY_D, KEY_W]
			_player.step(DT)
			_simulated_frames += 1
			_track()
		if not reached:
			print("ROUTE_BLOCK: ", label, " target ", target_index, " at ", _player.position,
				" want ", target, " ground=", _player.on_ground, " vx=", _player.vx, " vy=", _player.vy)
			return false
	return true


func _ground_route(start: int, end: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var direction := 1 if end >= start else -1
	for column in range(start, end + direction, direction):
		result.append({"pos": _feet(column, _surface(column))})
	return result


func _test_stair_skills() -> void:
	# 下列是独立局部能力测试；上述完整贯通已经结束，不把这些设置起点算作通关证据。
	for stair_index in _level.stairs.size():
		var stair: Dictionary = _level.stairs[stair_index]
		var left := int(stair["left_c"])
		var right := left + int(stair["steps"])
		for direction: int in [-1, 1]:
			for skill: int in [KEY_SHIFT, KEY_CTRL]:
				_player.reset_to_spawn()
				var start := left - 1 if direction > 0 else right + 1
				var end := right + 1 if direction > 0 else left - 1
				_player.position = _feet(start, _surface(start))
				_player.on_ground = true
				_player.face = direction
				_player.keys.clear()
				_player._prev_keys.clear()
				var intact := true
				var activated := false
				for frame in 150:
					_player.keys.clear()
					_player.keys[KEY_D if direction > 0 else KEY_A] = true
					if frame == 0:
						_player.keys[skill] = true
					_player.step(DT)
					activated = activated or _player.dashing() or _player.rolling()
					var column := floori(_player.position.x / 32.0)
					if column >= left and column < right:
						intact = intact and _player.position.y <= _surface(column) * 32.0 + 1.0
					if (_player.position.x - _feet(end, _surface(end)).x) * direction >= -10.0:
						break
				var reached := (_player.position.x - _feet(end, _surface(end)).x) * direction >= -10.0
				ok(activated and intact and reached,
					"第%d梯 方向%d %s不会穿入梯下，之后可继续步行" % [stair_index + 1, direction,
						"冲刺" if skill == KEY_SHIFT else "翻滚"], str(_player.position))


func _run() -> void:
	_configure()
	ok(_level.map_w == 460 and _level.map_h == 36, "460×36 地图由 LDtk 编译数据装载")
	ok(_level.rooms.size() == 14 and _level.stairs.size() == 5, "十四房与五段正式开放钢梯")
	ok(_player.position.distance_to(_feet(4, 32)) < 1.0, "只在 @ 起点初始化一次")
	var continuous := true
	var previous_column := 4
	for room: Dictionary in DATA.ROOMS:
		var rect: Array = room["rect"]
		var right := mini(int(rect[0]) + int(rect[2]) - 1, 454)
		if not _drive(_ground_route(previous_column, right), String(room["display_name"])):
			continuous = false
			break
		for platform: Array in OPTIONAL:
			if int(platform[0]) < int(rect[0]) or int(platform[1]) >= int(rect[0]) + int(rect[2]):
				continue
			# 不传送回支路：从当前真实位置走回起跳点，再上台、再回主线。
			var start := int(platform[0])
			var end := int(platform[1])
			var high := float(platform[2])
			var optional: Array[Dictionary] = _ground_route(right, start - 2)
			if high == 21.0:
				# 真192px上廊需两次跳跃；升降平台完全不参与此静态备用路线验收。
				var middle_end := 111 if start == 104 else 298
				var upper_start := 114 if start == 104 else 301
				optional.append({"pos": _feet(start + 2, 24.0), "jump": true})
				optional.append({"pos": _feet(middle_end, 24.0)})
				optional.append({"pos": _feet(upper_start, 21.0), "jump": true})
			else:
				optional.append({"pos": _feet(start + 1, high), "jump": true})
			optional.append({"pos": _feet(end, high)})
			optional.append({"pos": _feet(end + 2, _surface(end + 2))})
			optional.append_array(_ground_route(end + 2, right))
			var optional_ok := _drive(optional, String(room["display_name"]) + "维护回环")
			ok(optional_ok, String(room["display_name"]) + ("不等电梯，两段普通跳上192px完整上廊再回主线"
				if high == 21.0 else "可从低路返回，普通跳上96px高路再接回主线"))
			continuous = continuous and optional_ok
		previous_column = right
		ok(continuous and not _player.dead, String(room["display_name"]) + "连续到达")
		if right == 454:
			break
	ok(continuous and _player.position.distance_to(_level.exit_point) < 20.0, "真实 Player @→> 贯通；中途零传送/零复活")
	ok(_input_valid, "全程只注入 A/D/W，不依赖冲刺、翻滚或时停")
	ok(_touched_steps.size() == 50, "连续路线踩过五段楼梯全部50踏面", str(_touched_steps.size()))
	var missing: Array = []
	for index in DATA.ENTITIES.size():
		if not _visited_entities.has(index):
			missing.append(DATA.ENTITIES[index])
	ok(missing.is_empty(), "连续路线实际到达全部敌人/货箱/出生/出口位置", str(missing))
	ok(_visited_pickups.size() == 6, "六个烟雾补给点均可普通跑跳抵达")
	# 独立返程仍保持真实位置；从出口原路返回，覆盖左右向走梯，不隐式换起点。
	var reverse_ok := _drive(_ground_route(454, 4), "全图反向主线")
	ok(reverse_ok and _player.position.distance_to(_level.spawn) < 20.0, "终点到起点反向步行稳定，无需楼梯入口补跳")
	_test_stair_skills()
	_player.free()
	_level.free()
	_db = null
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_stairs = []
	await process_frame
	print("M04_TRAVERSAL_FRAMES: ", _simulated_frames)
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
