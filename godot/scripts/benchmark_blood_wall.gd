extends SceneTree
## 墙面血迹真窗口性能基准。按真实时间采样，使整轮在不同显卡上尽量稳定在 30–45 秒。
## 运行时必须使用 opengl3、关闭 VSync，禁止 headless 与 fixed-fps。

const VIEW_SIZE := Vector2(1360.0, 765.0)
const WARMUP_MSEC := 300
const SAMPLE_MSEC := 2200
const MAX_DECALS := 128

# 冷/热空场、数量阶梯、重叠/离屏和主要 shader 分支均独立测量。
const SCENARIOS := [
	{"name": "baseline_cold", "count": 0, "layout": "none"},
	{"name": "spread_32", "count": 32, "layout": "spread"},
	{"name": "spread_64", "count": 64, "layout": "spread"},
	{"name": "spread_128", "count": 128, "layout": "spread"},
	{"name": "baseline_warm_pool", "count": 0, "layout": "none"},
	{"name": "overlap_128", "count": 128, "layout": "overlap"},
	{"name": "overlap_no_dark_lift", "count": 128, "layout": "overlap",
			"dark_lift": false},
	{"name": "offscreen_128", "count": 128, "layout": "offscreen"},
	{"name": "raw_alpha_128", "count": 128, "layout": "overlap",
			"debug_mode": 1, "occlusion": false, "darkness": false,
			"refraction": false, "normal": false},
	{"name": "overlap_no_occlusion", "count": 128, "layout": "overlap",
			"occlusion": false},
	{"name": "overlap_no_refraction", "count": 128, "layout": "overlap",
			"refraction": false},
	{"name": "overlap_no_normal", "count": 128, "layout": "overlap",
			"normal": false},
	{"name": "overlap_steps_4", "count": 128, "layout": "overlap", "steps": 4},
	{"name": "overlap_steps_8", "count": 128, "layout": "overlap", "steps": 8},
	{"name": "overlap_steps_16", "count": 128, "layout": "overlap", "steps": 16},
	{"name": "overlap_steps_32", "count": 128, "layout": "overlap", "steps": 32},
]

var manager: BloodWallManager
var viewport_rid: RID
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_scene()
	# 管理器在 _ready() 中加载共享图集；先让资源和首帧渲染稳定下来。
	for _i in range(3):
		await process_frame

	viewport_rid = get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var started_msec := Time.get_ticks_msec()
	var results: Array[Dictionary] = []
	for scenario_index in range(SCENARIOS.size()):
		var scenario: Dictionary = SCENARIOS[scenario_index]
		var row: Dictionary = await _run_scenario(scenario)
		results.append(row)
		print(("BENCH_CASE: %s frames=%d wall_p50=%.3fms wall_p95=%.3fms "
				+ "gpu_p50=%.3fms draws_p50=%.1f active=%d slots=%d") % [
			row["name"], row["sample_frames"], row["wall_frame_ms"]["p50"],
			row["wall_frame_ms"]["p95"], row["render_gpu_ms"]["p50"],
			row["canvas_draw_calls"]["p50"], row["manager"]["active"],
			row["manager"]["slots"],
		])
		if scenario_index == 0:
			# 冷空场测完后预分配全部槽；后续数量对照共享相同节点/材质高水位。
			_prewarm_full_pool()

	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	var elapsed_seconds := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report := {
		"schema": 1,
		"generated_at": Time.get_datetime_string_from_system(true),
		"elapsed_seconds": elapsed_seconds,
		"warmup_msec_per_case": WARMUP_MSEC,
		"sample_msec_per_case": SAMPLE_MSEC,
		"godot": Engine.get_version_info(),
		"platform": OS.get_name(),
		"processor": OS.get_processor_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"adapter_api": RenderingServer.get_video_adapter_api_version(),
		"structural_failures": failures,
		"scenarios": results,
	}
	var report_path := _write_report(report)
	var passed := failures.is_empty() and not report_path.is_empty()
	print("BENCH_DURATION_SECONDS: %.2f" % elapsed_seconds)
	if not failures.is_empty():
		for failure in failures:
			print("BENCH_FAIL: ", failure)
	print("BENCH_RESULT: ", "PASS" if passed else "FAIL")
	print("REPORT_PATH: ", report_path)
	quit(0 if passed else 1)


