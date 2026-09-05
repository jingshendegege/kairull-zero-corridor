extends SceneTree
## 真窗口验收新 HUD：开场、正常游戏、低生命/CD、死亡和清关五种状态。
## 输出 user://hud_redesign/*.png；禁止用 headless 图像冒充视觉验收。

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("HUD 视觉验收必须使用真窗口")
		quit(1)
		return
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	game.set_physics_process(false)
	game.player.auto_input = false
	for minion: Node2D in game.minions:
		minion.process_mode = Node.PROCESS_MODE_DISABLED
	var out_dir := ProjectSettings.globalize_path("user://hud_redesign")
	DirAccess.make_dir_recursive_absolute(out_dir)
	game.player.position = game.level.spawn
	game.player.keys = {}
	for _i in range(3):
		game.player.step(1.0 / 60.0)
	game.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 0.7
	game.hud._overlay.reset_room_card()
	await _capture(out_dir, "01_intro")
	game.hud.level_start_t -= 15.0
	# 正常/低血截图移入真实检疫厅，而非只在黑色入口验收 UI 对比。
	game.player.position = Vector2(26 * 32 + 16, 28 * 32 - 0.1)
	game.player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	game._run_elapsed = 137.8
	game.hud._overlay.show_room_card("检疫货运长廊", 3, 5)
	await _capture(out_dir, "02_playing")
	game.player.hp = 1
	game.player.dash_cooldown_t = 0.75
	game.player._sync_dash_cooldown_ui()
	game.hud._overlay.reset_room_card()
	await _capture(out_dir, "03_low_hp_cooldown")
	game.player.dead = true
	game.player.set_state("death")
	game.player.frame = int(game.db.actions["hero_death"]["frames"]) - 1
	game.player._sync_sprite()
	game.player._sync_dash_cooldown_ui()
	await _capture(out_dir, "04_death")
	game.player.dead = false
	game.player.hp = 5
	game.player.set_state("gun_idle")
	game.player._sync_sprite()
	game.level_cleared = true
	game._run_elapsed = 321.2
	for minion: Node2D in game.minions:
		minion.dead = true
	for index in game.level.rooms.size():
		game._visited_rooms[index] = true
	await _capture(out_dir, "05_clear")
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
	boot.free()
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
