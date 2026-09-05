extends SceneTree
## 协议检疫站正式楼梯专项测试：高度场、镜像双向通行、停驻、单向跳穿与贴阶爆发。
## 跑法：godot --headless --path godot --script scripts/test_protocol_stair_physics.gd

const DT := 1.0 / 60.0
const W := 32
const H := 18
const LEFT_C := 6
const STEPS := 8
const BOTTOM_ROW := 14
const BOTTOM_Y := float(BOTTOM_ROW * CorridorLevel.TS)
const TOP_Y := BOTTOM_Y - STEPS * 16.0

var _pass := 0
var _fail := 0
var _db: AtlasDB


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func approx(a: float, b: float, tolerance := 0.55) -> bool:
	return absf(a - b) <= tolerance


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_db = AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json",
	])
	_test_heightfield_semantics()
	_test_walk_both_directions(1)
	_test_walk_both_directions(-1)
	_test_standing_and_one_way_jump()
	_test_burst_both_directions(1, true)
	_test_burst_both_directions(1, false)
	_test_burst_both_directions(-1, true)
	_test_burst_both_directions(-1, false)
	_test_clearance_and_burst_guards()
	_test_empty_stairs_regression()
	_reset_statics()
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	_db = null
	await process_frame
	quit(0 if _fail == 0 else 1)


func _test_heightfield_semantics() -> void:
	print("== 高度场语义 ==")
	var level := _make_level(1)
	ok(level.stairs.size() == 1, "合法偶数级楼梯进入运行时高度场")
	for index in range(STEPS):
		var x := (LEFT_C + index) * CorridorLevel.TS + 16.0
		var expected := BOTTOM_Y - (index + 1) * 16.0
		var got := level.stair_surface_near(x, expected, 0.0, 0.0)
		ok(approx(got, expected, 0.01), "向右升第 %d 级为 bottom-%dpx" % [index + 1,
				(index + 1) * 16], "got=%.2f expected=%.2f" % [got, expected])
	ok(not level.solid_at((LEFT_C + 3.5) * 32.0, BOTTOM_Y - 50.0),
			"开放式楼梯下方不写入实心网格")

	CorridorLevel.active_stairs = [{
		"left_c": LEFT_C, "bottom_row": BOTTOM_ROW, "steps": 7, "rise_dir": 1,
	}]
	var invalid := CorridorLevel.new()
	invalid.build(false)
	ok(invalid.stairs.is_empty(), "奇数级楼梯被校验拒绝，避免半格平台")
	invalid.free()
	level.free()


func _test_walk_both_directions(rise_dir: int) -> void:
	var label := "向右升" if rise_dir > 0 else "向左升"
	print("== 镜像双向步行：%s ==" % label)
	var level := _make_level(rise_dir)
	var bottom_x := LEFT_C * 32.0 - 20.0 if rise_dir > 0 \
			else (LEFT_C + STEPS) * 32.0 + 20.0
	var up_key := KEY_D if rise_dir > 0 else KEY_A
	var down_key := KEY_A if rise_dir > 0 else KEY_D
	var player := _make_player(level, Vector2(bottom_x, BOTTOM_Y - 0.1))
	var up := _drive(player, up_key, 64)
	ok(approx(player.position.y, TOP_Y - 0.1), "%s：无需跳跃走到上平台" % label,
			"pos=%s" % player.position)
	ok(bool(up["all_grounded"]), "%s：上楼全程保持地面状态" % label)

	var top_x := (LEFT_C + STEPS) * 32.0 + 20.0 if rise_dir > 0 \
			else LEFT_C * 32.0 - 20.0
	player.position = Vector2(top_x, TOP_Y - 0.1)
	player.vy = 0.0
	player.on_ground = true
	player.set_state("gun_idle")
	player.keys.clear()
	player._prev_keys.clear()
	var down := _drive(player, down_key, 64)
	ok(approx(player.position.y, BOTTOM_Y - 0.1), "%s：反向稳定走回下平台" % label,
			"pos=%s" % player.position)
	ok(bool(down["all_grounded"]), "%s：下楼与最低级接缝无悬空帧" % label)
	player.free()
	level.free()


