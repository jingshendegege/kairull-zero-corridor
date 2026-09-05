extends SceneTree
## 实体机壳/统一射线点击/持续导航/间歇屏幕故障合同；不把headless当美术验收。
const MENU := preload("res://scripts/surveillance_menu.gd")
const SESSION := preload("res://scripts/run_session.gd")
var passed := 0
var failed := 0
var starts := 0
var quits := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	SESSION.reset_for_tests()
	var menu := MENU.new()
	menu.suppress_external_actions = true
	menu.run_requested.connect(func(_difficulty: String): starts += 1)
	menu.quit_requested.connect(func(): quits += 1)
	root.add_child(menu)
	menu.set_process(false)
	check(menu.monitor_count == 1 and menu.subviewport_count == 1, "唯一真实3D CRT和唯一640×360纹理")
	check(SESSION.LEVEL_SCENES.size() == 3, "保留三关选择，不改变已完成地图")
	for index in 4:
		var monitor: Node3D = menu._monitor_nodes[0]
		var screen: MeshInstance3D = monitor.get_node("Screen")
		check(monitor.has_node("TuningKnob") and monitor.has_node("VolumeKnob")
			and monitor.has_node("ChannelNameplate"), "频道%d共用旋钮/实体铭牌" % (index + 1))
		check(screen.position.z < MENU.CASE_FACE_Z - .1, "频道%d共用真实内凹玻璃" % (index + 1))
		check(screen.material_override is ShaderMaterial, "频道%d故障仍只作用在唯一Screen网格" % (index + 1))
		menu._select_page(index, true)
		for point in [Vector2(100, 100), Vector2(320, 180), Vector2(530, 300)]:
			var screen_point: Vector2 = menu.canvas_to_screen(index, point)
			check(menu._monitor_canvas_point(index, screen_point).distance_to(point) < .02,
				"频道%d内部坐标正反投影一致" % (index + 1))
			check(menu._monitor_at_screen(screen_point) == 0, "频道%d射线始终命中唯一物理机壳" % (index + 1))
	menu._select_page(0, true)
	menu._handle_mouse_click(menu.canvas_to_screen(0, Vector2(320, 150)))
	check(starts == 0, "点击监控画面不会误开局")
	var frame_point := menu._camera.unproject_position(menu._monitor_nodes[0].to_global(Vector3(1.62, .65, .58)))
	menu._handle_mouse_click(frame_point)
	check(starts == 0 and menu.selected_page == 0, "点击当前机壳旋钮只聚焦，不触发开始")
	for index in 3:
		menu._handle_mouse_click(menu.canvas_to_screen(0, menu.level_card_rect(index).get_center()))
		check(menu.selected_level == index and starts == 0, "第%d关卡卡片完整可点且不立即开始" % (index + 1))
	menu._handle_mouse_click(menu.canvas_to_screen(0, MENU.START_BUTTON.get_center()))
	check(starts == 1 and menu.selected_level == 2, "精确开始按钮才请求进入当前第三关")
	for index in 4:
		menu._handle_mouse_click(menu._navigation.tab_rect(index).get_center())
		check(menu.selected_page == index and starts == 1 and quits == 0, "底部第%d导航标签真正可点击且只换页" % (index + 1))
	menu._select_page(1, true)
	menu._handle_mouse_click(menu.canvas_to_screen(1, MENU.difficulty_card_rect(1).get_center()))
	check(menu.selected_difficulty == "hard" and starts == 1, "困难卡使用真实屏幕坐标，不按窗口左右猜")
	menu._handle_mouse_click(menu.canvas_to_screen(1, MENU.DIFFICULTY_CONFIRM.get_center()))
	check(menu.selected_page == 0 and starts == 1, "鼠标确认难度返回开始而不进入游戏")
	menu._select_page(3, true)
	menu._handle_mouse_click(menu.canvas_to_screen(3, Vector2(320, 180)))
	check(quits == 0, "退出页装饰图也不是隐形退出按钮")
	menu._handle_mouse_click(menu.canvas_to_screen(3, MENU.EXIT_CONFIRM.get_center()))
	check(quits == 1, "只有退出确认按钮触发退出请求")
	check(menu._monitor_at_screen(Vector2(-2000, -2000)) == -1, "机壳外不会被固定250px点击框误判")

	print("== 间歇故障与回退 ==")
	var transforms: Array[Transform3D] = []
	for monitor: Node3D in menu._monitor_nodes:
		transforms.append(monitor.global_transform)
	var camera_before: Transform3D = menu._camera.global_transform
	menu.trigger_crt_fault(0, .22)
	menu._advance_crt_fault(.11)
	check(menu._fault_page == 0 and is_equal_approx(menu._fault_elapsed, .11), "短故障可在专用验收中推进到中帧")
	var affected := 0
	for material: ShaderMaterial in menu._screen_materials:
		affected += int(float(material.get_shader_parameter("fault_amount")) > 0.0)
	check(affected == 1, "一次只有一台CRT屏幕纹理发生故障")
	check(camera_before == menu._camera.global_transform, "故障没有摇动真实房间摄像机")
	var stable := true
	for index in menu._monitor_nodes.size():
		stable = stable and transforms[index] == menu._monitor_nodes[index].global_transform
	check(stable, "故障不摇动唯一实体外框")
	menu._advance_crt_fault(.20)
	check(menu._fault_page == -1 and menu._fault_wait >= 7.0 and menu._fault_wait <= 14.0,
		"短故障结束进入7～14秒安静间隔")
	check(float(menu._screen_materials[0].get_shader_parameter("fault_amount")) == 0.0, "结束后完全恢复原屏幕，不保留长残影")
	var serial_before: int = menu._fault_serial
	menu._advance_crt_fault(6.9)
	check(menu._fault_serial == serial_before, "安静期不会持续抖动或连发故障")
	menu._advance_crt_fault(7.2)
	check(menu._fault_serial == serial_before + 1 and menu._fault_duration >= .14 and menu._fault_duration <= .28,
		"超过随机间隔才触发一次0.14～0.28秒故障")
	menu.crt_faults_enabled = false
	menu._advance_crt_fault(.001)
	check(menu._fault_page == -1, "关闭开关立即清除在途故障")
	serial_before = menu._fault_serial
	menu._advance_crt_fault(100.0)
	menu.trigger_crt_fault(1)
	check(menu._fault_serial == serial_before, "关闭后经过长时间/调试触发也不会闪屏")
	menu.crt_faults_enabled = true
	menu._select_page(0, true)
	menu.trigger_crt_fault(0, .22)
	menu._advance_crt_fault(.11)
	var old_starts := starts
	menu._handle_mouse_click(menu.canvas_to_screen(0, MENU.START_BUTTON.get_center()))
	menu._handle_mouse_click(menu.canvas_to_screen(0, Vector2(320, 327)))
	check(starts == old_starts, "故障中变形按钮/边缘都不会误触开始")
	menu._handle_mouse_click(menu._navigation.tab_rect(2).get_center())
	check(menu.selected_page == 2, "故障不阻挡独立底部导航")
	menu._advance_crt_fault(.22)
	check(starts == old_starts, "故障结束不补发之前忽略的点击")
	menu._select_page(0, true)
	menu._handle_mouse_click(menu.canvas_to_screen(0, MENU.START_BUTTON.get_center()))
	check(starts == old_starts + 1, "故障结束后精确开始按钮立即恢复")
	menu._select_page(3, true)
	menu.trigger_crt_fault(3, .22)
	menu._advance_crt_fault(.10)
	var old_quits := quits
	menu._handle_mouse_click(menu.canvas_to_screen(3, MENU.EXIT_CONFIRM.get_center()))
	check(quits == old_quits, "故障中退出页也不会因热区漂移误退出")
	menu._handle_keycode(KEY_ESCAPE)
	check(menu.selected_page == 0, "故障期间键盘ESC仍可返回开始")
	menu._select_page(3, true)
	menu.crt_faults_enabled = false
	menu._advance_crt_fault(.001)
	menu._handle_mouse_click(menu.canvas_to_screen(3, MENU.EXIT_CONFIRM.get_center()))
	check(quits == old_quits + 1, "禁用故障后退出按钮立即恢复，不保留输入锁")
	menu.free()
	await process_frame
	SESSION.reset_for_tests()
	print("MENU_CRT_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
