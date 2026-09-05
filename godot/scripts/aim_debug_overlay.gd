extends Node2D

## 调试叠加层：画 pivot/muzzle 十字、瞄准射线、pivot→muzzle 连线。
##
## 为什么要独立成一个节点，而不是画在根节点的 _draw() 里：
##   Godot 中父节点的 _draw() 先于子节点渲染，所以根节点画的十字
##   会被第一个子节点 BG（铺满全屏的 ColorRect）整块盖掉 ——
##   实测截图里完全找不到绿/红十字，就是这个原因。
##   把叠加层作为**最后一个**子节点，才能画在所有内容之上。

var host: Node2D            ## 指回原型根节点，读取瞄准状态


func _draw() -> void:
	if host == null or not host._debug_visible:
		return
	var pivot: Vector2 = host._anchor
	var muzzle: Vector2 = host.get_node("MuzzleMarker").position
	var aim_pt: Vector2 = host._aim_point()

	# 鼠标瞄准射线（青，半透明）—— 纯七档下它与实际发射方向会有吸附误差
	draw_line(pivot, aim_pt, Color(0.4, 0.9, 1.0, 0.3), 1.0)

	# 实际发射射线（橙）：从 muzzle 沿该档实测角射出，这才是子弹真实轨迹
	var fire_deg: float = host._fire_deg
	if not host._facing_right:
		fire_deg = 180.0 - fire_deg
	var dir := Vector2(cos(deg_to_rad(-fire_deg)), sin(deg_to_rad(-fire_deg)))
	draw_line(muzzle, muzzle + dir * 420.0, Color(1.0, 0.55, 0.15, 0.55), 1.5)

	# pivot→muzzle 连线（黄）
	draw_line(pivot, muzzle, Color(1.0, 0.8, 0.15, 0.85), 2.0)
	# pivot 绿十字（握把枢轴）
	_cross(pivot, Color(0.2, 0.9, 0.4), 11.0)
	# muzzle 红十字（枪口 / 弹道起点）
	_cross(muzzle, Color(1.0, 0.3, 0.3), 9.0)


func _cross(p: Vector2, c: Color, r: float) -> void:
	draw_line(p - Vector2(r, 0), p + Vector2(r, 0), c, 2.0)
	draw_line(p - Vector2(0, r), p + Vector2(0, r), c, 2.0)
	draw_arc(p, r * 0.75, 0.0, TAU, 20, c, 1.5)
