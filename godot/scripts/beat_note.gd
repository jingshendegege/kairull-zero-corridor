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
const MISSILE_SPEED := 1.6                         ## 导弹比普通音符快 1.6 倍，从画面右侧外飞入，仍准点到达判定线
const MISSILE_WARN_X := 2200.0                     ## 预警「!」画在该层 Boss 身前（世界 x），不被 Boss 挡住
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
	if kind == "missile":
		speed = note_speed * MISSILE_SPEED
		scale = Vector2.ONE * 1.3   # 导弹放大，飞行中更醒目
		var flame := Node2D.new()
		flame.name = "Flame"
		flame.show_behind_parent = true
		var fmat := CanvasItemMaterial.new()
		fmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		flame.material = fmat
		flame.draw.connect(_draw_missile_flame.bind(flame))
		add_child(flame)
		var warn := Node2D.new()
		warn.name = "Warn"
		warn.top_level = true
		warn.position = Vector2(MISSILE_WARN_X, position.y)
		warn.draw.connect(_draw_missile_warn.bind(warn))
		add_child(warn)
	if kind == "bomb":
		scale = Vector2.ONE * 1.25   # 炸弹放大，配合光环更醒目
		var glow := Node2D.new()
		glow.name = "BombGlow"
		glow.show_behind_parent = true
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = mat
		glow.draw.connect(_draw_bomb_glow.bind(glow))
		add_child(glow)
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

## 炸弹光环：品红外圈 + 白色内圈，约 5Hz 脉动；让炸弹在红黑舞台上始终醒目。
func _draw_bomb_glow(glow: Node2D) -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 5.0)
	glow.draw_circle(Vector2.ZERO, 22.0 + 4.0 * pulse, Color(1.0, 0.2, 0.85, 0.28 + 0.2 * pulse))
	glow.draw_arc(Vector2.ZERO, 19.0 + 3.0 * pulse, 0.0, TAU, 32, Color(1, 1, 1, 0.5 + 0.3 * pulse), 2.0)


func _process(_dt: float) -> void:
	if kind == "bomb" and not spent:
		var glow := get_node_or_null("BombGlow")
		if glow != null:
			glow.queue_redraw()
	elif kind == "missile" and not spent:
		for child_name in ["Flame", "Warn"]:
			var node := get_node_or_null(child_name)
			if node != null:
				node.queue_redraw()


## 导弹尾焰：喷口在右侧，橙黄火舌向右拖出并快速闪烁。
func _draw_missile_flame(flame: Node2D) -> void:
	var f := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.08)
	var base := Vector2(texture.get_width() * 0.5 - 6, 0)
	flame.draw_colored_polygon(PackedVector2Array([base + Vector2(0, -6), base + Vector2(34 * f, 0), base + Vector2(0, 6)]), Color(1.0, 0.45, 0.1, 0.7))
	flame.draw_colored_polygon(PackedVector2Array([base + Vector2(0, -3), base + Vector2(18 * f, 0), base + Vector2(0, 3)]), Color(1.0, 0.95, 0.6, 0.9))


## 导弹预警：在该层右侧边缘闪红色「!」，导弹飞过后消失。
func _draw_missile_warn(warn: Node2D) -> void:
	if spent or position.x < MISSILE_WARN_X - 30.0:
		return
	if fmod(Time.get_ticks_msec() / 1000.0, 0.2) > 0.12:
		return
	warn.draw_colored_polygon(PackedVector2Array([Vector2(0, -22), Vector2(20, 14), Vector2(-20, 14)]), Color("0a0606"))
	warn.draw_colored_polygon(PackedVector2Array([Vector2(0, -17), Vector2(15, 11), Vector2(-15, 11)]), Color("ff2a1a"))
	warn.draw_rect(Rect2(-2, -9, 4, 11), Color.WHITE)
	warn.draw_rect(Rect2(-2, 5, 4, 4), Color.WHITE)


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
	if kind in ["bomb", "missile"]:
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
	if kind == "missile":
		texture = load(ART + "note_missile.png")
		return
	var suffix := "_air" if lane == "air" and kind != "heavy" else ""
	if cracked:
		suffix = "_cracked"
	texture = load(ART + "note_" + kind + suffix + ".png")