func _run_scenario(scenario: Dictionary) -> Dictionary:
	manager.clear_all()
	manager.persistent_enabled = true
	manager.debug_mode = int(scenario.get("debug_mode", 0))
	manager.occlusion_enabled = bool(scenario.get("occlusion", true))
	manager.darkness_enabled = bool(scenario.get("darkness", true))
	manager.refraction_enabled = bool(scenario.get("refraction", true))
	manager.linear_refraction_enabled = true
	manager.normal_lighting_enabled = bool(scenario.get("normal", true))
	manager.dark_surface_lift_enabled = bool(scenario.get("dark_lift", true))
	manager.occlusion_ray_steps = int(scenario.get("steps", 12))
	manager.direction_debug_enabled = false
	manager.apply_settings()

	var count := int(scenario["count"])
	_spawn_layout(String(scenario["layout"]), count)
	var stats := _compact_manager_stats(manager.debug_stats())
	_validate_structure(String(scenario["name"]), count, stats)

	var warmup_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - warmup_started < WARMUP_MSEC:
		await process_frame
	var samples: Dictionary = await _sample_for_msec(SAMPLE_MSEC)
	samples["name"] = String(scenario["name"])
	samples["layout"] = String(scenario["layout"])
	samples["requested_decals"] = count
	samples["debug_mode"] = manager.debug_mode
	samples["occlusion_enabled"] = manager.occlusion_enabled
	samples["darkness_enabled"] = manager.darkness_enabled
	samples["refraction_enabled"] = manager.refraction_enabled
	samples["normal_lighting_enabled"] = manager.normal_lighting_enabled
	samples["dark_surface_lift_enabled"] = manager.dark_surface_lift_enabled
	samples["dark_surface_lift_strength"] = manager.dark_surface_lift_strength
	samples["dark_surface_lift_start"] = manager.dark_surface_lift_start
	samples["dark_surface_lift_end"] = manager.dark_surface_lift_end
	samples["occlusion_ray_steps"] = manager.occlusion_ray_steps
	samples["manager"] = stats
	samples["video_memory_bytes"] = int(Performance.get_monitor(
			Performance.RENDER_VIDEO_MEM_USED))
	samples["fps_monitor"] = Performance.get_monitor(Performance.TIME_FPS)
	return samples


