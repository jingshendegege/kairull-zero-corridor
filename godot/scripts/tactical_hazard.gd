extends Node2D
class_name TacticalHazard
## 机关只接受game主动推进；没有_process/Timer，时停和死亡阶段不会漏走内部时钟。
## 坐标约定：炮塔pos是脚底；激光pos是左端线心；压机pos是顶部左角、floor_y是落地面。

signal projectile_requested(origin: Vector2, velocity: Vector2, damage_type: StringName)
signal sound_requested(event: StringName)
signal destroyed(world_position: Vector2)

const AMBER := Color("#f8c778")
const CYAN := Color("#83d9d0")
const DANGER := Color("#f48791")
const AIM_RED := Color("#ff5867")
const STEEL := Color("#384b57")
const DARK := Color("#15212b")
const TRACE_STEP := 4.0
const SNIPER_TRACK_TIME := 1.5 ## 跟踪时间减半；之后仍保留独立0.5秒锁定反应窗。
const SNIPER_LOCK_TIME := 0.5
const SNIPER_COOLDOWN := 1.5 ## 用户指定射后1.5秒冷却，不影响光栅/压机节拍。
const PRESS_PLATE_H := 24.0

var hazard_type := "auto_sniper"
var room_id := ""
var hard_only := false
var dead := false
var cleared_disabled := false
var state := "idle"
var frame := 0
var hitstop := 0.0 # 最小可击毁目标接口；器械不套用生物尸体求解器。
var hp := 1
var armed := false
var phase_time := 0.0
var shot_count := 0
var level: Node
var door_blockers: Array = []
var direction := Vector2.LEFT
var detection_range := 640.0
var bullet_speed := 2700.0
var warning_duration := SNIPER_TRACK_TIME
var active_duration := 0.08
var recovery_duration := SNIPER_COOLDOWN
var span := 160.0
var width := 64.0
var press_height := 160.0
var floor_y := 0.0
var beam_height := 6.0
var aim_direction := Vector2.LEFT
var last_target := Vector2.ZERO
var trace_end := Vector2.ZERO
var _press_previous_rect := Rect2()
var _recovery_after_shot := false


func setup(config: Dictionary, collision_level: Node, doors: Array = []) -> void:
	hazard_type = str(config.get("type", "auto_sniper"))
	room_id = str(config.get("room_id", ""))
	hard_only = bool(config.get("hard_only", false))
	position = _vector(config.get("pos", Vector2.ZERO), Vector2.ZERO)
	level = collision_level
	door_blockers = doors
	var raw_direction: Variant = config.get("direction", [-1.0, 0.0])
	if raw_direction is float or raw_direction is int:
		direction = Vector2(-1.0 if float(raw_direction) < 0.0 else 1.0, 0.0)
	else:
		direction = _vector(raw_direction, Vector2.LEFT).normalized()
	if direction.is_zero_approx():
		direction = Vector2.LEFT
	# 不能从远处隔房盲锁：配置有硬上限，外层还必须校验房间和真实可视范围。
	detection_range = clampf(float(config.get("range", 640.0)), 128.0, 1024.0)
	bullet_speed = clampf(float(config.get("bullet_speed", 2700.0)), 2400.0, 3000.0)
	span = clampf(float(config.get("span", config.get("length", 160.0))), 64.0, 320.0)
	width = clampf(float(config.get("width", 64.0)), 40.0, 128.0)
	floor_y = float(config.get("floor_y", position.y + 160.0))
	press_height = clampf(floor_y - position.y, 64.0, 320.0)
	beam_height = 6.0
	match hazard_type:
		"laser_gate":
			warning_duration = maxf(0.95, float(config.get("warning", 0.95)))
			active_duration = clampf(float(config.get("active", 0.52)), 0.2, 0.8)
			recovery_duration = maxf(1.3, float(config.get("recovery", 1.3)))
		"press":
			warning_duration = maxf(1.1, float(config.get("warning", 1.1)))
			active_duration = clampf(float(config.get("active", 0.48)), 0.2, 0.75)
			recovery_duration = maxf(1.35, float(config.get("recovery", 1.35)))
		_:
			hazard_type = "auto_sniper"
			# 用户确定新节奏：跟踪3秒→锁向半秒→一枪→冷却3秒，旧地图参数不能缩短。
			warning_duration = SNIPER_TRACK_TIME
			active_duration = 0.08
			recovery_duration = SNIPER_COOLDOWN
	dead = false
	cleared_disabled = false
	hp = 1
	armed = false
	state = "idle"
	phase_time = 0.0
	frame = 0
	shot_count = 0
	_recovery_after_shot = false
	aim_direction = direction
	last_target = muzzle_position() + direction * detection_range
	trace_end = muzzle_position() + direction * detection_range
	_press_previous_rect = _press_plate_rect()
	z_index = 1
	queue_redraw()


