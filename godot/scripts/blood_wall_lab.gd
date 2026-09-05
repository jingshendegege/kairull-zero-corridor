extends Node2D
## 墙面血迹真窗口实验室：用固定明暗结构检查四向遮蔽、暗区剔除、折射和伪法线。
## 运行：godot --path godot --rendering-driver opengl3 res://scenes/tests/blood_wall_lab.tscn

const VIEW_SIZE := Vector2(1360.0, 765.0)
const WORLD_SIZE := Vector2(2048.0, 900.0)
const MODE_NAMES := [
	"完整合成", "原始 Alpha", "定向遮蔽", "暗区遮罩", "背景亮度", "背景伪法线",
	"暗墙补色范围",
]

var manager: BloodWallManager
var camera: Camera2D
var status_label: Label
var notice_label: Label
var test_angle_degrees := 0.0
var seed_counter := 7600
var _status_elapsed := 0.0


func _ready() -> void:
	_build_environment()

	# 管理器位于墙面之后、前景遮挡物之前，保持与正式游戏相同的世界层级语义。
	manager = BloodWallManager.new()
	manager.name = "BloodWallManager"
	manager.max_decals = 128
	add_child(manager)

	_build_foreground_check()
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.position = VIEW_SIZE * 0.5
	add_child(camera)
	camera.make_current()
	_build_hud()

	# 等待管理器 _ready() 完成共享快照图集加载，再生成首批样本。
	await get_tree().process_frame
	_reset_lab()
	# 自动验收仍走真实窗口；传入 `-- capture_suite` 时保存七种视图和补色 A/B 后退出。
	if OS.get_cmdline_user_args().has("capture_suite"):
		call_deferred("_capture_suite")


func _process(dt: float) -> void:
	_status_elapsed += dt
	if _status_elapsed >= 0.20:
		_status_elapsed = 0.0
		_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	var handled := true
	match key.keycode:
		KEY_0:
			manager.set_debug_mode(0)
		KEY_1:
			manager.set_debug_mode(1)
		KEY_2:
			manager.set_debug_mode(2)
		KEY_3:
			manager.set_debug_mode(3)
		KEY_4:
			manager.set_debug_mode(4)
		KEY_5:
			manager.set_debug_mode(5)
		KEY_6:
			manager.set_debug_mode(6)
		KEY_SPACE:
			_spawn_current_sample()
		KEY_ENTER:
			_spawn_cardinal_samples()
		KEY_P:
			manager.set_persistent_enabled(not manager.persistent_enabled)
		KEY_O:
			manager.occlusion_enabled = not manager.occlusion_enabled
			manager.apply_settings()
		KEY_B:
			manager.darkness_enabled = not manager.darkness_enabled
			manager.apply_settings()
		KEY_T:
			manager.refraction_enabled = not manager.refraction_enabled
			manager.apply_settings()
		KEY_L:
			manager.linear_refraction_enabled = not manager.linear_refraction_enabled
			manager.apply_settings()
		KEY_N:
			manager.normal_lighting_enabled = not manager.normal_lighting_enabled
			manager.apply_settings()
		KEY_G:
			manager.set_dark_surface_lift_enabled(not manager.dark_surface_lift_enabled)
		KEY_V:
			manager.direction_debug_enabled = not manager.direction_debug_enabled
			manager.apply_settings()
		KEY_Q:
			test_angle_degrees = wrapf(test_angle_degrees - 15.0, -180.0, 180.0)
		KEY_E:
			test_angle_degrees = wrapf(test_angle_degrees + 15.0, -180.0, 180.0)
		KEY_J:
			manager.spray_angle_offset = wrapf(
					manager.spray_angle_offset - 5.0, -180.0, 180.0)
			manager.apply_settings()
		KEY_K:
			manager.spray_angle_offset = wrapf(
					manager.spray_angle_offset + 5.0, -180.0, 180.0)
			manager.apply_settings()
		KEY_Z:
			manager.occlusion_ray_steps = maxi(1, manager.occlusion_ray_steps - 2)
			manager.apply_settings()
		KEY_X:
			manager.occlusion_ray_steps = mini(32, manager.occlusion_ray_steps + 2)
			manager.apply_settings()
		KEY_LEFT:
			_move_camera(Vector2(-32.0, 0.0))
		KEY_RIGHT:
			_move_camera(Vector2(32.0, 0.0))
		KEY_UP:
			_move_camera(Vector2(0.0, -32.0))
		KEY_DOWN:
			_move_camera(Vector2(0.0, 32.0))
		KEY_R:
			_reset_lab()
		KEY_F12:
			call_deferred("_capture_screenshot")
		_:
			handled = false

	if handled:
		get_viewport().set_input_as_handled()
		_refresh_status()


