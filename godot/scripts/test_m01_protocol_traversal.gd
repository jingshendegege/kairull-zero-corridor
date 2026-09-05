extends SceneTree
## 正式第一关真实物理贯通测试。
##
## 直接消费 LDtk 编译数据实例化 game.tscn，只向真实 Player.step() 注入 A/D/W。
## 分别验证正式 10 级开放楼梯双向步行，以及从 @ 到 > 的完整主路线。
## 禁止 Shift/Ctrl/K/C，因此测试通过不能归功于闪现、滑铲或翻滚。

const DATA := preload("res://generated/m01_protocol_quarantine_data.gd")
const DT := 1.0 / 60.0
const TS := 32.0
const ALLOWED_KEYS := [KEY_A, KEY_D, KEY_W]

var _pass := 0
var _fail := 0
var _visited_entities: Dictionary = {}


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _runtime_rooms() -> Array:
	var result: Array = []
	for source: Dictionary in DATA.ROOMS:
		var room := source.duplicate(true)
		var raw: Array = room["rect"]
		room["rect"] = Rect2i(int(raw[0]), int(raw[1]), int(raw[2]), int(raw[3]))
		room["name"] = String(room["display_name"])
		result.append(room)
	return result


func _runtime_stairs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in DATA.STAIRS:
		var bottom: Array = source["bottom_cell"]
		var top: Array = source["top_cell"]
		result.append({
			"left_c": mini(int(bottom[0]), int(top[0])),
			"bottom_row": int(bottom[1]),
			"steps": int(source["steps"]),
			"rise_dir": 1 if String(source["direction"]) == "right_up" else -1,
		})
	return result


func _reset_statics() -> void:
	# 新关卡专用字段也必须逐项清空，避免同进程后续测试继承检疫站状态。
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_stairs = []
	CorridorLevel.active_art_style = ""
	CorridorLevel.active_semantic_layers = {}
	CorridorLevel.active_semantic_ids = {}
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_title = ""
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_campaign_mode = false
	CorridorLevel.active_restart_scene = ""
	GameBackground.active_cfg = []


func _configure_map() -> void:
	CorridorLevel.active_map = DATA.MAP_TEXT
	CorridorLevel.active_rooms = _runtime_rooms()
	CorridorLevel.active_stairs = _runtime_stairs()
	CorridorLevel.active_art_style = "quarantine"
	CorridorLevel.active_semantic_layers = DATA.SEMANTIC_LAYERS.duplicate(true)
	CorridorLevel.active_semantic_ids = DATA.SEMANTIC_IDS.duplicate(true)
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "none"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_title = "M01 协议检疫站 · 物理测试"
	CorridorLevel.active_tile_style = {"name": "quarantine"}
	CorridorLevel.active_tileset_path = "res://assets/maps/quarantine/tileset_quarantine.png"
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = GameBackground.CFG_QUARANTINE


func _feet(cell_x: int, surface_row: float) -> Vector2:
	return Vector2(cell_x * TS + TS * 0.5, surface_row * TS - 0.1)


func _set_player_at(player: KairullPlayer, position: Vector2) -> void:
	player.position = position
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = true
	player.dead = false
	player.keys.clear()
	player._prev_keys.clear()
	player.set_state("gun_idle")


func _step_with_keys(player: KairullPlayer, keys: Array) -> bool:
	player.keys.clear()
	var allowed := true
	for key: int in keys:
		if key not in ALLOWED_KEYS:
			allowed = false
			continue
		player.keys[key] = true
	player.step(DT)
	return allowed


