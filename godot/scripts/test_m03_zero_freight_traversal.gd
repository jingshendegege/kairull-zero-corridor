extends SceneTree
## M03 真实物理回环验收：机器人从到达台走到东楼梯，上层横穿后双 S 回落。
## 跑法：godot --headless --path godot --script scripts/test_m03_zero_freight_traversal.gd

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


func _run() -> void:
	_reset_statics()
	var boot: Node2D = load("res://scenes/m03_zero_freight.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var player: KairullPlayer = game.player
	player.auto_input = false
	player.hp = 999
	for i in range(3):
		await physics_frame

	# 只留维修库一敌维持总出口锁定；沿途清房门均会解锁。
	var survivor: Node2D
	for minion in game.minions:
		var cell: Vector2i = minion.get_meta("spawn_cell")
		if survivor == null and (game.level.rooms[6]["rect"] as Rect2i).has_point(cell):
			survivor = minion
		else:
			minion.take_hit(minion.position.x, 1)
	for i in range(4):
		await physics_frame
	ok(survivor != null and not survivor.dead, "保留维修库一敌，出口仍锁定")
	ok(game._exit_gated(), "回环途中不会误触出生点旁出口")
	var route: Array[Vector2] = [
		Vector2(28 * 32 + 16, 25 * 32 - 0.1),
		Vector2(45 * 32 + 16, 25 * 32 - 0.1),
		Vector2(78 * 32 + 16, 25 * 32 - 0.1),
		Vector2(83 * 32 + 16, 23 * 32 - 0.1),
		Vector2(87 * 32 + 16, 21 * 32 - 0.1),
		Vector2(91 * 32 + 16, 19 * 32 - 0.1),
		Vector2(92 * 32 + 16, 16 * 32 - 0.1),
		Vector2(110 * 32 + 16, 16 * 32 - 0.1),
		Vector2(96 * 32 + 16, 16 * 32 - 0.1),
		Vector2(70 * 32 + 16, 16 * 32 - 0.1),
		Vector2(33 * 32 + 16, 16 * 32 - 0.1),
		Vector2(23 * 32 + 16, 16 * 32 - 0.1),
	]

	print("== 机器人走位：下层 → 东楼梯 → 上层 → 西回落井 ==")
	var route_ok := true
	for wi in route.size():
		var target := route[wi]
		var reached := false
		var last_x := player.position.x
		var stall := 0
		var jump_cd := 0
		for f in range(900):
			var dx := target.x - player.position.x
			var dy := target.y - player.position.y
			if absf(dx) <= 10.0 and absf(player.position.y - target.y) <= 20.0:
				reached = true
				break
			player.keys.clear()
			if dx > 6.0:
				player.keys[KEY_D] = true
			elif dx < -6.0:
				player.keys[KEY_A] = true
			jump_cd = maxi(0, jump_cd - 1)
			if absf(player.position.x - last_x) < 2.0 and absf(dx) > 6.0 and player.on_ground:
				stall += 1
			else:
				stall = 0
			last_x = player.position.x
			var want_up := dy < -24.0 and absf(dx) < 64.0
			if player.on_ground and jump_cd == 0 and (want_up or stall >= 20):
				player.keys[KEY_W] = true
				jump_cd = 22
				stall = 0
			player.step(1.0 / 60.0)
			await physics_frame
		if reached:
			_pass += 1
			print("  PASS  路点 %02d -> c%d r%d" % [wi,
				floori(player.position.x / 32.0), floori(player.position.y / 32.0)])
		else:
			route_ok = false
			_fail += 1
			print("  FAIL  路点 %02d 卡在 %s，目标 %s" % [wi, player.position, target])
			break

	if route_ok:
		# 单向台必须双 S 才下穿；单按 S 不应掉下。
		var y_before := player.position.y
		player.keys = {KEY_S: true}
		player.step(1.0 / 60.0)
		await physics_frame
		player.keys.clear()
		player.step(1.0 / 60.0)
		await physics_frame
		ok(absf(player.position.y - y_before) < 3.0, "单按 S 不下穿")
		player.keys = {KEY_S: true}
		player.step(1.0 / 60.0)
		await physics_frame
		player.keys.clear()
		for i in range(180):
			player.step(1.0 / 60.0)
			await physics_frame
			if player.on_ground and player.position.y > 23.0 * 32.0:
				break
		ok(player.on_ground and absf(player.position.y - (25 * 32 - 0.1)) < 3.0,
			"双 S 从西井回落到底层", str(player.position))

		# 回落后才清最后一敌并折返出口，验证完整 U 形闭环。
		survivor.take_hit(survivor.position.x, 1)
		for i in range(4):
			await physics_frame
		ok(not game._exit_gated(), "最后一敌清除后最终出口解锁")
		var target_exit: Vector2 = game.level.exit_point
		for i in range(360):
			player.keys.clear()
			if target_exit.x < player.position.x - 4.0:
				player.keys[KEY_A] = true
			elif target_exit.x > player.position.x + 4.0:
				player.keys[KEY_D] = true
			player.step(1.0 / 60.0)
			await physics_frame
			if game.level_cleared:
				break
		ok(game.level_cleared, "回到出生区出口完成闭环")
	else:
		ok(false, "完整回环", "路点走位未完成")

	boot.free()
	_reset_statics()
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