func _vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


func set_armed(value: bool) -> void:
	if cleared_disabled or dead:
		armed = false
		return
	if value == armed:
		return
	armed = value
	# 离屏/离房取消旧锁定，重新进入时一定看到完整预警，不保存偷射倒计时。
	if not armed and not dead:
		_change_state("idle")
		_press_previous_rect = _press_plate_rect()
	queue_redraw()


func deactivate_cleared() -> void:
	# 清房停机不同于暂时离屏：本次关卡永久停用，下一帧可视激活不得把它复活。
	if dead or cleared_disabled:
		return
	cleared_disabled = true
	armed = false
	_change_state("disabled")
	_press_previous_rect = _press_plate_rect()
	queue_redraw()


func advance(dt: float, player: Node2D, smoke_obscured := false) -> void:
	if dead or cleared_disabled or not armed or not is_instance_valid(player):
		return
	if "dead" in player and player.dead:
		return
	if hazard_type == "auto_sniper" and smoke_obscured and state in ["warning", "locked"]:
		# 烟雾遮断目标也取消最后半秒锁定：清除旧目标与红线，出烟重走完整3秒+0.5秒。
		# 这是视线失效而非计时推进；时停中走入已有烟也须立即失锁，不能解冻后偷射。
		_change_state("idle")
		last_target = Vector2.ZERO
		trace_end = Vector2.ZERO
		aim_direction = direction
		queue_redraw()
		return
	if dt <= 0.0:
		return
	frame += 1
	_press_previous_rect = _press_plate_rect()
	if hazard_type == "auto_sniper":
		_advance_sniper(dt, player, smoke_obscured)
	else:
		_advance_trap(dt)
	queue_redraw()


func _advance_sniper(dt: float, player: Node2D, smoke_obscured: bool) -> void:
	match state:
		"idle":
			if _can_acquire(player, smoke_obscured):
				_track(player)
				_change_state("warning")
		"warning":
			if not _can_acquire(player, smoke_obscured):
				_change_state("recovery")
				return
			_track(player)
			phase_time += dt
			if phase_time >= warning_duration:
				_change_state("locked")
				sound_requested.emit(&"sniper_lock")
		"locked":
			# 跟踪结束后另等0.5s，弹道和last_target固定；烟雾由advance入口统一取消锁定。
			trace_end = _ray_end(muzzle_position(), aim_direction, detection_range)
			phase_time += dt
			if phase_time >= SNIPER_LOCK_TIME:
				shot_count += 1
				projectile_requested.emit(muzzle_position(), aim_direction * bullet_speed, &"gunshot")
				_change_state("recovery")
				_recovery_after_shot = true
		"recovery":
			phase_time += dt
			if phase_time >= recovery_duration:
				_change_state("idle")


func _advance_trap(dt: float) -> void:
	# 每次最多跨一个阶段，丢帧也不吞掉预警/安全窗，更不会一帧内连放多轮伤害。
	match state:
		"idle":
			_change_state("warning")
		"warning":
			phase_time += dt
			if phase_time >= warning_duration:
				_change_state("active")
				if hazard_type == "press":
					sound_requested.emit(&"metal_impact")
		"active":
			phase_time += dt
			if phase_time >= active_duration:
				_change_state("recovery")
		"recovery":
			phase_time += dt
			if phase_time >= recovery_duration:
				_change_state("warning")


func _change_state(value: String) -> void:
	state = value
	phase_time = 0.0
	frame = 0
	_recovery_after_shot = false


func _can_acquire(player: Node2D, smoke_obscured: bool) -> bool:
	if smoke_obscured:
		return false
	var target := player.position + Vector2(0.0, -58.0)
	var offset := target - muzzle_position()
	if offset.length() > detection_range or offset.length() < 22.0:
		return false
	if offset.normalized().dot(direction) < 0.72 or absf(offset.y) > 160.0:
		return false
	var end := _ray_end(muzzle_position(), offset.normalized(), offset.length())
	return end.distance_to(target) <= TRACE_STEP


func _track(player: Node2D) -> void:
	# 瞄准胸头之间的固定高度，不跟着翻滚低框往脚下追，低姿态才有明确用途。
	last_target = player.position + Vector2(0.0, -58.0)
	aim_direction = (last_target - muzzle_position()).normalized()
	trace_end = _ray_end(muzzle_position(), aim_direction, detection_range)


func muzzle_position() -> Vector2:
	return position + Vector2(direction.x * 26.0, -56.0)


