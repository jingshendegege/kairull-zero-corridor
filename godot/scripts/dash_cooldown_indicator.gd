extends Node2D
## 跟随凯露尔的冲刺冷却提示：冷却时显示，蓄满后自动隐藏。

const PANEL_WIDTH := 58.0
const BAR_WIDTH := 48.0
const BAR_HEIGHT := 3.0
const SEGMENTS := 6

var remaining := 0.0
var total := 1.0


func set_cooldown(next_remaining: float, next_total: float, enabled := true) -> void:
	remaining = maxf(0.0, next_remaining)
	total = maxf(0.001, next_total)
	visible = enabled and remaining > 0.001
	queue_redraw()


func _draw() -> void:
	# 紧凑充能条不遮白发轮廓；六段由暗至亮填满，就绪时整个控件直接隐藏。
	draw_rect(Rect2(-PANEL_WIDTH * 0.5, -12.0, PANEL_WIDTH, 18.0), Color("#0b171e"))
	draw_rect(Rect2(-PANEL_WIDTH * 0.5, -12.0, 2.0, 18.0), Color("#7fcbd0"))
	draw_string(ThemeDB.fallback_font, Vector2(-23.0, -2.0), "SHIFT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#92b1b9"))
	var time_text := "%.1f" % remaining
	var time_width := ThemeDB.fallback_font.get_string_size(time_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(ThemeDB.fallback_font, Vector2(24.0 - time_width, -2.0), time_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#e4eee8"))
	var ratio := ready_ratio()
	for index in SEGMENTS:
		var segment := Rect2(-BAR_WIDTH * 0.5 + index * 8.0, 1.0, 6.0, BAR_HEIGHT)
		draw_rect(segment, Color("#263a44"))
		var fill := clampf(ratio * SEGMENTS - index, 0.0, 1.0)
		if fill > 0.0:
			segment.size.x = ceilf(segment.size.x * fill)
			draw_rect(segment, Color("#92ecdd"))


func ready_ratio() -> float:
	return clampf(1.0 - remaining / total, 0.0, 1.0)