func _test_standing_and_one_way_jump() -> void:
	print("== 停驻、下方跳穿与上方落梯 ==")
	var level := _make_level(1)
	var mid_x := (LEFT_C + 3) * 32.0 + 16.0
	var mid_surface := BOTTOM_Y - 4.0 * 16.0
	var player := _make_player(level, Vector2(mid_x, mid_surface - 0.1))
	var stable := true
	for _i in range(120):
		player.keys.clear()
		player.step(DT)
		stable = stable and player.on_ground and approx(player.position.y, mid_surface - 0.1)
	ok(stable, "任一级停驻 120 帧不漂移、不反复离地", "pos=%s" % player.position)

	# 从下层地面起跳：上升阶段忽略梯面，越过后下落才会被同一踏板接住。
	player.position = Vector2(mid_x, BOTTOM_Y - 0.1)
	player.vy = 0.0
	player.on_ground = true
	player.set_state("gun_idle")
	player.keys = {KEY_W: true}
	player._prev_keys.clear()
	player.step(DT)
	var highest_y := player.position.y
	var landed := false
	for _i in range(90):
		player.keys.clear()
		player.step(DT)
		highest_y = minf(highest_y, player.position.y)
		if player.on_ground and approx(player.position.y, mid_surface - 0.1):
			landed = true
			break
	ok(highest_y < mid_surface - 8.0, "从下方起跳可穿过楼梯踏面",
			"highest=%.2f surface=%.2f" % [highest_y, mid_surface])
	ok(landed, "穿过后从上方下落会站在踏板上", "pos=%s" % player.position)

	player.position = Vector2(mid_x, mid_surface - 80.0)
	player.vy = 0.0
	player.on_ground = false
	player.set_state("gun_jump_air")
	for _i in range(60):
		player.keys.clear()
		player.step(DT)
		if player.on_ground:
			break
	ok(player.on_ground and approx(player.position.y, mid_surface - 0.1),
			"从上方自由落下首先命中正确踏板", "pos=%s" % player.position)
	player.free()
	level.free()


func _test_burst_both_directions(rise_dir: int, use_dash: bool) -> void:
	var stair_label := "向右升" if rise_dir > 0 else "向左升"
	var action_label := "冲刺" if use_dash else "翻滚"
	print("== 贴阶爆发：%s / %s ==" % [stair_label, action_label])
	var level := _make_level(rise_dir)
	var bottom_x := LEFT_C * 32.0 - 20.0 if rise_dir > 0 \
			else (LEFT_C + STEPS) * 32.0 + 20.0
	var up_key := KEY_D if rise_dir > 0 else KEY_A
	var down_key := KEY_A if rise_dir > 0 else KEY_D
	var player := _make_player(level, Vector2(bottom_x, BOTTOM_Y - 0.1))
	var up_start := player.position
	var up := _drive_burst(player, up_key, use_dash, DT)
	var expected_distance := KairullPlayer.DASH_DISTANCE if use_dash \
			else KairullPlayer.ROLL_DISTANCE
	ok(bool(up["started"]), "%s/%s：下平台可启动" % [stair_label, action_label])
	ok(absf(player.position.x - up_start.x) >= expected_distance - 2.0,
			"%s/%s：完整通过爆发距离" % [stair_label, action_label],
			"pos=%s start=%s" % [player.position, up_start])
	ok(player.position.y <= up_start.y - 16.0,
			"%s/%s：上楼时脚底随踏板抬升" % [stair_label, action_label],
			"dy=%.2f" % (player.position.y - up_start.y))
	ok(bool(up["all_grounded"]), "%s/%s：上楼全程保持贴地" % [stair_label, action_label])
	ok(player._standing_on_stair(), "%s/%s：上楼终点落在楼梯高度场" % [stair_label, action_label])
	player.free()

	var top_x := (LEFT_C + STEPS) * 32.0 + 20.0 if rise_dir > 0 \
			else LEFT_C * 32.0 - 20.0
	player = _make_player(level, Vector2(top_x, TOP_Y - 0.1))
	var down_start := player.position
	# 一组使用 30fps，验证单帧跨较远时内部仍逐 2px 扫描，不会跳过台阶。
	var down_dt := 1.0 / 30.0 if use_dash else DT
	var down := _drive_burst(player, down_key, use_dash, down_dt)
	ok(bool(down["started"]), "%s/%s：上平台可启动" % [stair_label, action_label])
	ok(absf(player.position.x - down_start.x) >= expected_distance - 2.0,
			"%s/%s：下楼不被 16px 高差截断" % [stair_label, action_label],
			"pos=%s start=%s" % [player.position, down_start])
	ok(player.position.y >= down_start.y + 16.0,
			"%s/%s：下楼时脚底随踏板下降" % [stair_label, action_label],
			"dy=%.2f" % (player.position.y - down_start.y))
	ok(bool(down["all_grounded"]), "%s/%s：下楼全程保持贴地" % [stair_label, action_label])
	ok(player._standing_on_stair(), "%s/%s：下楼终点落在楼梯高度场" % [stair_label, action_label])
	player.free()
	level.free()


