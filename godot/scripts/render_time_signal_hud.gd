extends SceneTree
## 真窗口观感验收：正式场景固定时停/耗尽/倒地/等待/短倒带/花屏状态；不以截图推断物理正确。
## 输出 user://time_signal_hud/*.png，脚本只改变本次测试实例，不写项目资源。

const SESSION := preload("res://scripts/run_session.gd")
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("时停HUD观感验收必须使用真窗口")
		quit(1)
		return
	SESSION.begin_run("hard")
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	if game.get("player") == null:
		push_error("正式Game未就绪，停止视觉验收以免留下空测试窗口")
		boot.free()
		SESSION.reset_for_tests()
		quit(1)
		return
	game.set_physics_process(false)
	game.set_process(false) # 宿主回溯由真实时钟_process驱动；固定截图状态须一并暂停。
	game.player.auto_input = false
	for minion: Node2D in game.minions:
		minion.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.position = Vector2(26 * 32 + 16, 28 * 32 - 0.1)
	game.player.keys = {}
	game.player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	game.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 0.7
	game.hud._overlay.reset_room_card()
	var out_dir := ProjectSettings.globalize_path("user://time_signal_hud")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _capture(out_dir, "01_hard_intro")
	game.hud.level_start_t -= 15.0
	game.time_charge.energy = 1.2
	game.time_charge.active = true
	await _capture(out_dir, "02_time_stopped")
	game.time_charge.active = false
	game.time_charge.energy = 0.0
	game.time_charge.lockout = 1.2
	await _capture(out_dir, "03_exhausted")
	game.time_phase = "dying"
	game.player.dead = true
	game.player.hp = 0
	game.player.set_state("death")
	game.player.frame = int(game.db.actions["hero_death"]["frames"]) - 1
	game.player._sync_sprite()
	# 与逻辑层同一API：等待提示不得只靠测试专用表现开关伪造。
	game._death_elapsed = 0.4
	game._death_prompt_ready = false
	await _capture(out_dir, "04_fallen_before_prompt")
	game._death_elapsed = 1.1
	game._death_prompt_ready = true
	await _capture(out_dir, "05_death_waiting")
	game.time_phase = "rewinding"
	game.rewind_progress = 0.46
	await _capture(out_dir, "06_rewind")
	game.time_phase = "interference"
	game.glitch_progress = 0.46
	await _capture(out_dir, "06b_interference")
	game.time_phase = "playing"
	game.player.dead = false
	game.player.configure_max_health(5)
	game.player.set_state("gun_idle")
	game.player._sync_sprite()
	game.time_charge.reset()
	SESSION.difficulty = "easy"
	game.level_cleared = true
	await _capture(out_dir, "07_clear_easy")
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
	boot.free()
	SESSION.reset_for_tests()
	await process_frame
	print("RENDER_RESULT: ", "FAIL" if _failed else "PASS")
	print("PREVIEW_DIR: ", out_dir)
	quit(1 if _failed else 0)


func _capture(out_dir: String, name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var path := out_dir.path_join(name + ".png")
	var error := get_root().get_texture().get_image().save_png(path)
	_failed = _failed or error != OK
	print("SHOT: ", path, " err=", error)
