extends Node2D
class_name DashNode
## Contact and respawn use only the host's simulation delta, never a Timer/process callback.

const RADIUS := 14.0
var room_id := ""
var respawn := 2.0
var lit := true
var respawn_remaining := 0.0
var visual_phase := 0.0


func setup(config: Dictionary) -> void:
	var point: Variant = config.get("pos", [0.0, 0.0])
	position = point if point is Vector2 else Vector2(float(point[0]), float(point[1]))
	room_id = str(config.get("room_id", ""))
	respawn = maxf(0.0, float(config.get("respawn", 2.0)))
	z_index = 2
	visual_phase = 0.0
	reset_transient()


func reset_transient() -> void:
	lit = true
	respawn_remaining = 0.0
	queue_redraw()


func advance(dt: float, player: Node2D) -> void:
	if dt <= 0.0 or not is_instance_valid(player) or player.dead:
		return
	visual_phase = fposmod(visual_phase + dt * 3.0, TAU)
	if not lit:
		respawn_remaining = maxf(0.0, respawn_remaining - dt)
		lit = respawn_remaining <= 0.0
	if lit and player.dash_cooldown_t > 0.0 and _touches_player(player):
		player.dash_cooldown_t = 0.0
		lit = false
		respawn_remaining = respawn
		if player.has_method("_sync_dash_cooldown_ui"):
			player._sync_dash_cooldown_ui()
	queue_redraw()


func _touches_player(player: Node2D) -> bool:
	# Use the physical 22x52 movement body, not the larger visual/hurtbox rectangle.
	var body := Rect2(player.position.x - player.w * 0.5, player.position.y - player.h, player.w, player.h)
	var nearest := Vector2(clampf(position.x, body.position.x, body.end.x),
			clampf(position.y, body.position.y, body.end.y))
	return nearest.distance_squared_to(position) <= RADIUS * RADIUS


func _draw() -> void:
	_draw_visuals()


func _draw_visuals() -> void:
	var tint := Color("#80eee1") if lit else Color("#344b55")
	var pulse := 1.0 + sin(visual_phase) * 0.08
	draw_arc(Vector2.ZERO, RADIUS * pulse, 0.0, TAU, 24, tint, 1.5)
	if lit:
		draw_circle(Vector2.ZERO, 10.0, Color(0.3, 0.85, 0.8, 0.16))
	var points := PackedVector2Array([Vector2(2, -8), Vector2(-4, 1), Vector2(1, 1), Vector2(-2, 8), Vector2(5, -2), Vector2(0, -2)])
	draw_colored_polygon(points, tint)
