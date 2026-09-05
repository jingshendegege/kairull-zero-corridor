extends SceneTree
## 扩展主线的检查点、单次补给、清敌归属、结算与重开入口；不代替真实跑图。

var passed := 0
var failed := 0

func ok(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var boot := load("res://scenes/m01_protocol_quarantine.tscn").instantiate() as Node2D
	get_root().add_child(boot)
	await process_frame
	var game: Node2D = boot.get_node("Game")
	game.set_physics_process(false)
	game.set_process(false)
	game.player.auto_input = false
	game.music.stop()
	game.music.stream = null
	game._sfx.clear()
	# Dummy 音频驱动也要等一次回收周期，避免测试极速退出留下 MP3 playback 假泄漏。
	await create_timer(0.15).timeout
	var progress: Dictionary = game.run_progress()
	ok(progress["is_extended"] and progress["enemies_total"] == 20 and progress["rooms_total"] == 10,
		"扩展主线统计20敌10区")
	ok(game._checkpoint_beacons.size() == 2 and game._checkpoint_index == -1,
		"按LDtk创建两处尚未激活的检查点")
	ok(not game._can_restart_campaign(), "普通游玩Enter不误重开")
	var first: Node2D = game._checkpoint_beacons[4]
	var second: Node2D = game._checkpoint_beacons[7]
	var first_next: Node2D = null
	var second_next: Node2D = null
	for enemy: Node2D in game.minions:
		var spawn: Vector2i = enemy.get_meta("spawn_cell")
		if spawn.x == 120:
			first_next = enemy
		if spawn.x == 225:
			second_next = enemy
	game.player.position = first.position
	game._update_room_state()
	ok(first_next != null and not game._campaign_enemy_released(first_next),
		"首次进入维修站：隔壁288px近战兵不提前追入")
	game.player.on_ground = true
	game.player.hp = 1
	game._update_campaign_progress(0.1)
	ok(game._checkpoint_index == -1 and game.player.hp == 1,
		"跳过前段敌人不能解锁补给")
	for enemy: Node2D in game.minions:
		var cell: Vector2i = enemy.get_meta("spawn_cell")
		if cell.x < 119:
			enemy.dead = true
	game.player.on_ground = false
	game._update_campaign_progress(0.1)
	ok(game._checkpoint_index == -1, "须落地靠近终端才能激活")
	game.player.on_ground = true
	game._update_campaign_progress(0.1)
	ok(game._checkpoint_index == 4 and game.player.spawn == first.position,
		"首检查点写入实际玩家返回位置")
	ok(game.player.hp == KairullPlayer.HP_MAX and game.player.invuln_t >= 0.6,
		"新检查点一次性补满并给短保护")
	ok(first.activated and first.unlocked, "终端显示正确激活状态")
	game.player.hp = 2
	game._update_campaign_progress(0.1)
	ok(game.player.hp == 2, "原地停留不能反复回满生命")
	game.player.position = second.position
	game._update_room_state()
	ok(second_next != null and not game._campaign_enemy_released(second_next),
		"首次进入上联站：隔壁320px近战兵仍休眠")
	game._update_campaign_progress(0.1)
	ok(game._checkpoint_index == 4, "后段未清场不激活第二点")
	for enemy: Node2D in game.minions:
		var cell: Vector2i = enemy.get_meta("spawn_cell")
		if cell.x < 219:
			enemy.dead = true
	game._update_campaign_progress(0.1)
	ok(game._checkpoint_index == 7 and game.player.spawn == second.position, "清场后解锁第二检查点")
	game.player.position = first.position
	game._update_campaign_progress(0.1)
	ok(game.player.spawn == second.position, "回走不覆盖更晚检查点")
	var retry := InputEventKey.new()
	retry.keycode = KEY_BACKSPACE
	retry.pressed = true
	game.player.dead = true
	ok(game._can_restart_campaign(), "死亡允许Enter完整重开")
	game._unhandled_input(retry)
	ok(not game.player.dead and game.player.position.is_equal_approx(second.position),
		"Backspace实际回到最近检查点")
	ok(game.run_progress()["enemies_defeated"] > 0, "轻量重试保留已清敌人")
	game.player.position = Vector2(220 * 32 + 16, 23 * 32 - 0.1)
	game._update_room_state()
	ok(game._campaign_enemy_released(second_next), "跨入核心战斗房才唤醒后段敌人")
	game.player.position = second.position
	game._update_room_state()
	ok(game._campaign_enemy_released(second_next), "退回中继站不会强制睡掉已经唤醒的追兵")
	var living: Node2D = null
	for enemy: Node2D in game.minions:
		if not enemy.dead:
			living = enemy
			break
	var cell: Vector2i = living.get_meta("spawn_cell")
	var home_room: int = game.level.room_at(cell.x * 32 + 16, cell.y * 32 + 16)
	var before: int = game.room_alive_count(home_room)
	living.position = first.position
	ok(game.room_alive_count(home_room) == before, "敌人跨房移动不改变出生房间威胁统计")
	var elapsed: float = game.run_progress()["elapsed"]
	game.player.dead = true
	game._update_campaign_progress(2.0)
	ok(is_equal_approx(game.run_progress()["elapsed"], elapsed), "死亡界面不增长游戏计时")
	game.player.dead = false
	game.level_cleared = true
	game._update_campaign_progress(2.0)
	ok(is_equal_approx(game.run_progress()["elapsed"], elapsed) and game._can_restart_campaign(),
		"结算计时冻结并允许完整重开")
	ok(CorridorLevel.active_next_scene.is_empty(), "扩展关通关不跳进旧M02美术")
	# 真正发送 Enter 并等待 SceneTree 切换，不能只凭按钮允许条件声称可重开。
	var previous_id := boot.get_instance_id()
	current_scene = boot
	var restart := InputEventKey.new()
	restart.keycode = KEY_ENTER
	restart.pressed = true
	game._unhandled_input(restart)
	for i in 4:
		await process_frame
	boot = current_scene as Node2D
	game = boot.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.music.stop()
	game.music.stream = null
	game._sfx.clear()
	ok(boot.get_instance_id() != previous_id, "Enter实际重建正式第一关场景")
	ok(game._checkpoint_index == -1 and game._campaign_frontier <= 0,
		"完整重开重置返回点与AI分段进度")
	ok(game.minions.size() == 20 and game.run_progress()["enemies_defeated"] == 0,
		"完整重开二十敌全部复活")
	ok(game.player.position.is_equal_approx(game.level.spawn) and game.props.size() == 11,
		"完整重开回入口并恢复十一货箱")
	boot.free()
	await process_frame
	await create_timer(0.15).timeout
	ok(not CorridorLevel.active_campaign_mode and CorridorLevel.active_restart_scene.is_empty(),
		"离开新关卡后不污染旧场景静态配置")
	print("TEST_RESULT: %s (%d passed, %d failed)" % ["PASS" if failed == 0 else "FAIL", passed, failed])
	quit(0 if failed == 0 else 1)
