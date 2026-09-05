extends SceneTree
## 同一真窗口同相位比较备份旧实现/新缓存实现：只替换测试实例，生产文件从不还原覆盖。
const SESSION := preload("res://scripts/run_session.gd")
const BACKUP := "C:/Users/Administrator/Documents/ChatGPT/游戏制作/work/chrono-freight-before-20260905/quarantine-architecture-before-cache.gd"
const SCENES := ["m01_protocol_quarantine", "m04_chrono_freight", "m05_vertical_freight"]
var results: Array = []
var comparisons := 0
var failed := 0
var old_script: GDScript


func _init() -> void:
	call_deferred("_run")


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)


func _select(pairs: Array, old_active: bool, animate := false) -> void:
	for pair: Dictionary in pairs:
		pair.old.visible = old_active
		pair.new.visible = not old_active
		pair.old.set_process(animate and old_active and not pair.old.front_only)
		pair.new.set_process(animate and not old_active and not pair.new.front_only)
		pair.old.queue_redraw()
		pair.new.queue_redraw()


func _capture() -> Image:
	for _index in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _measure(label: String) -> void:
	for _index in 12:
		await process_frame
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for _index in 120:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var total := 0.0
	for sample in samples:
		total += sample
	samples.sort()
	var row := {"kind": "timing", "label": label, "frames": 120, "avg_ms": total / 120.0,
		"p95_ms": samples[114], "max_ms": samples[119],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	results.append(row)
	print("SEMANTIC_CACHE_AB ", JSON.stringify(row))


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("缓存画面/性能证明必须真窗口")
		quit(1)
		return
	if not FileAccess.file_exists(BACKUP):
		push_error("原版本备份不存在，禁止伪造旧版对比")
		quit(1)
		return
	var source := FileAccess.get_file_as_string(BACKUP)
	old_script = GDScript.new()
	# 只移除临时脚本的全局类注册，方法实现/所有绘制语句保持原备份逐字不变。
	old_script.source_code = source.replace("class_name QuarantineArchitecture", "")
	if old_script.reload() != OK:
		push_error("旧脚本临时实例解析失败")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = root.size
	root.title = "Semantic cache: same-pixel true-window A/B"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for scene_name: String in SCENES:
		await _compare_scene(scene_name)
	var report := FileAccess.open("user://semantic_cache_equivalence.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"old_sha256": source.sha256_text(),
		"new_sha256": FileAccess.get_file_as_string("res://scripts/quarantine_architecture.gd").sha256_text(),
		"gpu": RenderingServer.get_video_adapter_name(), "comparisons": comparisons, "failed": failed,
		"results": results}, "\t"))
	report.close()
	print("SEMANTIC_CACHE_EQUIVALENCE_RESULT: ", comparisons, " comparisons, ", failed, " failures")
	print("SEMANTIC_CACHE_REPORT ", ProjectSettings.globalize_path("user://semantic_cache_equivalence.json"))
	old_script = null
	SESSION.reset_for_tests()
	await create_timer(.2).timeout
	quit(0 if failed == 0 and comparisons == 9 else 1)


func _compare_scene(scene_name: String) -> void:
	SESSION.begin_run("hard")
	var boot := load("res://scenes/" + scene_name + ".tscn").instantiate() as Node2D
	root.add_child(boot)
	current_scene = boot
	var game := boot.get_node("Game") as Node2D
	game.player.auto_input = false
	game.action_audio_enabled = false
	game.hud.visible = false
	game._sfx.clear()
	if game.action_audio != null:
		game.action_audio.stop_all()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	var pairs: Array = []
	for child in game.get_children():
		if child is QuarantineArchitecture:
			var old: Node2D = old_script.new()
			old.name = child.name + "_BeforeCacheComparison"
			old.setup(game.level, child.semantic_layers, child.semantic_ids, child.front_only)
			game.add_child(old)
			game.move_child(old, child.get_index() + 1)
			pairs.append({"old": old, "new": child})
	_freeze(boot)
	var spots: Array[Vector2] = [game.level.spawn,
		Vector2(game.level.world_w * .5, game.level.world_h * .5), game.level.exit_point]
	if scene_name == "m05_vertical_freight":
		spots[1] = Vector2(74 * 32 + 16, 51 * 32 - .1)
	for index in spots.size():
		game.player.position = spots[index]
		game.player._sync_sprite()
		game._update_room_state()
		game.cam_tl = game._cam_target().round()
		game.cam.position = game.cam_tl + Vector2(680, 382.5)
		game.cam.reset_smoothing()
		game.cam.force_update_scroll()
		game._sync_temporal_projection()
		var fixed_phase := .713 + float(index) * .8
		for pair: Dictionary in pairs:
			pair.old._phase = fixed_phase
			pair.new._phase = fixed_phase
		_select(pairs, true)
		var before: Image = await _capture()
		_select(pairs, false)
		var after: Image = await _capture()
		var same := before.get_data() == after.get_data()
		comparisons += 1
		failed += int(not same)
		var row := {"kind": "pixels", "scene": scene_name, "spot": index,
			"camera": str(game.cam_tl), "phase": fixed_phase, "same_rgba_bytes": same}
		results.append(row)
		print("SEMANTIC_CACHE_PIXELS ", JSON.stringify(row))
		if scene_name == "m05_vertical_freight" and index == 1:
			before.save_png("user://semantic_cache_m05_before.png")
			after.save_png("user://semantic_cache_m05_after.png")
			_select(pairs, true, true)
			await _measure("M05_original_all_geometry")
			_select(pairs, false, true)
			await _measure("M05_cache_only_all_geometry")
			_select(pairs, false, false)
	boot.free()
	await create_timer(.2).timeout