func _sample_for_msec(duration_msec: int) -> Dictionary:
	var wall_frame: Array[float] = []
	var process_time: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var draw_calls: Array[float] = []
	var objects: Array[float] = []
	var sampling_started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - sampling_started < duration_msec:
		var frame_started := Time.get_ticks_usec()
		await process_frame
		wall_frame.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
		process_time.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(
				viewport_rid))
		var gpu_time := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		if gpu_time > 0.0:
			render_gpu.append(gpu_time)
		draw_calls.append(float(RenderingServer.viewport_get_render_info(
				viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		objects.append(float(RenderingServer.viewport_get_render_info(
				viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
				RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
	return {
		"sample_frames": wall_frame.size(),
		"wall_frame_ms": _summary(wall_frame),
		"process_ms": _summary(process_time),
		"render_cpu_ms": _summary(render_cpu),
		"render_gpu_ms": _summary(render_gpu),
		"gpu_measurement_available": not render_gpu.is_empty(),
		"canvas_draw_calls": _summary(draw_calls),
		"canvas_objects": _summary(objects),
	}


func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"samples": 0, "mean": 0.0, "min": 0.0, "p50": 0.0,
				"p95": 0.0, "max": 0.0}
	var sorted: Array[float] = []
	sorted.assign(values)
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	var p50_index := clampi(ceili(float(sorted.size()) * 0.50) - 1,
			0, sorted.size() - 1)
	var p95_index := clampi(ceili(float(sorted.size()) * 0.95) - 1,
			0, sorted.size() - 1)
	return {
		"samples": sorted.size(),
		"mean": total / float(sorted.size()),
		"min": sorted.front(),
		"p50": sorted[p50_index],
		"p95": sorted[p95_index],
		"max": sorted.back(),
	}


func _spawn_layout(layout: String, count: int) -> void:
	for i in range(count):
		var world_position: Vector2
		var power := 0.45
		match layout:
			"spread":
				var column := i % 16
				var row := floori(float(i) / 16.0)
				world_position = Vector2(78.0 + column * 80.0, 116.0 + row * 70.0)
			"overlap":
				# 避开中央纯黑门洞，否则暗区剔除会让最坏 overdraw 失真。
				world_position = Vector2(330.0, 390.0)
				power = 0.75
			"offscreen":
				var column := i % 16
				var row := floori(float(i) / 16.0)
				world_position = Vector2(-6000.0 + column * 80.0,
						-6000.0 + row * 70.0)
			_:
				return
		var direction := Vector2.RIGHT.rotated(float(i % 8) * TAU / 8.0)
		manager.spawn_snapshot(world_position, direction, power, 9000 + i,
				false, 0.5, Color("#c01630"))


func _prewarm_full_pool() -> void:
	manager.clear_all()
	manager.persistent_enabled = true
	manager.debug_mode = 0
	manager.occlusion_enabled = true
	manager.darkness_enabled = true
	manager.refraction_enabled = true
	manager.normal_lighting_enabled = true
	manager.dark_surface_lift_enabled = true
	manager.occlusion_ray_steps = 12
	manager.apply_settings()
	# 离屏预分配不会把额外 overdraw 混入冷空场结果。
	_spawn_layout("offscreen", MAX_DECALS)
	manager.clear_all()


func _compact_manager_stats(raw: Dictionary) -> Dictionary:
	var material_rids: Array = raw.get("material_rids", [])
	var unique_rids := {}
	for material_rid in material_rids:
		unique_rids[material_rid] = true
	return {
		"active": int(raw.get("active", -1)),
		"visible": int(raw.get("visible", -1)),
		"slots": int(raw.get("slots", -1)),
		"max_decals": int(raw.get("max_decals", -1)),
		"serial": int(raw.get("serial", -1)),
		"material_rid_count": material_rids.size(),
		"unique_material_rid_count": unique_rids.size(),
	}


func _validate_structure(case_name: String, expected_active: int,
		stats: Dictionary) -> void:
	if int(stats["active"]) != expected_active:
		failures.append("%s active=%s expected=%s" % [
			case_name, stats["active"], expected_active])
	if int(stats["visible"]) != expected_active:
		failures.append("%s visible=%s expected=%s" % [
			case_name, stats["visible"], expected_active])
	if int(stats["slots"]) > MAX_DECALS:
		failures.append("%s slots 超过 %d：%s" % [
			case_name, MAX_DECALS, stats["slots"]])
	if int(stats["material_rid_count"]) != int(stats["slots"]):
		failures.append("%s 材质 RID 数与槽位数不一致" % case_name)
	if int(stats["unique_material_rid_count"]) != int(stats["slots"]):
		failures.append("%s 存在共享 ShaderMaterial，参数会串槽" % case_name)


func _write_report(report: Dictionary) -> String:
	var out_dir := ProjectSettings.globalize_path("user://blood_wall_benchmark")
	var dir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if dir_error != OK:
		failures.append("报告目录创建失败：%s" % dir_error)
		return ""
	var report_path := out_dir.path_join("report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		failures.append("报告文件打开失败：%s" % FileAccess.get_open_error())
		return ""
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	return report_path


func _build_scene() -> void:
	var environment := Node2D.new()
	environment.name = "BenchmarkEnvironment"
	get_root().add_child(environment)
	_add_rect(environment, Vector2.ZERO, VIEW_SIZE, Color("#050914"))
	_add_rect(environment, Vector2(36.0, 72.0), Vector2(1288.0, 594.0),
			Color("#27384b"))
	for x in range(68, 1324, 64):
		_add_line(environment, Vector2(x, 72.0), Vector2(x, 666.0),
				Color(0.38, 0.52, 0.66, 0.32))
	for y in range(104, 666, 48):
		_add_line(environment, Vector2(36.0, y), Vector2(1324.0, y),
				Color(0.42, 0.57, 0.70, 0.38))
	_add_rect(environment, Vector2(540.0, 210.0), Vector2(280.0, 330.0),
			Color("#020307"))
	_add_rect(environment, Vector2(524.0, 194.0), Vector2(16.0, 362.0),
			Color("#91aabd"))
	_add_rect(environment, Vector2(820.0, 194.0), Vector2(16.0, 362.0),
			Color("#91aabd"))
	_add_rect(environment, Vector2(524.0, 194.0), Vector2(312.0, 16.0),
			Color("#b8cad8"))

	manager = BloodWallManager.new()
	manager.name = "BloodWallManager"
	manager.max_decals = MAX_DECALS
	get_root().add_child(manager)

	var benchmark_camera := Camera2D.new()
	benchmark_camera.position = VIEW_SIZE * 0.5
	get_root().add_child(benchmark_camera)
	benchmark_camera.make_current()


func _add_rect(parent: Node, at: Vector2, rect_size: Vector2,
		color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = rect_size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


func _add_line(parent: Node, from: Vector2, to: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 1.0
	line.default_color = color
	line.antialiased = false
	parent.add_child(line)
