extends SceneTree
## 只在临时真窗测试实例做A/B开关，不修改生产场景、材质资源或地图文件。
## 使用与M05静态巡检相同的冻结宿主配置；CPU/GPU帧间隔不是headless代替值。
const SESSION := preload("res://scripts/run_session.gd")
var game: Node2D
var boot: Node2D
var results: Array = []


func _init() -> void:
	call_deferred("_run")


func _measure(label: String, frame_count := 90) -> void:
	for _index in 12:
		await process_frame
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var cpu_total := 0.0
	var previous := Time.get_ticks_usec()
	for _index in frame_count:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
		cpu_total += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var total := 0.0
	for value in samples:
		total += value
	samples.sort()
	var row := {"label": label, "frames": frame_count, "avg_ms": total / frame_count,
		"p95_ms": samples[int(floor(frame_count * .95))], "max_ms": samples.back(),
		"cpu_process_ms": cpu_total / frame_count,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}
	results.append(row)
	print("VERTICAL_COMPONENT_AB ", JSON.stringify(row))


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("性能A/B必须真窗口，不可headless")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = root.size
	root.title = "M05 Components A/B - temporary QA instance"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	SESSION.begin_run("hard")
	boot = load("res://scenes/m05_vertical_freight.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	game = boot.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.hud.visible = false
	game.action_audio_enabled = false
	if game.action_audio != null:
		game.action_audio.stop_all()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	game.player.position = Vector2(74 * 32 + 16, 51 * 32 - .1)
	game.player.on_ground = true
	game.player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	game.cam.reset_smoothing()
	game._sync_temporal_projection()
	var architecture: Node2D = game.quarantine_architecture
	var architecture_source := FileAccess.get_file_as_string("res://scripts/quarantine_architecture.gd")
	var layers: Dictionary = architecture.semantic_layers
	var layer_sizes: Dictionary = {}
	for key: String in layers:
		layer_sizes[key] = layers[key].size()
	print("VERTICAL_COMPONENT_META ", JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(),
		"architecture_sha256": architecture_source.sha256_text(), "semantic_counts": layer_sizes,
		"rooms": game.level.rooms.size(), "enemies": game.minions.size(), "view": str(game.cam_tl)}))
	await _measure("01_baseline_static")
	architecture.set_process(false)
	await _measure("02_architecture_cached_visible")
	architecture.visible = false
	await _measure("03_architecture_hidden")
	architecture.visible = true
	architecture.set_process(true)
	game.bg.visible = false
	game.bg.set_process(false)
	await _measure("04_background_disabled")
	game.bg.visible = true
	game.bg.set_process(true)
	var front: Node2D
	for child in game.get_children():
		if child is QuarantineArchitecture and child.front_only:
			front = child
	if front != null:
		front.visible = false
		await _measure("05_foreground_hidden")
		front.visible = true
	for enemy: Node2D in game.minions:
		enemy.visible = false
	await _measure("06_enemy_sprites_hidden")
	for enemy: Node2D in game.minions:
		enemy.visible = true
	await _measure("07_baseline_recheck")
	# 冻结宿主已排除了这段逻辑；单独计200次，只定位动态战斗潜在额外成本。
	var begin_us := Time.get_ticks_usec()
	for _index in 200:
		game._refresh_smoke_cover()
	print("VERTICAL_SMOKE_REFRESH_US_PER_CALL ", float(Time.get_ticks_usec() - begin_us) / 200.0)
	var source_layers := layers.duplicate(true)
	var source_rooms: Array = game.level.rooms.duplicate(true)
	var view := Rect2(game.cam_tl, Vector2(1360, 765)).grow(192.0)
	# 只剪临时实例的数据，用于估计viewport方案收益；不能当作已实现的生产裁剪。
	var visible_rooms: Array = []
	for room: Dictionary in source_rooms:
		var rect: Rect2i = room.rect
		if view.intersects(Rect2(Vector2(rect.position * 32), Vector2(rect.size * 32))):
			visible_rooms.append(room)
	game.level.rooms = visible_rooms
	for key: String in layers:
		var retained: Array = []
		for triple in layers[key]:
			if view.has_point(Vector2(float(triple[0]) * 32, float(triple[1]) * 32)):
				retained.append(triple)
		layers[key] = retained
	architecture.setup(game.level, layers, architecture.semantic_ids, false)
	await _measure("08_instance_viewport_subset_estimate")
	game.level.rooms = source_rooms
	architecture.setup(game.level, source_layers, architecture.semantic_ids, false)
	var report := FileAccess.open("user://benchmark_vertical_components.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(results, "\t"))
	report.close()
	print("VERTICAL_COMPONENT_REPORT ", ProjectSettings.globalize_path("user://benchmark_vertical_components.json"))
	boot.free()
	SESSION.reset_for_tests()
	await create_timer(.2).timeout
	quit(0)
