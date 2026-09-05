extends SceneTree
## M03「零号货运站」无头验收：LDtk 同步后的地图结构、房间归属、门闸与纯近战开关。
## 跑法：godot --headless --path godot --script scripts/test_m03_zero_freight.gd

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _reset_statics() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = []


## 站立格：自身非实心，脚下一格为实体或单向台。
func _is_stand(level: CorridorLevel, c: int, r: int) -> bool:
	return not level.is_solid_char(level.tile_at(c, r)) \
		and level.is_solid_char(level.tile_at(c, r + 1))


func _run() -> void:
	print("== M03 地图结构 ==")
	_reset_statics()
	CorridorLevel.active_map = CorridorLevel.MAP_M03_ZERO_FREIGHT
	CorridorLevel.active_rooms = CorridorLevel.MAP_M03_ZERO_FREIGHT_ROOMS
	var level := CorridorLevel.new()
	level.build(false)
	ok(level.map_w == 128 and level.map_h == 28, "地图为 128x28", "%dx%d" % [level.map_w, level.map_h])
	ok(level.rooms.size() == 7, "7 个房间", str(level.rooms.size()))
	ok(level.spawn == Vector2(4 * 32 + 16, 25 * 32 - 0.1), "出生点 @ c4 r24", str(level.spawn))
	ok(level.exit_point == Vector2(11 * 32 + 16, 25 * 32 - 0.1), "出口 > c11 r24", str(level.exit_point))
	ok(level.enemy_spawns.size() == 12, "12 个清场目标", str(level.enemy_spawns.size()))
	ok(level.enemy_spawn_kinds.size() == 12, "敌人类型与刷点逐一对应")
	ok(level.enemy_spawn_kinds.count("melee") == 6
		and level.enemy_spawn_kinds.count("") == 6,
		"地图含 6 近战兵 + 6 通用枪手", str(level.enemy_spawn_kinds))
	ok(level.door_spawns.size() == 5, "5 道房门", str(level.door_spawns.size()))
	ok(level.prop_spawns.size() == 6, "6 个道具（2 桶 + 4 CRT）", str(level.prop_spawns.size()))

	var overlap := false
	for i in level.rooms.size():
		for j in range(i + 1, level.rooms.size()):
			if (level.rooms[i]["rect"] as Rect2i).intersects(level.rooms[j]["rect"]):
				overlap = true
	ok(not overlap, "房间两两不重叠")
	var covered := true
	for r in level.map_h:
		for c in level.map_w:
			if level.is_solid_char(level.tile_at(c, r)):
				continue
			if level.room_at(c * 32 + 16, r * 32 + 16) < 0:
				covered = false
				print("    未覆盖活动格：c%d r%d" % [c, r])
	ok(covered, "房间覆盖全部活动格")

	print("== 跳跃预算 BFS ==")
	var start := Vector2i(4, 24)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for c2 in range(maxi(0, p.x - 8), mini(level.map_w, p.x + 9)):
			for r2 in range(maxi(0, p.y - 3), mini(level.map_h - 1, p.y + 20)):
				var q := Vector2i(c2, r2)
				if seen.has(q) or not _is_stand(level, c2, r2):
					continue
				var rise := p.y - r2
				var dc := absi(c2 - p.x)
				if rise >= 0:
					var budget: int = {0: 8, 1: 6, 2: 5, 3: 3}.get(rise, -1)
					if dc > budget:
						continue
				elif dc > 8:
					continue
				seen[q] = true
				queue.append(q)
	ok(seen.has(Vector2i(11, 24)), "出口格可达")
	var all_enemy_reachable := true
	for sp in level.enemy_spawns:
		var cell := Vector2i(floori(sp.x / 32.0), floori(sp.y / 32.0))
		if not seen.has(cell):
			all_enemy_reachable = false
			print("    不可达刷点：", cell)
	ok(all_enemy_reachable, "全部 12 个刷点可达")

	print("== 场景运行与门闸 ==")
	var boot: Node2D = load("res://scenes/m03_zero_freight.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	ok(CorridorLevel.active_title == "M03 零号货运站", "M03 boot 配置生效")
	ok(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED,
		"枪械与滑铲保持禁用")
	var grunt_count := 0
	var melee_count := 0
	var melee_script: Script = load("res://scripts/freight_inspector.gd")
	for minion in game.minions:
		if minion is GruntGunner:
			grunt_count += 1
		elif minion.get_script() == melee_script:
			melee_count += 1
	ok(game.minions.size() == 12 and grunt_count == 6 and melee_count == 6
		and game.red_boss == null, "运行时 6 枪手 + 6 近战兵、无 Boss",
		"total=%d grunt=%d melee=%d" % [game.minions.size(), grunt_count, melee_count])
	ok(game.doors.size() == 5, "运行时生成 5 道 RoomDoor", str(game.doors.size()))
	var expected_totals := [0, 0, 4, 3, 0, 3, 2]
	for i in expected_totals.size():
		ok(game.room_total_count(i) == expected_totals[i],
			"房间 %d 敌人数 = %d" % [i, expected_totals[i]], str(game.room_total_count(i)))
	for i in range(3):
		await physics_frame
	var door_by_cell := {}
	for door in game.doors:
		door_by_cell[Vector2i(floori((door.position.x - 16.0) / 32.0),
			floori((door.position.y + 0.2) / 32.0) - 1)] = door
	ok(door_by_cell.has(Vector2i(31, 24)) and not door_by_cell[Vector2i(31, 24)].locked,
		"西回落井下门常开")
	ok(door_by_cell.has(Vector2i(79, 24)) and door_by_cell[Vector2i(79, 24)].locked,
		"候车厅未清时东门锁定")
	ok(door_by_cell.has(Vector2i(32, 15)) and door_by_cell[Vector2i(32, 15)].locked,
		"信号室未清时西门锁定")
	ok(game._exit_gated() and game.exit_door.locked, "出生点旁出口先锁定")

	for minion in game.minions:
		if is_instance_valid(minion) and not minion.dead:
			minion.take_hit(minion.position.x, 1)
	for i in range(4):
		await physics_frame
	var all_unlocked := true
	for door in game.doors:
		all_unlocked = all_unlocked and not door.locked
	ok(all_unlocked, "全清后 5 门全部解锁")
	ok(not game._exit_gated() and not game.exit_door.locked, "全清后最终出口解锁")
	game.player.auto_input = false
	game.player.position = game.level.exit_point
	for i in range(4):
		await physics_frame
	ok(game.level_cleared, "返回出生区出口后过关")

	boot.free()
	ok(CorridorLevel.active_map.is_empty() and CorridorLevel.active_rooms.is_empty(),
		"M03 退出后静态配置还原")
	_reset_statics()
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
