extends SceneTree
## 两座货梯在真正新关中的低站上车→上升→上廊→返回→下落→下车。
## 只冻结宿主AI/战斗；真实game._step_tactics+Player.step接线，不直接改平台相位和中途位置。

const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
var passed := 0
var failed := 0
var game: Node2D


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func tick(direction := 0) -> void:
	game.player.keys.clear()
	if direction:
		game.player.keys[KEY_D if direction > 0 else KEY_A] = true
	game._step_tactics(DT)
	game.player.step(DT)


func walk_to(target_x: float, target_y: float, frames := 120) -> bool:
	for _i in frames:
		if absf(game.player.position.x - target_x) < 7.0 and absf(game.player.position.y - target_y) < 1.1:
			return true
		tick(1 if target_x > game.player.position.x else -1)
	return false


func _run() -> void:
	for lift_index in 2:
		SESSION.begin_run("easy")
		var boot := load("res://scenes/m04_chrono_freight.tscn").instantiate() as Node2D
		root.add_child(boot)
		current_scene = boot
		game = boot.get_node("Game")
		game.set_process(false)
		game.set_physics_process(false)
		game.player.auto_input = false
		game.action_audio_enabled = false
		game._sfx.clear()
		if game.action_audio != null:
			game.action_audio.stop_all()
		check(game.moving_lifts.size() == 2 and game.player.moving_platforms.size() == 2,
			"第%d货梯场景接线：两平台实际共享给Player" % (lift_index + 1))
		var lift: Node2D = game.moving_lifts[lift_index]
		var player: KairullPlayer = game.player
		# 唯一局部测试起点：平台左100px稳定地面，之后整个往返不再设置position。
		player.position = Vector2(lift.position.x - 100.0, lift.bottom_y - 0.1)
		player.vx = 0.0
		player.vy = 0.0
		player.on_ground = true
		player.hp = 999
		player.keys.clear()
		player._prev_keys.clear()
		game._update_room_state()
		check(walk_to(lift.position.x, lift.bottom_y - 0.1), "从低路实际步行到第%d货梯中央" % (lift_index + 1))
		check(lift.supports_rider(player), "低站真正获得平台脚底支撑")
		var synced := true
		var top_reached := false
		var saw_up := false
		for _i in 360:
			tick()
			synced = synced and absf(player.position.y - (lift.position.y - 0.1)) < 1.1
			saw_up = saw_up or lift.state == "up"
			if lift.state == "top_wait":
				top_reached = true
				break
		check(saw_up and top_reached and synced and not lift.stalled,
			"第%d货梯携带真实主角上升192px，不穿过备用中继台/挤头" % (lift_index + 1), str(player.position))
		check(is_equal_approx(lift.bottom_y - lift.top_y, 192.0)
			and absf(player.position.y - 671.9) < 1.1, "上站到达192px连廊实际高度")
		var right_x: float = lift.position.x + 96.0
		check(walk_to(right_x, lift.top_y - 0.1), "从上站不用跳跃直接向右接入上层连廊")
		check(game.level.is_platform(player.position.x, player.position.y + 1.1)
			and not lift.supports_rider(player), "离开货梯后脚下确为静态上廊，不是悬空假站立")
		check(walk_to(lift.position.x, lift.top_y - 0.1), "从上廊步行返回尚在上站等待的货梯")
		var bottom_reached := false
		var saw_down := false
		synced = true
		for _i in 420:
			tick()
			synced = synced and absf(player.position.y - (lift.position.y - 0.1)) < 1.1
			saw_down = saw_down or lift.state == "down"
			if saw_down and lift.state == "bottom_wait":
				bottom_reached = true
				break
		check(saw_down and bottom_reached and synced, "货梯下降时人物同速随行，不悬空、不掉穿台面")
		check(walk_to(lift.position.x - 100.0, lift.bottom_y - 0.1), "下站真正下车并重新接回原地面路线")
		check(not player.dead and player.on_ground, "整个上下廊往返无死亡/复活或额外跳跃输入")
		await create_timer(0.20).timeout
		boot.free()
		await create_timer(0.20).timeout
	SESSION.reset_for_tests()
	print("M04_LIFT_ROUTES_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
