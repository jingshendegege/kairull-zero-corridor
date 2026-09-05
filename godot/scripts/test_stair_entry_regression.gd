extends SceneTree
## 直接消费正式 M01 编译楼梯，覆盖真实落稳后从两端走路/冲刺/翻滚进入。
## 特意不把 on_ground 手动设为 true；避免旧纯高度场测试绕过入口失地。

const DATA := preload("res://generated/m01_protocol_quarantine_data.gd")
const BOOT := preload("res://scripts/m01_protocol_quarantine_boot.gd")

var _passed := 0
var _failed := 0
var _db: AtlasDB
var _level: CorridorLevel


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: %s %s" % [label, detail])


func _run() -> void:
	var boot := BOOT.new()
	CorridorLevel.active_map = DATA.MAP_TEXT
	CorridorLevel.active_stairs = boot._runtime_stairs()
	boot.free()
	_level = CorridorLevel.new()
	_level.build(false)
	_db = AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json",
	])
	_check(_level.stairs.size() == 3 and _level.map_w == 280,
			"正式 M01 三段钢梯与 280 列地图接线")
	for stair_index in _level.stairs.size():
		var stair: Dictionary = _level.stairs[stair_index]
		for direction in [-1, 1]:
			for fps in [30, 60, 120]:
				for mode in ["walk", "dash", "roll"]:
					for margin in [12.0, 25.0, 48.0]:
						_test_entry(stair_index, stair, direction, fps, mode, margin)
		_test_underneath_entry(stair_index, stair)
		_test_airborne_low_dash(stair_index, stair)
		_test_jump_and_mid_stair_landing(stair_index, stair)
	_level.free()
	_db = null
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
	print("STAIR_ENTRY_RESULT: %s %d passed, %d failed" % [
			"PASS" if _failed == 0 else "FAIL", _passed, _failed])
	await process_frame
	quit(0 if _failed == 0 else 1)


func _player_at(at: Vector2) -> KairullPlayer:
	var player := KairullPlayer.new()
	player.auto_input = false
	player.db = _db
	player.level = _level
	player.spawn = at
	get_root().add_child(player)
	player.position = at
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = false
	player.keys.clear()
	player._prev_keys.clear()
	return player


func _expected_surface(stair: Dictionary, player: KairullPlayer) -> float:
	var left_x := float(stair["left_c"]) * 32.0
	var right_x := left_x + float(stair["steps"]) * 32.0
	var bottom_y := float(stair["bottom_row"]) * 32.0
	var top_y := bottom_y - float(stair["steps"]) * 16.0
	var right_up := int(stair["rise_dir"]) > 0
	var result := INF
	for x in [player.position.x - player.w * 0.5 + 3.0, player.position.x,
			player.position.x + player.w * 0.5 - 3.0]:
		if x < left_x:
			result = minf(result, bottom_y if right_up else top_y)
		elif x >= right_x:
			result = minf(result, top_y if right_up else bottom_y)
		else:
			var index := floori((x - left_x) / 32.0)
			var rank := index + 1 if right_up else int(stair["steps"]) - index
			result = minf(result, bottom_y - float(rank) * 16.0)
	return result - 0.1


func _test_entry(stair_index: int, stair: Dictionary, direction: int,
		fps: int, mode: String, margin: float) -> void:
	var left_x := float(stair["left_c"]) * 32.0
	var right_x := left_x + float(stair["steps"]) * 32.0
	var bottom_y := float(stair["bottom_row"]) * 32.0
	var top_y := bottom_y - float(stair["steps"]) * 16.0
	var from_bottom := direction == int(stair["rise_dir"])
	var start_x := left_x - margin if direction > 0 else right_x + margin
	var start_y := bottom_y if from_bottom else top_y
	var player := _player_at(Vector2(start_x, start_y - 8.0))
	var dt := 1.0 / float(fps)
	for frame in range(fps):
		player.step(dt)
	var label := "stair%d dir%d %s %dfps margin%.0f" % [
			stair_index, direction, mode, fps, margin]
	_check(player.on_ground and absf(player.position.y - (start_y - 0.1)) < 0.6,
			label + " settles on actual entry", str(player.position))
	var move_key := KEY_D if direction > 0 else KEY_A
	player.keys = {move_key: true}
	if mode == "dash":
		player.keys[KEY_SHIFT] = true
	elif mode == "roll":
		player.keys[KEY_CTRL] = true
	var start := player.position
	var no_penetration := true
	var all_grounded := true
	var detail := ""
	var frames := ceili((320.0 + margin * 2.0) / (KairullPlayer.RUN * 60.0) * fps)
	if mode == "dash":
		frames = ceili(KairullPlayer.DASH_DURATION * fps)
	elif mode == "roll":
		frames = ceili(KairullPlayer.ROLL_DURATION * fps)
	for frame in range(frames):
		player.step(dt)
		var expected := _expected_surface(stair, player)
		if player.position.y > expected + 1.0:
			no_penetration = false
			if detail.is_empty():
				detail = "frame%d pos%s expected%.2f ground%s" % [
						frame, player.position, expected, player.on_ground]
		all_grounded = all_grounded and player.on_ground
	_check(no_penetration, label + " never below tread", detail)
	_check(all_grounded, label + " stays grounded", str(player.position))
	_check(absf(player.position.x - start.x) >= 150.0,
			label + " advances without jump", str(player.position))
	player.free()