func _test_clearance_and_burst_guards() -> void:
	print("== 净空与爆发移动防穿 ==")
	var level := _make_level(1, true)
	var start := Vector2(LEFT_C * 32.0 - 20.0, BOTTOM_Y - 0.1)
	var player := _make_player(level, start)
	_drive(player, KEY_D, 12)
	ok(player.position.x < LEFT_C * 32.0 and approx(player.position.y, BOTTOM_Y - 0.1),
			"低顶阻止抬阶，角色不会钻入天花板", "pos=%s" % player.position)
	player.free()
	level.free()

	# 低顶同样约束冲刺和翻滚：允许动作起步，但安全终点必须停在楼梯入口前。
	for use_dash in [true, false]:
		level = _make_level(1, true)
		player = _make_player(level, start)
		var result := _drive_burst(player, KEY_D, use_dash, DT)
		var label := "冲刺" if use_dash else "翻滚"
		ok(bool(result["started"]), "低顶前%s仍能响应输入" % label)
		ok(player.position.x < LEFT_C * 32.0 \
				and approx(player.position.y, BOTTOM_Y - 0.1)
				and player._body_clear_at(player.position.x, player.position.y),
				"低顶阻止%s钻入楼梯/天花板" % label, "pos=%s" % player.position)
		player.free()
		level.free()


func _test_empty_stairs_regression() -> void:
	print("== 旧地图空配置回归 ==")
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
	var level := CorridorLevel.new()
	level.build(false)
	ok(level.stairs.is_empty(), "active_stairs=[] 不生成额外碰撞")
	ok(level.map_w == 160 and level.map_h == 24, "默认旧地图尺寸保持 160×24")
	ok(level.solid_at(5.5 * 32.0, 19.5 * 32.0), "默认旧地图实心格查询保持不变")
	ok(level.stair_surface_near(100.0, 100.0, 16.0, 16.0) == INF,
			"空楼梯查询返回 INF")
	level.free()


func _make_level(rise_dir: int, low_ceiling := false) -> CorridorLevel:
	CorridorLevel.active_map = _map_for(rise_dir, low_ceiling)
	CorridorLevel.active_stairs = [{
		"left_c": LEFT_C,
		"bottom_row": BOTTOM_ROW,
		"steps": STEPS,
		"rise_dir": rise_dir,
	}]
	var level := CorridorLevel.new()
	level.build(false)
	return level


func _make_player(level: CorridorLevel, at: Vector2) -> KairullPlayer:
	var player := KairullPlayer.new()
	player.auto_input = false
	player.db = _db
	player.level = level
	player.spawn = at
	get_root().add_child(player)
	player.position = at
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = true
	player.set_state("gun_idle")
	player.keys.clear()
	player._prev_keys.clear()
	return player


func _drive(player: KairullPlayer, key: int, frames: int) -> Dictionary:
	var all_grounded := true
	for _i in range(frames):
		player.keys = {key: true}
		player.step(DT)
		all_grounded = all_grounded and player.on_ground
	player.keys.clear()
	return {"all_grounded": all_grounded}


func _drive_burst(player: KairullPlayer, move_key: int, use_dash: bool,
		dt: float) -> Dictionary:
	var action_key := KEY_SHIFT if use_dash else KEY_CTRL
	player.keys = {move_key: true, action_key: true}
	player._prev_keys.clear()
	player.step(dt)
	var active := player.dashing() if use_dash else player.rolling()
	var started := active
	var all_grounded := player.on_ground
	var ticks := 1
	while active and ticks < 90:
		player.keys = {move_key: true, action_key: true}
		player.step(dt)
		all_grounded = all_grounded and player.on_ground
		active = player.dashing() if use_dash else player.rolling()
		ticks += 1
	player.keys.clear()
	return {"started": started, "all_grounded": all_grounded, "ticks": ticks}


func _map_for(rise_dir: int, low_ceiling: bool) -> String:
	var rows := PackedStringArray()
	for row_index in range(H):
		var row := ".".repeat(W)
		if row_index == 10:
			row = (".".repeat(LEFT_C + STEPS) + "#".repeat(W - LEFT_C - STEPS)) \
					if rise_dir > 0 else ("#".repeat(LEFT_C) + ".".repeat(W - LEFT_C))
		elif row_index == BOTTOM_ROW:
			row = "#".repeat(W)
		if low_ceiling and row_index == 11:
			var ceiling_c := LEFT_C if rise_dir > 0 else LEFT_C + STEPS - 1
			row = row.substr(0, ceiling_c) + "##" + row.substr(ceiling_c + 2)
		rows.append(row)
	return "\n".join(rows)


func _reset_statics() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
