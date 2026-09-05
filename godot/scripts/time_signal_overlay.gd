extends CanvasLayer
class_name TimeSignalOverlay
## 时停/短倒带/花屏的独立信号层；不采屏幕纹理，花屏只在重开前短暂出现一次。
## 可由 game 设置 host 自动读 timeline_view_model，也可直接调用 set_time_state。

const CYAN := Color("#86dac9")
const WARM := Color("#dfbd7d")
const MAX_SCAN_ALPHA := 0.12
const DEFAULT_RECHARGE := 5.0
const DEATH_PROMPT := ["不对……", "这样不行。", "（按任意按钮重开）"]
const GLITCH_BANDS := 9
const GLITCH_BLOCKS := 18
const GLITCH_RED := Color("#df5680")
const GLITCH_BLUE := Color("#598ec7")

var host: Node
var _model: Dictionary = normalize_view_model({})
var _surface: Control
var _font: Font
var _visual_clock := 0.0


class SignalCanvas extends Control:
	var renderer: Node
	func _draw() -> void:
		if renderer != null:
			renderer.draw_signal(self)


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	_font = font
	_surface = SignalCanvas.new()
	_surface.name = "SignalCanvas"
	_surface.renderer = self
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_surface)
	_sync_visibility()


## 缺省关闭，保证没有时间 API 的旧地图/测试宿主继续使用原 HUD。
static func normalize_view_model(raw: Dictionary) -> Dictionary:
	var enabled := bool(raw.get("enabled", false))
	var phase := str(raw.get("phase", "playing"))
	if phase not in ["playing", "dying", "rewinding", "interference"] or not enabled:
		phase = "playing"
	var duration := maxf(0.01, _finite_float(raw.get("max_duration", 2.0), 2.0))
	var energy := clampf(_finite_float(raw.get("energy_ratio", 1.0), 0.0), 0.0, 1.0)
	var lockout := maxf(0.0, _finite_float(raw.get("lockout", 0.0), 0.0))
	var difficulty := str(raw.get("difficulty", "normal"))
	return {"enabled": enabled, "active": enabled and bool(raw.get("active", false)) and phase == "playing",
		"energy_ratio": energy, "remaining": clampf(_finite_float(raw.get("remaining", energy * duration), 0.0), 0.0, duration),
		"max_duration": duration, "lockout": lockout,
		"lockout_ratio": clampf(_finite_float(raw.get("lockout_ratio", lockout / DEFAULT_RECHARGE), 0.0), 0.0, 1.0),
		"phase": phase, "rewind_progress": clampf(_finite_float(raw.get("rewind_progress", 0.0), 0.0), 0.0, 1.0),
		"glitch_progress": clampf(_finite_float(raw.get("glitch_progress", 0.0), 0.0), 0.0, 1.0),
		"death_prompt_ready": enabled and phase == "dying" and bool(raw.get("death_prompt_ready", false)),
		"difficulty": difficulty}


static func _finite_float(value: Variant, fallback: float) -> float:
	if not value is float and not value is int:
		return fallback
	var result := float(value)
	return result if is_finite(result) else fallback


func set_time_state(active: bool, energy_ratio: float, lockout_ratio: float,
		phase: String, rewind_progress: float, glitch_progress := 0.0) -> void:
	apply_view_model({"enabled": true, "active": active, "energy_ratio": energy_ratio,
		"lockout_ratio": lockout_ratio, "lockout": lockout_ratio * DEFAULT_RECHARGE,
		"phase": phase, "rewind_progress": rewind_progress, "glitch_progress": glitch_progress})


func apply_view_model(raw: Dictionary) -> void:
	var next := normalize_view_model(raw)
	if next["phase"] != _model["phase"]:
		_visual_clock = 0.0
	_model = next
	_sync_visibility()


func view_model() -> Dictionary:
	var result := _model.duplicate()
	result["effect_visible"] = bool(_model["active"]) or _model["phase"] in ["dying", "rewinding", "interference"]
	result["scanline_mode"] = "torn" if _model["phase"] == "interference" else \
			("reverse" if _model["phase"] == "rewinding" else ("held" if _model["active"] else "none"))
	result["full_screen_filter"] = false
	result["interference_visible"] = _model["phase"] == "interference"
	result["death_prompt_visible"] = bool(_model["death_prompt_ready"])
	return result


