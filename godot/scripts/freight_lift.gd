extends Node2D
class_name FreightLift
## 往返货梯只有外部advance推进；相位解析不依赖帧数，时停下行和上行都会冻结。
## pos是下端台面中心，top_y是上端台面；平台保持单向承载，角色可从下方跳穿。

var level: Node
var door_blockers: Array = []
var room_id := ""
var width := 96.0
var height := 12.0
var bottom_y := 384.0
var top_y := 224.0
var travel_time := 2.8
var dwell := 1.2
var state := "bottom_wait"
var phase_time := 0.0
var delta_y := 0.0
var previous_top_y := 384.0
var locked := true # 供主线选择性纳入动态子弹/尸体遮挡，不能混入RoomDoor清房逻辑。
var stalled := false
var _clock := 0.0
var _before_clock := 0.0
var _carried_ids: Dictionary = {}


func setup(config: Dictionary, collision_level: Node, doors: Array = []) -> void:
	var point: Variant = config.get("pos", [0.0, 384.0])
	position = point if point is Vector2 else Vector2(float(point[0]), float(point[1]))
	bottom_y = position.y
	top_y = minf(bottom_y - 32.0, float(config.get("top_y", bottom_y - 160.0)))
	width = clampf(float(config.get("width", 96.0)), 80.0, 192.0)
	height = clampf(float(config.get("height", 12.0)), 8.0, 24.0)
	travel_time = maxf(1.0, float(config.get("travel_time", 2.8)))
	dwell = maxf(0.8, float(config.get("dwell", 1.2)))
	room_id = str(config.get("room_id", ""))
	level = collision_level
	door_blockers = doors
	_clock = 0.0
	_before_clock = 0.0
	previous_top_y = bottom_y
	delta_y = 0.0
	locked = true
	stalled = false
	_carried_ids.clear()
	_set_pose_from_clock()
	z_index = 1
	queue_redraw()


func advance(dt: float) -> void:
	previous_top_y = position.y
	delta_y = 0.0
	_carried_ids.clear()
	_before_clock = _clock
	if dt <= 0.0:
		return
	stalled = false
	_clock += dt
	_set_pose_from_clock()
	delta_y = position.y - previous_top_y
	queue_redraw()


func _set_pose_from_clock() -> void:
	var cycle := 2.0 * (dwell + travel_time)
	var tick := fposmod(_clock, cycle)
	if tick < dwell:
		state = "bottom_wait"
		phase_time = tick
		position.y = bottom_y
	elif tick < dwell + travel_time:
		state = "up"
		phase_time = tick - dwell
		position.y = lerpf(bottom_y, top_y, _travel_curve(phase_time / travel_time))
	elif tick < 2.0 * dwell + travel_time:
		state = "top_wait"
		phase_time = tick - dwell - travel_time
		position.y = top_y
	else:
		state = "down"
		phase_time = tick - 2.0 * dwell - travel_time
		position.y = lerpf(top_y, bottom_y, _travel_curve(phase_time / travel_time))


func _travel_curve(unit_time: float) -> float:
	var u := clampf(unit_time, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u) # 两端缓启缓停，中段匀畅，固定总运行时长。


func top_rect() -> Rect2:
	return Rect2(position.x - width * 0.5, position.y, width, 2.0)


func body_rect() -> Rect2:
	return Rect2(position.x - width * 0.5, position.y, width, height)


func supports_rider(rider: Node2D, use_previous := false) -> bool:
	if not is_instance_valid(rider) or rider.dead or not rider.on_ground or rider.vy < 0.0:
		return false
	var surface := previous_top_y if use_previous else position.y
	if absf(rider.position.y - (surface - 0.1)) > 1.0:
		return false
	return rider.position.x + rider.w * 0.5 - 3.0 > position.x - width * 0.5 \
		and rider.position.x - rider.w * 0.5 + 3.0 < position.x + width * 0.5


func carry_rider(rider: Node2D) -> bool:
	if not is_instance_valid(rider) or _carried_ids.has(rider.get_instance_id()):
		return false
	if not supports_rider(rider, true):
		return false
	_carried_ids[rider.get_instance_id()] = true
	if is_zero_approx(delta_y):
		return true
	var feet_from := rider.position.y
	var feet_to := position.y - 0.1
	var steps := maxi(1, ceili(absf(feet_to - feet_from) / 2.0))
	for index in range(1, steps + 1):
		var feet := lerpf(feet_from, feet_to, float(index) / float(steps))
		if not _rider_clear_at(rider, feet):
			# 不制造挤压穿墙：本次平台与相位一并退回，下一帧待乘客离开或净空恢复。
			_clock = _before_clock
			_set_pose_from_clock()
			position.y = previous_top_y
			delta_y = 0.0
			stalled = true
			queue_redraw()
			return false
	rider.position.y = feet_to
	rider.vy = 0.0
	rider.on_ground = true
	return true


func _rider_clear_at(rider: Node2D, feet: float) -> bool:
	var half_w: float = rider.w * 0.5
	if is_instance_valid(level):
		for x in [rider.position.x - half_w + 0.5, rider.position.x, rider.position.x + half_w - 0.5]:
			for y in [feet - rider.h + 0.5, feet - rider.h * 0.5, feet - 0.5]:
				if level.solid_at(x, y) and not level.is_platform(x, y):
					return false
	var body := Rect2(rider.position.x - half_w + 0.1, feet - rider.h + 0.1, rider.w - 0.2, rider.h - 0.2)
	for door in door_blockers:
		if is_instance_valid(door) and door.locked and door.body_rect().intersects(body):
			return false
	return true


func _draw() -> void:
	var rail_top := top_y - position.y - 78.0
	var rail_bottom := bottom_y - position.y + height
	# 导轨固定在世界上下端；平台绘制在自身局部原点，因此承重台与人同速。
	for x in [-width * 0.5 + 7.0, width * 0.5 - 7.0]:
		draw_rect(Rect2(x - 3, rail_top, 6, rail_bottom - rail_top), Color("#25353f"))
		draw_rect(Rect2(x + 1, rail_top, 1, rail_bottom - rail_top), Color("#61767f"))
		for y in range(int(rail_top) + 6, int(rail_bottom), 32):
			draw_rect(Rect2(x - 5, y, 10, 3), Color("#3a505b"))
		draw_rect(Rect2(x - 5, -3, 10, height + 5), Color("#4c646f"))
	draw_rect(Rect2(-width * 0.5, 0, width, height), Color("#0e1c24"))
	draw_rect(Rect2(-width * 0.5 + 2, 3, width - 4, height - 5), Color("#405863"))
	draw_line(Vector2(-width * 0.5, 0), Vector2(width * 0.5, 0), Color("#b4d5d7"), 2.0)
	for x in range(int(-width * 0.5) + 8, int(width * 0.5) - 8, 20):
		draw_line(Vector2(x, 5), Vector2(x + 6, height - 2), Color("#b4935f"), 2.0)
	var lamp := Color("#e1bc75") if stalled else Color("#8ce2ce")
	var sign_y := -18.0
	var dir := 1.0 if state == "down" else -1.0
	draw_rect(Rect2(-10, -27, 20, 15), Color("#142831"))
	if state.ends_with("wait") or stalled:
		draw_line(Vector2(-5, sign_y), Vector2(5, sign_y), lamp, 2.0)
	else:
		draw_line(Vector2(-4, sign_y - dir * 3), Vector2(0, sign_y + dir * 2), lamp, 2.0)
		draw_line(Vector2(0, sign_y + dir * 2), Vector2(4, sign_y - dir * 3), lamp, 2.0)
