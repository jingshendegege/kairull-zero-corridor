extends SceneTree
## 真实窗口验证唯一CRT机壳/同屏四频道/三难度/三关卡/仅屏幕故障和恢复。
## 相机按位姿误差收敛后截图，不能用固定28帧冒充高帧率机器上的聚焦完成。

const MENU := preload("res://scripts/surveillance_menu.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/single-crt-checkpoint-20260906"
var _failed := false
var _checks := 0
var _paths: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	_checks += 1
	_failed = _failed or not value
	print("PASS " if value else "FAIL ", label)


func settle(menu: MENU) -> void:
	for _i in 480:
		await process_frame
		var target: Transform3D = menu._camera_targets[menu.selected_page]
		if menu._camera.global_position.distance_to(target.origin) < .003 \
				and menu._camera.global_basis.get_rotation_quaternion().angle_to(
					target.basis.get_rotation_quaternion()) < .002:
			break
	for _i in 5:
		await process_frame


func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func projected_rect(menu: MENU, page: int, case_frame := false) -> Rect2:
	var points: Array[Vector2] = []
	if case_frame:
		for x in [-MENU.CASE_FACE_SIZE.x * .5, MENU.CASE_FACE_SIZE.x * .5]:
			for y in [-MENU.CASE_FACE_SIZE.y * .5, MENU.CASE_FACE_SIZE.y * .5]:
				points.append(menu._camera.unproject_position(
					menu._monitor_nodes[0].to_global(Vector3(x, y, MENU.CASE_FACE_Z))))
	else:
		for uv in [Vector2.ZERO, Vector2(640, 0), Vector2(640, 360), Vector2(0, 360)]:
			points.append(menu.canvas_to_screen(page, uv))
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box


func save_image(stem: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(1360, 765), stem + "为1360×765真窗口")
	var path := OUT.path_join(stem + ".png")
	check(image.save_png(path) == OK, stem + "写盘成功")
	_paths.append(path)
	print("MENU_SCREENSHOT: ", path)
	return image


func run_focus_check(menu: MENU, page: int, stem: String) -> void:
	menu._select_page(page)
	await settle(menu)
	var frame := projected_rect(menu, page, true)
	var screen := projected_rect(menu, page)
	check(frame.position.x >= 10 and frame.end.x <= 1350 \
		and frame.position.y >= 66 and frame.end.y <= 655,
		stem + "完整机壳在导航之外且未裁切")
	check(screen.size.x >= 600 and screen.size.y >= 335,
		stem + "主屏正文显示尺寸不低于600×335")
	await save_image(stem)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("菜单美术必须使用真窗口")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = Vector2i(1360, 765)
	DirAccess.make_dir_recursive_absolute(OUT)
	var menu: MENU = load("res://scenes/surveillance_menu.tscn").instantiate()
	menu.suppress_external_actions = true
	menu.crt_faults_enabled = false
	root.add_child(menu)
	for _i in 20:
		await process_frame
	check(menu.monitor_count == 1 and menu.subviewport_count == 1, "只存在一台真实CRT和一个SubViewport")
	if "--controls-only" in OS.get_cmdline_user_args():
		await run_focus_check(menu, MENU.PAGE_CONTROLS, "05-操作频道-检查点续行说明")
		menu.free()
		await process_frame
		quit(int(_failed))
		return

	var original_case_id: int = menu._monitor_nodes[0].get_instance_id()
	var original_canvas_id: int = menu._screen_canvases[0].get_instance_id()
	await run_focus_check(menu, MENU.PAGE_START, "01-单台电视-开始频道")
	menu._set_level(2)
	await wait_seconds(.10)
	await save_image("02-同屏选择第三关")
	menu._select_page(MENU.PAGE_DIFFICULTY)
	await wait_seconds(.12)
	await save_image("03-同一外框-频道切换中")
	await settle(menu)
	menu._set_difficulty("easy")
	await run_focus_check(menu, MENU.PAGE_DIFFICULTY, "04-三档难度-简单5血")
	menu._set_difficulty("hard")
	await wait_seconds(.10)
	await save_image("04b-三档难度-困难3血")
	menu._set_difficulty("zero")
	await wait_seconds(.10)
	await save_image("04c-三档难度-武士零1血")
	await run_focus_check(menu, MENU.PAGE_CONTROLS, "05-操作频道-检查点续行说明")
	await run_focus_check(menu, MENU.PAGE_EXIT, "06-退出频道-同一机壳")
	check(menu._monitor_nodes[0].get_instance_id() == original_case_id \
		and menu._screen_canvases[0].get_instance_id() == original_canvas_id,
		"四频道始终复用原机壳/画布，没有切换隐藏电视")

	# 总览是巡检取景，生产菜单仍从开始电视聚焦进入。
	menu.set_process(false)
	menu._camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 7.7)).looking_at(
		Vector3(0, 2.25, .30), Vector3.UP)
	for _i in 8:
		await process_frame
	await save_image("07-唯一实体电视总览")
	menu._select_page(0, true)
	menu.set_process(true)
	await settle(menu)
	await wait_seconds(.35)
	menu.set_process(false)
	for canvas: Control in menu._screen_canvases:
		canvas.set_process(false)
	for _i in 5:
		await process_frame
	var camera_before: Transform3D = menu._camera.global_transform
	var clean := await save_image("08-故障前稳定画面")
	menu.crt_faults_enabled = true
	menu.trigger_crt_fault(0, .22)
	menu._advance_crt_fault(.11)
	var faulty := await save_image("09-偶发屏幕失步与局部雪花")
	var allowed := projected_rect(menu, 0).grow(3)
	var inside_changed := 0
	var outside_changed := 0
	for y in range(0, 765, 3):
		for x in range(0, 1360, 3):
			if clean.get_pixel(x, y) != faulty.get_pixel(x, y):
				if allowed.has_point(Vector2(x, y)):
					inside_changed += 1
				else:
					outside_changed += 1
	check(inside_changed > 100, "实际GPU屏幕画面发生失步/撕裂")
	check(outside_changed == 0, "故障没有改变机壳、房间或持续导航像素")
	check(camera_before == menu._camera.global_transform, "故障期间相机完全不抖")
	menu._advance_crt_fault(.30)
	var restored := await save_image("10-故障结束完全恢复")
	check(clean.get_data() == restored.get_data(), "故障恢复帧与故障前逐像素一致")
	print("MENU_FAULT_DIFF: inside=", inside_changed, " outside=", outside_changed)
	var report := FileAccess.open(OUT.path_join("真窗口验收记录.txt"), FileAccess.WRITE)
	if report:
		report.store_string("Single CRT / four channels / 5-3-1 difficulty true-window review\n" + Engine.get_version_info()["string"] \
			+ "\nGPU: " + RenderingServer.get_video_adapter_name() \
			+ "\n1360x765 / one real CRT + one SubViewport\n" \
			+ "Fault pixel samples: inside=%d outside=%d\n" % [inside_changed, outside_changed] \
			+ "故障测试固定相机/普通CRT动画，仅推进生产故障参数；恢复帧逐像素比较。\n" \
			+ "\n".join(_paths) + "\n")
		report.close()
	menu.free()
	for _i in 4:
		await process_frame
	print("MENU_CRT_RENDER_RESULT: ", "FAIL" if _failed else "PASS", " checks=", _checks)
	quit(int(_failed))