func _reset_lab() -> void:
	manager.clear_all()
	manager.persistent_enabled = true
	manager.occlusion_enabled = true
	manager.darkness_enabled = true
	manager.refraction_enabled = true
	manager.linear_refraction_enabled = true
	manager.normal_lighting_enabled = true
	manager.dark_surface_lift_enabled = true
	manager.direction_debug_enabled = false
	manager.spray_angle_offset = 0.0
	manager.occlusion_ray_steps = 12
	manager.debug_mode = 0
	manager.apply_settings()
	test_angle_degrees = 0.0
	camera.position = (VIEW_SIZE * 0.5).round()
	notice_label.text = "R 已恢复默认参数；方向键可验证血迹随世界移动。"
	_spawn_cardinal_samples()


func _spawn_cardinal_samples() -> void:
	manager.clear_all()
	# 右侧覆盖正式 M03 三种暗墙，并把六种生产血色全部放进同一张图验收。
	var samples := [
		{"position": Vector2(150.0, 260.0), "direction": Vector2.RIGHT,
				"color": Color("#43e8ff"), "seed": 7701},
		{"position": Vector2(730.0, 170.0), "direction": Vector2.RIGHT,
				"color": Color("#ff4fa3"), "seed": 7700},
		{"position": Vector2(900.0, 170.0), "direction": Vector2.DOWN,
				"color": Color("#43e8ff"), "seed": 7701},
		{"position": Vector2(1110.0, 170.0), "direction": Vector2.LEFT,
				"color": Color("#9b5cff"), "seed": 7702},
		{"position": Vector2(730.0, 430.0), "direction": Vector2.RIGHT,
				"color": Color("#ffb347"), "seed": 7703},
		{"position": Vector2(930.0, 500.0), "direction": Vector2.UP,
				"color": Color("#7dff6a"), "seed": 7704},
		{"position": Vector2(1120.0, 520.0), "direction": Vector2.LEFT,
				"color": Color("#5c8aff"), "seed": 7705},
	]
	for i in range(samples.size()):
		var sample: Dictionary = samples[i]
		manager.spawn_snapshot(sample["position"], sample["direction"], 0.48,
				int(sample["seed"]), false, 0.48, sample["color"])
	# 同一点叠两张，专门检查普通 blend_mix 下是否出现黑边或透明光晕。
	manager.spawn_snapshot(Vector2(430.0, 345.0), Vector2(1.0, -0.25),
			0.58, 7710, false, 0.42, Color("#9f142c"))
	manager.spawn_snapshot(Vector2(438.0, 351.0), Vector2(1.0, 0.18),
			0.50, 7711, false, 0.58, Color("#d72d78"))
	notice_label.text = "右侧为 M03 三层暗墙六色样本；左侧同款青色用于明暗对照。"
	_refresh_status()


func _spawn_current_sample() -> void:
	seed_counter += 1
	var direction := Vector2.RIGHT.rotated(deg_to_rad(test_angle_degrees))
	# 生成点跟随相机中心，但仍是世界坐标；移动相机后可验证不会粘在屏幕上。
	var spawn_position := (camera.position + Vector2(0.0, 26.0)).round()
	manager.spawn_snapshot(spawn_position, direction, 0.64, seed_counter,
			false, 0.50, Color("#d72d78"))
	notice_label.text = "新增测试血迹：方向 %.0f°，seed %d" % [
		test_angle_degrees, seed_counter]


