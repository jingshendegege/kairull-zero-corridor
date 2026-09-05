extends SceneTree
## 扩展地图轻量真窗口性能采样：同一终战镜头比较正常状态与 128 枚持久血迹。
## 跑法：Godot --path godot --rendering-driver opengl3 \
##         --script scripts/benchmark_extended_campaign.gd

const SAMPLE_FRAMES := 240
const WARMUP_FRAMES := 180
const TS := 32

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("真实帧耗时必须在窗口渲染器中采样")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var player: KairullPlayer = game.player
	player.auto_input = false
	player.hp = 999
	player.position = Vector2(221 * TS + 16, 23 * TS - 0.1)
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680.0, 382.5)
	if game.minions.size() != 20:
		_failed = true
		push_error("性能样本必须包含正式 20 敌，实际=%d" % game.minions.size())

	for i in range(WARMUP_FRAMES):
		await process_frame
	var baseline_before := await _sample_frames()

	var manager: BloodWallManager = game.paint_layer.blood_wall_manager
	_spawn_visible_blood(game, 128)
	if manager == null or manager.active_count() != 128:
		_failed = true
		push_error("128 血迹压力样本创建失败：%s" %
				("null" if manager == null else str(manager.active_count())))
	for i in range(WARMUP_FRAMES):
		await process_frame
	var blood := await _sample_frames()
	# 再隐藏血迹复测正常场景，用前后均值抵消驱动升频、shader 首编译和系统抖动。
	manager.visible = false
	for i in range(WARMUP_FRAMES):
		await process_frame
	var baseline_after := await _sample_frames()
	var baseline := _average_samples(baseline_before, baseline_after)

	_print_sample("NORMAL_BEFORE", baseline_before)
	_print_sample("NORMAL_AFTER", baseline_after)
	_print_sample("NORMAL_AVERAGED_20_ENEMIES", baseline)
	_print_sample("BLOOD128_20_ENEMIES", blood)
	print("PERF_DELTA_MEAN_MS: %.3f" %
			(float(blood["wall_mean_ms"]) - float(baseline["wall_mean_ms"])))
	print("PERF_RESULT: ", "FAIL" if _failed else "PASS")

	_cleanup_audio(game)
	boot.free()
	for i in range(3):
		await process_frame
	await create_timer(0.15).timeout
	quit(1 if _failed else 0)


func _sample_frames() -> Dictionary:
	var wall_samples: Array[float] = []
	var process_sum := 0.0
	var physics_sum := 0.0
	var draw_call_sum := 0.0
	for i in range(SAMPLE_FRAMES):
		var started := Time.get_ticks_usec()
		await process_frame
		wall_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		process_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		draw_call_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	wall_samples.sort()
	var wall_sum := 0.0
	for sample in wall_samples:
		wall_sum += sample
	var p95_index := clampi(floori((wall_samples.size() - 1) * 0.95),
			0, wall_samples.size() - 1)
	return {
		"frames": SAMPLE_FRAMES,
		"wall_mean_ms": wall_sum / wall_samples.size(),
		"wall_p95_ms": wall_samples[p95_index],
		"wall_max_ms": wall_samples[-1],
		"process_mean_ms": process_sum / SAMPLE_FRAMES,
		"physics_mean_ms": physics_sum / SAMPLE_FRAMES,
		"draw_calls_mean": draw_call_sum / SAMPLE_FRAMES,
	}


func _spawn_visible_blood(game: Node2D, count: int) -> void:
	# 16×8 全落在终战房可见背墙上，确保 128 个 SCREEN_TEXTURE 材质确实进入渲染样本。
	var colors := [Color("#c01630"), Color("#ff4fa3"), Color("#43e8ff"), Color("#ffb347")]
	for index in range(count):
		var column := index % 16
		var row := index / 16
		var position := Vector2(222 * TS + 36 + column * 68,
				7 * TS + 28 + row * 55)
		var direction := Vector2(1.0 if index % 2 == 0 else -1.0,
				-0.22 + float(index % 5) * 0.11).normalized()
		game.paint_layer.spawn_wall_snapshot(position, direction, 0.48,
				index + 1, false, 0.62, colors[index % colors.size()])


func _print_sample(label: String, sample: Dictionary) -> void:
	print("PERF_%s: frames=%d wall_mean_ms=%.3f wall_p95_ms=%.3f wall_max_ms=%.3f " % [
			label, int(sample["frames"]), float(sample["wall_mean_ms"]),
			float(sample["wall_p95_ms"]), float(sample["wall_max_ms"])]
			+ "process_mean_ms=%.3f physics_mean_ms=%.3f draw_calls_mean=%.1f" % [
			float(sample["process_mean_ms"]), float(sample["physics_mean_ms"]),
			float(sample["draw_calls_mean"])])


func _average_samples(first: Dictionary, second: Dictionary) -> Dictionary:
	return {
		"frames": int(first["frames"]) + int(second["frames"]),
		"wall_mean_ms": (float(first["wall_mean_ms"]) + float(second["wall_mean_ms"])) * 0.5,
		"wall_p95_ms": (float(first["wall_p95_ms"]) + float(second["wall_p95_ms"])) * 0.5,
		"wall_max_ms": maxf(float(first["wall_max_ms"]), float(second["wall_max_ms"])),
		"process_mean_ms": (float(first["process_mean_ms"]) + float(second["process_mean_ms"])) * 0.5,
		"physics_mean_ms": (float(first["physics_mean_ms"]) + float(second["physics_mean_ms"])) * 0.5,
		"draw_calls_mean": (float(first["draw_calls_mean"]) + float(second["draw_calls_mean"])) * 0.5,
	}


func _cleanup_audio(game: Node2D) -> void:
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
