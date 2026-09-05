extends Node2D
## 世界时间域压暗：夹在普通场景/瞬时特效之上、时停主角之下，不遮HUD或重做地图素材。
const SHADE_Z := 40
@export_range(0.0, 0.7) var darkness := 0.46
var host: Node2D
var opacity := 0.0

func _ready() -> void:
	z_index = SHADE_Z
	visible = false

func _process(dt: float) -> void:
	if not is_instance_valid(host):
		return
	var active: bool = host.timeline_enabled and host.time_charge.active and host.time_phase == "playing"
	opacity = move_toward(opacity, darkness if active else 0.0, maxf(dt, 0.0) * 7.0)
	position = host.cam_tl
	visible = opacity > 0.001
	if visible:
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.018, 0.029, 0.043, opacity))
