extends RefCounted
## 敌人与主角共用的真实世界死亡弹道：空中保留横向动量，小抛物线、单次回弹、落地摩擦。
## 只解算脚底中心，不负责动画/伤害/音效；最大1/120秒子步与2px扫掠防止穿薄墙地板。

const SPEEDS := [520.0, 580.0, 640.0]
const UP_SPEED := 300.0
const GRAVITY := 2000.0
const AIR_DRAG := 60.0
const GROUND_FRICTION := 2600.0
const BOUNCE_RATIO := 0.30
const LANDING_SPEED_RETAIN := 0.72
const MAX_TIME := 3.0
const MAX_STEP := 1.0 / 120.0
const SWEEP_STEP := 2.0
const CONTACT_EPS := 0.25

var position := Vector2.ZERO
var velocity := Vector2.ZERO
var elapsed := 0.0
var active := false
var grounded := false
var landed := false
var bounce_count := 0
var ground_y := INF
var ground_valid := false
var landing_position := Vector2.ZERO


func launch(origin: Vector2, direction: float, stage := 0, initial_velocity := Vector2.ZERO) -> void:
	position = origin
	var sign_x := -1.0 if direction < 0.0 else 1.0
	velocity = Vector2(sign_x * (SPEEDS[clampi(stage, 0, 2)] \
			+ clampf(initial_velocity.x * sign_x * 0.15, -60.0, 60.0)),
			minf(-UP_SPEED, clampf(initial_velocity.y * 0.35, -420.0, 0.0)))
	elapsed = 0.0
	active = true
	grounded = false
	landed = false
	bounce_count = 0
	ground_y = INF
	ground_valid = false
	landing_position = origin


func advance(dt: float, level: CorridorLevel, half_width: float, body_height: float,
		doors: Array = []) -> bool:
	if not active or dt <= 0.0:
		return false
	var first_contact := false
	var left := minf(dt, MAX_TIME - elapsed)
	while left > 0.000001 and active:
		var step_dt := minf(left, MAX_STEP)
		first_contact = _step(step_dt, level, half_width, body_height, doors) or first_contact
		elapsed += step_dt
		left -= step_dt
		if grounded and absf(velocity.x) < 0.01:
			active = false
		if elapsed >= MAX_TIME - 0.000001:
			active = false  # 深渊中也不永久留下更新任务，回溯由宿主负责。
	if not active:
		velocity = Vector2.ZERO
	ground_y = _surface_below(level, position, half_width, doors)
	ground_valid = ground_y < INF
	return first_contact


func _step(dt: float, level: CorridorLevel, half_width: float, body_height: float, doors: Array) -> bool:
	if grounded:
		var support := _crossed_floor(level, position, position.y + 0.5, half_width, doors)
		if support == INF:
			grounded = false
	var before_vx := velocity.x
	velocity.x = move_toward(velocity.x, 0.0, (GROUND_FRICTION if grounded else AIR_DRAG) * dt)
	var dx := (before_vx + velocity.x) * 0.5 * dt
	var steps := maxi(1, ceili(absf(dx) / SWEEP_STEP))
	for index in steps:
		var candidate := position + Vector2(dx / steps, 0.0)
		if grounded and level != null:
			var step_y := _stair_near(level, candidate.x, position.y, half_width, 16.35, 16.35)
			if step_y < INF:
				candidate.y = step_y - 0.1
		if _body_blocked(level, candidate, half_width, body_height, doors) \
				or _stair_side_blocked(level, position, candidate, half_width, body_height):
			velocity.x = 0.0
			break  # 撞实物只吞横向动量，不把仍在空中的尸体钉住或瞬移。
		position = candidate
	if grounded:
		var support := _crossed_floor(level, position, position.y + 0.5, half_width, doors)
		if support < INF:
			position.y = support - 0.1
			return false
		grounded = false  # 真正飞出平台后继续落向下层，不在平台边沿悬空。
	var old_vy := velocity.y
	velocity.y += GRAVITY * dt
	var dy := (old_vy + velocity.y) * 0.5 * dt
	var y_steps := maxi(1, ceili(absf(dy) / SWEEP_STEP))
	for index in y_steps:
		var next_y := position.y + dy / y_steps
		if dy >= 0.0:
			var floor_y := _crossed_floor(level, position, next_y, half_width, doors)
			if floor_y < INF:
				position.y = floor_y - 0.1
				var first := not landed
				if first:
					landed = true
					landing_position = Vector2(position.x, floor_y)
					velocity.x *= LANDING_SPEED_RETAIN
				if bounce_count == 0 and velocity.y > 100.0:
					bounce_count = 1
					velocity.y = -minf(130.0, velocity.y * BOUNCE_RATIO)
				else:
					velocity.y = 0.0
					grounded = true
				return first
		elif _body_blocked(level, Vector2(position.x, next_y), half_width, body_height, doors):
			velocity.y = 0.0
			break
		position.y = next_y
	return false


