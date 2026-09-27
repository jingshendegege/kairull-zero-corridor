extends Node2D
class_name GlassPanel
## Door-compatible blocker; the host advances particles and owns all feedback.

signal shattered(panel: GlassPanel)

const MAX_SHARDS := 18
const SHARD_LIFETIME := 0.45
var broken := false
var locked: bool:
	get: return not broken
var dead: bool:
	get: return broken
var room_id := ""
var size := Vector2(32, 128)
var shards: Array[Dictionary] = []


func setup(config: Dictionary) -> void:
	var bounds: Array = config.get("rect", [0, 0, 32, 128])
	position = Vector2(float(bounds[0]), float(bounds[1]))
	size = Vector2(maxf(1.0, float(bounds[2])), maxf(1.0, float(bounds[3])))
	room_id = str(config.get("room_id", ""))
	set_meta("checkpoint_key", str(config.get("id", "glass:%s:%s" % [position, size])))
	restore_broken(false)


func body_rect() -> Rect2:
	return Rect2(position, size)


func take_hit(_from_x: float, damage := 1) -> bool:
	if broken or damage <= 0:
		return false
	broken = true
	shards.clear()
	for index in MAX_SHARDS:
		var angle := float(index) * 2.399963
		shards.append({"p": Vector2(size.x * (float(index % 3) + 0.5) / 3.0,
				size.y * (float(index) + 0.5) / MAX_SHARDS),
			"v": Vector2(cos(angle) * 160.0, -70.0 - absf(sin(angle)) * 120.0),
			"life": SHARD_LIFETIME})
	shattered.emit(self)
	queue_redraw()
	return true


func advance(dt: float) -> void:
	if dt <= 0.0 or shards.is_empty():
		return
	for bit: Dictionary in shards:
		bit.p += bit.v * dt
		bit.v.y += 680.0 * dt
		bit.life -= dt
	shards = shards.filter(func(bit: Dictionary) -> bool: return bit.life > 0.0)
	queue_redraw()


func restore_broken(value: bool) -> void:
	broken = value
	shards.clear()
	queue_redraw()


func capture_timeline_state() -> Dictionary:
	return {"broken": broken, "shards": shards.duplicate(true)}


func apply_timeline_state(state: Dictionary) -> void:
	broken = bool(state.get("broken", false))
	shards.assign(state.get("shards", []).slice(0, MAX_SHARDS).duplicate(true))
	queue_redraw()


func _draw() -> void:
	_draw_visuals()


func _draw_visuals() -> void:
	if not broken:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.78, 0.82, 0.62))
		draw_rect(Rect2(Vector2.ZERO, size), Color("#abdfe4"), false, 2.0)
		for y in range(12, int(size.y), 24):
			draw_line(Vector2(5, y), Vector2(size.x - 5, y - 8), Color("#d6f3ee"), 1.0)
	for bit: Dictionary in shards:
		var tint := Color("#b9edf2")
		tint.a = clampf(float(bit.life) / SHARD_LIFETIME, 0.0, 1.0)
		draw_line(bit.p, bit.p + Vector2(3, -5), tint, 2.0)
