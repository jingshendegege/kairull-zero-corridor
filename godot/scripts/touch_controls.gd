extends CanvasLayer
## 手机触屏操作层（Claude，2026-09-30 用户要求适配手机版）。
## 全局自动加载；只有收到真实触摸后才出现，按下实体键盘或鼠标即隐藏——桌面玩家看不到。
## 不改玩法代码：每个虚拟键都注入与实体键盘/鼠标相同的输入事件（Input.parse_input_event），
## 角色/节奏战/暂停仍按原来的 Input.is_key_pressed / is_mouse_button_pressed 读取。
## 关卡内关闭"触摸模拟鼠标"，避免任意触摸都变成左键挥棒；菜单/暂停页打开它，点按即可操作。

const INK := Color(0.02, 0.05, 0.07, 0.42)
const EDGE := Color(0.85, 0.97, 1.0, 0.55)
const ACTIVE := Color(0.24, 0.95, 1.0, 0.55)
const TEXT := Color(0.94, 0.98, 1.0, 0.9)

## 普通关卡按钮：[名称, 标签, 输入码, 中心, 半径]。输入码 < 10 视为鼠标键。
const FIELD_BUTTONS := [
	["left", "◀", KEY_A, Vector2(108, 648), 62.0],
	["right", "▶", KEY_D, Vector2(252, 648), 62.0],
	["down", "▼", KEY_S, Vector2(180, 530), 44.0],
	["attack", "攻击", MOUSE_BUTTON_LEFT, Vector2(1228, 628), 70.0],
	["jump", "跳", KEY_W, Vector2(1090, 690), 52.0],
	["dash", "冲刺", KEY_SHIFT, Vector2(1066, 560), 46.0],
	["roll", "翻滚", KEY_CTRL, Vector2(1146, 462), 42.0],
	["time", "时停", MOUSE_BUTTON_RIGHT, Vector2(1280, 470), 42.0],
	["smoke", "烟", KEY_R, Vector2(958, 660), 38.0],
]
const PAUSE_BUTTON := ["pause", "Ⅱ", KEY_ESCAPE, Vector2(680, 38), 26.0]

var touch_mode := false          ## 收到过真实触摸 → 显示虚拟键
var _held := {}                  ## 触点 index → 按钮名
var _pressed_codes := {}         ## 按钮名 → 输入码（正在按住）
var _font: SystemFont
var _canvas: Control


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	_font.font_weight = 800
	_font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	_canvas = Control.new()
	_canvas.name = "TouchCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


func _game() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Game") if scene != null else null


## 关卡内且未暂停时才显示虚拟键；返回当前布局："field" / "rhythm" / ""。
func layout() -> String:
	if not touch_mode:
		return ""
	var game := _game()
	if game == null or not is_instance_valid(game):
		return ""
	if game.get("pause_controller") != null and game.pause_controller.active:
		return ""
	var arena = game.get("beat_arena")
	if arena != null and is_instance_valid(arena) and arena.rhythm_lock:
		return "rhythm"
	return "field"


func buttons() -> Array:
	match layout():
		"field":
			return FIELD_BUTTONS + [PAUSE_BUTTON]
		"rhythm":
			# 用户要求（2026-09-30）：上半屏 = 上层（W），下半屏 = 下层（S）；上下同时按 = 双键重音符
			var view := _canvas.get_viewport_rect().size
			return [["air", "▲ 上层", KEY_W, Vector2(view.x * 0.5, view.y * 0.25), 0.0],
				["ground", "▼ 下层", KEY_S, Vector2(view.x * 0.5, view.y * 0.75), 0.0], PAUSE_BUTTON]
	return []


