extends Node2D
class_name GameDebugOverlay
## 调试叠加层：膛线、枪口/握把标记、碰撞盒。
## 必须作为最后一个世界空间子节点，画在所有内容之上（父节点先渲染的坑）。

var host: Node2D   ## game


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if host == null or not host.debug:
		return
	var p: KairullPlayer = host.player
	var gp: Dictionary = p.gun_pose()
	if not gp.is_empty():
		draw_line(gp["grip"], gp["muzzle"], Color(1, 0.82, 0.35, 0.65), 1.4)
		var dir := Vector2(cos(gp["rad"]), sin(gp["rad"]))
		draw_line(gp["muzzle"], gp["muzzle"] + dir * 1400.0, Color(0.47, 0.78, 1, 0.22), 1.0)
		draw_arc(gp["muzzle"], 4, 0, TAU, 12, Color(1, 0.31, 0.31, 0.95), 1.6)
		draw_arc(gp["grip"], 3, 0, TAU, 12, Color(0.35, 0.9, 0.55, 0.8), 1.4)
	# 绿框=地图物理体；品红框=站立受击体、橙框=翻滚低姿态，避免把两者混看。
	draw_rect(host._player_rect(), Color(0.47, 1, 0.7, 0.65), false, 1.0)
	var hurt_color := Color(1, 0.64, 0.22, 0.95) if p.rolling() else Color(1, 0.25, 0.68, 0.95)
	draw_rect(host._player_hurtbox(), hurt_color, false, 1.0)
