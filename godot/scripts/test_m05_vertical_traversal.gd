extends SceneTree
## 第三关真实Player静态贯通：中枢→井底→回中枢→塔顶，访问全部敌箱/烟雾位置。
## 只有A/D/W/双S下穿，没有传送/复活/冲刺/翻滚/时停；不让不存在的静态电梯盖住开口。

const DATA := preload("res://generated/m05_vertical_freight_data.gd")
const DT := 1.0 / 60.0
var passed := 0
var failed := 0
var level: CorridorLevel
var player: KairullPlayer
var db: AtlasDB
var visited: Dictionary = {}
var smoke_visited: Dictionary = {}
var treads: Dictionary = {}
var frames := 0
var min_y := INF
var max_y := -INF


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func feet(c: int, floor: float) -> Vector2:
	return Vector2(c * 32.0 + 16.0, floor * 32.0 - 0.1)


func track() -> void:
	min_y = minf(min_y, player.position.y)
	max_y = maxf(max_y, player.position.y)
	for index in DATA.ENTITIES.size():
		var cell: Array = DATA.ENTITIES[index]["cell"]
		var pos := feet(int(cell[0]), float(cell[1]) + 1.0)
		if absf(player.position.x - pos.x) < 21.0 and absf(player.position.y - pos.y) < 21.0:
			visited[index] = true
	for index in DATA.TACTICAL_OBJECTS.size():
		var item: Dictionary = DATA.TACTICAL_OBJECTS[index]
		if item["type"] == "smoke_pickup":
			var pos: Array = item["pos"]
			if player.position.distance_to(Vector2(pos[0], pos[1])) < 30.0:
				smoke_visited[index] = true
	for index in level.stairs.size():
		var stair: Dictionary = level.stairs[index]
		var step := floori(player.position.x / 32.0) - int(stair["left_c"])
		if step >= 0 and step < int(stair["steps"]):
			var rank := step + 1 if int(stair["rise_dir"]) > 0 else int(stair["steps"]) - step
			var y := float(stair["bottom_row"]) * 32.0 - rank * 16.0 - 0.1
			if player.on_ground and absf(player.position.y - y) < 1.5:
				treads[index * 100 + step] = true


func go(c: int, floor: float, jump := false) -> bool:
	var target := feet(c, floor)
	var pressed_jump := false
	for _i in 1200:
		var delta := target - player.position
		if absf(delta.x) < 8.0 and absf(delta.y) < 15.0:
			track()
			return true
		player.keys.clear()
		if delta.x > 4.0:
			player.keys[KEY_D] = true
		elif delta.x < -4.0:
			player.keys[KEY_A] = true
		if jump and not pressed_jump and player.on_ground and absf(delta.x) < 180.0:
			player.keys[KEY_W] = true
			pressed_jump = true
		player.step(DT)
		frames += 1
		track()
	print("M05_ROUTE_BLOCK: at=", player.position, " target=", target,
		" ground=", player.on_ground, " jump=", jump, " state=", player.state)
	return false


func room_stair(floor: int, up: bool) -> bool:
	if up:
		if not go(49, floor + 6):
			return false
		for i in 12:
			if not go(50 + i, float(floor + 6) - float(i + 1) * 0.5):
				return false
		return go(66, floor)
	if not go(62, floor):
		return false
	for i in range(11, -1, -1):
		if not go(50 + i, float(floor + 6) - float(i + 1) * 0.5):
			return false
	return go(49, floor + 6)


func shaft_cross(floor: int, right: bool) -> bool:
	var openings: Array[int] = []
	for item: Dictionary in DATA.TACTICAL_OBJECTS:
		if item["type"] != "freight_lift":
			continue
		if int(item["pos"][1]) == floor * 32 or int(item["top_y"]) == floor * 32:
			openings.append(int(float(item["pos"][0]) / 32.0))
	openings.sort()
	if not right:
		openings.reverse()
	for center in openings:
		if not go(center - 2 if right else center + 3, floor):
			return false
		if not go(center + 3 if right else center - 2, floor, true):
			return false
	return go(106 if right else 74, floor)


func visit_floor(floor: int) -> bool:
	if not room_stair(floor, false):
		return false
	if floor == 15:
		# 两格实心踏台是侧向64px中继；不从地面硬跳128px，也不假装低路能钻过实心块。
		if not go(14, 21) or not go(12, 19, true) or not go(9, 21) or not go(3, 21):
			return false
		if not go(9, 21) or not go(11, 19, true) or not go(14, 17, true) or not go(26, 17) or not go(28, 21):
			return false
	elif not go(3, floor + 6):
		return false
	if not go(42, floor + 6) or not room_stair(floor, true) or not go(74, floor):
		return false
	if not shaft_cross(floor, true):
		return false
	if floor == 15:
		if not go(109, 15) or not go(111, 13, true) or not go(114, 11, true) or not go(132, 11) or not go(134, 15) or not go(142, 15):
			return false
		# 真正返回低路经过剩余枪手/货箱，再翻越侧踏台离开，不漏掉上廊下方的刷点。
		if not go(114, 15) or not go(112, 13, true) or not go(110, 15):
			return false
	elif not go(142, floor):
		return false
	return shaft_cross(floor, false)


