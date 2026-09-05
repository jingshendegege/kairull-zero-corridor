class_name SurveillanceMenu
extends Node3D
## 单台工业CRT开始菜单：四频道都在同一玻璃屏内切换，实体外框始终保留。
## 只创建一个SubViewport，不实例化Game，避免污染关卡静态状态。

signal run_requested(difficulty: String)
signal quit_requested

const SESSION := preload("res://scripts/run_session.gd")
const CRT_SHADER := preload("res://shaders/menu_crt_fault.gdshader")

const PAGE_START := 0
const PAGE_DIFFICULTY := 1
const PAGE_CONTROLS := 2
const PAGE_EXIT := 3
const PAGE_COUNT := 4
const SCREEN_SIZE := Vector2i(640, 360)
const START_BUTTON := Rect2(178, 286, 284, 47)
const DIFFICULTY_CONFIRM := Rect2(130, 291, 380, 42)
const CONTROLS_RETURN := Rect2(444, 326, 172, 27)
const EXIT_CONFIRM := Rect2(132, 281, 376, 47)
const CASE_FACE_SIZE := Vector2(3.82, 2.40)
const CASE_FACE_Z := 0.58

@export var suppress_external_actions := false
@export var crt_faults_enabled := true
@export_range(0.0, 1.0, 0.01) var crt_fault_strength := 0.46
@export_range(7.0, 14.0, 0.1) var crt_fault_interval_min := 7.0
@export_range(7.0, 14.0, 0.1) var crt_fault_interval_max := 14.0
@export_range(0.14, 0.28, 0.01) var crt_fault_duration_min := 0.14
@export_range(0.14, 0.28, 0.01) var crt_fault_duration_max := 0.24
@export var crt_fault_seed := 9306

var selected_page := PAGE_START
var selected_difficulty := "easy"
var selected_level := 0
var monitor_count := 0
var subviewport_count := 0
var camera_motion_distance := 0.0

var _camera: Camera3D
var _monitor_nodes: Array[Node3D] = []
var _screen_canvases: Array[Control] = []
var _screen_materials: Array[ShaderMaterial] = []
var _status_lights: Array[OmniLight3D] = []
var _led_materials: Array[StandardMaterial3D] = []
var _camera_targets: Array[Transform3D] = []
var _hovered_page := -1
var _difficulty_notice_time := 0.0
var _transition_serial := 0
var _navigation: MenuGuide
var _fault_rng := RandomNumberGenerator.new()
var _fault_wait := 9.0
var _fault_elapsed := 0.0
var _fault_duration := 0.20
var _fault_page := -1
var _fault_serial := 0