func aim_line_fast_flashing() -> bool:
	# 总预射3.5s中，最后1s闪线：跟踪末0.5s + 锁向0.5s；绝不闪整个屏幕。
	return hazard_type == "auto_sniper" and (state == "locked" \
		or (state == "warning" and phase_time >= SNIPER_TRACK_TIME - 0.5))


func aim_line_alpha() -> float:
	if not aim_line_fast_flashing():
		return 0.70
	var prefire_time := phase_time if state == "warning" else SNIPER_TRACK_TIME + phase_time
	var half_cycles := int(floor((prefire_time - (SNIPER_TRACK_TIME - 0.5)) * 12.0))
	# 6Hz明暗交替，暗相保留28%红线，玩家始终看得清已锁定弹道。
	return 0.95 if half_cycles % 2 == 0 else 0.28


func _ray_end(origin: Vector2, ray_direction: Vector2, distance: float) -> Vector2:
	var steps := maxi(1, ceili(distance / TRACE_STEP))
	for index in range(1, steps + 1):
		var point := origin + ray_direction * minf(float(index) * TRACE_STEP, distance)
		if _point_blocked(point):
			return origin + ray_direction * maxf(0.0, float(index - 1) * TRACE_STEP)
	return origin + ray_direction * distance


func _point_blocked(point: Vector2) -> bool:
	if is_instance_valid(level) and level.solid_at(point.x, point.y):
		return true
	for door in door_blockers:
		if is_instance_valid(door) and door.locked and door.body_rect().has_point(point):
			return true
	return false


func damage_active() -> bool:
	return armed and not dead and not cleared_disabled and hazard_type != "auto_sniper" and state == "active"


func damage_rect() -> Rect2:
	if not damage_active():
		return Rect2()
	if hazard_type == "laser_gate":
		var end := _ray_end(position, Vector2.RIGHT, span)
		return Rect2(position + Vector2(0.0, -beam_height * 0.5), Vector2(maxf(0.0, end.x - position.x), beam_height))
	# 压板每步扫过的区域也算，避免快落压机从头到脚穿过却未命中。
	return _press_plate_rect().merge(_press_previous_rect)


func body_rect() -> Rect2:
	if hazard_type != "auto_sniper" or dead:
		return Rect2()
	return Rect2(position + Vector2(-23.0, -78.0), Vector2(46.0, 78.0))


func take_hit(_from_x: float, damage := 1) -> bool:
	if hazard_type != "auto_sniper" or dead or damage <= 0:
		return false
	hp = maxi(0, hp - damage)
	if hp > 0:
		return true
	dead = true
	armed = false
	_change_state("dead")
	sound_requested.emit(&"metal_impact")
	destroyed.emit(position + Vector2(0.0, -48.0))
	queue_redraw()
	return true


func _press_plate_rect() -> Rect2:
	var travel := 0.0
	if state == "warning":
		travel = 4.0 * minf(1.0, phase_time / warning_duration)
	elif state == "active":
		travel = (press_height - PRESS_PLATE_H) * pow(minf(1.0, phase_time / 0.14), 2.0)
	elif state == "recovery":
		travel = (press_height - PRESS_PLATE_H) * (1.0 - minf(1.0, phase_time / 0.35))
	return Rect2(position + Vector2(0.0, travel), Vector2(width, PRESS_PLATE_H))


func _draw() -> void:
	match hazard_type:
		"auto_sniper": _draw_sniper()
		"laser_gate": _draw_laser()
		"press": _draw_press()


