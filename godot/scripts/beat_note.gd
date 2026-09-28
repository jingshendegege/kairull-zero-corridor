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
## 2026-09-28 用户要求：黄色重音改为「上下一起按」的双键音符，显示在两层中间，打中后被击飞。
var dual_press := {"air": -INF, "ground": -INF}   ## 双键音符两层各自的按键时刻
var fly_from := Vector2.ZERO
var fly_t := -1.0                                  ## >= 0 时按击飞弧线飞向 Boss
var _lane_ys := Vector2.ZERO                       ## (上层 y, 下层 y)，用于画双键连接光柱
var _slow_x := 0.0

func setup(event: Dictionary, config: Dictionary, note_speed: float, now: float) -> void:
	kind = event.kind
	lane = event.lane
	hit_time = float(event.time)
	cycle = int(event.get("cycle", 0))
	speed = note_speed
	judge_x = float(config.judge_x)
	position.y = float(config["lane_" + lane + "_y"])
	if kind == "heavy":
		_lane_ys = Vector2(float(config.lane_air_y), float(config.lane_ground_y))
		position.y = (_lane_ys.x + _lane_ys.y) * 0.5
		var beam := Node2D.new()
		beam.name = "DualBeam"
		beam.show_behind_parent = true
		beam.draw.connect(_draw_dual_beam.bind(beam))
		add_child(beam)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sync_texture()
	advance_incoming(now)

## 双键提示：上下两层各一个金色小钻 + 竖向光柱，告诉玩家这一拍要上下一起按。
func _draw_dual_beam(beam: Node2D) -> void:
	if reflected:
		return
	var top := _lane_ys.x - position.y
	var bottom := _lane_ys.y - position.y
	beam.draw_rect(Rect2(-3, top, 6, bottom - top), Color("ffb020", 0.55))
	beam.draw_rect(Rect2(-1, top, 2, bottom - top), Color("fff0b0", 0.9))
	for y in [top, bottom]:
		beam.draw_colored_polygon(PackedVector2Array([Vector2(0, y - 9), Vector2(9, y), Vector2(0, y + 9), Vector2(-9, y)]), Color("0a0606"))
		beam.draw_colored_polygon(PackedVector2Array([Vector2(0, y - 7), Vector2(7, y), Vector2(0, y + 7), Vector2(-7, y)]), Color("ffb020"))

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
