extends SceneTree
## 必须真窗口：拍摄倒地位移、指定字幕、角色/相机倒放和整关重建，不用 headless 图冒充验收。
const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
var game: Node2D

func _init() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://shot_loop_%s.png" % name
	root.get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("时间循环视觉验收需要真窗口")
		quit(1)
		return
	SESSION.begin_run("hard")
	change_scene_to_file("res://scenes/m01_protocol_quarantine.tscn")
	for i in 4:
		await process_frame
	game = current_scene.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	# 只隔离测试推进，实际游戏不允许瞬移；在真实路径上记录跑步、冻结和死亡。
	game.player.keys[KEY_D] = true
	for i in 80:
		game.player.step(DT)
		game._process(DT)
		await process_frame
	game.player.keys.erase(KEY_D)
	game.enemy_bullets.append({"x": game.player.position.x + 140.0, "y": game.player.position.y - 36.0,
		"vx": -240.0, "vy": 0.0, "life": 3.0})
	game.enemy_bullets.append({"x": game.player.position.x + 260.0, "y": game.player.position.y - 36.0,
		"vx": -240.0, "vy": 0.0, "life": 3.0})
	game.player.keys[MOUSE_BUTTON_RIGHT] = true
	game.player.keys[KEY_D] = true
	for i in 25:
		game._physics_process(DT)
		game.player.step(DT)
		game._process(DT)
		await process_frame
	await _shot("01_time_stopped")
	game.player.keys.clear()
	game._advance_time_charge(DT)
	for i in 10:
		await process_frame
	await _shot("01b_normal_world")
	game.player.force_death(game.player.position.x - 60.0)
	for i in 12:
		game.player.step(DT)
		game._process(DT)
		await process_frame
	await _shot("02_death_knockback")
	for i in 49:
		game.player.step(DT)
		game._process(DT)
		await process_frame
	await _shot("03_death_prompt")
	var retry := InputEventKey.new()
	retry.keycode = KEY_ENTER
	retry.pressed = true
	game._unhandled_input(retry)
	for i in 12:
		game._advance_rewind(DT)
		await process_frame
	await _shot("04_reverse_death")
	for i in 30:
		game._advance_rewind(DT)
		await process_frame
	await _shot("05_interference")
	game._advance_rewind(1.0)
	for i in 4:
		await process_frame
	game = current_scene.get_node("Game")
	game.player.auto_input = false
	await _shot("06_reset_origin")
	var start_us := Time.get_ticks_usec()
	var max_us := 0
	for i in 120:
		var tick := Time.get_ticks_usec()
		await process_frame
		max_us = maxi(max_us, Time.get_ticks_usec() - tick)
	print("LOOP_REAL_WINDOW_FRAME_AVG_MS=", float(Time.get_ticks_usec() - start_us) / 120000.0,
		" MAX_MS=", float(max_us) / 1000.0,
		" ENEMIES=", game._enemies().size(), " HISTORY=", game.attempt_timeline.frames.size())
	var valid: bool = SESSION.attempt == 2 and game.player.hp == 1 and game._enemies().size() == 20
	print("TIME_LOOP_RENDER_RESULT: ", "PASS" if valid else "FAIL")
	current_scene.free()
	SESSION.reset_for_tests()
	await create_timer(0.15).timeout
	quit(int(not valid))