## 路点字典：pos=脚底目标；jump=true 允许在接近目标时按 W。
## 返回第一处卡点，便于直接换算到 LDtk 格坐标诊断。
func _drive_route(player: KairullPlayer, route: Array[Dictionary], phase: String,
		track_stair_steps := false) -> Dictionary:
	var all_allowed := true
	var touched_steps: Dictionary = {}
	for waypoint_index in route.size():
		var waypoint: Dictionary = route[waypoint_index]
		var target: Vector2 = waypoint["pos"]
		var allow_jump := bool(waypoint.get("jump", false))
		var reached := false
		var last_x := player.position.x
		var stall_frames := 0
		var jump_cooldown := 0
		for frame in range(720):
			var dx := target.x - player.position.x
			var dy := target.y - player.position.y
			if absf(dx) <= 10.0 and absf(dy) <= 19.0:
				reached = true
				break
			var keys: Array = []
			if dx > 5.0:
				keys.append(KEY_D)
			elif dx < -5.0:
				keys.append(KEY_A)
			jump_cooldown = maxi(0, jump_cooldown - 1)
			if absf(player.position.x - last_x) < 1.0 and absf(dx) > 5.0 and player.on_ground:
				stall_frames += 1
			else:
				stall_frames = 0
			last_x = player.position.x
			# 只对明确标记的上升路点起跳；楼梯逐级路点故意不用 W，验证走梯吸附。
			if allow_jump and player.on_ground and jump_cooldown == 0 \
					and dy < -20.0 and absf(dx) <= 150.0:
				keys.append(KEY_W)
				jump_cooldown = 24
			elif allow_jump and player.on_ground and jump_cooldown == 0 and stall_frames >= 18:
				keys.append(KEY_W)
				jump_cooldown = 24
				stall_frames = 0
			all_allowed = _step_with_keys(player, keys) and all_allowed
			await physics_frame
			for entity_index in DATA.ENTITIES.size():
				var entity: Dictionary = DATA.ENTITIES[entity_index]
				var cell: Array = entity["cell"]
				var entity_feet := _feet(int(cell[0]), float(cell[1]) + 1.0)
				if absf(player.position.x - entity_feet.x) <= 20.0 \
						and absf(player.position.y - entity_feet.y) <= 20.0:
					_visited_entities[entity_index] = true
			if track_stair_steps:
				for stair_id in player.level.stairs.size():
					var stair: Dictionary = player.level.stairs[stair_id]
					var stair_index := floori(player.position.x / TS) - int(stair["left_c"])
					if stair_index >= 0 and stair_index < int(stair["steps"]):
						var rank := stair_index + 1 if int(stair["rise_dir"]) > 0 \
								else int(stair["steps"]) - stair_index
						var expected_y := float(stair["bottom_row"]) * TS - float(rank) * 16.0 - 0.1
						if absf(player.position.y - expected_y) <= 2.0:
							touched_steps[stair_id * 100 + stair_index] = true
		if not reached:
			var cell := Vector2i(floori(player.position.x / TS), floori(player.position.y / TS))
			return {
				"ok": false,
				"detail": "%s 路点%d卡在 c%d r%d，脚底=(%.1f, %.1f)，目标=(%.1f, %.1f)" % [
					phase, waypoint_index, cell.x, cell.y, player.position.x,
					player.position.y, target.x, target.y],
				"allowed": all_allowed,
				"steps": touched_steps,
			}
	return {"ok": true, "detail": "", "allowed": all_allowed, "steps": touched_steps}


