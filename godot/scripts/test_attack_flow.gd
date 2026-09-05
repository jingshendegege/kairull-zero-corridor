extends SceneTree
## 攻击流专项：连续带步、碰撞扫掠、命中后取消与爆发动作末尾的一次性输入缓冲。

const DT := 1.0 / 60.0
const FLOOR_Y := 448.0
var _pass := 0
var _fail := 0
var _db: AtlasDB


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_db = AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json", "res://assets/clips/hero/hero_atlas.json",
	])
	_test_motion()
	_test_collision()
	_test_cancel()
	_test_buffer()
	_test_air_and_lifecycle()
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
	_db = null
	await process_frame
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _make_level(wall := false, stairs := false) -> CorridorLevel:
	var rows := PackedStringArray()
	for y in range(18):
		var row := "#".repeat(48) if y == 14 else ".".repeat(48)
		if wall and y >= 8 and y < 14:
			row = row.substr(0, 12) + "#" + row.substr(13)
		if stairs and y == 10:
			row = ".".repeat(28) + "#".repeat(20)
		rows.append(row)
	CorridorLevel.active_map = "\n".join(rows)
	var stair_definitions: Array[Dictionary] = []
	if stairs:
		stair_definitions.append({"left_c": 20, "bottom_row": 14,
			"steps": 8, "rise_dir": 1})
	CorridorLevel.active_stairs = stair_definitions
	var level := CorridorLevel.new()
	level.build(false)
	return level


func _make_player(level: CorridorLevel, x := 128.0) -> KairullPlayer:
	var player := KairullPlayer.new()
	player.auto_input = false
	player.level = level
	player.db = _db
	player.spawn = Vector2(x, FLOOR_Y - 0.1)
	get_root().add_child(player)
	player.reset_to_spawn()
	player.on_ground = true
	player.keys.clear()
	player._prev_keys.clear()
	return player


func _wait_progress(player: KairullPlayer, progress: float) -> void:
	for _i in range(90):
		if not player.batting() or player._bat_progress() >= progress:
			break
		player.keys = {}
		player.step(DT)


func _test_motion() -> void:
	print("== 连续攻击步伐 ==")
	var level := _make_level()
	var player := _make_player(level)
	var initial_x := player.position.x
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player.step(DT)
	var first_dx := player.position.x - initial_x
	ok(player.batting() and first_dx > 0.0 and first_dx < 20.0,
			"首帧有动量但不再瞬移 38px", str(first_dx))
	_wait_progress(player, 0.60)
	ok(absf(player.position.x - initial_x - KairullPlayer.BAT1_STEP) < 0.05,
			"无方向输入只前送约 1.2 格", str(player.position.x - initial_x))
	var stopped_x := player.position.x
	for _i in range(15):
		player.step(DT)
	ok(absf(player.position.x - stopped_x) < 0.05, "松开方向不会强制持续滑行")
	player.reset_to_spawn()
	player.on_ground = true
	player._prev_keys.clear()
	player.keys = {MOUSE_BUTTON_LEFT: true, KEY_D: true}
	player.step(DT)
	var moved_ticks := 0
	var recovery_vx := 0.0
	for _i in range(15):
		var before := player.position.x
		player.keys = {KEY_D: true}
		player.step(DT)
		if player.batting() and player.position.x > before:
			moved_ticks += 1
		if player._bat_progress() >= 0.60:
			recovery_vx = player.vx
	ok(moved_ticks >= 13, "同向持续输入时挥棒持续推进，不再钉在原地", str(moved_ticks))
	ok(recovery_vx > KairullPlayer.RUN * 0.7 and recovery_vx < KairullPlayer.RUN,
			"收招恢复大部分奔跑速度但仍保留动作重量", str(recovery_vx))
	player.reset_to_spawn()
	player.on_ground = true
	player.face = 1
	player._prev_keys.clear()
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player.step(DT)
	player.keys = {KEY_A: true}
	player.step(DT)
	ok(player.batting() and player.face == 1 and player.vx == 0.0,
			"前摇反向输入只刹脚，不翻转攻击或倒滑")
	_wait_progress(player, 0.62)
	var reverse_x := player.position.x
	player.keys = {KEY_A: true}
	player.step(DT)
	ok(not player.batting() and player.face == -1 and player.position.x < reverse_x,
			"收招后段反向输入直接转身奔跑")
	player.free()
	level.free()


func _test_collision() -> void:
	print("== 带步碰撞与楼梯 ==")
	var wall_level := _make_level(true)
	var player := _make_player(wall_level, 354.0)
	player.keys = {KEY_D: true, MOUSE_BUTTON_LEFT: true}
	for _i in range(8):
		player.step(1.0 / 30.0)
	ok(player.position.x + player.w * 0.5 < 384.0,
			"30fps 首击前送与带步不穿实心墙", str(player.position.x))
	ok(player._body_clear_at(player.position.x, player.position.y), "撞墙后身体仍处于净空")
	player.free()
	wall_level.free()
	var stair_level := _make_level(false, true)
	player = _make_player(stair_level, 620.0)
	player.keys = {KEY_D: true, MOUSE_BUTTON_LEFT: true}
	var grounded := true
	for _i in range(18):
		player.step(DT)
		grounded = grounded and player.on_ground
	ok(player.position.x > 690.0 and player.position.y < FLOOR_Y - 32.0,
			"挥棒带步沿正式 16px 楼梯上行", str(player.position))
	ok(grounded and player._body_clear_at(player.position.x, player.position.y),
			"上阶全程贴地且不钻入踏板")
	player.keys.clear()
	while player.batting():
		player.step(DT)
	player.face = -1
	player._prev_keys.clear()
	player.keys = {KEY_A: true, MOUSE_BUTTON_LEFT: true}
	var down_from := player.position
	for _i in range(18):
		player.step(DT)
	ok(player.position.x < down_from.x - 70.0 and player.position.y > down_from.y,
			"带步挥棒也可稳定下台阶", str(player.position))
	player.free()
	stair_level.free()