func _move_camera(delta: Vector2) -> void:
	var half_view := VIEW_SIZE * 0.5
	var minimum := half_view
	var maximum := WORLD_SIZE - half_view
	camera.position = Vector2(
			clampf(camera.position.x + delta.x, minimum.x, maximum.x),
			clampf(camera.position.y + delta.y, minimum.y, maximum.y)).round()


func _capture_screenshot() -> void:
	var out_dir := ProjectSettings.globalize_path("user://blood_wall_lab")
	var dir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if dir_error != OK:
		notice_label.text = "截图目录创建失败：%s" % dir_error
		return
	# 截图只在人工验收时触发，不参与任何性能采样。
	await get_tree().process_frame
	RenderingServer.force_draw()
	var output_path := out_dir.path_join("blood_wall_%d.png" % Time.get_ticks_msec())
	var error := get_viewport().get_texture().get_image().save_png(output_path)
	if error == OK:
		notice_label.text = "截图已保存：%s" % output_path
		print("PREVIEW_PATH: ", output_path)
	else:
		notice_label.text = "截图保存失败：%s" % error


func _capture_suite() -> void:
	var out_dir := ProjectSettings.globalize_path("user://blood_wall_lab")
	var dir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if dir_error != OK:
		push_error("实验室截图目录创建失败：%s" % dir_error)
		get_tree().quit(1)
		return
	for mode in range(MODE_NAMES.size()):
		manager.set_debug_mode(mode)
		_refresh_status()
		await get_tree().process_frame
		await get_tree().process_frame
		RenderingServer.force_draw()
		var path := out_dir.path_join("mode_%d.png" % mode)
		var error := get_viewport().get_texture().get_image().save_png(path)
		if error != OK:
			push_error("实验室模式 %d 截图失败：%s" % [mode, error])
			get_tree().quit(1)
			return
	# 单独保存同一场景、同一血色的开关 A/B，便于判断补色是否过强。
	manager.set_debug_mode(0)
	manager.set_dark_surface_lift_enabled(true)
	_refresh_status()
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	var readability_on_path := out_dir.path_join("readability_on.png")
	var readability_on_error := get_viewport().get_texture().get_image().save_png(
			readability_on_path)
	if readability_on_error != OK:
		push_error("实验室暗墙补色开启截图失败：%s" % readability_on_error)
		get_tree().quit(1)
		return
	manager.set_dark_surface_lift_enabled(false)
	_refresh_status()
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	var readability_off_path := out_dir.path_join("readability_off.png")
	var readability_off_error := get_viewport().get_texture().get_image().save_png(
			readability_off_path)
	if readability_off_error != OK:
		push_error("实验室暗墙补色关闭截图失败：%s" % readability_off_error)
		get_tree().quit(1)
		return
	manager.set_dark_surface_lift_enabled(true)
	manager.set_debug_mode(0)
	manager.direction_debug_enabled = true
	manager.apply_settings()
	_refresh_status()
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	var direction_path := out_dir.path_join("direction_overlay.png")
	var direction_error := get_viewport().get_texture().get_image().save_png(direction_path)
	if direction_error != OK:
		push_error("实验室方向图截图失败：%s" % direction_error)
		get_tree().quit(1)
		return
	# 最后一张移动真实 Camera2D，验证血迹与墙体共同留在世界空间。
	manager.direction_debug_enabled = false
	manager.apply_settings()
	_move_camera(Vector2(96.0, 0.0))
	_refresh_status()
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	var camera_path := out_dir.path_join("camera_shifted.png")
	var camera_error := get_viewport().get_texture().get_image().save_png(camera_path)
	if camera_error != OK:
		push_error("实验室相机移动截图失败：%s" % camera_error)
		get_tree().quit(1)
		return
	print("RENDER_RESULT: PASS")
	print("PREVIEW_DIR: ", out_dir)
	get_tree().quit(0)


