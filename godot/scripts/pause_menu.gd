class_name GamePauseMenu
extends CanvasLayer
## 纯暂停UI：不自动注册输入，不改场景/音乐/时间。由pause_controller转发事件并处理信号。
## 全屏点击屏障+抬起确认，避免“继续”按钮的同一下鼠标按下穿透成游戏挥棒。

signal resume_requested
signal retry_requested
signal menu_requested
signal difficulty_requested(mode: String)

const SESSION := preload("res://scripts/run_session.gd")
const PANEL_SIZE := Vector2(600, 528)
const INK := Color("#0b191d")
const FRAME := Color("#50635c")
const PAPER := Color("#dceae3")
const MUTED := Color("#8aa09b")
const ACCENT := Color("#74d8cb")
const WARN := Color("#e3b677")

var host: Node2D
var menu_open := false
var selected_index := 0
var confirmation_action := ""
var confirmation_choice := 0 # 0=取消、1=确认；破坏进度的动作默认落在安全选项。
var _context: Dictionary = {}
var _action_pending := false
var _mouse_down_target := -1
var _mouse_down_action := ""
var _surface: PauseSurface


class PauseSurface extends Control:
	var menu: CanvasLayer
	var font: SystemFont

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
		font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
		set_process(false)

	func _at(local: Vector2) -> Vector2:
		return menu.panel_rect().position + local * menu.ui_scale()

	func _rect(local: Rect2) -> Rect2:
		return Rect2(_at(local.position), local.size * menu.ui_scale())

	func _text(at: Vector2, value: String, font_size: int, color: Color, max_width := 544.0) -> void:
		var size_px := maxi(10, roundi(font_size * menu.ui_scale()))
		var allowed: float = max_width * menu.ui_scale()
		var shown := value
		while shown.length() > 2 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > allowed:
			shown = shown.left(shown.length() - 2) + "…"
		draw_string(font, _at(at).round(), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

	func _center_text(at_y: float, value: String, font_size: int, color: Color) -> void:
		var size_px := maxi(10, roundi(font_size * menu.ui_scale()))
		var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var panel: Rect2 = menu.panel_rect()
		draw_string(font, Vector2(panel.get_center().x - width * .5, panel.position.y + at_y * menu.ui_scale()).round(),
			value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

	func _draw() -> void:
		if menu == null or not menu.menu_open or font == null:
			return
		var s: float = menu.ui_scale()
		draw_rect(get_viewport_rect(), Color(0, 0, 0, .57))
		var panel: Rect2 = menu.panel_rect()
		draw_rect(panel, FRAME)
		draw_rect(panel.grow(-4 * s), Color("#1f342f"))
		draw_rect(panel.grow(-12 * s), INK)
		draw_line(_at(Vector2(16, 15)), _at(Vector2(584, 15)), Color("#93a998"), 2 * s)
		for local in [Vector2(7, 7), Vector2(589, 7), Vector2(7, 517), Vector2(589, 517)]:
			draw_rect(Rect2(_at(local), Vector2(4, 4) * s), Color("#b1b9a5"))
		_text(Vector2(28, 45), "暂停 / PAUSED", 27, PAPER)
		_text(Vector2(28, 71), menu.level_title(), 17, MUTED)
		_text(Vector2(28, 96), "难度：%s · %d格生命   返回点：%s" % [
			SESSION.name_for_difficulty(menu.difficulty()), SESSION.health_for_difficulty(menu.difficulty()),
			menu.checkpoint_name()], 13, ACCENT)
		draw_line(_at(Vector2(28, 110)), _at(Vector2(572, 110)), Color(ACCENT, .35), s)
		if menu.confirmation_action.is_empty():
			for index in 4:
				var rect: Rect2 = menu.button_rect(index)
				var chosen: bool = index == menu.selected_index
				var color := ACCENT if index == 0 else WARN
				draw_rect(rect, Color("#183029") if chosen else Color("#101f22"))
				draw_rect(rect, Color(color, .9 if chosen else .25), false, 2 * s if chosen else s)
				if chosen:
					draw_rect(Rect2(rect.position + Vector2(9, 10) * s, Vector2(4, 32) * s), color)
				_text(Vector2(51, 166 + index * 62), menu.button_label(index), 21, PAPER if chosen else MUTED)
			_text(Vector2(28, 411), "原场景停在当前时刻，继续不会重开。", 13, MUTED)
		elif menu.confirmation_action == "difficulty":
			_center_text(152, "选择难度 · 立即更新生命上限", 22, PAPER)
			for index in 3:
				var rect: Rect2 = menu.difficulty_button_rect(index)
				var mode: String = SESSION.DIFFICULTIES[index]
				var chosen: bool = mode == menu.difficulty()
				draw_rect(rect, Color("#183029") if chosen else INK)
				draw_rect(rect, ACCENT if chosen else FRAME, false, 2*s)
				_text(Vector2(62+index*170, 224), "%s %d血"%[SESSION.name_for_difficulty(mode),SESSION.health_for_difficulty(mode)],18,PAPER,160)
			_center_text(284, "← → 或点击卡片切换，立即生效",14,ACCENT)
			_center_text(318, "保留现场和检查点；切换不补血、不复活。",14,MUTED)
			_center_text(350, "机关配置在下次重试或进入下一关时更新。",13,WARN)
		else:
			var retry: bool = menu.confirmation_action == "retry"
			var question: String = "确认%s？" % menu.button_label(1) if retry else "确认返回主菜单？"
			_center_text(166, question, 25, PAPER)
			var warning: String = "将放弃检查点之后的进度。" if retry and menu.has_checkpoint() \
				else "将放弃本轮进度，从关卡入口重新开始。" if retry \
				else "返回主菜单将清除本轮检查点。"
			_center_text(206, warning, 16, WARN)
			var detail: String = "重试位置：" + menu.checkpoint_name() if retry else "下次开始将从关卡入口重来。"
			_center_text(236, detail, 14, MUTED)
			for index in 2:
				var rect: Rect2 = menu.confirm_button_rect(index)
				var chosen: bool = index == menu.confirmation_choice
				var tint := ACCENT if index == 0 else WARN
				draw_rect(rect, Color("#183029") if chosen else Color("#101f22"))
				draw_rect(rect, Color(tint, .95 if chosen else .32), false, 2 * s if chosen else s)
				var label: String = "取消" if index == 0 else "确认重试" if retry else "确认返回"
				var text_px := maxi(10, roundi(19 * s))
				var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px).x
				draw_string(font, Vector2(rect.get_center().x - text_w * .5, rect.position.y + 32 * s).round(),
					label, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, PAPER if chosen else MUTED)
			_text(Vector2(28, 359), "不会自动确认；Esc 仍然直接原地继续。", 13, MUTED)
		_text(Vector2(28, 452), "Esc 原地继续   ↑↓ / W S 选择   Enter 确认", 14, ACCENT)
		_text(Vector2(28, 481), "返回主菜单会清除本轮检查点。", 13, WARN)
		_text(Vector2(28, 507), "单击明确按钮；画面外点击不会传到游戏。", 11, MUTED)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_surface = PauseSurface.new()
	_surface.name = "PauseClickBarrier"
	_surface.menu = self
	add_child(_surface)
	set_process(false)
	visible = menu_open


func ui_scale() -> float:
	var view := Vector2(1360, 765) if get_viewport() == null else get_viewport().get_visible_rect().size
	return maxf(.45, minf(1.0, minf((view.x - 32) / PANEL_SIZE.x, (view.y - 32) / PANEL_SIZE.y)))


func panel_rect() -> Rect2:
	var view := Vector2(1360, 765) if get_viewport() == null else get_viewport().get_visible_rect().size
	var dimensions := PANEL_SIZE * ui_scale()
	return Rect2((view - dimensions) * .5, dimensions)


func button_rect(index: int) -> Rect2:
	return Rect2(panel_rect().position + Vector2(28, 132 + index * 62) * ui_scale(), Vector2(544, 52) * ui_scale())


func confirm_button_rect(index: int) -> Rect2:
	return Rect2(panel_rect().position + Vector2(56 + index * 256, 284) * ui_scale(), Vector2(232, 50) * ui_scale())

func difficulty_button_rect(index: int) -> Rect2:
	return Rect2(panel_rect().position + Vector2(45+index*170,180)*ui_scale(),Vector2(160,72)*ui_scale())

func set_difficulty(mode: String) -> void:
	_context["difficulty"] = mode
	_redraw()


func difficulty() -> String:
	return SESSION.normalize_difficulty(str(_context.get("difficulty", "easy")))


func has_checkpoint() -> bool:
	return bool(_context.get("has_checkpoint", false))


func checkpoint_name() -> String:
	if not has_checkpoint():
		return "关卡入口"
	var value := str(_context.get("checkpoint", "中段检查点")).strip_edges()
	return "中段检查点" if value.is_empty() else value


func level_title() -> String:
	return str(_context.get("level_title", "凯露尔 · 零号回廊"))


func button_label(index: int) -> String:
	match index:
		0: return "继续游戏"
		1: return "从检查点重试" if has_checkpoint() else "从入口重试"
		2: return "返回主菜单"
		_: return "切换难度 · " + SESSION.name_for_difficulty(difficulty())


func show_menu(context: Dictionary) -> void:
	_context = context.duplicate(true)
	menu_open = true
	visible = true
	selected_index = 0
	confirmation_action = ""
	confirmation_choice = 0
	_action_pending = false
	_mouse_down_target = -1
	_mouse_down_action = ""
	_redraw()


func hide_menu() -> void:
	menu_open = false
	visible = false
	confirmation_action = ""
	confirmation_choice = 0
	_action_pending = false
	_mouse_down_target = -1
	_mouse_down_action = ""
	_redraw()


func _redraw() -> void:
	if _surface != null:
		_surface.queue_redraw()


func _consume() -> void:
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


func handle_input(event: InputEvent) -> void:
	if not menu_open:
		return
	# Esc永远由controller恢复当前现场，不能在确认页变成退一级或重开。
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		return
	_consume()
	if _action_pending:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if confirmation_action == "difficulty":
			var index := SESSION.DIFFICULTIES.find(difficulty())
			if event.keycode in [KEY_LEFT,KEY_A,KEY_UP,KEY_W]:
				difficulty_requested.emit(SESSION.DIFFICULTIES[posmod(index-1,3)])
			elif event.keycode in [KEY_RIGHT,KEY_D,KEY_DOWN,KEY_S]:
				difficulty_requested.emit(SESSION.DIFFICULTIES[posmod(index+1,3)])
			elif event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
				difficulty_requested.emit(difficulty())
			_redraw()
			return
		if not confirmation_action.is_empty():
			if event.keycode in [KEY_LEFT, KEY_A]:
				confirmation_choice = 0
			elif event.keycode in [KEY_RIGHT, KEY_D]:
				confirmation_choice = 1
			elif event.keycode in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
				confirmation_choice = 1 - confirmation_choice
			elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_activate_confirmation()
				return
		else:
			if event.keycode in [KEY_UP, KEY_W]:
				selected_index = posmod(selected_index - 1, 4)
			elif event.keycode in [KEY_DOWN, KEY_S]:
				selected_index = posmod(selected_index + 1, 4)
			elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_activate()
				return
		_redraw()
	elif event is InputEventMouseMotion:
		var index := _button_at(event.position)
		if index >= 0:
			if confirmation_action.is_empty():
				selected_index = index
			else:
				confirmation_choice = index
			_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _button_at(event.position)
		if event.pressed:
			_mouse_down_target = index
			_mouse_down_action = confirmation_action
			if index >= 0:
				if confirmation_action.is_empty():
					selected_index = index
				else:
					confirmation_choice = index
			_redraw()
		else:
			var valid_click := index >= 0 and index == _mouse_down_target and _mouse_down_action == confirmation_action
			_mouse_down_target = -1
			if valid_click:
				if confirmation_action == "difficulty":
					difficulty_requested.emit(SESSION.DIFFICULTIES[index])
				elif confirmation_action.is_empty():
					selected_index = index
					_activate()
				else:
					confirmation_choice = index
					_activate_confirmation()


func _button_at(point: Vector2) -> int:
	if confirmation_action == "difficulty":
		for index in 3:
			if difficulty_button_rect(index).has_point(point):
				return index
		return -1
	for index in (4 if confirmation_action.is_empty() else 2):
		var rect := button_rect(index) if confirmation_action.is_empty() else confirm_button_rect(index)
		if rect.has_point(point):
			return index
	return -1


func _activate() -> void:
	if selected_index == 3:
		confirmation_action = "difficulty"
		_mouse_down_target = -1
		_redraw()
		return
	if selected_index == 0:
		_action_pending = true
		resume_requested.emit()
		return
	confirmation_action = "retry" if selected_index == 1 else "menu"
	confirmation_choice = 0
	_mouse_down_target = -1
	_redraw()


func _activate_confirmation() -> void:
	if confirmation_choice == 0:
		confirmation_action = ""
		_mouse_down_target = -1
		_redraw()
		return
	_action_pending = true
	if confirmation_action == "retry":
		retry_requested.emit()
	else:
		menu_requested.emit()