func _process(dt: float) -> void:
	_visual_clock += clampf(dt, 0.0, 0.1)
	if is_instance_valid(host) and host.has_method("timeline_view_model"):
		var raw: Variant = host.call("timeline_view_model")
		apply_view_model(raw if raw is Dictionary else {})
	if _surface != null and _surface.visible:
		_surface.queue_redraw()


func _sync_visibility() -> void:
	if _surface != null:
		_surface.visible = bool(_model["active"]) or _model["phase"] in ["dying", "rewinding", "interference"]
		_surface.queue_redraw()


func _text(canvas: Control, at: Vector2, value: String, size: int, color: Color) -> void:
	canvas.draw_string(_font, at.round(), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _center_text(canvas: Control, center: Vector2, value: String, size: int, color: Color) -> void:
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(canvas, center - Vector2(width * 0.5, 0.0), value, size, color)


func draw_signal(canvas: Control) -> void:
	if _font == null:
		return
	var viewport_size := canvas.get_viewport_rect().size
	var phase := str(_model["phase"])
	var color := WARM if phase == "dying" else CYAN
	# 四角仅占少量像素；花屏只叠有限条带，不用全屏白闪或模糊。
	for corner: Vector2 in [Vector2(12, 12), Vector2(viewport_size.x - 12, 12),
			Vector2(12, viewport_size.y - 12), viewport_size - Vector2(12, 12)]:
		var inward := Vector2(1 if corner.x < viewport_size.x * 0.5 else -1,
			1 if corner.y < viewport_size.y * 0.5 else -1)
		canvas.draw_line(corner, corner + Vector2(inward.x * 20.0, 0), Color(color, 0.60), 1.0)
		canvas.draw_line(corner, corner + Vector2(0, inward.y * 20.0), Color(color, 0.60), 1.0)
	if phase == "interference":
		_draw_interference(canvas, viewport_size)
	elif phase == "rewinding":
		# 三条低透明度逆向扫描线模拟倒带；不复制场景纹理，不产生长残影。
		for index in range(3):
			var y := fposmod(viewport_size.y - _visual_clock * 340.0 + index * viewport_size.y / 3.0, viewport_size.y)
			canvas.draw_rect(Rect2(12.0, floorf(y), viewport_size.x - 24.0, 1.0), Color(CYAN, MAX_SCAN_ALPHA))
			canvas.draw_rect(Rect2(viewport_size.x - 68.0, floorf(y) + 3.0, 44.0, 2.0), Color(CYAN, 0.23))
		_center_text(canvas, Vector2(viewport_size.x * 0.5, 30), "REWIND  <<  短倒带", 13, Color(CYAN, 0.9))
		_draw_rewind_timeline(canvas, viewport_size)
	elif phase == "dying":
		_center_text(canvas, Vector2(viewport_size.x * 0.5, 30), "SIGNAL LOST  /  信号丢失", 13, Color(WARM, 0.8))
		if bool(_model["death_prompt_ready"]):
			_draw_death_prompt(canvas, viewport_size)
	else:
		# 时停扫描线固定在原位，不能仍然正向扫动，视觉上明确“画面被暂停”。
		var held_y := floorf(viewport_size.y * 0.43)
		canvas.draw_rect(Rect2(12, held_y, viewport_size.x - 24.0, 1), Color(CYAN, 0.065))
		var remaining := float(_model["remaining"])
		_center_text(canvas, Vector2(viewport_size.x * 0.5, 30), "PAUSE  ||  %04.1fs" % remaining, 13, Color(CYAN, 0.85))


func _draw_death_prompt(canvas: Control, viewport_size: Vector2) -> void:
	# 先播完倒地再出现两句青色字幕；不放旧死亡卡，也不盖全屏黑层。
	var center := Vector2(viewport_size.x * 0.5, viewport_size.y * 0.46)
	for index in range(3):
		var at := center + Vector2(0, [0, 43, 106][index])
		var size := 17 if index == 2 else 30
		# 单像素暗投影只保护字形边缘，亮墙/显示屏后方仍不需要全屏压暗。
		_center_text(canvas, at + Vector2(1, 1), DEATH_PROMPT[index], size, Color(0.02, 0.05, 0.06, 0.9))
		_center_text(canvas, at, DEATH_PROMPT[index], size, Color(CYAN, 0.85 if index == 2 else 1.0))


## 一次性花屏几何：固定错码块仅做单向轻移，不随机闪烁、不开关整屏亮度。
static func interference_blocks(viewport_size: Vector2, progress: float) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return blocks
	var bounds := Rect2(Vector2.ZERO, viewport_size)
	var p := clampf(progress, 0.0, 1.0)
	var strength := 0.82 - 0.20 * p
	for index in range(GLITCH_BANDS):
		var x := floorf(viewport_size.x * (0.03 + float((index * 19) % 23) * 0.01))
		var y := floorf(viewport_size.y * (0.10 + index * 0.096))
		var width := floorf(viewport_size.x * (0.53 + float((index * 7) % 29) * 0.01))
		var height := float(3 + (index * 7) % 8)
		var shift := floorf((4.0 + p * 14.0) * (1.0 if index % 2 == 0 else -1.0))
		blocks.append({"rect": Rect2(x, y, width, height).intersection(bounds), "color": Color(0.02, 0.05, 0.065, 0.76)})
		blocks.append({"rect": Rect2(x + shift, y - 2.0, floorf(width * 0.70), 2.0).intersection(bounds), "color": Color(GLITCH_RED, strength * 0.67)})
		blocks.append({"rect": Rect2(x - shift, y + 1.0, floorf(width * 0.58), 2.0).intersection(bounds), "color": Color(CYAN, strength * 0.70)})
		blocks.append({"rect": Rect2(x + floorf(shift * 0.5), y + height, floorf(width * 0.81), 2.0).intersection(bounds), "color": Color(GLITCH_BLUE, strength * 0.75)})
	for index in range(GLITCH_BLOCKS):
		var x := floorf(viewport_size.x * (0.08 + float((index * 37) % 83) * 0.01))
		var y := floorf(viewport_size.y * (0.12 + float((index * 23) % 74) * 0.01))
		var rect := Rect2(x + floorf(p * 8.0), y, 12.0 + (index * 11) % 58, 3.0 + (index * 7) % 11)
		var color := [CYAN, GLITCH_RED, GLITCH_BLUE][index % 3] as Color
		blocks.append({"rect": rect.intersection(bounds), "color": Color(color, strength * 0.48)})
	return blocks


func _draw_interference(canvas: Control, viewport_size: Vector2) -> void:
	for block: Dictionary in interference_blocks(viewport_size, float(_model["glitch_progress"])):
		canvas.draw_rect(block["rect"], block["color"])
	# 单条错码标签标识信号切断，不出现记录点或死亡等待字样。
	_center_text(canvas, Vector2(viewport_size.x * 0.5, 30), "SIGNAL // 0x-- // RESET", 13, Color(CYAN, 0.8))


func _draw_rewind_timeline(canvas: Control, viewport_size: Vector2) -> void:
	var center := Vector2(viewport_size.x * 0.5, viewport_size.y - 40.0)
	var width := 252.0
	var progress := float(_model["rewind_progress"])
	var left := center.x - width * 0.5
	canvas.draw_line(Vector2(left, center.y), Vector2(left + width, center.y), Color(CYAN, 0.28), 1.0)
	for index in range(13):
		var x := left + index * width / 12.0
		canvas.draw_line(Vector2(x, center.y - 3), Vector2(x, center.y + 3), Color(CYAN, 0.36), 1.0)
	# 播放头由右向左归零，和逆向扫描保持同一时间方向。
	var cursor_x := left + width * (1.0 - progress)
	canvas.draw_rect(Rect2(cursor_x - 2.0, center.y - 6.0, 4.0, 12.0), Color(CYAN, 0.84))
	_center_text(canvas, center - Vector2(0, 13), "CLIP  <<  %03d%%" % roundi(progress * 100.0), 11, Color(CYAN, 0.8))