func _refresh_status() -> void:
	if manager == null or status_label == null:
		return
	var stats := manager.debug_stats()
	status_label.text = (
			"模式 %d：%s  |  生成方向 %.0f°  |  Shader 校准 %+0.0f°  |  射线 %d 步\n"
			+ "P持久=%s  G暗墙补色=%s  O遮蔽=%s  B暗区=%s  T折射=%s  L线性=%s  N法线=%s  V方向=%s"
			+ "  |  active=%d visible=%d slots=%d  |  Camera=(%.0f, %.0f)") % [
		manager.debug_mode, MODE_NAMES[manager.debug_mode], test_angle_degrees,
		manager.spray_angle_offset, manager.occlusion_ray_steps,
		_on_off(manager.persistent_enabled), _on_off(manager.dark_surface_lift_enabled),
		_on_off(manager.occlusion_enabled),
		_on_off(manager.darkness_enabled), _on_off(manager.refraction_enabled),
		_on_off(manager.linear_refraction_enabled),
		_on_off(manager.normal_lighting_enabled),
		_on_off(manager.direction_debug_enabled), int(stats["active"]),
		int(stats["visible"]), int(stats["slots"]),
		camera.position.x, camera.position.y,
	]


func _on_off(value: bool) -> String:
	return "开" if value else "关"


func _build_environment() -> void:
	var environment := Node2D.new()
	environment.name = "Environment"
	add_child(environment)
	_add_rect(environment, Vector2.ZERO, WORLD_SIZE, Color("#050914"))

	# 左侧中亮砖墙：门框、砖缝和机器亮边为定向遮蔽提供明确高度差。
	_add_rect(environment, Vector2(48.0, 92.0), Vector2(610.0, 530.0),
			Color("#35465a"))
	_add_rect(environment, Vector2(64.0, 108.0), Vector2(578.0, 498.0),
			Color("#27384b"))
	for x in range(96, 640, 64):
		_add_line(environment, Vector2(x, 108.0), Vector2(x, 606.0),
				Color(0.38, 0.52, 0.66, 0.32), 1.0)
	for y in range(140, 606, 48):
		_add_line(environment, Vector2(64.0, y), Vector2(642.0, y),
				Color(0.42, 0.57, 0.70, 0.38), 1.0)
	_add_rect(environment, Vector2(248.0, 190.0), Vector2(158.0, 266.0),
			Color("#010205"))
	_add_rect(environment, Vector2(234.0, 176.0), Vector2(14.0, 294.0),
			Color("#90a9bd"))
	_add_rect(environment, Vector2(406.0, 176.0), Vector2(14.0, 294.0),
			Color("#90a9bd"))
	_add_rect(environment, Vector2(234.0, 176.0), Vector2(186.0, 14.0),
			Color("#b7cada"))

	# 右侧暗墙刻意接近关卡暗底，同时保留纯黑空洞，便于调 darkness_threshold。
	_add_rect(environment, Vector2(702.0, 92.0), Vector2(610.0, 530.0),
			Color("#202938"))
	# 直接使用正式 M03 的 F1/F2/F3 墙色，避免实验室比游戏本体亮而漏掉问题。
	_add_rect(environment, Vector2(718.0, 108.0), Vector2(578.0, 166.0),
			Color("#1b1630"))
	_add_rect(environment, Vector2(718.0, 274.0), Vector2(578.0, 166.0),
			Color("#161d19"))
	_add_rect(environment, Vector2(718.0, 440.0), Vector2(578.0, 166.0),
			Color("#21161a"))
	for y in range(140, 606, 48):
		_add_line(environment, Vector2(718.0, y), Vector2(1296.0, y),
				Color(0.23, 0.31, 0.42, 0.42), 1.0)
	_add_rect(environment, Vector2(1000.0, 186.0), Vector2(190.0, 250.0),
			Color("#000000"))
	_add_rect(environment, Vector2(988.0, 174.0), Vector2(214.0, 12.0),
			Color("#617b91"))
	_add_rect(environment, Vector2(988.0, 174.0), Vector2(12.0, 274.0),
			Color("#4b6278"))
	_add_rect(environment, Vector2(1190.0, 174.0), Vector2(12.0, 274.0),
			Color("#4b6278"))

	var machine := Polygon2D.new()
	machine.name = "MachineSilhouette"
	machine.polygon = PackedVector2Array([
		Vector2(748.0, 548.0), Vector2(748.0, 362.0), Vector2(792.0, 330.0),
		Vector2(884.0, 330.0), Vector2(920.0, 374.0), Vector2(920.0, 548.0),
	])
	machine.color = Color("#080d16")
	environment.add_child(machine)
	_add_line(environment, Vector2(748.0, 362.0), Vector2(792.0, 330.0),
			Color("#7194ad"), 3.0)
	_add_line(environment, Vector2(792.0, 330.0), Vector2(884.0, 330.0),
			Color("#7194ad"), 3.0)

	_add_rect(environment, Vector2(0.0, 622.0), Vector2(WORLD_SIZE.x, 278.0),
			Color("#101824"))
	_add_rect(environment, Vector2(0.0, 622.0), Vector2(WORLD_SIZE.x, 12.0),
			Color("#778c9f"))