func _run() -> void:
	_reset_statics()
	_configure_map()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(game)
	await process_frame
	await process_frame
	var level: CorridorLevel = game.level
	var player: KairullPlayer = game.player
	player.auto_input = false
	for i in range(3):
		await physics_frame

	print("== 协议检疫站结构合同 ==")
	ok(level.spawn.distance_to(_feet(4, 28.0)) < 1.0, "@ 出生点来自生成数据")
	ok(level.exit_point.distance_to(_feet(274, 23.0)) < 1.0, "> 扩展出口来自生成数据")
	ok(game.minions.is_empty(), "active_minion=none，不生成测试干扰敌人")
	ok(level.rooms.size() == 10, "十个显式 room_id 房间已配置")
	ok(level.stairs.size() == 3 and int(level.stairs[0]["steps"]) == 10,
		"三段正式十级楼梯已配置")
	var stair_samples_ok := true
	for step_index in range(10):
		var x := (52.0 + float(step_index) + 0.5) * TS
		var expected_y := 28.0 * TS - float(step_index + 1) * 16.0
		var actual_y := level.stair_surface_near(x, expected_y, 1.0, 1.0)
		stair_samples_ok = stair_samples_ok and absf(actual_y - expected_y) < 0.1
	ok(stair_samples_ok, "正式楼梯 10 个 32×16px 外露踏面均可查询")
	var old_platforms_absent := true
	for row in range(23, 28):
		for column in range(52, 62):
			old_platforms_absent = old_platforms_absent \
					and level.tile_at(column, row) != "="
	ok(old_platforms_absent, "维护竖井已移除旧 2+2+1 单向兜底平台")
	ok(level.is_platform(62.0 * TS + 1.0, 23.0 * TS + 1.0),
		"c62/row23 保留一格同高上端接口，且不覆盖十级踏面")

	print("== 阶段一：正式 10 级开放楼梯双向步行 ==")
	_set_player_at(player, _feet(50, 28.0))
	var stair_up_route: Array[Dictionary] = [{"pos": _feet(51, 28.0)}]
	for step_index in range(10):
		stair_up_route.append({"pos": _feet(52 + step_index,
				28.0 - float(step_index + 1) * 0.5)})
	stair_up_route.append({"pos": _feet(64, 23.0)})
	var stair_up_result: Dictionary = await _drive_route(
			player, stair_up_route, "正式楼梯上行", true)
	ok(bool(stair_up_result["allowed"]), "楼梯上行只注入 A/D")
	ok(bool(stair_up_result["ok"]), "正式楼梯从 row28 步行接到 row23",
		String(stair_up_result["detail"]))
	ok((stair_up_result["steps"] as Dictionary).size() == 10,
		"上行实际踩到全部 10 个外露踏面",
		"实际踏面=%s" % str((stair_up_result["steps"] as Dictionary).keys()))

	var stair_down_route: Array[Dictionary] = []
	for step_index in range(9, -1, -1):
		stair_down_route.append({"pos": _feet(52 + step_index,
				28.0 - float(step_index + 1) * 0.5)})
	stair_down_route.append({"pos": _feet(50, 28.0)})
	var stair_down_result: Dictionary = await _drive_route(
			player, stair_down_route, "正式楼梯下行", true)
	ok(bool(stair_down_result["allowed"]), "楼梯下行只注入 A/D")
	ok(bool(stair_down_result["ok"]), "正式楼梯从 row23 稳定走回 row28",
		String(stair_down_result["detail"]))
	ok((stair_down_result["steps"] as Dictionary).size() == 10,
		"下行实际踩到全部 10 个外露踏面",
		"实际踏面=%s" % str((stair_down_result["steps"] as Dictionary).keys()))
	# 新增两段分别包含向左升/向右升；每段单独覆盖双向连续步行，而不是只做位置查询。
	for stair_id in range(1, level.stairs.size()):
		var stair: Dictionary = level.stairs[stair_id]
		var left := int(stair["left_c"])
		var steps := int(stair["steps"])
		var bottom := float(stair["bottom_row"])
		var right_up := int(stair["rise_dir"]) > 0
		var left_floor := bottom if right_up else bottom - steps * 0.5
		var right_floor := bottom - steps * 0.5 if right_up else bottom
		_set_player_at(player, _feet(left - 1, left_floor))
		var forward: Array[Dictionary] = []
		for step_index in range(steps):
			var rank := step_index + 1 if right_up else steps - step_index
			forward.append({"pos": _feet(left + step_index, bottom - rank * 0.5)})
		forward.append({"pos": _feet(left + steps + 1, right_floor)})
		var forward_result: Dictionary = await _drive_route(player, forward, "新增钢梯前行", true)
		ok(bool(forward_result["ok"]) and (forward_result["steps"] as Dictionary).size() == steps,
			"新增钢梯%d 向右走遍全部踏面" % stair_id, String(forward_result["detail"]))
		var backward: Array[Dictionary] = []
		for step_index in range(steps - 1, -1, -1):
			var rank := step_index + 1 if right_up else steps - step_index
			backward.append({"pos": _feet(left + step_index, bottom - rank * 0.5)})
		backward.append({"pos": _feet(left - 1, left_floor)})
		var backward_result: Dictionary = await _drive_route(player, backward, "新增钢梯返程", true)
		ok(bool(backward_result["ok"]) and (backward_result["steps"] as Dictionary).size() == steps,
			"新增钢梯%d 向左返回全部踏面" % stair_id, String(backward_result["detail"]))

	print("== 阶段二：可选维护步道与下方货运线 ==")
	_set_player_at(player, _feet(39, 28.0))
	var optional_route: Array[Dictionary] = [
		{"pos": _feet(43, 25.0), "jump": true},
		{"pos": _feet(46, 25.0)},
		{"pos": _feet(49, 28.0)},
	]
	var optional_result: Dictionary = await _drive_route(player, optional_route, "可选维护步道")
	ok(bool(optional_result["allowed"]), "可选高路只注入 A/D/W，不依赖位移技能")
	ok(bool(optional_result["ok"]), "普通跳跃登上96px步道，再回到货运地面",
		String(optional_result["detail"]))
	_set_player_at(player, _feet(39, 28.0))
	var ground_result: Dictionary = await _drive_route(player,
		[{"pos": _feet(49, 28.0)}], "维护步道下方")
	ok(bool(ground_result["ok"]), "不跳跃也能从步道下方直接通行",
		String(ground_result["detail"]))

	print("== 阶段三：@ → 双层分流 → 两处检查点 → 冷却池/重载仓 → 核心 → > ==")
	player.reset_to_spawn()
	_visited_entities.clear()
	var full_route: Array[Dictionary] = [
		{"pos": _feet(24, 28.0)},
		{"pos": _feet(29, 28.0)},
		{"pos": _feet(35, 28.0)},
		{"pos": _feet(42, 28.0)},
		{"pos": _feet(48, 28.0)},
	]
	# 第一级只高 16px；十级全部只按 D 逐级走上去。
	for step_index in range(10):
		full_route.append({"pos": _feet(52 + step_index,
				28.0 - float(step_index + 1) * 0.5)})
	full_route.append_array([
		{"pos": _feet(64, 23.0)},
		{"pos": _feet(92, 23.0)},
		{"pos": _feet(73, 23.0)},
		{"pos": _feet(77, 20.0), "jump": true},
		{"pos": _feet(90, 20.0)},
		{"pos": _feet(93, 23.0)},
		{"pos": _feet(96, 22.0), "jump": true},
		{"pos": _feet(101, 23.0)},
		{"pos": _feet(111, 23.0)},
		{"pos": _feet(123, 23.0)},
	])
	for step_index in range(10):
		full_route.append({"pos": _feet(124 + step_index, 23.0 + step_index * 0.5)})
	full_route.append_array([
		{"pos": _feet(135, 28.0)}, {"pos": _feet(174, 28.0)},
		{"pos": _feet(163, 28.0)}, {"pos": _feet(167, 25.0), "jump": true},
		{"pos": _feet(171, 25.0)}, {"pos": _feet(173, 28.0)},
		{"pos": _feet(178, 26.0), "jump": true}, {"pos": _feet(176, 26.0)},
		{"pos": _feet(182, 26.0)}, {"pos": _feet(184, 28.0)},
		{"pos": _feet(203, 28.0)},
	])
	for step_index in range(10):
		full_route.append({"pos": _feet(204 + step_index, 28.0 - (step_index + 1) * 0.5)})
	full_route.append_array([
		{"pos": _feet(215, 23.0)}, {"pos": _feet(232, 23.0)},
		{"pos": _feet(237, 21.0), "jump": true}, {"pos": _feet(234, 21.0)},
		{"pos": _feet(239, 21.0)}, {"pos": _feet(242, 23.0)},
		{"pos": _feet(254, 23.0)}, {"pos": _feet(243, 23.0)},
		{"pos": _feet(247, 20.0), "jump": true}, {"pos": _feet(252, 20.0)},
		{"pos": _feet(257, 23.0)}, {"pos": _feet(274, 23.0)},
	])
	var full_result: Dictionary = await _drive_route(player, full_route,
			"正式主路线", true)
	ok(bool(full_result["allowed"]), "全程只注入 A/D/W，未使用 Shift/Ctrl/K/C")
	ok(bool(full_result["ok"]), "真实 Player 从 @ 贯通到 >",
		String(full_result["detail"]))
	var touched: Dictionary = full_result["steps"]
	var exposed_steps_ok := touched.size() == 30
	for stair_id in range(3):
		for step_index in range(10):
			exposed_steps_ok = exposed_steps_ok and touched.has(stair_id * 100 + step_index)
	ok(exposed_steps_ok, "整段连续路线踩过三段钢梯全部30个踏面",
		"实际踏面索引=%s" % str(touched.keys()))
	var missing_entities: Array = []
	for entity_index in DATA.ENTITIES.size():
		if not _visited_entities.has(entity_index):
			missing_entities.append(DATA.ENTITIES[entity_index])
	ok(missing_entities.is_empty(), "不重置、不传送的连续路线实际到达全部敌人/货箱/出入口",
		str(missing_entities))

	if bool(full_result["ok"]):
		for i in range(8):
			_step_with_keys(player, [])
			await physics_frame
		ok(game.level_cleared, "触碰 > 后触发 level_cleared")
	else:
		ok(false, "触碰 > 后触发 level_cleared", "主路线在出口前中断")

	game.free()
	_reset_statics()
	ok(CorridorLevel.active_stairs.is_empty()
			and CorridorLevel.active_art_style.is_empty()
			and CorridorLevel.active_semantic_layers.is_empty()
			and CorridorLevel.active_semantic_ids.is_empty(),
		"退出后清空楼梯、美术与语义静态配置")

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