func _body_blocked(level: CorridorLevel, feet: Vector2, half_width: float, body_height: float, doors: Array) -> bool:
	var body := Rect2(feet - Vector2(half_width, body_height), Vector2(half_width * 2.0, body_height))
	if level != null:
		if body.position.x < 0.0 or body.end.x > level.world_w:
			return true
		for row in range(floori((body.position.y + 0.5) / 32.0), floori((body.end.y - 0.5) / 32.0) + 1):
			for col in range(floori((body.position.x + 0.5) / 32.0), floori((body.end.x - 0.5) / 32.0) + 1):
				var point := Vector2(col * 32.0 + 16.0, row * 32.0 + 16.0)
				if level.solid_at(point.x, point.y) and not level.is_platform(point.x, point.y):
					return true
	for door in doors:
		if is_instance_valid(door) and door.locked and door.body_rect().intersects(body):
			return true
	return false


func _foot_probes(x: float, half_width: float) -> Array[float]:
	var offset := maxf(0.0, half_width - 3.0)
	return [x - offset, x, x + offset]


func _crossed_floor(level: CorridorLevel, from: Vector2, to_y: float, half_width: float, doors: Array) -> float:
	var best := INF
	if level != null:
		for x in _foot_probes(from.x, half_width):
			best = minf(best, level.stair_surface_crossed(x, from.y, to_y))
			for row in range(floori((from.y - CONTACT_EPS) / 32.0), floori((to_y + CONTACT_EPS) / 32.0) + 1):
				var top := row * 32.0
				if top >= from.y - CONTACT_EPS and top <= to_y + CONTACT_EPS and level.solid_at(x, top + 0.5):
					best = minf(best, top)
	for door in doors:
		if not is_instance_valid(door) or not door.locked:
			continue
		var rect: Rect2 = door.body_rect()
		if from.x + half_width > rect.position.x and from.x - half_width < rect.end.x \
				and rect.position.y >= from.y - CONTACT_EPS and rect.position.y <= to_y + CONTACT_EPS:
			best = minf(best, rect.position.y)
	return best


func _stair_near(level: CorridorLevel, x: float, y: float, half_width: float, up: float, down: float) -> float:
	var best := INF
	for probe in _foot_probes(x, half_width):
		best = minf(best, level.stair_surface_near(probe, y, up, down))
	return best


func _stair_side_blocked(level: CorridorLevel, from: Vector2, to: Vector2, half_width: float, body_height: float) -> bool:
	if level == null or is_equal_approx(from.x, to.x):
		return false
	var dir := signf(to.x - from.x)
	var front := maxf(0.0, half_width - 3.0) * dir
	for stair: Dictionary in level.stairs:
		if int(stair.rise_dir) != int(dir):
			continue
		for index in int(stair.steps):
			var edge := (int(stair.left_c) + index + (0 if dir > 0.0 else 1)) * 32.0
			if (edge - from.x - front) * dir < -0.001 or (to.x + front - edge) * dir <= 0.0:
				continue
			var rank := index + 1 if dir > 0.0 else int(stair.steps) - index
			var y := int(stair.bottom_row) * 32.0 - rank * 16.0
			if to.y > y + CONTACT_EPS and to.y - body_height < y + 16.0:
				return true
	return false


func _surface_below(level: CorridorLevel, feet: Vector2, half_width: float, doors: Array = []) -> float:
	if level == null:
		return INF
	var best := _stair_near(level, feet.x, feet.y, half_width, CONTACT_EPS, level.world_h + 32.0)
	for x in _foot_probes(feet.x, half_width):
		for row in range(maxi(0, floori((feet.y - CONTACT_EPS) / 32.0)), level.map_h):
			var top := row * 32.0
			if top >= feet.y - CONTACT_EPS and level.solid_at(x, top + 0.5):
				best = minf(best, top)
				break
	# 升降钢台面也属于尸体的实际落点；阴影不能穿过台面投到更低楼层。
	for obstacle in doors:
		if not is_instance_valid(obstacle) or not obstacle.locked:
			continue
		var rect: Rect2 = obstacle.body_rect()
		if feet.x + half_width > rect.position.x and feet.x - half_width < rect.end.x \
				and rect.position.y >= feet.y - CONTACT_EPS:
			best = minf(best, rect.position.y)
	return best