func _hit(point: Vector2) -> Array:
	var list := buttons()
	for button: Array in list:
		if button[0] == "pause" and point.distance_to(button[3]) <= button[4] + 14.0:
			return button
	if layout() == "rhythm":
		var view := _canvas.get_viewport_rect().size
		return list[0] if point.y < view.y * 0.5 else list[1]
	var best: Array = []
	var best_d := INF
	for button: Array in list:
		var d := point.distance_to(button[3])
		if d <= button[4] + 16.0 and d < best_d:   # 触摸容差比画出来的圆大一圈
			best = button
			best_d = d
	return best


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not touch_mode:
			touch_mode = true
			_canvas.queue_redraw()
		_sync_mouse_emulation()
		if layout().is_empty():
			return
		_handle_touch(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.is_echo() and event.device != -7:
		# 实体键盘（注入的事件 device 标 -7）→ 退出触屏模式
		if touch_mode and event.pressed:
			_leave_touch_mode()
	elif event is InputEventMouseButton and event.device != -7 and event.device != InputEvent.DEVICE_ID_EMULATION:
		if touch_mode and event.pressed and layout() != "":
			_leave_touch_mode()


func _leave_touch_mode() -> void:
	_release_all()
	touch_mode = false
	var game := _game()
	if game != null and is_instance_valid(game) and game.player != null:
		game.player.aim_override = null
	Input.emulate_mouse_from_touch = true
	_canvas.queue_redraw()


func _handle_touch(event: InputEvent) -> void:
	var index: int = event.index
	if event is InputEventScreenTouch and not event.pressed:
		_release_touch(index)
		return
	var button := _hit(event.position)
	var name: String = button[0] if not button.is_empty() else ""
	var previous: String = _held.get(index, "")
	if event is InputEventScreenDrag:
		# 只有方向键允许手指滑动切换（◀ ↔ ▶），其余按钮按下后锁定到该手指
		if previous in ["left", "right"] and name in ["left", "right"] and name != previous:
			_release_touch(index)
		else:
			return
	if name.is_empty():
		_tap_empty()
		return
	_held[index] = name
	if not _pressed_codes.has(name):
		_pressed_codes[name] = button[2]
		_send(button[2], true)
	_canvas.queue_redraw()


## 点空白处：倒地/通关提示时相当于"任意键 / Enter"。
func _tap_empty() -> void:
	var game := _game()
	if game != null and (game.level_cleared or game.player.dead):
		_send(KEY_ENTER, true)
		_send(KEY_ENTER, false)


func _release_touch(index: int) -> void:
	var name: String = _held.get(index, "")
	_held.erase(index)
	if name.is_empty() or name in _held.values():
		return
	var code = _pressed_codes.get(name)
	_pressed_codes.erase(name)
	if code != null:
		_send(code, false)
	_canvas.queue_redraw()


func _release_all() -> void:
	for name in _pressed_codes.keys():
		_send(_pressed_codes[name], false)
	_pressed_codes.clear()
	_held.clear()


func _send(code: int, pressed: bool) -> void:
	var event: InputEvent
	if code < 10:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = code
		mouse.pressed = pressed
		mouse.position = _canvas.get_viewport_rect().size * 0.5
		mouse.global_position = mouse.position
		event = mouse
	else:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = pressed
		event = key
	event.device = -7
	Input.parse_input_event(event)


func _sync_mouse_emulation() -> void:
	# 关卡内：触摸只走虚拟键；菜单、暂停页、结算：触摸模拟鼠标点击按钮。
	Input.emulate_mouse_from_touch = layout().is_empty()


func _process(_dt: float) -> void:
	if not touch_mode:
		if visible and _canvas != null:
			_canvas.queue_redraw()
		return
	_sync_mouse_emulation()
	if layout().is_empty() and not _pressed_codes.is_empty():
		_release_all()
	# 投烟瞄准：触屏没有鼠标指针，烟雾弹朝角色面向的前上方投出
	var game := _game()
	if game != null and is_instance_valid(game) and game.player != null:
		var p: Node2D = game.player
		p.aim_override = p.position + Vector2(260.0 * p.face, -90.0) if layout() == "field" else null
	_canvas.queue_redraw()


func _draw_controls() -> void:
	var view := _canvas.get_viewport_rect().size
	var window := DisplayServer.window_get_size()
	if (touch_mode or DisplayServer.is_touchscreen_available()) and window.y > window.x:
		# 竖屏：提示横屏游玩
		_canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.01, 0.02, 0.03, 0.92))
		var msg := "请把手机横过来游玩"
		var w := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		_canvas.draw_string(_font, Vector2((view.x - w) * 0.5, view.y * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, TEXT)
		var t := Time.get_ticks_msec() / 1000.0
		var c := Vector2(view.x * 0.5, view.y * 0.5 + 110)
		var ang := sin(t * 2.0) * 0.8 - 0.8
		var r := Transform2D(ang, c)
		var phone := PackedVector2Array([r * Vector2(-28, -48), r * Vector2(28, -48), r * Vector2(28, 48), r * Vector2(-28, 48), r * Vector2(-28, -48)])
		_canvas.draw_polyline(phone, ACTIVE, 4.0)
		return
	var mode := layout()
	if mode.is_empty():
		return
	for button: Array in buttons():
		var name: String = button[0]
		var pressed := _pressed_codes.has(name)
		if mode == "rhythm" and name != "pause":
			var half := Rect2(0, 0 if name == "air" else view.y * 0.5, view.x, view.y * 0.5)
			if pressed:
				_canvas.draw_rect(half, Color(ACTIVE, 0.10))
			# 分界：只在左右屏边画短刻度，不在画面中间拉线挡住轨道
			if name == "air":
				_canvas.draw_rect(Rect2(0, view.y * 0.5 - 1, 36, 2), Color(EDGE, 0.5))
				_canvas.draw_rect(Rect2(view.x - 36, view.y * 0.5 - 1, 36, 2), Color(EDGE, 0.5))
			var label: String = button[1]
			var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
			var ly := 150.0 if name == "air" else view.y - 20.0   # 上：Boss 血条下方；下：地板上，不压轨道和 Boss
			_canvas.draw_string(_font, Vector2((view.x - lw) * 0.5, ly), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(TEXT, 0.45 if not pressed else 0.95))
			continue
		var center: Vector2 = button[3]
		var radius: float = button[4]
		_canvas.draw_circle(center, radius, ACTIVE if pressed else INK)
		_canvas.draw_arc(center, radius, 0, TAU, 40, ACTIVE if pressed else EDGE, 3.0 if pressed else 2.0, true)
		var text: String = button[1]
		var size := 30 if text.length() <= 1 else (22 if text.length() == 2 else 18)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_canvas.draw_string(_font, center + Vector2(-tw * 0.5, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TEXT)