func _test_underneath_entry(stair_index: int, stair: Dictionary) -> void:
	# 诊断历史盲区：角色落在第二级下方，再平走向上时，不应把它误认成正常入口。
	# 这里记录结果但不强行改变单向梯设计；主回归仅约束两端正常通路。
	var rise_dir := int(stair["rise_dir"])
	var left_x := float(stair["left_c"]) * 32.0
	var right_x := left_x + float(stair["steps"]) * 32.0
	var start_x := left_x + 48.0 if rise_dir > 0 else right_x - 48.0
	var bottom_y := float(stair["bottom_row"]) * 32.0
	for mode in ["walk", "dash"]:
		var player := _player_at(Vector2(start_x, bottom_y - 0.1))
		for frame in range(10):
			player.step(1.0 / 60.0)
		player.keys = {KEY_D if rise_dir > 0 else KEY_A: true}
		if mode == "dash":
			player.keys[KEY_SHIFT] = true
		for frame in range(20):
			player.step(1.0 / 60.0)
		print("UNDER_STAIR_DIAG stair%d %s pos%s on_ground%s support%s" % [
				stair_index, mode, player.position, player.on_ground,
				player._standing_on_stair()])
		player.free()


func _test_airborne_low_dash(stair_index: int, stair: Dictionary) -> void:
	# 真正漏掉的入口：跳跃刚要落地但尚未 grounded 时按冲刺；不能钻进首级后永远沿梯下跑。
	var rise_dir := int(stair["rise_dir"])
	var left_x := float(stair["left_c"]) * 32.0
	var right_x := left_x + float(stair["steps"]) * 32.0
	var entry_x := left_x if rise_dir > 0 else right_x
	var bottom_y := float(stair["bottom_row"]) * 32.0
	for height in [1.0, 8.0, 15.0]:
		for mode in ["walk", "dash", "roll"]:
			var player := _player_at(Vector2(entry_x - float(rise_dir) * 20.0,
					bottom_y - height))
			player.vy = 4.0
			player.set_state("gun_jump_air")
			var move_key := KEY_D if rise_dir > 0 else KEY_A
			player.keys = {move_key: true}
			if mode == "dash":
				player.keys[KEY_SHIFT] = true
			elif mode == "roll":
				player.keys[KEY_CTRL] = true
			for frame in range(7 if mode != "roll" else 20):
				player.step(1.0 / 60.0)
			var advanced := (player.position.x - entry_x) * float(rise_dir)
			var supported := player._standing_on_stair()
			var label := "stair%d low-air %s %.0fpx" % [stair_index, mode, height]
			_check(advanced <= 0.0 or supported,
					label + " cannot tunnel under entrance",
					"pos%s advanced%.1f support%s" % [player.position, advanced, supported])
			# 技能被入口截停之后只按方向键；不靠 W、传送或强写 on_ground 恢复通路。
			player.keys = {move_key: true}
			for frame in range(90):
				player.step(1.0 / 60.0)
			var top_y := bottom_y - float(stair["steps"]) * 16.0
			_check(absf(player.position.y - top_y + 0.1) < 0.6 and player.on_ground,
					label + " continues up without jump", str(player.position))
			player.free()


func _test_jump_and_mid_stair_landing(stair_index: int, stair: Dictionary) -> void:
	var rise_dir := int(stair["rise_dir"])
	var index := 4 if rise_dir > 0 else int(stair["steps"]) - 5
	var x := (float(stair["left_c"]) + float(index) + 0.5) * 32.0
	var bottom_y := float(stair["bottom_row"]) * 32.0
	var surface := bottom_y - 5.0 * 16.0
	var player := _player_at(Vector2(x, bottom_y - 0.1))
	for frame in range(10):
		player.step(1.0 / 60.0)
	player.keys = {KEY_W: true}
	player.step(1.0 / 60.0)
	player.keys.clear()
	var min_y := player.position.y
	var landed := false
	for frame in range(70):
		player.step(1.0 / 60.0)
		min_y = minf(min_y, player.position.y)
		if player.on_ground and absf(player.position.y - surface + 0.1) < 0.6:
			landed = true
			break
	_check(min_y < surface - 8.0, "stair%d upward jump still passes underside" % stair_index)
	_check(landed, "stair%d jump lands on the same middle tread" % stair_index,
			str(player.position))
	player.free()
	player = _player_at(Vector2(x, surface - 32.0))
	player.vy = 4.0
	for frame in range(30):
		player.step(1.0 / 60.0)
		if player.on_ground:
			break
	_check(player.on_ground and absf(player.position.y - surface + 0.1) < 0.6,
			"stair%d downward mid-air entry lands on tread" % stair_index, str(player.position))
	player.free()
