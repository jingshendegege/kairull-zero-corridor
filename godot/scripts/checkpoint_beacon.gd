extends Node2D
## 中途补给终端：只提供视觉，不产生挡路碰撞。进度判定由 game 集中处理。

var unlocked := false
var activated := false
var _pulse := 0.0
var run_checkpoint := false ## 正式单存点显示明确状态字，不增加碰撞或常驻动画。
var locked_hint := "清前段后解锁"
var _font: SystemFont


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	if run_checkpoint:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
		_font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]


func set_status(next_unlocked: bool, next_active: bool) -> void:
	if unlocked == next_unlocked and activated == next_active:
		return
	unlocked = next_unlocked
	if next_active and not activated:
		_pulse = 0.7
		set_process(true)
	activated = next_active
	queue_redraw()


func _process(dt: float) -> void:
	_pulse = maxf(0.0, _pulse - dt)
	queue_redraw()
	if _pulse <= 0.0:
		set_process(false)


func _draw() -> void:
	var signal_color := Color("#7edbce") if unlocked else Color("#a08863")
	if activated:
		signal_color = Color("#caf7d9")
	if run_checkpoint and _font != null:
		var label := "检查点已记录" if activated else ("靠近记录检查点" if unlocked else locked_hint)
		var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		# 标签高于约94px白发轮廓，重生站在终端中心也不让头部挡住存档提示。
		draw_rect(Rect2(-width * .5 - 5, -124, width + 10, 20), Color(0.02, 0.06, 0.075, .88))
		draw_string(_font, Vector2(-width * .5, -109).round(), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, signal_color)
	# 铜底座/倾斜控制台/状态屏，形状不同于能击飞的黄色小货箱。
	draw_rect(Rect2(-23, -5, 46, 5), Color("#101b25"))
	draw_rect(Rect2(-18, -9, 36, 5), Color("#6d7b7d"))
	draw_rect(Rect2(-10, -46, 20, 38), Color("#253b47"))
	draw_rect(Rect2(-7, -43, 3, 30), Color("#597780"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-22, -68), Vector2(15, -68), Vector2(23, -43), Vector2(-17, -43),
	]), Color("#152936"))
	draw_rect(Rect2(-16, -63, 29, 15), Color("#304c56"))
	draw_rect(Rect2(-13, -61, 23, 2), signal_color)
	draw_rect(Rect2(-13, -57, 14, 2), signal_color.darkened(0.3))
	draw_rect(Rect2(-13, -53, 19 if activated else 7, 2), signal_color.darkened(0.2))
	draw_rect(Rect2(16, -37, 6, 27), Color("#756b52"))
	draw_rect(Rect2(17, -34, 4, 5), signal_color)
	if _pulse > 0.0:
		var radius := 22.0 + (1.0 - _pulse / 0.7) * 36.0
		draw_rect(Rect2(-radius, -3, radius * 2.0, 2),
				Color(signal_color, _pulse / 0.7 * 0.55))