func descend(floor: int) -> bool:
	# 维修井右缘是可见的下降口；双S用既有单向台下穿规则，不直接设置位置或vy。
	if not go(66, floor):
		return false
	for keys: Array in [[KEY_S], [], [KEY_S]]:
		player.keys.clear()
		for key: int in keys:
			player.keys[key] = true
		player.step(DT)
		frames += 1
		track()
	for _i in 180:
		player.keys.clear()
		player.step(DT)
		frames += 1
		track()
		if player.on_ground and absf(player.position.y - feet(66, floor + 18).y) < 1.5:
			return go(74, floor + 18)
	print("M05_DROP_BLOCK: ", player.position, " target_floor=", floor + 18)
	return false


func ascend(floor: int) -> bool:
	# 四次96px跳跃＋192px钢梯，跨完整576px层高，明确比乘货梯更长。
	return go(66, floor) and go(64, floor - 3, true) and go(61, floor - 6, true) \
		and go(58, floor - 9, true) and go(52, floor - 9) and go(49, floor - 12, true) \
		and room_stair(floor - 18, true) and go(74, floor - 18)


func configure() -> void:
	CorridorLevel.active_map = DATA.MAP_TEXT
	CorridorLevel.active_rooms = []
	CorridorLevel.active_stairs = []
	for source: Dictionary in DATA.ROOMS:
		var room := source.duplicate(true)
		var rect: Array = room["rect"]
		room["rect"] = Rect2i(rect[0], rect[1], rect[2], rect[3])
		room["name"] = room["display_name"]
		CorridorLevel.active_rooms.append(room)
	for source: Dictionary in DATA.STAIRS:
		var bottom: Array = source["bottom_cell"]
		var top: Array = source["top_cell"]
		CorridorLevel.active_stairs.append({"left_c": mini(bottom[0], top[0]), "bottom_row": bottom[1],
			"steps": source["steps"], "rise_dir": 1 if source["direction"] == "right_up" else -1})
	level = CorridorLevel.new()
	level.build(false)
	db = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json", "res://assets/clips/hero/hero_atlas.json"])
	player = KairullPlayer.new()
	player.auto_input = false
	player.level = level
	player.db = db
	player.spawn = level.spawn
	root.add_child(player)
	player.on_ground = true
	player.keys.clear()


func _run() -> void:
	configure()
	check(level.map_w == 144 and level.map_h == 114, "第三关是144×114真纵向空间")
	check(level.rooms.size() == 20 and level.stairs.size() == 6, "20不重叠房框与六段12级房间接梯")
	check(player.position.distance_to(feet(74, 105)) < 1.0, "出生在最底层安全桥，从井底逐层上攀")
	var route_ok := visit_floor(105)
	check(route_ok, "井底左右两塔实走后返回缓冲桥")
	var touched_bottom := max_y > 110.0 * 32.0
	check(touched_bottom, "真正抵达井底row111，未传送或假定下行完成")
	for floor: int in [105, 87, 69]:
		if route_ok:
			route_ok = ascend(floor) and visit_floor(floor - 18)
		check(route_ok, "不用货梯，沿维修栈道实际上行row%d→%d" % [floor, floor - 18])
	for floor: int in [51, 33]:
		if route_ok:
			route_ok = ascend(floor) and visit_floor(floor - 18)
		check(route_ok, "实际上探row%d并清查双塔/上层支路" % (floor - 18))
	check(route_ok and player.position.distance_to(level.exit_point) < 20.0,
		"连续@井底→配重→检修→中枢→上联→塔冠>，过程零传送/零复活")
	var missing: Array = []
	for index in DATA.ENTITIES.size():
		if not visited.has(index):
			missing.append(DATA.ENTITIES[index])
	check(missing.is_empty(), "所有52敌+26箱+出入口格均由同一真实角色连续抵达", str(missing))
	check(smoke_visited.size() == 8, "八个烟雾补给点均实际经过", str(smoke_visited.size()))
	check(treads.size() == 72, "六段楼梯全部72踏面实际踩到", str(treads.size()))
	check(min_y < 12.0 * 32.0 + 1.0 and max_y > 110.0 * 32.0, "真实脚底轨迹覆盖上/下超过98格纵深")
	print("M05_TRAVERSAL_PROFILE: frames=", frames, " min_y=", min_y, " max_y=", max_y)
	player.free()
	level.free()
	db = null
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_stairs = []
	await process_frame
	print("M05_TRAVERSAL_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
