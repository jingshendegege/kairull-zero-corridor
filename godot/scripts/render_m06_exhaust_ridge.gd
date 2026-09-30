extends SceneTree
## Non-headless room review; camera fixtures are not a playthrough.
const DATA := preload("res://generated/m06_exhaust_ridge_data.gd")
const SESSION := preload("res://scripts/run_session.gd")
const OUT := "user://m06_review/"
var failed := false

func _init() -> void:
	call_deferred("_run")

func safe_floor(game: Node2D, rect: Rect2i) -> Vector2:
	var candidates: Array[Vector2] = []
	for row in range(rect.position.y + 4, rect.end.y):
		for col in range(rect.position.x + 1, rect.end.x - 1):
			if game.level.tile_at(col, row) not in ["#", "="]:
				continue
			var point := Vector2(col * 32 + 16, row * 32 - .1)
			var body := Rect2(point - Vector2(game.player.w * .5, game.player.h), Vector2(game.player.w, game.player.h))
			var clear := true
			for y in range(row - 3, row):
				clear = clear and game.level.tile_at(col, y) != "#"
			for blocker: Node2D in game._world_blockers():
				clear = clear and not blocker.body_rect().grow(8).intersects(body)
			for enemy: Node2D in game.minions:
				clear = clear and not enemy.body_rect().grow(48).intersects(body)
			for fan: Node2D in game.updraft_fans:
				clear = clear and point.distance_to(fan.position) > 64.0
			for hazard: Node2D in game.tactical_hazards:
				clear = clear and absf(point.x - hazard.position.x) > 96.0
			if clear:
				candidates.append(point)
	var center := Vector2(rect.get_center()) * 32.0
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(center) < b.distance_squared_to(center))
	return candidates[0] if not candidates.is_empty() else Vector2.INF

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("M06 review requires a non-headless renderer")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	SESSION.begin_run("easy")
	var boot: Node2D = load("res://scenes/m06_exhaust_ridge.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	var game: Node2D = boot.get_node("Game")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.auto_input = false
	game.action_audio_enabled = false
	game.action_audio.stop_all()
	var output := OUT
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output = argument.trim_prefix("--output-dir=")
	var directory := ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot create " + directory)
		quit(1)
		return
	for index in DATA.ROOMS.size():
		var rect: Rect2i = game.level.rooms[index].rect
		var point := safe_floor(game, rect)
		if point == Vector2.INF:
			push_error("No safe review floor in " + String(DATA.ROOMS[index].room_id))
			failed = true
			continue
		game.player.position = point
		game.player.vx = 0.0
		game.player.vy = 0.0
		game.player.on_ground = true
		game.player.keys.clear()
		game.player._sync_sprite()
		game._update_room_state()
		var room_size := Vector2(rect.size) * 32.0
		var zoom := minf(1.0, minf(1360.0 / (room_size.x + 32), 765.0 / (room_size.y + 32)))
		game.cam.zoom = Vector2.ONE * zoom
		game.cam.position_smoothing_enabled = false
		game.cam.position = (Vector2(rect.position) + Vector2(rect.size) * .5) * 32.0
		game.cam.limit_left = -100000
		game.cam.limit_top = -100000
		game.cam.limit_right = 100000
		game.cam.limit_bottom = 100000
		game.cam_tl = game.cam.position - Vector2(680, 382.5) / zoom
		game.cam.reset_smoothing()
		game.cam.force_update_scroll()
		# Frozen simulation still needs fresh camera projection and HUD draws for each room.
		game.bg.scale = Vector2.ONE / zoom
		game.bg._process(0.0)
		game.hud._process(0.0)
		game.hud._overlay.queue_redraw()
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join("%02d_%s.png" % [index + 1, DATA.ROOMS[index].room_id])
		var error := root.get_texture().get_image().save_png(path)
		failed = failed or error != OK
		print("M06_SCREENSHOT: ", path, " | ", "PASS" if error == OK else "FAIL", " | safe_feet=", point)
	boot.free()
	current_scene = null
	SESSION.reset_for_tests()
	await process_frame
	print("M06_RENDER_RESULT: ", "FAIL" if failed else "PASS")
	quit(int(failed))