func _build_foreground_check() -> void:
	var foreground := Node2D.new()
	foreground.name = "ForegroundCheck"
	foreground.z_index = 10
	add_child(foreground)
	# 这些遮挡物在血迹之后绘制，用于确认血迹不会盖过正式前景或角色轮廓。
	_add_rect(foreground, Vector2(625.0, 118.0), Vector2(18.0, 510.0),
			Color("#090d16"))
	_add_rect(foreground, Vector2(630.0, 118.0), Vector2(4.0, 510.0),
			Color("#657b90"))
	# 短竖管直接穿过左向样本，截图中可一眼确认前景确实盖在血迹之上。
	_add_rect(foreground, Vector2(505.0, 392.0), Vector2(14.0, 126.0),
			Color("#090d16"))
	_add_rect(foreground, Vector2(508.0, 392.0), Vector2(3.0, 126.0),
			Color("#71879b"))
	_add_rect(foreground, Vector2(82.0, 548.0), Vector2(1180.0, 14.0),
			Color("#090d16"))
	_add_rect(foreground, Vector2(82.0, 548.0), Vector2(1180.0, 3.0),
			Color("#71879b"))


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 20
	add_child(hud)
	_add_rect(hud, Vector2(12.0, 10.0), Vector2(1336.0, 91.0),
			Color(0.015, 0.025, 0.05, 0.92))

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	status_label = Label.new()
	status_label.position = Vector2(24.0, 17.0)
	status_label.add_theme_font_override("font", font)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color("#d7e8f5"))
	hud.add_child(status_label)

	var help := Label.new()
	help.text = "0–6 调试视图 · G暗墙补色 · Space 新样本 · Enter 六色 · Q/E 方向 · J/K Shader角度 · Z/X 射线步数 · 方向键移动相机 · R 重置 · F12 截图"
	help.position = Vector2(24.0, 73.0)
	help.add_theme_font_override("font", font)
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color("#8faabd"))
	hud.add_child(help)

	notice_label = Label.new()
	notice_label.position = Vector2(18.0, 728.0)
	notice_label.add_theme_font_override("font", font)
	notice_label.add_theme_font_size_override("font_size", 13)
	notice_label.add_theme_color_override("font_color", Color("#ffe45c"))
	notice_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice_label.add_theme_constant_override("shadow_size", 2)
	hud.add_child(notice_label)


func _add_rect(parent: Node, at: Vector2, rect_size: Vector2,
		color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = rect_size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _add_line(parent: Node, from: Vector2, to: Vector2, color: Color,
		width: float) -> Line2D:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = width
	line.default_color = color
	line.antialiased = false
	parent.add_child(line)
	return line