class MenuGuide extends Control:
	## 独立于CRT故障的持续导航；屏幕内文字变形时也不会失去操作提示。
	var menu: Node3D
	var font: SystemFont
	const TITLES := ["01  开始", "02  难度", "03  操作", "04  退出"]
	const ACCENTS := [Color("#55dcd5"), Color("#e7bc78"), Color("#91d1a4"), Color("#e89196")]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
		font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
		set_process(false)

	func tab_rect(index: int) -> Rect2:
		var view := get_viewport_rect().size
		return Rect2(view.x * .5 - 310.0 + index * 158.0, view.y - 104.0, 146.0, 34.0)

	func tab_at(point: Vector2) -> int:
		for index in 4:
			if tab_rect(index).has_point(point):
				return index
		return -1

	func _draw() -> void:
		if font == null or menu == null:
			return
		var view := get_viewport_rect().size
		draw_string(font, Vector2(34, 41), "凯露尔 · 零号回廊", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#c9d5ce"))
		draw_string(font, Vector2(35, 62), "监控接入  /  SURVEILLANCE ARCHIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#829393"))
		var context: String = SESSION.LEVEL_NAMES[menu.selected_level] + "  ·  " + SESSION.name_for_difficulty(menu.selected_difficulty) \
			+ " / %d HP" % SESSION.health_for_difficulty(menu.selected_difficulty)
		var context_w := font.get_string_size(context, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(view.x - context_w - 34, 39), context, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a7b4ac"))
		for index in 4:
			var rect := tab_rect(index)
			var active: bool = index == menu.selected_page
			draw_rect(rect, Color("#18242a") if active else Color("#0d151bcc"))
			draw_line(rect.position + Vector2(0, rect.size.y - 1), rect.end,
				ACCENTS[index] if active else Color("#405157"), 2.0 if active else 1.0)
			var text_w := font.get_string_size(TITLES[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(font, rect.position + Vector2((rect.size.x - text_w) * .5, 23), TITLES[index],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENTS[index] if active else Color("#92a2a3"))
		var hints := [
			"A/D 或 ←→ 换频道    ↑↓ 选择关卡    ENTER 开始    鼠标点击明确按钮",
			"A/D 换频道    ↑↓ 循环选择三档难度    ENTER 确认并返回（不会开局）",
			"A/D 换频道    ENTER / ESC 返回开始    游戏内 Esc 暂停 / 再按原地继续",
			"A/D 换频道    ENTER 确认退出    ESC 返回开始"]
		var hint: String = hints[menu.selected_page]
		var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2((view.x - hint_w) * .5, view.y - 36), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#b1c0bb"))


class MonitorCanvas extends Control:
	## 唯一640×360画布保持同一资源，只更新频道内容，再贴回同一3D屏幕。
	var page := 0
	var focused := false
	var hovered := false
	var difficulty := "easy"
	var level_choice := 0
	var elapsed := 0.0
	var notice_time := 0.0
	var font: SystemFont

	const INK := Color("#071116")
	const PAPER := Color("#d8f3ee")
	const MUTED := Color("#66898b")
	const CYAN := Color("#35d5d2")
	const AMBER := Color("#e4a94e")
	const RED := Color("#e15468")
	const GREEN := Color("#78d5a3")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
		font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]

	func _process(delta: float) -> void:
		elapsed += delta
		notice_time = maxf(0.0, notice_time - delta)
		queue_redraw()

	func _draw() -> void:
		var accent := _accent()
		draw_rect(Rect2(Vector2.ZERO, size), INK)
		_draw_camera_grid(accent)
		_draw_header(accent)
		match page:
			PAGE_START:
				_draw_start(accent)
			PAGE_DIFFICULTY:
				_draw_difficulty(accent)
			PAGE_CONTROLS:
				_draw_controls(accent)
			PAGE_EXIT:
				_draw_exit(accent)
		_draw_scanlines(accent)

	func _accent() -> Color:
		match page:
			PAGE_DIFFICULTY:
				return AMBER
			PAGE_CONTROLS:
				return GREEN
			PAGE_EXIT:
				return RED
			_:
				return CYAN

	func _draw_camera_grid(accent: Color) -> void:
		for x in range(0, int(size.x), 40):
			draw_line(Vector2(x, 45), Vector2(x, size.y), Color(accent, 0.035), 1.0)
		for y in range(45, int(size.y), 32):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(accent, 0.035), 1.0)
		# 日常只保留很弱扫光；明显故障由屏幕材质间歇触发，不能让菜单一直像坏信号。
		var sweep_y := 50.0 + fposmod(elapsed * 43.0 + page * 71.0, 286.0)
		draw_rect(Rect2(0, sweep_y, size.x, 4), Color(accent, 0.010))

	func _draw_header(accent: Color) -> void:
		draw_rect(Rect2(0, 0, size.x, 45), Color("#0d1b20"))
		draw_rect(Rect2(0, 43, size.x, 2), Color(accent, 0.65 if focused else 0.23))
		var rec_alpha := 1.0 if fmod(elapsed, 1.0) < 0.62 else 0.28
		draw_circle(Vector2(23, 21), 5, Color(RED, rec_alpha))
		_text(Vector2(36, 28), "REC", 15, PAPER)
		_text(Vector2(92, 27), "K-00 / SURVEILLANCE", 13, MUTED)
		_text(Vector2(354, 27), "CH %02d/04 · A/D" % (page + 1), 12, MUTED)
		var frames := int(fposmod(elapsed * 24.0, 24.0))
		var seconds := int(elapsed) % 60
		var minutes := (int(elapsed) / 60) % 60
		var code := "00:%02d:%02d:%02d" % [minutes, seconds, frames]
		_text(Vector2(498, 27), code, 13, accent)

	func _draw_start(accent: Color) -> void:
		# 监控画面只画关卡剪影，不加载正式 Game/Boot。
		var feed := Rect2(28, 63, 584, 205)
		draw_rect(feed, Color("#07151a"))
		draw_rect(Rect2(feed.position, Vector2(feed.size.x, 3)), Color(accent, 0.42))
		for i in range(6):
			var x := feed.position.x + i * 104.0
			draw_rect(Rect2(x, 83, 88, 112), Color("#10272c"))
			draw_line(Vector2(x + 8, 101), Vector2(x + 80, 101), Color("#24464b"), 2)
			draw_line(Vector2(x + 44, 105), Vector2(x + 44, 188), Color("#1b3940"), 2)
		# 维护步道和地板被画成有功能层次的监控剪影。
		draw_rect(Rect2(28, 194, 584, 12), Color("#29464b"))
		for x in range(34, 606, 28):
			draw_line(Vector2(x, 197), Vector2(x + 10, 203), Color("#5b7775"), 2)
		draw_rect(Rect2(28, 235, 584, 22), Color("#17282d"))
		for x in range(36, 606, 42):
			draw_rect(Rect2(x, 242, 18, 4), Color("#315159"))
		# 白发角色与敌对传感点仅作动态剪影，防止菜单改写关卡状态。
		var bob := roundf(sin(elapsed * 2.3) * 2.0)
		var hero := Vector2(324, 225 + bob)
		draw_circle(hero + Vector2(0, -27), 9, Color("#eef5f0"))
		draw_colored_polygon(PackedVector2Array([
			hero + Vector2(-12, -18), hero + Vector2(11, -18),
			hero + Vector2(8, 1), hero + Vector2(-8, 1)]), Color("#c9ebe8"))
		draw_line(hero + Vector2(9, -12), hero + Vector2(28, -20), AMBER, 5)
		for enemy_x in [124.0, 458.0, 548.0]:
			draw_circle(Vector2(enemy_x, 226), 10, Color("#111c22"))
			draw_circle(Vector2(enemy_x, 213), 3, Color(RED, 0.85))
		_text(Vector2(42, 86), "CAM / " + SESSION.LEVEL_NAMES[level_choice], 15, PAPER)
		_text(Vector2(430, 86), "SIGNAL  87%", 12, accent)
		# 三张关卡卡片都在开始频道内；切关卡和切频道是两套明确导航。
		for index in SESSION.LEVEL_SCENES.size():
			var card := Rect2(38 + index * 188, 219, 176, 43)
			var chosen := index == level_choice
			draw_rect(card, Color("#122830") if chosen else Color("#09191f"))
			draw_rect(card, Color(accent, 0.9 if chosen else 0.3), false, 2)
			_text(card.position + Vector2(8, 27), SESSION.LEVEL_NAMES[index], 15, PAPER if chosen else MUTED)
		var button := START_BUTTON
		draw_rect(button, Color(accent, 0.18 if focused else 0.08))
		draw_rect(button, Color(accent, 0.95 if focused else 0.35), false, 3)
		_text(Vector2(246, 318), "开始行动  /  ENTER", 19, PAPER if focused else MUTED)
		_text(Vector2(28, 350), "↑↓ 选择关卡  /  当前协议：%s · %d HP" % [
			SESSION.name_for_difficulty(difficulty), SESSION.health_for_difficulty(difficulty)], 12, accent)

	func _draw_difficulty(accent: Color) -> void:
		_text(Vector2(30, 76), "生存协议 / DIFFICULTY", 20, PAPER)
		_text(Vector2(30, 98), "上下键或点击选择；确认难度不会直接开局", 12, MUTED)
		var details := ["5格生命，容错宽松", "3格生命，稳扎稳打", "1格生命，一击倒下"]
		var colors := [GREEN, AMBER, RED]
		for index in SESSION.DIFFICULTIES.size():
			var mode: String = SESSION.DIFFICULTIES[index]
			_draw_difficulty_card(SurveillanceMenu.difficulty_card_rect(index), mode,
				SESSION.name_for_difficulty(mode), "生命 %02d" % SESSION.health_for_difficulty(mode),
				details[index], colors[index])
		var locked := "已确认 · 返回开始屏" if notice_time > 0.0 else "确认难度并返回 / ENTER"
		draw_rect(DIFFICULTY_CONFIRM, Color(accent, .10))
		draw_rect(DIFFICULTY_CONFIRM, Color(accent, .66), false, 2)
		var width := font.get_string_size(locked, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_text(Vector2(DIFFICULTY_CONFIRM.get_center().x - width * .5, 318), locked, 15, PAPER)
		_text(Vector2(30, 344), "当前选择：%s / %d HP" % [SESSION.name_for_difficulty(difficulty),
			SESSION.health_for_difficulty(difficulty)], 13, PAPER)

	func _draw_difficulty_card(rect: Rect2, mode: String, title: String,
			hp: String, detail: String, color: Color) -> void:
		var selected := difficulty == mode
		draw_rect(rect, Color("#0d1b20"))
		draw_rect(rect, Color(color, 0.95 if selected else 0.22), false, 4 if selected else 2)
		if selected:
			draw_rect(Rect2(rect.position + Vector2(8, 8), Vector2(6, rect.size.y - 16)), color)
		_text(rect.position + Vector2(24, 38), title, 23, PAPER if selected else MUTED)
		_text(rect.position + Vector2(24, 77), hp, 20, color)
		_text(rect.position + Vector2(22, 111), detail, 11, PAPER if selected else MUTED)
		_text(rect.position + Vector2(24, 137), "● 已选" if selected else "○ 待命", 12, color if selected else MUTED)

	func _draw_controls(accent: Color) -> void:
		_text(Vector2(30, 76), "操作归档 / CONTROL TAPE", 20, PAPER)
		_text(Vector2(30, 99), "纯球棒近战协议 · 无枪械 · 无滑铲", 12, accent)
		var rows := [
			["A / D", "移动"], ["W", "跳跃"], ["左键", "挥棒 / 击飞货箱"],
			["CTRL", "翻滚"], ["SHIFT", "冲刺 · 1.5 秒冷却"], ["双击 S", "下穿单向平台"],
			["RMB / 右键", "时间操控"], ["R + 左键", "按住R瞄准，左键投烟"]]
		for i in range(rows.size()):
			var y := 116.0 + i * 27.0
			var row_color := CYAN if i == rows.size() - 1 else accent
			draw_rect(Rect2(32, y, 112, 22), Color(row_color, 0.14))
			draw_rect(Rect2(32, y, 112, 22), Color(row_color, 0.58), false, 2)
			_text(Vector2(42, y + 16), rows[i][0], 12, PAPER)
			_text(Vector2(158, y + 17), rows[i][1], 13,
					PAPER if i == rows.size() - 1 else MUTED)

		# 右侧改成独立时停卡，关键容量与时间域关系不能埋在普通键位说明里。
		var chrono_card := Rect2(374, 116, 238, 166)
		draw_rect(chrono_card, Color("#08161b"))
		draw_rect(chrono_card, Color(CYAN, 0.72), false, 3)
		draw_rect(Rect2(chrono_card.position + Vector2(3, 3), Vector2(232, 27)), Color(CYAN, 0.10))
		_text(Vector2(390, 137), "RMB / 右键按住", 14, PAPER)
		_text(Vector2(506, 137), "CHRONO", 11, CYAN)
		var gauge_center := Vector2(421, 210)
		draw_circle(gauge_center, 34, Color("#0b2228"))
		draw_arc(gauge_center, 31, -PI * 0.5, PI * 1.5, 48, Color(CYAN, 0.90), 4)
		draw_arc(gauge_center, 24, -PI * 0.5, PI * 0.9, 36, Color(accent, 0.42), 2)
		_text(Vector2(402, 216), "2.0s", 15, PAPER)
		_text(Vector2(470, 179), "世界动态暂停", 14, PAPER)
		_text(Vector2(470, 207), "主角速度 × 55%", 12, CYAN)
		_text(Vector2(470, 234), "完整复充 5 秒", 12, AMBER)
		_text(Vector2(470, 259), "耗尽后松开再启动", 10, MUTED)
		_text(Vector2(32, 344), "Esc 暂停 / 再按原地继续", 12, accent)
		# 短倒带后重建场景，已激活中段检查点的续行状态由正式游戏宿主恢复。
		_text(Vector2(386, 301), "倒地后 · 任意新按键短倒带", 12, PAPER)
		_text(Vector2(386, 320), "中段检查点后从检查点续行", 12, MUTED)
		draw_rect(CONTROLS_RETURN, Color(accent, .08))
		draw_rect(CONTROLS_RETURN, Color(accent, .48), false, 1)
		_text(Vector2(464, 345), "返回开始 / ESC", 12, accent)

	func _draw_exit(accent: Color) -> void:
		_text(Vector2(30, 78), "断开监控链路 / EXIT", 20, PAPER)
		var center := Vector2(320, 185)
		for radius in [96.0, 73.0, 48.0]:
			draw_arc(center, radius, 0.0, TAU, 48, Color(accent, 0.18 + radius / 500.0), 3)
		var pulse := 0.55 + sin(elapsed * 3.2) * 0.2
		draw_circle(center, 17, Color(accent, pulse))
		draw_line(center + Vector2(0, -49), center + Vector2(0, -9), PAPER, 6)
		draw_rect(EXIT_CONFIRM, Color(accent, .12))
		draw_rect(EXIT_CONFIRM, Color(accent, .72), false, 2)
		_text(Vector2(198, 310), "确认断开 / ENTER", 18, accent)
		_text(Vector2(206, 337), "ESC 返回开始监控", 12, MUTED)

	func _draw_scanlines(accent: Color) -> void:
		# 扫描线只做低透明叠色，不能切断微软雅黑的细横画。
		for y in range(0, int(size.y), 4):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.055), 1)
		for y in range(2, int(size.y), 16):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(accent, 0.009), 1)
		var border := Color(_accent(), 0.88 if focused else (0.45 if hovered else 0.18))
		draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), border, false, 3)

	func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
		draw_string(font, at.round(), value, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, color)