func _draw_sniper() -> void:
	var face := -1.0 if direction.x < 0.0 else 1.0
	var lamp := CYAN if armed else Color("#52636a")
	if cleared_disabled:
		lamp = Color("#467978")
	if state in ["warning", "locked", "active"]:
		lamp = DANGER if state != "warning" else AMBER
	# 小型固定工业炮：有底座/装甲/枪管，不复用枪手人物或改变其获认可美术。
	draw_rect(Rect2(-22, -12, 44, 12), DARK)
	draw_line(Vector2(-16, -10), Vector2(-7, -38), STEEL, 5.0)
	draw_line(Vector2(16, -10), Vector2(7, -38), STEEL, 5.0)
	draw_rect(Rect2(-19, -72, 38, 35), Color("#0b141c"))
	draw_rect(Rect2(-16, -69, 32, 29), STEEL if not dead else Color("#273039"))
	draw_line(Vector2(-15, -69), Vector2(15, -69), Color("#6b8088"), 2.0)
	var barrel_tip := Vector2(face * (19.0 if dead else 30.0), -49.0 if dead else -56.0)
	draw_line(Vector2(face * 7.0, -54.0), barrel_tip, Color("#101a22"), 10.0)
	draw_line(Vector2(face * 9.0, -57.0), barrel_tip + Vector2(0, -2), STEEL, 4.0)
	draw_rect(Rect2(-7, -78, 14, 5), Color("#1f2b34") if dead else lamp)
	for x in [-12.0, 8.0]:
		draw_rect(Rect2(x, -47, 4, 3), Color("#718089"))
	if dead:
		draw_line(Vector2(-9, -69), Vector2(7, -52), Color("#10171f"), 3.0)
		return
	var charge := 0.0
	if state == "warning":
		charge = phase_time / warning_duration
	elif state == "locked" or state == "active":
		charge = 1.0
	draw_rect(Rect2(-14, -64, 28, 4), Color("#17242b"))
	draw_rect(Rect2(-14, -64, floorf(28.0 * clampf(charge, 0.0, 1.0)), 4), lamp)
	if state in ["warning", "locked"]:
		var start := muzzle_position() - position
		var finish := trace_end - position
		var tint := Color(AIM_RED, aim_line_alpha())
		draw_line(start.round(), finish.round(), tint, 1.0 if state == "warning" else 2.0)
		draw_rect(Rect2(finish.round() - Vector2(2, 3), Vector2(4, 6)), Color(AIM_RED, aim_line_alpha()))
		if state == "locked":
			draw_rect(Rect2(start + Vector2(-3, -3), Vector2(6, 6)), AMBER)
	if state == "recovery" and _recovery_after_shot and phase_time < active_duration:
		var start := muzzle_position() - position
		draw_line(start, start + aim_direction * 19.0, AMBER, 4.0)


func _draw_laser() -> void:
	var active := damage_active()
	var lamp := DANGER if active else AMBER if state == "warning" else CYAN
	if not armed:
		lamp = Color("#53646b")
	for x in [-8.0, span]:
		draw_rect(Rect2(x - 3, -15, 11, 30), Color("#111c25"))
		draw_rect(Rect2(x, -12, 5, 24), STEEL)
		draw_rect(Rect2(x, -4, 5, 8), lamp)
	var end := _ray_end(position, Vector2.RIGHT, span) - position
	if active:
		draw_line(Vector2.ZERO, end, Color(DANGER, 0.20), 6.0)
		draw_line(Vector2.ZERO, end, DANGER, 2.0)
		draw_line(Vector2.ZERO, end, Color("#ffe2c8"), 1.0)
	elif state == "warning":
		for x in range(0, int(end.x), 14):
			draw_line(Vector2(x, 0), Vector2(minf(x + 6.0, end.x), 0), Color(AMBER, 0.55), 1.0)
		var charge := clampf(phase_time / warning_duration, 0.0, 1.0)
		draw_rect(Rect2(-9, 18, floorf(span * charge), 2), AMBER)


func _draw_press() -> void:
	var plate := _press_plate_rect()
	plate.position -= position
	var lamp := DANGER if damage_active() else AMBER if state == "warning" else CYAN
	if not armed:
		lamp = Color("#53646b")
	# 落点两侧细导轨和地面警戒纹让压机空间可读；不做全屏红闪。
	for x in [0.0, width - 5.0]:
		draw_rect(Rect2(x, -6, 5, press_height + 6), Color("#24333d"))
		draw_rect(Rect2(x + 1, -6, 1, press_height + 4), Color("#5a707a"))
	draw_rect(Rect2(6, -10, width - 12, 15), DARK)
	draw_rect(Rect2(width * 0.5 - 5, -7, 10, 4), lamp)
	for x in [width * 0.32, width * 0.66]:
		draw_line(Vector2(x, 4), Vector2(x, plate.position.y + 4), Color("#77898f"), 5.0)
		draw_line(Vector2(x + 1, 4), Vector2(x + 1, plate.position.y + 4), Color("#364951"), 2.0)
	draw_rect(plate, Color("#101a21"))
	draw_rect(plate.grow(-3), STEEL)
	draw_line(plate.position + Vector2(3, 2), plate.position + Vector2(width - 3, 2), Color("#91a2a2"), 2.0)
	for x in range(6, int(width) - 8, 13):
		draw_line(plate.position + Vector2(x, 17), plate.position + Vector2(x + 7, 21), AMBER, 3.0)
	draw_line(Vector2(0, press_height - 1), Vector2(width, press_height - 1), Color(lamp, 0.7), 2.0)
	if state == "warning":
		for y in range(34, int(press_height) - 10, 18):
			draw_line(Vector2(width * 0.5 - 4, y), Vector2(width * 0.5, y + 4), Color(AMBER, 0.6), 1.0)
			draw_line(Vector2(width * 0.5, y + 4), Vector2(width * 0.5 + 4, y), Color(AMBER, 0.6), 1.0)
