extends SceneTree
## 单台CRT四频道/三难度/显式确认：无头只验逻辑，外框连续性另由真窗口验证。
const SESSION := preload("res://scripts/run_session.gd")
const MENU := preload("res://scripts/surveillance_menu.gd")
var _pass := 0
var _fail := 0
var _run_requests: Array[String] = []
var _quit_requests := 0


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String) -> void:
	_pass += int(condition)
	_fail += int(not condition)
	print("PASS " if condition else "FAIL ", label)


func _run() -> void:
	var menu: MENU = load("res://scenes/surveillance_menu.tscn").instantiate()
	menu.suppress_external_actions = true
	menu.run_requested.connect(func(mode: String): _run_requests.append(mode))
	menu.quit_requested.connect(func(): _quit_requests += 1)
	root.add_child(menu)
	for _i in 4:
		await process_frame
	ok(menu.monitor_count == 1 and menu._monitor_nodes.size() == 1, "只有一个实体CRT，不是把其他电视藏起来")
	ok(menu.subviewport_count == 1 and menu._screen_canvases.size() == 1, "四频道共用一个SubViewport")
	ok(menu._camera is Camera3D and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "真实Camera3D及系统指针保留")
	var case_id: int = menu._monitor_nodes[0].get_instance_id()
	var screen_id: int = menu._monitor_nodes[0].get_node("Screen").get_instance_id()
	var canvas_id: int = menu._screen_canvases[0].get_instance_id()
	var case_transform: Transform3D = menu._monitor_nodes[0].global_transform
	for page in 4:
		menu._select_page(page, true)
		ok(menu._screen_canvases[0].page == page and menu._screen_canvases[0].focused, "频道%d内容和标题在同一画布切换" % (page + 1))
		ok(menu._monitor_nodes[0].get_instance_id() == case_id \
			and menu._monitor_nodes[0].get_node("Screen").get_instance_id() == screen_id \
			and menu._screen_canvases[0].get_instance_id() == canvas_id \
			and menu._monitor_nodes[0].global_transform == case_transform, "频道%d切换不替换或移动实体外框" % (page + 1))
	var micro_only := menu._camera_targets.size() == 4
	for target: Transform3D in menu._camera_targets:
		micro_only = micro_only and target.origin.distance_to(menu._camera_targets[0].origin) < .06
	ok(micro_only, "频道只做厘米级微聚焦，不横跨多台电视")
	menu._select_page(0, true)
	var before: Vector3 = menu._camera.global_position
	menu._select_page(1)
	await process_frame
	var full: float = before.distance_to(menu._camera_targets[1].origin)
	var step: float = before.distance_to(menu._camera.global_position)
	ok(step > 0 and step < full, "轻微聚焦仍平滑，而非硬切机位")

	ok(SESSION.DIFFICULTIES == ["easy", "hard", "zero"], "共享三难度协议完整")
	ok(SESSION.health_for_difficulty("easy") == 5 and SESSION.health_for_difficulty("hard") == 3 \
		and SESSION.health_for_difficulty("zero") == 1, "简单5血/困难3血/武士零1血来自Session")
	menu._set_difficulty("easy")
	menu._select_page(1, true)
	menu._handle_keycode(KEY_DOWN)
	ok(menu.selected_difficulty == "hard", "向下从简单进入困难3血")
	menu._handle_keycode(KEY_DOWN)
	ok(menu.selected_difficulty == "zero", "再向下进入武士零1血")
	menu._handle_keycode(KEY_DOWN)
	ok(menu.selected_difficulty == "easy", "向下三档循环回简单")
	menu._handle_keycode(KEY_UP)
	ok(menu.selected_difficulty == "zero", "向上也循环，简单上一档为武士零")
	menu._activate_page()
	ok(menu.selected_page == 0 and _run_requests.is_empty(), "确认武士零难度只返回开始，不自动开局")
	menu._activate_page()
	ok(_run_requests == ["zero"], "明确开始才发送zero")
	for mode in ["hard", "easy"]:
		menu._select_page(1, true)
		menu._set_difficulty(mode)
		menu._activate_page()
		menu._activate_page()
	ok(_run_requests == ["zero", "hard", "easy"], "三个难度使用同一个明确开始入口")
	for index in 3:
		menu._select_page(1, true)
		menu._handle_mouse_click(menu.canvas_to_screen(1, MENU.difficulty_card_rect(index).get_center()))
		ok(menu.selected_difficulty == SESSION.DIFFICULTIES[index] and _run_requests.size() == 3, "难度卡%d只改变选择" % (index + 1))
	menu._handle_mouse_click(menu.canvas_to_screen(1, MENU.DIFFICULTY_CONFIRM.get_center()))
	ok(menu.selected_page == 0 and _run_requests.size() == 3, "鼠标确认难度也不跳过开始")
	menu._handle_mouse_click(menu._navigation.tab_rect(2).get_center())
	ok(menu.selected_page == 2 and menu._monitor_nodes.size() == 1, "点击操作导航只切唯一屏幕的内容")
	menu._handle_mouse_click(menu.canvas_to_screen(2, MENU.CONTROLS_RETURN.get_center()))
	ok(menu.selected_page == 0, "同一屏幕的返回按钮准确可点")
	menu._handle_keycode(KEY_ESCAPE)
	ok(menu.selected_page == 3 and _quit_requests == 0, "ESC先进入退出频道，不立即退出")
	menu._handle_mouse_click(menu.canvas_to_screen(3, MENU.EXIT_CONFIRM.get_center()))
	ok(_quit_requests == 1, "明确退出按钮才发送退出请求")
	menu.free()
	for _i in 4:
		await process_frame
	SESSION.reset_for_tests()
	print("SINGLE_CRT_MENU_RESULT: %d PASS / %d FAIL" % [_pass, _fail])
	quit(int(_fail > 0))