func _ready() -> void:
	# 正式关卡会隐藏鼠标；从关卡返回监控室时必须主动恢复指针。
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	selected_difficulty = _normalized_difficulty(String(SESSION.difficulty))
	selected_level = clampi(SESSION.start_level, 0, SESSION.LEVEL_SCENES.size() - 1)
	_build_dark_room()
	_build_camera()
	_build_monitors()
	var guide_layer := CanvasLayer.new()
	guide_layer.name = "MenuNavigationLayer"
	guide_layer.layer = 15
	add_child(guide_layer)
	_navigation = MenuGuide.new()
	_navigation.name = "PersistentGuide"
	_navigation.menu = self
	guide_layer.add_child(_navigation)
	_fault_rng.seed = crt_fault_seed
	_fault_wait = _next_fault_interval()
	_select_page(PAGE_START, true)
	set_process_input(true)


func _process(delta: float) -> void:
	if _camera == null or _camera_targets.is_empty():
		return
	var before := _camera.global_position
	var desired := _camera_targets[selected_page]
	var weight := 1.0 - exp(-delta * 5.8)
	_camera.global_transform = _camera.global_transform.interpolate_with(desired, weight)
	camera_motion_distance += before.distance_to(_camera.global_position)
	_difficulty_notice_time = maxf(0.0, _difficulty_notice_time - delta)
	_update_focus_lighting(delta)
	_advance_crt_fault(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# 确认可能立即切场景并移走菜单；必须先消费输入，不能切完再取旧viewport。
		get_viewport().set_input_as_handled()
		_handle_keycode(event.keycode)
	elif event is InputEventMouseMotion:
		_hovered_page = _monitor_at_screen(event.position)
		_sync_canvas_state()
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move_page(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move_page(1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_mouse_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_select_page(PAGE_START)


func _handle_keycode(keycode: Key) -> void:
	match keycode:
		KEY_LEFT, KEY_A:
			_move_page(-1)
		KEY_RIGHT, KEY_D:
			_move_page(1)
		KEY_UP, KEY_W:
			if selected_page == PAGE_DIFFICULTY:
				_move_difficulty(-1)
			elif selected_page == PAGE_START:
				_set_level(posmod(selected_level - 1, SESSION.LEVEL_SCENES.size()))
		KEY_DOWN, KEY_S:
			if selected_page == PAGE_DIFFICULTY:
				_move_difficulty(1)
			elif selected_page == PAGE_START:
				_set_level(posmod(selected_level + 1, SESSION.LEVEL_SCENES.size()))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_page()
		KEY_ESCAPE:
			if selected_page == PAGE_START:
				_select_page(PAGE_EXIT)
			else:
				_select_page(PAGE_START)


func _move_page(delta: int) -> void:
	_select_page(posmod(selected_page + delta, PAGE_COUNT))


func _select_page(index: int, instant := false) -> void:
	selected_page = clampi(index, 0, PAGE_COUNT - 1)
	_transition_serial += 1
	_sync_canvas_state()
	if instant and not _camera_targets.is_empty():
		_camera.global_transform = _camera_targets[selected_page]


func _activate_page() -> void:
	match selected_page:
		PAGE_START:
			_request_run()
		PAGE_DIFFICULTY:
			# 难度确认只返回开始屏，绝不在此处开始游戏。
			_difficulty_notice_time = 0.9
			for canvas: MonitorCanvas in _screen_canvases:
				canvas.notice_time = 0.9
			_select_page(PAGE_START)
		PAGE_CONTROLS:
			_select_page(PAGE_START)
		PAGE_EXIT:
			_request_quit()


func _set_difficulty(mode: String) -> void:
	selected_difficulty = _normalized_difficulty(mode)
	_sync_canvas_state()


func _move_difficulty(delta: int) -> void:
	var index: int = SESSION.DIFFICULTIES.find(selected_difficulty)
	_set_difficulty(SESSION.DIFFICULTIES[posmod(index + delta, SESSION.DIFFICULTIES.size())])


func _set_level(index: int) -> void:
	selected_level = clampi(index, 0, SESSION.LEVEL_SCENES.size() - 1)
	SESSION.start_level = selected_level
	_sync_canvas_state()


func _request_run() -> void:
	run_requested.emit(selected_difficulty)
	if suppress_external_actions:
		return
	SESSION.begin_run(selected_difficulty)
	SESSION.start_level = selected_level
	var error := get_tree().change_scene_to_file(SESSION.selected_scene())
	if error != OK:
		push_error("无法进入所选关卡：%s" % error_string(error))


func _request_quit() -> void:
	quit_requested.emit()
	if not suppress_external_actions:
		get_tree().quit()


func _handle_mouse_click(screen_position: Vector2) -> void:
	if _navigation != null:
		var tab := _navigation.tab_at(screen_position)
		if tab >= 0:
			_select_page(tab)
			return
	var hit := _monitor_at_screen(screen_position)
	if hit < 0:
		return
	# 失步时画面UV与按钮原坐标短暂分离；不排队、不猜GPU噪声逆映射，忽略本台屏内鼠标。
	# 最长0.28秒后自然恢复；底部导航先处理、键盘也仍响应，避免卡住菜单。
	if _fault_page == hit:
		return
	var canvas_point := _monitor_canvas_point(hit, screen_position)
	# 点击机壳只聚焦，不透过边框激活按钮；空白屏幕也不等价于开始/退出。
	if not Rect2(Vector2.ZERO, Vector2(SCREEN_SIZE)).has_point(canvas_point):
		return
	if selected_page == PAGE_DIFFICULTY:
		for index in SESSION.DIFFICULTIES.size():
			if difficulty_card_rect(index).has_point(canvas_point):
				_set_difficulty(SESSION.DIFFICULTIES[index])
				return
		if DIFFICULTY_CONFIRM.has_point(canvas_point):
			_activate_page()
	elif selected_page == PAGE_START:
		for index in SESSION.LEVEL_SCENES.size():
			if level_card_rect(index).has_point(canvas_point):
				_set_level(index)
				return
		if START_BUTTON.has_point(canvas_point):
			_activate_page()
	elif selected_page == PAGE_CONTROLS and CONTROLS_RETURN.has_point(canvas_point):
		_activate_page()
	elif selected_page == PAGE_EXIT and EXIT_CONFIRM.has_point(canvas_point):
		_activate_page()


static func level_card_rect(index: int) -> Rect2:
	return Rect2(38 + index * 188, 219, 176, 43)


static func difficulty_card_rect(index: int) -> Rect2:
	return Rect2(30 + index * 196, 118, 188, 156)


func canvas_to_screen(_page: int, point: Vector2) -> Vector2:
	# 统一真实平面正/反投影入口，测试与点击逻辑不另维护一份近似屏幕坐标。
	var screen: MeshInstance3D = _monitor_nodes[0].get_node("Screen")
	var dimensions: Vector2 = (screen.mesh as QuadMesh).size
	return _camera.unproject_position(screen.to_global(Vector3(
		(point.x / SCREEN_SIZE.x - .5) * dimensions.x,
		(.5 - point.y / SCREEN_SIZE.y) * dimensions.y, 0.0)))


func _monitor_canvas_point(_page: int, screen_position: Vector2) -> Vector2:
	# 用真实3D屏幕平面反投影，避免相机焦距/窗口大小变化后卡片点击跑偏。
	var screen: MeshInstance3D = _monitor_nodes[0].get_node("Screen")
	var inverse := screen.global_transform.affine_inverse()
	var origin := inverse * _camera.project_ray_origin(screen_position)
	var ray := inverse.basis * _camera.project_ray_normal(screen_position)
	if absf(ray.z) < 0.000001:
		return Vector2(INF, INF)
	var distance := -origin.z / ray.z
	if distance <= 0.0:
		return Vector2(INF, INF)
	var local := origin + ray * distance
	var size: Vector2 = (screen.mesh as QuadMesh).size
	return Vector2((local.x / size.x + 0.5) * SCREEN_SIZE.x, (0.5 - local.y / size.y) * SCREEN_SIZE.y)


func _monitor_at_screen(screen_position: Vector2) -> int:
	if _camera == null:
		return -1
	var best := -1
	var best_distance := INF
	for index in range(_monitor_nodes.size()):
		var monitor: Node3D = _monitor_nodes[index]
		if _camera.is_position_behind(monitor.global_position):
			continue
		var inverse := monitor.global_transform.affine_inverse()
		var ray_origin := inverse * _camera.project_ray_origin(screen_position)
		var ray_direction := inverse.basis * _camera.project_ray_normal(screen_position)
		if absf(ray_direction.z) < .000001:
			continue
		var ray_t := (CASE_FACE_Z - ray_origin.z) / ray_direction.z
		if ray_t <= 0.0:
			continue
		var local_hit := ray_origin + ray_direction * ray_t
		if absf(local_hit.x) > CASE_FACE_SIZE.x * .5 or absf(local_hit.y) > CASE_FACE_SIZE.y * .5:
			continue
		var distance := _camera.global_position.distance_squared_to(monitor.to_global(local_hit))
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func _normalized_difficulty(mode: String) -> String:
	return SESSION.normalize_difficulty(mode)


func _sync_canvas_state() -> void:
	if _navigation != null:
		_navigation.queue_redraw()
	for index in range(_screen_canvases.size()):
		var canvas: MonitorCanvas = _screen_canvases[index]
		canvas.page = selected_page
		canvas.focused = true
		canvas.hovered = index == _hovered_page
		canvas.difficulty = selected_difficulty
		canvas.level_choice = selected_level
		canvas.notice_time = maxf(canvas.notice_time, _difficulty_notice_time)
		canvas.queue_redraw()


func _update_focus_lighting(delta: float) -> void:
	var weight := 1.0 - exp(-delta * 7.0)
	for index in range(_screen_materials.size()):
		var energy := 1.02
		var gain := float(_screen_materials[index].get_shader_parameter("focus_gain"))
		_screen_materials[index].set_shader_parameter("focus_gain", lerpf(gain, energy, weight))
		_status_lights[index].light_energy = lerpf(_status_lights[index].light_energy,
				0.72, weight)
		var accent: Color = MenuGuide.ACCENTS[selected_page]
		_status_lights[index].light_color = _status_lights[index].light_color.lerp(accent, weight)
		_led_materials[index].emission = _led_materials[index].emission.lerp(accent, weight)
		_led_materials[index].emission_energy_multiplier = lerpf(
				_led_materials[index].emission_energy_multiplier, 2.6, weight)


func _next_fault_interval() -> float:
	var low := clampf(crt_fault_interval_min, 7.0, 14.0)
	return _fault_rng.randf_range(low, clampf(crt_fault_interval_max, low, 14.0))


func trigger_crt_fault(_page := -1, duration := -1.0) -> void:
	# 专用验收入口同样服从开关；一次只污染一台屏幕，不修改Camera/机壳/导航。
	if not crt_faults_enabled or crt_fault_strength <= 0.0 or _screen_materials.is_empty():
		return
	_clear_crt_fault()
	_fault_page = 0 # 永远作用于唯一物理屏幕；_page只为旧调试调用保留形参兼容。
	_fault_serial += 1
	_fault_elapsed = 0.0
	var low := clampf(crt_fault_duration_min, .14, .28)
	var high := clampf(crt_fault_duration_max, low, .28)
	_fault_duration = _fault_rng.randf_range(low, high) if duration < 0.0 else clampf(duration, .14, .28)
	var material := _screen_materials[_fault_page]
	material.set_shader_parameter("fault_seed", float(_fault_serial * 11 + selected_page * 17))
	material.set_shader_parameter("fault_progress", 0.0)
	material.set_shader_parameter("fault_amount", crt_fault_strength)


func _clear_crt_fault() -> void:
	for material: ShaderMaterial in _screen_materials:
		material.set_shader_parameter("fault_amount", 0.0)
		material.set_shader_parameter("fault_progress", 0.0)
	_fault_page = -1
	_fault_elapsed = 0.0


func _advance_crt_fault(delta: float) -> void:
	if not crt_faults_enabled or crt_fault_strength <= 0.0:
		if _fault_page >= 0:
			_clear_crt_fault()
		return
	if _fault_page >= 0:
		_fault_elapsed += maxf(0.0, delta)
		if _fault_elapsed >= _fault_duration:
			_clear_crt_fault()
			_fault_wait = _next_fault_interval()
		else:
			_screen_materials[_fault_page].set_shader_parameter("fault_progress", _fault_elapsed / _fault_duration)
		return
	_fault_wait -= maxf(0.0, delta)
	if _fault_wait <= 0.0:
		trigger_crt_fault(0)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "FocusCamera"
	_camera.current = true
	_camera.fov = 40.0
	_camera.near = 0.05
	_camera.far = 40.0
	add_child(_camera)


func _build_dark_room() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "DarkRoomEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#020406")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#7b918b")
	environment.ambient_light_energy = 0.65
	world_environment.environment = environment
	add_child(world_environment)
	# 正面局部柔光照出灰绿机壳，环境仍暗；不把黑框问题伪装成全屏提曝光。
	var face_key := OmniLight3D.new()
	face_key.name = "ConsoleFaceKey"
	face_key.position = Vector3(0.0, 3.8, 4.6)
	face_key.omni_range = 15.0
	face_key.light_energy = 2.0
	face_key.light_color = Color("#d6ddd0")
	face_key.shadow_enabled = false
	add_child(face_key)

	_box(self, "BackWall", Vector3(18.0, 5.4, 0.28), Vector3(0, 2.5, -0.65), Color("#11191d"), 0.05)
	_box(self, "Floor", Vector3(19.0, 0.22, 9.0), Vector3(0, -0.14, 3.0), Color("#0b1013"), 0.7)
	_box(self, "Ceiling", Vector3(19.0, 0.18, 5.0), Vector3(0, 5.28, 1.0), Color("#080d10"), 0.8)
	# 长管、线槽与分段桌面提供暗室纵深，不靠全屏后处理伪造。
	for y in [0.46, 4.62]:
		_box(self, "WallRail", Vector3(18.0, 0.12, 0.16), Vector3(0, y, -0.39), Color("#283940"), 0.55)
	for x in [-6.9, -3.5, 0.0, 3.5, 6.9]:
		_box(self, "WallRib", Vector3(0.10, 4.0, 0.12), Vector3(x, 2.5, -0.38), Color("#223138"), 0.62)
	for x in [0.0]:
		_box(self, "ConsoleDesk", Vector3(3.68, 0.18, 1.15), Vector3(x, 0.62, 0.7), Color("#263333"), 0.72)
		_box(self, "DeskFootL", Vector3(0.16, 0.85, 0.65), Vector3(x - 1.2, 0.18, 0.55), Color("#0c1418"), 0.8)
		_box(self, "DeskFootR", Vector3(0.16, 0.85, 0.65), Vector3(x + 1.2, 0.18, 0.55), Color("#0c1418"), 0.8)
	for x in [-7.2, 0.0, 7.2]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 4.6, 2.0)
		lamp.omni_range = 5.2
		lamp.light_energy = 0.75
		lamp.light_color = Color("#7fa8aa") if x == 0.0 else Color("#b88755")
		lamp.shadow_enabled = false
		add_child(lamp)


func _build_monitors() -> void:
	# 四个菜单频道共用这一台实体CRT，不能靠藏掉另外三台来假装只剩一个外框。
	var monitor := Node3D.new()
	monitor.name = "ArchiveCRT"
	monitor.position = Vector3(0.0, 2.35, 0.36)
	add_child(monitor)
	_monitor_nodes.append(monitor)
	_build_monitor_case(monitor, PAGE_START, Color("#35d5d2"))
	monitor_count = _monitor_nodes.size()
	subviewport_count = _screen_canvases.size()
	var screen: MeshInstance3D = monitor.get_node("Screen")
	var screen_center := screen.global_position
	var micro_focus := [Vector3.ZERO, Vector3(.018, 0, .012), Vector3(-.012, .008, .018), Vector3(.012, -.004, .008)]
	for index in PAGE_COUNT:
		# 仅厘米级微聚焦，仍是同一机壳；不再横跨不同电视或让框体离开画面。
		var camera_position: Vector3 = screen_center + monitor.global_basis.z * 4.85 \
			+ monitor.global_basis.x * .46 + Vector3(0, .16, 0) + micro_focus[index]
		var focus_center := monitor.to_global(Vector3(0.0, -0.02, 0.42))
		var target := Transform3D(Basis.IDENTITY, camera_position).looking_at(focus_center, Vector3.UP)
		_camera_targets.append(target)


func _build_monitor_case(monitor: Node3D, page: int, accent: Color) -> void:
	_box(monitor, "Housing", Vector3(3.76, 2.34, 0.84), Vector3(0, 0, -0.12), Color("#586762"), 0.70)
	_box(monitor, "InnerBezel", Vector3(3.22, 1.90, 0.10), Vector3(-.22, .16, .35), Color("#111b1b"), 0.88)
	for x in [-1.84, 1.84]:
		_box(monitor, "SideGuard", Vector3(0.13, 2.38, .32), Vector3(x, 0, .41), Color("#75847b"), .62)
	_box(monitor, "TopGuard", Vector3(3.60, .13, .32), Vector3(0, 1.14, .41), Color("#8c978a"), .60)
	_box(monitor, "BottomGuard", Vector3(3.60, .25, .36), Vector3(0, -1.08, .40), Color("#485953"), .72)
	# 前唇凸出到z=.58，而玻璃z=.415，靠真实几何形成内凹，不能用平面黑框替代。
	for x in [-1.78, 1.34]:
		_box(monitor, "RecessSide", Vector3(.10, 1.88, .22), Vector3(x, .16, .47), Color("#30423e"), .78)
	for y in [-.75, 1.08]:
		_box(monitor, "RecessEdge", Vector3(3.08, .09, .22), Vector3(-.22, y, .47), Color("#354941"), .76)
	_box(monitor, "ControlPanel", Vector3(.37, 1.94, .25), Vector3(1.60, .08, .44), Color("#626f64"), .66)
	_knob(monitor, "TuningKnob", Vector3(1.61, .57, .65), .105, .12)
	_knob(monitor, "VolumeKnob", Vector3(1.61, .22, .65), .075, .11)
	for index in 6:
		_box(monitor, "SpeakerSlot", Vector3(.235, .032, .018), Vector3(1.60, -.17 - index * .09, .582), Color("#172722"), .9)
	_box(monitor, "ServicePlate", Vector3(.86, .14, .02), Vector3(-1.12, -1.05, .59), Color("#d1cbb3"), .82)
	var plate := Label3D.new()
	plate.name = "ChannelNameplate"
	plate.text = "K-00 / ARCHIVE"
	plate.font_size = 26
	plate.pixel_size = .0019
	plate.modulate = Color("#22322c")
	plate.outline_size = 0
	plate.no_depth_test = false
	plate.position = Vector3(-1.12, -1.05, .607)
	monitor.add_child(plate)
	for x in [-1.70, 1.71]:
		for y in [-1.10, 1.12]:
			_box(monitor, "CaseScrew", Vector3(.036, .036, .03), Vector3(x, y, .59), Color("#b1b4a3"), .4)
	_box(monitor, "Stand", Vector3(.64, .42, .57), Vector3(0, -1.35, -.02), Color("#3f514b"), .74)
	_box(monitor, "StandBase", Vector3(1.68, .13, 1.02), Vector3(0, -1.55, .10), Color("#526058"), .75)

	var viewport := SubViewport.new()
	viewport.name = "CRTViewport"
	viewport.size = SCREEN_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas := MonitorCanvas.new()
	canvas.name = "MonitorCanvas"
	canvas.page = page
	canvas.position = Vector2.ZERO
	canvas.size = Vector2(SCREEN_SIZE)
	viewport.add_child(canvas)
	_screen_canvases.append(canvas)

	var quad := QuadMesh.new()
	quad.size = Vector2(3.00, 1.6875)
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = quad
	screen.position = Vector3(-.22, .16, .415)
	var screen_material := ShaderMaterial.new()
	screen_material.shader = CRT_SHADER
	screen_material.set_shader_parameter("screen_image", viewport.get_texture())
	screen_material.set_shader_parameter("focus_gain", .62)
	screen_material.set_shader_parameter("fault_amount", 0.0)
	screen.material_override = screen_material
	monitor.add_child(screen)
	_screen_materials.append(screen_material)

	var led_material := _material(Color("#091012"), 0.3, 0.65)
	led_material.emission_enabled = true
	led_material.emission = accent
	led_material.emission_energy_multiplier = 0.45
	var led_mesh := BoxMesh.new()
	led_mesh.size = Vector3(0.20, 0.08, 0.05)
	var led := MeshInstance3D.new()
	led.name = "StatusLED"
	led.mesh = led_mesh
	led.material_override = led_material
	led.position = Vector3(1.20, -1.07, .61)
	monitor.add_child(led)
	_led_materials.append(led_material)

	var screen_light := OmniLight3D.new()
	screen_light.name = "ScreenGlow"
	screen_light.position = Vector3(0, 0, 1.05)
	screen_light.omni_range = 3.1
	screen_light.light_color = accent
	screen_light.light_energy = 0.18
	screen_light.shadow_enabled = false
	monitor.add_child(screen_light)
	_status_lights.append(screen_light)
	var case_fill := OmniLight3D.new()
	case_fill.name = "CaseFillLight"
	case_fill.position = Vector3(-1.5, 1.35, 1.55)
	case_fill.omni_range = 3.8
	case_fill.light_color = Color("#ccd7bb")
	case_fill.light_energy = .72
	case_fill.shadow_enabled = false
	monitor.add_child(case_fill)


func _knob(parent: Node3D, node_name: String, at: Vector3, radius: float, depth: float) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = depth
	cylinder.radial_segments = 16
	var knob := MeshInstance3D.new()
	knob.name = node_name
	knob.mesh = cylinder
	knob.position = at
	knob.rotation_degrees.x = 90
	knob.material_override = _material(Color("#293a33"), .62, .1)
	parent.add_child(knob)
	_box(parent, node_name + "Tick", Vector3(.02, radius * .72, .012), at + Vector3(0, radius * .30, depth * .5 + .009),
		Color("#d4d6bc"), .72)


func _box(parent: Node3D, node_name: String, box_size: Vector3, at: Vector3,
		color: Color, roughness: float) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = box_size
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _material(color, roughness, 0.12)
	parent.add_child(mesh)
	return mesh


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
