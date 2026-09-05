extends SceneTree
## 纯UI fixture只收信号，不切实际game；runtime暂停/计时冻结由控制器专项验证。
const UI := preload("res://scripts/pause_menu.gd")
var passed := 0
var failed := 0
var resumes := 0
var retries := 0
var menus := 0
var ui: UI


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func key(code: Key, pressed := true, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	ui.handle_input(event)


func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	ui.handle_input(event)


func click(point: Vector2) -> void:
	mouse(point, true)
	mouse(point, false)


func context(checkpoint := false, difficulty := "easy") -> Dictionary:
	return {"difficulty": difficulty, "checkpoint": "中部安全枢纽", "has_checkpoint": checkpoint,
		"level_title": "03 垂直货运井"}


func _run() -> void:
	var host := Node2D.new()
	host.position = Vector2(127, 256)
	root.add_child(host)
	ui = UI.new()
	ui.host = host
	ui.resume_requested.connect(func(): resumes += 1)
	ui.retry_requested.connect(func(): retries += 1)
	ui.menu_requested.connect(func(): menus += 1)
	host.add_child(ui)
	check(not ui.menu_open and not ui.visible, "未打开时UI不挡游戏")
	check(ui.process_mode == Node.PROCESS_MODE_ALWAYS and ui.layer > 80, "暂停树时可处理UI，并盖住通关层")
	check(ui._surface.mouse_filter == Control.MOUSE_FILTER_STOP, "全屏点击屏障阻挡透传")
	var code := FileAccess.get_file_as_string("res://scripts/pause_menu.gd")
	check(not code.contains("func _input(") and not code.contains("func _unhandled_input(")
		and not code.contains("func _gui_input("), "只由controller显式转发，没有重复自动输入入口")
	var initial := context()
	ui.show_menu(initial)
	initial["level_title"] = "外部随后修改"
	check(ui.menu_open and ui.visible and ui.selected_index == 0, "打开默认选中继续游戏")
	check(ui.level_title() == "03 垂直货运井", "context复制后保持本次暂停信息稳定")
	check(ui.button_label(1) == "从入口重试" and ui.checkpoint_name() == "关卡入口", "无检查点时准确提示入口，不误用旧名称")
	check(ui.difficulty() == "easy", "难度上下文正确")
	key(KEY_DOWN)
	check(ui.selected_index == 1, "向下选择重试")
	key(KEY_DOWN, true, true)
	check(ui.selected_index == 1, "keydown echo不重复移动")
	key(KEY_UP)
	check(ui.selected_index == 0, "向上回继续")
	key(KEY_W)
	check(ui.selected_index == 3, "W循环选择新增难度项")
	key(KEY_S)
	check(ui.selected_index == 0, "S循环选择下一项")
	key(KEY_DOWN, false)
	check(ui.selected_index == 0, "松键不触发选择")
	key(KEY_ENTER)
	check(resumes == 1 and ui.menu_open, "继续只发信号，不自行伪造恢复runtime")
	key(KEY_ENTER)
	check(resumes == 1, "等待controller处理期间不重复发继续")
	ui.hide_menu()
	key(KEY_ENTER)
	check(not ui.menu_open and not ui.visible and resumes == 1, "隐藏后不响应事件")

	ui.show_menu(context(true, "hard"))
	check(ui.button_label(1) == "从检查点重试" and ui.checkpoint_name() == "中部安全枢纽"
		and ui.difficulty() == "hard", "有记录点时显示正确重试点和难度")
	key(KEY_DOWN)
	key(KEY_ENTER)
	check(ui.confirmation_action == "retry" and ui.confirmation_choice == 0 and retries == 0,
		"重试先确认且默认取消，不立即丢进度")
	key(KEY_ENTER)
	check(ui.confirmation_action.is_empty() and retries == 0, "默认Enter选择取消")
	key(KEY_ENTER)
	key(KEY_ESCAPE)
	check(ui.menu_open and ui.confirmation_action == "retry" and resumes == 1,
		"Esc在UI完全不处理，由controller直接原地继续")
	key(KEY_RIGHT)
	check(ui.confirmation_choice == 1, "明确选择确认重试")
	key(KEY_ENTER)
	key(KEY_ENTER)
	check(retries == 1, "确认重试只发一次信号")

	ui.show_menu(context(true, "zero"))
	key(KEY_DOWN)
	key(KEY_DOWN)
	key(KEY_ENTER)
	check(ui.confirmation_action == "menu" and menus == 0, "返回主菜单也必须二次确认")
	key(KEY_S)
	key(KEY_ENTER)
	check(menus == 1, "确认后只发返回主菜单信号，不退出系统")
	check(host.position == Vector2(127, 256) and not paused and is_equal_approx(Engine.time_scale, 1.0),
		"纯UI未改宿主位置、暂停状态或全局时间")

	ui.show_menu(context())
	mouse(ui.button_rect(0).get_center(), true)
	check(resumes == 1, "鼠标按下只选择，不在按下时恢复游戏")
	mouse(Vector2(10, 10), false)
	check(resumes == 1, "拖出按钮后抬起取消点击")
	mouse(Vector2(10, 10), true)
	mouse(ui.button_rect(0).get_center(), false)
	check(resumes == 1, "从背景按下再移入按钮不会误继续")
	click(ui.button_rect(0).get_center())
	check(resumes == 2, "在同一个明确按钮内按下抬起才继续")
	ui.show_menu(context(true))
	click(ui.button_rect(1).get_center())
	check(ui.confirmation_action == "retry" and retries == 1, "鼠标重试按钮先展示确认")
	click(ui.confirm_button_rect(1).get_center())
	check(retries == 2, "鼠标明确确认后才请求重试")
	ui.show_menu(context(true))
	click(ui.button_rect(2).get_center())
	click(ui.confirm_button_rect(0).get_center())
	check(ui.confirmation_action.is_empty() and menus == 1, "鼠标取消不清检查点、不返回菜单")
	var before := Vector3(resumes, retries, menus)
	click(Vector2(1, 1))
	click(ui.panel_rect().position + Vector2(20, 80))
	check(Vector3(resumes, retries, menus) == before, "背景和正文点击没有隐形动作热区")
	mouse(ui.button_rect(1).get_center(), true)
	ui.show_menu(context(false))
	mouse(ui.button_rect(1).get_center(), false)
	check(ui.confirmation_action.is_empty(), "重开UI清除之前鼠标按下，不能跨上下文误确认")
	ui.show_menu(context(true))
	click(ui.button_rect(1).get_center())
	ui.hide_menu()
	check(ui.confirmation_action.is_empty() and not ui.menu_open, "hide清除确认页和待处理状态")
	host.free()
	await process_frame
	print("PAUSE_MENU_UI_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
