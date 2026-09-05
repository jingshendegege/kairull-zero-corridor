extends Node2D
## 小罐体是代码原生像素图形；地上补给与头顶携带槽共用，不新增模糊素材。

func _draw() -> void:
	# 携带与地上补给都只画罐体，不再夹带R或其他字符；按键说明交给操作提示。
	var offset := Vector2.ZERO
	draw_rect(Rect2(offset + Vector2(-6, -8), Vector2(12, 17)), Color("#132c34"))
	draw_rect(Rect2(offset + Vector2(-4, -6), Vector2(8, 13)), Color("#b1d8cc"))
	draw_rect(Rect2(offset + Vector2(-4, -1), Vector2(8, 4)), Color("#2d8075"))
	draw_rect(Rect2(offset + Vector2(-2, -10), Vector2(5, 3)), Color("#edf3cb"))
	draw_rect(Rect2(offset + Vector2(3, -9), Vector2(4, 2)), Color("#cdd9a5"))
	draw_rect(Rect2(offset + Vector2(-4, -5), Vector2(2, 4)), Color("#f0f8e8"))
