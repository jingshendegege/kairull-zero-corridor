extends Sprite2D
class_name BeatNote
const ART := "res://assets/boss/beat_warden/"
var kind := "normal"
var lane := "ground"
var hit_time := 0.0
var cycle := 0
var speed := 520.0
var judge_x := 0.0
var cracked := false
var reflected := false
var reflection_target := Vector2.ZERO
var spent := false
var contacted := false
var missed := false
var last_swing := -1
var _slow_time := 0.0
var _slow_x := 0.0

func setup(event: Dictionary, config: Dictionary, note_speed: float, now: float) -> void:
	kind = event.kind
	lane = event.lane
	hit_time = float(event.time)
	cycle = int(event.get("cycle", 0))
	speed = note_speed
	judge_x = float(config.judge_x)
	position.y = float(config["lane_" + lane + "_y"])
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sync_texture()
	advance_incoming(now)

func body_rect() -> Rect2:
	return Rect2(position - texture.get_size() * 0.5, texture.get_size())

func advance_incoming(now: float) -> void:
	position.x = _slow_x - (now - _slow_time) * speed if cracked \
			else judge_x + (hit_time - now) * speed

func bat_contact(swing: int, now: float) -> bool:
	if spent or reflected or last_swing == swing:
		return false
	last_swing = swing
	contacted = true
	if kind == "bomb":
		spent = true
	elif kind == "heavy" and not cracked:
		cracked = true
		_slow_time = now
		_slow_x = position.x
		speed *= 0.5
		_sync_texture()
	else:
		reflected = true
	return true

func _sync_texture() -> void:
	var suffix := "_air" if lane == "air" and kind != "heavy" else ""
	if cracked:
		suffix = "_cracked"
	texture = load(ART + "note_" + kind + suffix + ".png")
