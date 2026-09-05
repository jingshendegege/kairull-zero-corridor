extends SceneTree
## 主角难度生命、死亡击退/倒地、回溯姿势与旧地图掉落兼容；只用确定性手动步进。

const DT := 1.0 / 60.0
const FLOOR_Y := 448.0
var _pass := 0
var _fail := 0
var _db: AtlasDB


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _run() -> void:
	_db = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json"])
	_test_health()
	_test_motion()
	_test_shared_solver_and_framerate()
	_test_collision_and_gravity()
	_test_timeline_pose()
	_test_forced_death_and_fall()
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
	_db = null
	await process_frame
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _make_level(wall := false, stairs := false) -> CorridorLevel:
	var rows := PackedStringArray()
	for y in 18:
		var row := "#".repeat(48) if y == 14 else ".".repeat(48)
		if wall and y >= 8 and y < 14:
			row = row.substr(0, 12) + "#" + row.substr(13)
		if stairs and y == 10:
			row = ".".repeat(28) + "#".repeat(20)
		rows.append(row)
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_stairs = []
	if stairs:
		CorridorLevel.active_stairs = [{"left_c": 20, "bottom_row": 14, "steps": 8, "rise_dir": 1}]
	var level := CorridorLevel.new()
	level.build(false)
	return level


func _make_player(level: CorridorLevel, x := 128.0, health := 5) -> KairullPlayer:
	var player := KairullPlayer.new()
	player.auto_input = false
	player.level = level
	player.db = _db
	player.max_hp = health
	player.spawn = Vector2(x, FLOOR_Y - 0.1)
	get_root().add_child(player)
	player.on_ground = true
	player.keys.clear()
	player._sync_sprite()
	return player


func _test_health() -> void:
	print("== 难度生命与信号 ==")
	var level := _make_level()
	for maximum in [1, 5]:
		var player := _make_player(level, 128, maximum)
		var signals := [0, 0]
		player.hurt.connect(func(): signals[0] += 1)
		player.died.connect(func(): signals[1] += 1)
		ok(player.hp == maximum and player.max_hp == maximum, "_ready 按 %dHP 难度补满" % maximum)
		player.take_damage(1, 0)
		ok(player.hp == maximum - 1 and player.dead == (maximum == 1),
				"%dHP 受击后的生死正确" % maximum)
		ok(signals[0] == 1 and signals[1] == int(maximum == 1), "受伤/死亡信号各只触发应有次数")
		player.reset_to_spawn()
		ok(player.hp == maximum and not player.dead and player._death_elapsed == 0.0,
				"reset 恢复 %dHP 并清空死亡计时" % maximum)
		player.free()
	var player := _make_player(level)
	var signals := [0]
	player.hurt.connect(func(): signals[0] += 1)
	player.died.connect(func(): signals[0] += 1)
	player.hp = 2
	player.configure_max_health(1, false)
	ok(player.hp == 1 and player.max_hp == 1, "降低上限且不补血时钳住现有生命")
	player.configure_max_health(5, false)
	ok(player.hp == 1 and player.max_hp == 5, "提高上限且不补血时保留伤势")
	player.configure_max_health(5)
	ok(player.hp == 5 and signals[0] == 0, "显式补满不触发任何战斗信号")
	player.configure_max_health(0)
	ok(player.max_hp == 1 and player.hp == 1, "非法零上限安全钳至1")
	player.free()
	level.free()


func _test_motion() -> void:
	print("== 世界空间惯性小抛物线与15帧倒地 ==")
	var level := _make_level()
	for direction in [-1, 1]:
		var player := _make_player(level, 600, 1)
		var start := player.position
		var landings: Array[Vector2] = []
		player.death_landed.connect(func(point: Vector2, _power: float, _direction: float):
			landings.append(point))
		player.keys = {KEY_A: true, KEY_D: true, KEY_SHIFT: true, KEY_CTRL: true, MOUSE_BUTTON_LEFT: true}
		player.take_damage(1, player.position.x - direction * 100)
		ok(player.position == start and player.dead, "死亡不在受击当帧瞬移（方向%d）" % direction)
		player.step(DT)
		var first_distance := absf(player.position.x - start.x)
		ok(first_distance > 5.0 and first_distance < 15.0, "首个物理帧平滑推进而非一次飞出3格")
		var last_delta := first_distance
		var smooth := true
		var highest_y := player.position.y
		for _i in 17:
			var old_x := player.position.x
			player.step(DT)
			var moved := absf(player.position.x - old_x)
			smooth = smooth and moved <= last_delta + 0.01
			last_delta = moved
			highest_y = minf(highest_y, player.position.y)
		ok((player.position.x - start.x) * direction > 150.0 and smooth,
				".30秒仍有前冲惯性，比旧3格滑移更远（方向%d）" % direction, str(player.position - start))
		ok(highest_y < start.y - 18.0 and highest_y > start.y - 40.0,
				"真实位置形成小抛物线，不靠单独平移精灵假装腾空", str(start.y - highest_y))
		ok(player.face == -direction and player.state == "death" and player.frame >= 5,
				"朝向锁定伤害来源，倒地图集持续推进")
		player.hitstop = 0.2
		for _i in 29:
			player.step(DT)
		var distance: float = (player.position.x - start.x) * direction
		ok(distance > 180.0 and distance < 300.0 and player.frame == 14 \
				and player.death_animation_finished(), "惯性比原3格更远；hitstop不冻结倒地，.75秒停在第15帧", str(distance))
		ok(player.on_ground and absf(player.position.y - start.y) < 0.2 \
				and not player._death_inertia_active and player._death_inertia.bounce_count == 1,
				"落地仅轻弹一次再摩擦停稳，不受移动/翻滚/冲刺输入干扰")
		ok(landings.size() == 1 and absf(landings[0].y - FLOOR_Y) < 0.2,
				"首次接地只发一次尘土信号，坐标锁定真实地面")
		var stop_position := player.position
		for _i in 18:
			player.step(DT)
		ok(player.position == stop_position and landings.size() == 1,
				"尸体停稳后无抖动，不因后续步进重复扬尘")
		player.reset_to_spawn()
		player.keys.clear()
		player.step(DT)
		ok(player.position.x == start.x and player._death_direction == 0 \
				and player._death_motion_applied == 0.0 and player.state != "death" \
				and player._death_inertia == null and not player._death_inertia_active,
				"复活不残留击退冲量、求解器或死亡状态")
		player.free()
	level.free()


