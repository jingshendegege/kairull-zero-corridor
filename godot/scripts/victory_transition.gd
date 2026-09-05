class_name VictoryTransition
extends CanvasLayer
## 时间线主线的安静通关收束：白字缓显，背景1.4秒渐黑，绝不触发死亡花屏/切关/停音乐。
## game在level_cleared同一帧隐藏旧CLEAR/HUD；本层只读host状态，Enter/Esc仍由game处理。

const MESSAGE := "很好，这样能行。"
const PROMPT := "Enter 重新挑战    /    Esc 暂停菜单"
const FADE_DURATION := 1.4
const TEXT_FADE_DURATION := .25
const READY_DELAY := 1.6
const PROMPT_FADE_DURATION := .18

var host: Node2D
var elapsed := 0.0
var fade_progress := 0.0
var text_opacity := 0.0
var prompt_opacity := 0.0
var _active := false
var _last_usec := 0
var _surface: VictorySurface


class VictorySurface extends Control:
	var transition: CanvasLayer
	var font: SystemFont

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
		font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
		set_process(false)

	func _draw() -> void:
		if transition == null or not transition._active or font == null:
			return
		var view := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, transition.fade_progress))
		# 量实际中文宽度后居中；主体在屏幕约60%高度，留出大面积黑色负空间。
		var title_w := font.get_string_size(MESSAGE, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		draw_string(font, Vector2((view.x - title_w) * .5, view.y * .60).round(), MESSAGE,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, transition.text_opacity))
		if transition.prompt_opacity > 0.0:
			var prompt: String = transition.prompt_text()
			var prompt_w := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(font, Vector2((view.x - prompt_w) * .5, view.y * .88).round(), prompt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(.72, .77, .77, transition.prompt_opacity))


func _ready() -> void:
	layer = 80 # 压住旧HUD/CLEAR层，但只在正式timeline通关时可见。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_surface = VictorySurface.new()
	_surface.name = "VictorySurface"
	_surface.transition = self
	add_child(_surface)
	_last_usec = Time.get_ticks_usec()
	reset()


func _process(_delta: float) -> void:
	# 用真实时钟，不继承主角55%速度/命中停顿，也不修改Engine.time_scale或SceneTree暂停。
	var now := Time.get_ticks_usec()
	var real_delta := float(now - _last_usec) / 1000000.0
	_last_usec = now
	advance(real_delta)


func advance(dt: float) -> void:
	var allowed := is_instance_valid(host) and bool(host.get("timeline_enabled")) and bool(host.get("level_cleared"))
	if not allowed:
		if _active or visible:
			reset()
		return
	if not is_finite(dt) or dt < 0.0:
		return
	if not _active:
		_active = true
		visible = true
		elapsed = 0.0
	elapsed += dt
	fade_progress = clampf(elapsed / FADE_DURATION, 0.0, 1.0)
	text_opacity = clampf(elapsed / TEXT_FADE_DURATION, 0.0, 1.0)
	prompt_opacity = clampf((elapsed - READY_DELAY) / PROMPT_FADE_DURATION, 0.0, 1.0)
	if _surface != null:
		_surface.queue_redraw()


func is_ready() -> bool:
	return _active and elapsed >= READY_DELAY


func prompt_text() -> String:
	if is_instance_valid(host) and host.has_method("victory_next_scene") \
			and not String(host.victory_next_scene()).is_empty():
		return "即将进入下一关    /    Esc 暂停菜单"
	return PROMPT


func reset() -> void:
	elapsed = 0.0
	fade_progress = 0.0
	text_opacity = 0.0
	prompt_opacity = 0.0
	_active = false
	visible = false
	_last_usec = Time.get_ticks_usec()
	if _surface != null:
		_surface.queue_redraw()
