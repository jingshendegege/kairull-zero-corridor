extends Node2D
class_name UpdraftFan
## The host is the sole clock: pass zero during time-stop, and never step during pause/death.

const RETRIGGER_COOLDOWN := 0.25
var room_id := ""
var width := 64.0
var launch_height := 288.0
var cooldown_t := 0.0
var spin_phase := 0.0


func setup(config: Dictionary) -> void:
	var point: Variant = config.get("pos", [0.0, 0.0])
	position = point if point is Vector2 else Vector2(float(point[0]), float(point[1]))
	room_id = str(config.get("room_id", ""))
	width = maxf(1.0, float(config.get("width", 64.0)))
	launch_height = maxf(0.0, float(config.get("launch_height", 288.0)))
	z_index = 1
	spin_phase = 0.0
	reset_transient()


func reset_transient() -> void:
	cooldown_t = 0.0
	queue_redraw()


func advance(dt: float, player: Node2D) -> void:
	if dt <= 0.0 or not is_instance_valid(player) or player.dead:
		return
	cooldown_t = maxf(0.0, cooldown_t - dt)
	spin_phase = fposmod(spin_phase + dt * TAU * 3.0, TAU)
	if cooldown_t <= 0.0 and player.on_ground and player.vy >= 0.0 \
			and absf(player.position.y - position.y) <= 1.0 \
			and absf(player.position.x - position.x) <= width * 0.5:
		# Player adds gravity before displacement. Half a 60Hz gravity step compensates
		# the discrete apex loss (about 10px at height 288) without changing its physics.
		player.vy = -(sqrt(2.0 * KairullPlayer.GRAV * launch_height) + KairullPlayer.GRAV * 0.5)
		player.on_ground = false
		# A ground burst must stop snapping to the floor after launch. Dash keeps its
		# existing brief vertical freeze, then uses the preserved upward velocity.
		if "_dash_follow_ground" in player:
			player._dash_follow_ground = false
		if "_roll_follow_ground" in player:
			player._roll_follow_ground = false
		cooldown_t = RETRIGGER_COOLDOWN
	queue_redraw()


func _draw() -> void:
	_draw_visuals()


## 像素精灵（tools/art/m06/build_m06_props.py）：4 帧 64×16，扇心 x=32，y=0 贴地表。
const SHEET := preload("res://assets/maps/m06/fan_sheet.png")


func _draw_visuals() -> void:
	var frame := int(floor(spin_phase / TAU * 8.0)) % 4
	draw_texture_rect_region(SHEET, Rect2(-32.0, -2.0, 64.0, 16.0), Rect2(frame * 64, 0, 64, 16))
	for index in 5:
		var x := lerpf(-width * 0.4, width * 0.4, float(index) / 4.0)
		var rise := fposmod(spin_phase / TAU * 36.0 + float(index) * 9.0, 36.0)
		draw_line(Vector2(x, -rise - 3.0), Vector2(x, -rise - 12.0), Color(0.5, 0.88, 0.87, 0.45), 1.0)