func _test_shared_solver_and_framerate() -> void:
	print("== 共用求解器与帧率一致性 ==")
	var level := _make_level()
	var final_positions: Array[Vector2] = []
	for fps in [15, 30, 60, 120]:
		var player := _make_player(level, 600, 1)
		var solver := KairullPlayer.DEATH_INERTIA_SCRIPT.new()
		solver.launch(player.position, 1.0, KairullPlayer.DEATH_INERTIA_STAGE)
		player.take_damage(1, 100)
		var matched := true
		for _i in fps:
			player.step(1.0 / fps)
			solver.advance(1.0 / fps, level, player.w * 0.5, player.h)
			matched = matched and player.position.distance_to(solver.position) < 1.0
		ok(matched, "%dfps 主角位置与共享求解器一致，没有活体重力二次积分" % fps)
		final_positions.append(player.position)
		player.free()
	var consistent := true
	for point in final_positions:
		consistent = consistent and point.distance_to(final_positions[0]) < 2.0
	ok(consistent, "15/30/60/120fps 最终射程误差低于2px", str(final_positions))
	level.free()


func _test_collision_and_gravity() -> void:
	print("== 撞墙、楼梯与空中重力 ==")
	var level := _make_level(true)
	for fps in [15, 30, 60]:
		var player := _make_player(level, 350, 1)
		player.take_damage(1, 100)
		for _i in fps:
			player.step(1.0 / fps)
		ok(player.position.x + player.w * 0.5 < 384.0 \
				and player._body_clear_at(player.position.x, player.position.y),
				"%dfps 2px尸体扫掠不穿墙且净空有效" % fps, str(player.position))
		ok(player.on_ground and absf(player.position.y - FLOOR_Y) < 0.2,
				"%dfps 尸体重力不会穿过薄地板" % fps)
		player.free()
	level.free()
	level = _make_level(false, true)
	var player := _make_player(level, 620, 1)
	player.take_damage(1, 100)
	for _i in 60:
		player.step(DT)
	ok(player.position.x > 620.0 and player.position.x < 640.0 and player.on_ground \
			and player._body_clear_at(player.position.x, player.position.y),
			"低角度撞首级台阶时耗掉横向动量，不自动爬升或穿过踏面", str(player.position))
	player.reset_to_spawn()
	player.position = Vector2(730.0, 399.9) ## 第三级真实踏面，从楼梯上向低层抛飞。
	var stair_position := player.position
	player.on_ground = true
	player.take_damage(1, 900)
	for _i in 60:
		player.step(DT)
	ok(player.position.x < stair_position.x - 100.0 and absf(player.position.y - FLOOR_Y) < 0.2 \
			and player.on_ground, "向下惯性击飞自然接回底层地面", str(player.position))
	player.free()
	level.free()
	level = _make_level()
	player = _make_player(level, 200, 1)
	player.position.y = 180
	player.on_ground = false
	player.vy = 0
	player.take_damage(1, 0)
	for _i in 30:
		player.step(DT)
	ok(player.position.y > 220 and player.vy > 0 and player.position.x > 380,
			"空中死亡先受向上冲量再自然下落，横向惯性不提前断掉", str(player.position))
	ok(player._death_ground_valid and absf(player._shadow.global_position.y - (FLOOR_Y - 1.0)) < 1.1,
			"腾空时影子留在下方地面，不跟尸体一起悬浮")
	var air_pose := player.capture_timeline_pose()
	var landing_count := [0]
	player.death_landed.connect(func(_point: Vector2, _power: float, _direction: float):
		landing_count[0] += 1)
	player.apply_timeline_pose(air_pose)
	ok(air_pose.has("ground_y") and air_pose.has("ground_valid") \
			and player._shadow.global_position.y > player.position.y + 10.0 and landing_count[0] == 0,
			"回溯姿势记录世界地面高度，恢复不重发扬尘信号")
	var interpolated_pose := air_pose.duplicate(true)
	interpolated_pose["position"] = player.position + Vector2(8.25, -5.5)
	interpolated_pose["ground_y"] = 440.25
	player.apply_timeline_pose(interpolated_pose)
	ok(player._shadow.global_position == Vector2(player.position.x, 439.25).round() \
			and landing_count[0] == 0,
			"位置与地面分别插值后重新投影影子，不随nearest局部坐标漂移")
	player.free()
	level.free()