func _test_cancel() -> void:
	print("== 命中后取消与一次判定 ==")
	var level := _make_level()
	for action in [KEY_CTRL, KEY_SHIFT, KEY_W]:
		var player := _make_player(level)
		var hits := [0]
		player.bat_swung.connect(func(_box: Rect2, _stage: int) -> void: hits[0] += 1)
		player.keys = {MOUSE_BUTTON_LEFT: true}
		player.step(DT)
		player.keys = {action: true}
		player.step(DT)
		ok(player.batting(), "前摇不能用 %s 跳过命中承诺" % OS.get_keycode_string(action))
		_wait_progress(player, KairullPlayer.BAT_CANCEL_OPEN)
		player.keys = {MOUSE_BUTTON_LEFT: true}
		player._prev_keys.clear()
		player.step(DT)
		ok(player.bat_queued, "取消前有下一击排队")
		player.keys = {action: true}
		player.step(DT)
		var expected := "roll" if action == KEY_CTRL else ("dash" if action == KEY_SHIFT else "gun_jump_air")
		ok(player.state == expected and not player.bat_queued,
				"命中后 %s 可取消且清除连招排队" % OS.get_keycode_string(action), player.state)
		for _i in range(30):
			player.keys = {}
			player.step(DT)
		ok(hits[0] == 1, "取消不会重复或延迟追加攻击判定", str(hits[0]))
		player.free()
	var stopped := _make_player(level)
	stopped.keys = {MOUSE_BUTTON_LEFT: true, KEY_D: true}
	stopped.step(DT)
	_wait_progress(stopped, 0.45)
	stopped.hitstop = 0.04
	var stopped_at := stopped.position
	var stopped_frame := stopped.frame
	stopped.keys = {KEY_D: true, KEY_CTRL: true}
	stopped.step(DT)
	ok(stopped.position == stopped_at and stopped.frame == stopped_frame and stopped.batting(),
			"短命中停顿同时冻结挥棒位移和帧，不可中途取消")
	stopped.free()
	level.free()


func _test_buffer() -> void:
	print("== 移动末尾左键缓冲 ==")
	var level := _make_level()
	for action in [KEY_CTRL, KEY_SHIFT]:
		var player := _make_player(level)
		var starts := [0]
		player.bat_swing_started.connect(func(_stage: int) -> void: starts[0] += 1)
		player.keys = {action: true, KEY_D: true}
		player.step(DT)
		var duration := KairullPlayer.ROLL_DURATION if action == KEY_CTRL else KairullPlayer.DASH_DURATION
		var until_input := maxi(0, int(ceil((duration - 0.07) / DT)) - 1)
		for _i in range(until_input):
			player.keys = {KEY_D: true}
			player.step(DT)
		player.keys = {KEY_D: true, MOUSE_BUTTON_LEFT: true}
		player.step(DT)
		ok(not player.batting() and player._bat_input_buffer_t > 0.0,
				"%s 末尾记录左键但不提前中断移动" % OS.get_keycode_string(action))
		for _i in range(40):
			player.step(DT)
		ok(starts[0] == 1 and player._bat_input_buffer_t == 0.0,
				"%s 结束后只触发一次攻击，按住不重放" % OS.get_keycode_string(action), str(starts[0]))
		player.free()
	var expired := _make_player(level)
	expired.keys = {KEY_CTRL: true}
	expired.step(DT)
	expired.keys = {MOUSE_BUTTON_LEFT: true}
	expired.step(DT)
	for _i in range(30):
		expired.keys = {}
		expired.step(DT)
	ok(not expired.batting() and expired._bat_input_buffer_t == 0.0,
			"翻滚早期点按超过 0.1s 即过期，不在很久后误出棒")
	expired.free()
	level.free()


func _test_air_and_lifecycle() -> void:
	print("== 空中规则与重置 ==")
	var level := _make_level()
	var player := _make_player(level)
	player.position.y = 220.0
	player.on_ground = false
	player.keys = {MOUSE_BUTTON_LEFT: true, KEY_D: true}
	var air_x := player.position.x
	player.step(DT)
	ok(player.batting() and player.air_bat_used and not player._bat_ground_lunge,
			"空中起手仍只有一次且不附带地面前送")
	ok(player.position.y > 220.0 and player.position.x - air_x < 3.0,
			"空中挥棒继续重力，仅保留可控水平带步")
	player._bat_input_buffer_t = 0.08
	player.bat_queued = true
	player.take_damage(100, 0.0)
	ok(player.dead and player._bat_input_buffer_t == 0.0 and not player.bat_queued,
			"死亡清空待消费攻击和连招")
	player._bat_input_buffer_t = 0.08
	player.reset_to_spawn()
	ok(player._bat_input_buffer_t == 0.0 and not player._bat_ground_lunge \
			and player._bat_lunge_applied == 0.0, "重置清除新攻击状态")
	ok(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED,
			"纯球棒与旧滑铲关闭不变")
	player.free()
	level.free()