func _test_timeline_pose() -> void:
	print("== 纯呈现回溯姿势 ==")
	var level := _make_level()
	var player := _make_player(level)
	player.face = -1
	player._start_bat(1)
	for _i in 5:
		player.step(DT)
	var pose := player.capture_timeline_pose()
	var before_sprite: Dictionary = pose["visuals"]["sprite"]
	var before_slash: Dictionary = pose["visuals"]["slash"]
	var signals := [0]
	player.hurt.connect(func(): signals[0] += 1)
	player.died.connect(func(): signals[0] += 1)
	player.bat_swing_started.connect(func(_stage: int): signals[0] += 1)
	player.bat_swung.connect(func(_hitbox: Rect2, _stage: int): signals[0] += 1)
	player.reset_to_spawn()
	player.position += Vector2(300, -100)
	player.hp = 2
	player.dash_cooldown_t = 0.8
	player.face = 1
	player._sync_sprite()
	player.apply_timeline_pose(pose)
	ok(player.position == pose["position"] and player.face == -1 \
			and player.state == pose["state"] and player.frame == pose["frame"] and player.t == pose["t"],
			"恢复位置、朝向、状态、帧号与视觉时刻")
	ok(player._sprite.texture == before_sprite["texture"] \
			and player._sprite.region_rect == before_sprite["region_rect"] \
			and player._sprite.transform == before_sprite["transform"] \
			and player._sprite.flip_h == before_sprite["flip_h"], "本体图集切片、位置缩放与镜像精确恢复")
	ok(player._slash.visible == before_slash["visible"] \
			and player._slash.region_rect == before_slash["region_rect"], "回溯包含同帧弧光而非只还原人物")
	ok(player.hp == 2 and player.dash_cooldown_t == 0.8 and signals[0] == 0,
			"回放不恢复生命/CD、不重发受伤/死亡/挥棒信号")
	var interpolated := pose.duplicate()
	interpolated["position"] = pose["position"] + Vector2(14.25, -6.5)
	player.apply_timeline_pose(interpolated)
	var expected_visual: Vector2 = (interpolated["position"] + before_sprite["transform"].origin).round()
	ok(player.position == interpolated["position"] and player._sprite.global_position == expected_visual,
			"宿主可改position插值，人物视觉仍保持整数像素取整")
	ok(not player._dash_trail_root.visible and not player.dash_cooldown_ui_visible(),
			"回放隐藏现时残影和CD，避免与历史姿势串画")
	player.reset_to_spawn()
	player.keys.clear()
	player.step(DT)
	ok(player._dash_trail_root.visible and not player._slash.visible \
			and player.hp == player.max_hp, "回溯结束reset恢复普通显示与满血")
	player.free()
	level.free()


func _test_forced_death_and_fall() -> void:
	print("== 强制死亡与掉落兼容 ==")
	var level := _make_level()
	var player := _make_player(level)
	var signals := [0, 0]
	player.died.connect(func(): signals[0] += 1)
	player.fell_out.connect(func(): signals[1] += 1)
	player.invuln_t = 10
	player.debug_hotkeys_enabled = true # 此用例显式测试开发快捷键；生产默认仍关闭K自杀。
	player.keys = {KEY_K: true}
	player.step(DT)
	ok(player.dead and player.hp == 0 and signals[0] == 1, "K调试死亡忽略无敌并统一触发died")
	player.debug_hotkeys_enabled = false
	player.force_death(0)
	player.step(DT)
	ok(signals[0] == 1, "反复强制死亡不重复触发事件")
	player.reset_to_spawn()
	player.keys.clear()
	player.position.y = level.world_h + 210
	player.on_ground = false
	player.step(DT)
	ok(player.position == player.spawn and not player.dead and signals[1] == 1,
			"默认旧地图掉落仍立即复位并emit fell_out")
	player.rewind_on_fall = true
	player.position.y = level.world_h + 210
	player.on_ground = false
	player.invuln_t = 10
	player.step(DT)
	ok(player.dead and player.hp == 0 and player.position != player.spawn \
			and signals[0] == 2 and signals[1] == 1, "回溯模式跌落保留现场并只emit died")
	for _i in 10:
		player.step(DT)
	ok(signals[0] == 2 and signals[1] == 1, "越界死后持续下落不重复触发任何死亡事件")
	player.free()
	level.free()
