extends Node2D
## 世界空间烟雾系统：宿主唯一调用step；时停传0，不使用_process或Engine.time_scale。
## 物品设计：单格携带、鼠标定点抛投，遮蔽枪线而不防近战/陷阱，补给位置由地图控制。

signal grenade_thrown(world_point: Vector2)
signal smoke_deployed(world_point: Vector2)
signal grenade_picked_up(world_point: Vector2)

const ICON_SCRIPT := preload("res://scripts/smoke_grenade_icon.gd")
const GRAVITY := 900.0
const MAX_THROW_RANGE := 420.0
const MIN_FLIGHT_TIME := 0.42
const MAX_FLIGHT_TIME := 0.88
const MAX_CLOUDS := 4
const MAX_PICKUPS := 16
const MAX_GRENADES := 4
const SMOKE_RADIUS := 336.0 ## 用户要求左右范围变为原3倍；视觉/遮弹/遮视线统一取此半径。
const SMOKE_VERTICAL_RADIUS := 96.0
const SMOKE_VISUAL_REFERENCE_RADIUS := 112.0
const SMOKE_OUTLINE_SEGMENTS := 64 ## 缓存薄烟轮廓覆盖整个保护椭圆，不留旧宽度之外的隐形免伤带。
const SMOKE_OUTLINE_OBSTACLE_QUANTUM := 4.0 ## 动态货梯最多每移动4px刷新轮廓，避免亚像素位移重复64条射线。
const SMOKE_BASE_OPACITY := 0.28 ## 更浓的底雾明确传达掩护区域；仍让墙面纹理透过，不做不透明灰板。
const SMOKE_LOBE_OPACITY := 0.17 ## 团簇再加局部浓度，配合人物深色剪影保持敌我轮廓可读。
const SMOKE_DURATION := 4.8
const SMOKE_FADE_IN := 0.16
const SMOKE_FADE_OUT := 0.80
const SWEEP_STEP := 3.0
const PICKUP_REACH := 42.0

@export var show_trajectory := true
var level: Node2D
var doors: Array = []
var player: Node2D
var pickups: Array[Dictionary] = []
var grenades: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var _clock := 0.0
var _serial := 0
var _preview := PackedVector2Array()
var _preview_impact := Vector2.ZERO
var _preview_visible := false


func setup(next_level: Node2D, next_doors: Array, next_player: Node2D) -> void:
	level = next_level
	doors = next_doors
	player = next_player
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 薄雾在人物之上仍保留轮廓；宿主可根据自己的层栈覆盖此值。
	z_index = 18


## pos是地图脚底坐标；站在补给旁自动拾取，满槽时原罐体保留。
func spawn_pickup(pos: Vector2) -> Node2D:
	if pickups.size() >= MAX_PICKUPS:
		return null
	var icon := ICON_SCRIPT.new()
	icon.name = "SmokePickup"
	add_child(icon)
	icon.global_position = pos + Vector2(0, -12)
	pickups.append({"position": pos, "node": icon})
	return icon


func try_pickup(actor: Node2D = null) -> bool:
	actor = player if actor == null else actor
	if not _live_actor(actor) or bool(actor.get("carried_smoke")):
		return false
	for index in pickups.size():
		var point: Vector2 = pickups[index]["position"]
		if absf(actor.global_position.x - point.x) > PICKUP_REACH \
				or absf(actor.global_position.y - point.y) > 52.0:
			continue
		# 隔墙贴近的补给不能被吸进背包，房门仍是明确的物理边界。
		if not _line_open(point + Vector2(0, -12), actor.global_position + Vector2(0, -18)):
			continue
		actor.call("set_carried_smoke", true)
		var icon: Node2D = pickups[index]["node"]
		if is_instance_valid(icon):
			icon.free()
		pickups.remove_at(index)
		grenade_picked_up.emit(point)
		return true
	return false


func _live_actor(actor: Node2D) -> bool:
	return is_instance_valid(actor) and not bool(actor.get("dead")) \
			and actor.has_method("set_carried_smoke")


func hand_position(actor: Node2D) -> Vector2:
	var direction := float(actor.get("face"))
	var low: bool = actor.has_method("rolling") and bool(actor.call("rolling"))
	return actor.global_position + Vector2(direction * 10.0, -22.0 if low else -48.0)


## 固定重力反解落点速度；鼠标超范围时等比例截到420px，预览和实弹复用此唯一解。
func trajectory(origin: Vector2, target_world: Vector2) -> Dictionary:
	var offset := target_world - origin
	if offset.length() > MAX_THROW_RANGE:
		offset = offset.normalized() * MAX_THROW_RANGE
	var flight := lerpf(MIN_FLIGHT_TIME, MAX_FLIGHT_TIME,
			clampf(absf(offset.x) / MAX_THROW_RANGE, 0.0, 1.0))
	var velocity := offset / flight - Vector2(0.0, GRAVITY * flight * 0.5)
	return {"origin": origin, "target": origin + offset,
			"velocity": velocity, "duration": flight}


func throw_from(actor: Node2D, target_world: Vector2) -> bool:
	if not _live_actor(actor) or not bool(actor.get("carried_smoke")) \
			or grenades.size() >= MAX_GRENADES:
		return false
	var origin := hand_position(actor)
	# 枪口贴进墙时不穿墙出生，也不吞掉仍可用的携带物。
	if _hard_solid(origin):
		return false
	var solution := trajectory(origin, target_world)
	_serial += 1
	grenades.append({"position": origin, "velocity": solution["velocity"],
			"remaining": solution["duration"], "age": 0.0, "id": _serial})
	actor.call("set_carried_smoke", false)
	grenade_thrown.emit(origin)
	_preview_visible = false
	queue_redraw()
	return true


func step(dt: float) -> void:
	var remaining := maxf(0.0, dt)
	# 长帧也限步，不能跨越墙体/门或跳过烟雾寿命。
	while remaining > 0.000001:
		var substep := minf(remaining, 1.0 / 60.0)
		_advance(substep)
		remaining -= substep
	update_aim_preview()
	queue_redraw()


func _advance(dt: float) -> void:
	_clock += dt
	for index in range(clouds.size() - 1, -1, -1):
		clouds[index]["age"] = float(clouds[index]["age"]) + dt
		if float(clouds[index]["age"]) >= SMOKE_DURATION:
			clouds.remove_at(index)
	for index in range(grenades.size() - 1, -1, -1):
		var grenade: Dictionary = grenades[index]
		var use_dt := minf(dt, float(grenade["remaining"]))
		var from: Vector2 = grenade["position"]
		var velocity: Vector2 = grenade["velocity"]
		var target := from + velocity * use_dt + Vector2(0, 0.5 * GRAVITY * use_dt * use_dt)
		var impact := _sweep(from, target)
		grenade["position"] = impact["position"]
		grenade["velocity"] = velocity + Vector2(0, GRAVITY * use_dt)
		grenade["remaining"] = float(grenade["remaining"]) - use_dt
		grenade["age"] = float(grenade["age"]) + use_dt
		if bool(impact["hit"]) or float(grenade["remaining"]) <= 0.000001:
			deploy_cloud(grenade["position"])
			grenades.remove_at(index)


## 接地/墙面即释烟；烟心向上48px伸展，顶棚不足时保持可用空间，不挪进别的房间。
func deploy_cloud(point: Vector2) -> void:
	var center := point
	for _i in 16:
		var next := center + Vector2(0, -3)
		if _hard_solid(next):
			break
		center = next
	while clouds.size() >= MAX_CLOUDS:
		clouds.pop_front()
	_serial += 1
	var cloud := {"position": center, "age": 0.0, "id": _serial}
	_update_cloud_outline(cloud)
	clouds.append(cloud)
	smoke_deployed.emit(point)
	queue_redraw()


func cloud_opacity(cloud: Dictionary) -> float:
	var age := float(cloud["age"])
	return minf(clampf(age / SMOKE_FADE_IN, 0.0, 1.0),
			clampf((SMOKE_DURATION - age) / SMOKE_FADE_OUT, 0.0, 1.0))


func contains_point(world_point: Vector2) -> bool:
	if _hard_solid(world_point):
		return false
	for cloud in clouds:
		if cloud_opacity(cloud) < 0.12:
			continue ## 完全透明的起消端不提供看不见的免伤。
		var center: Vector2 = cloud["position"]
		var delta := world_point - center
		if Vector2(delta.x / SMOKE_RADIUS, delta.y / SMOKE_VERTICAL_RADIUS).length_squared() <= 1.0 \
				and _line_open(center, world_point):
			return true
	return false


## 身体中心进入烟区才算藏身；仅发梢/武器碰到边缘不获得整个身体的枪击免伤。
func contains_actor(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or bool(actor.get("dead")):
		return false
	var center := actor.global_position + Vector2(0, -32)
	if actor.has_method("hurtbox_rect"):
		center = (actor.call("hurtbox_rect") as Rect2).get_center()
	elif actor.has_method("body_rect"):
		center = (actor.call("body_rect") as Rect2).get_center()
	return contains_point(center)


## 视线穿过有效烟区即被遮断；只是索敌/预警条件，不直接删除子弹或免除近战伤害。
func blocks_segment(from: Vector2, to: Vector2) -> bool:
	for cloud in clouds:
		if cloud_opacity(cloud) < 0.12:
			continue
		var center: Vector2 = cloud["position"]
		var scale_xy := Vector2(SMOKE_RADIUS, SMOKE_VERTICAL_RADIUS)
		var start := (from - center) / scale_xy
		var delta := (to - from) / scale_xy
		var progress := clampf(-start.dot(delta) / maxf(delta.length_squared(), 0.000001), 0.0, 1.0)
		var nearest := from.lerp(to, progress)
		if (start + delta * progress).length_squared() <= 1.0 \
				and _line_open(center, nearest):
			return true
	return false


func _hard_solid(point: Vector2) -> bool:
	if level != null and level.has_method("solid_at") \
			and bool(level.call("solid_at", point.x, point.y)):
		if not level.has_method("is_platform") or not bool(level.call("is_platform", point.x, point.y)):
			return true
	for door in doors:
		if is_instance_valid(door) and bool(door.get("locked")) and door.has_method("body_rect"):
			if (door.call("body_rect") as Rect2).grow(2.0).has_point(point):
				return true
	return false


func _line_open(from: Vector2, to: Vector2) -> bool:
	var count := maxi(1, ceili(from.distance_to(to) / SWEEP_STEP))
	for index in count + 1:
		if _hard_solid(from.lerp(to, float(index) / count)):
			return false
	return true


## 对每3px分段检查墙、闭门、向下跨单向台和16px楼梯；开敞台阶上升可穿。
func _sweep(from: Vector2, to: Vector2) -> Dictionary:
	var count := maxi(1, ceili(from.distance_to(to) / SWEEP_STEP))
	var previous := from
	for index in range(1, count + 1):
		var point := from.lerp(to, float(index) / count)
		var blocked := _hard_solid(point)
		if not blocked and level != null and point.y >= previous.y:
			if level.has_method("is_platform") and bool(level.call("is_platform", point.x, point.y)):
				var top := floorf(point.y / 32.0) * 32.0
				blocked = previous.y <= top + 0.1
			if not blocked and level.has_method("stair_surface_crossed"):
				blocked = float(level.call("stair_surface_crossed", point.x, previous.y, point.y)) < INF
		if blocked:
			return {"position": previous, "hit": true}
		previous = point
	return {"position": to, "hit": false}


func update_aim_preview() -> void:
	_preview.clear()
	_preview_visible = show_trajectory and _live_actor(player) and player.has_method("smoke_aiming") \
			and bool(player.call("smoke_aiming"))
	if not _preview_visible or not player.has_method("_aim_point"):
		return
	var solution := trajectory(hand_position(player), player.call("_aim_point"))
	var origin: Vector2 = solution["origin"]
	var velocity: Vector2 = solution["velocity"]
	var duration := float(solution["duration"])
	var previous := origin
	_preview.append(origin)
	for index in range(1, 25):
		var at := duration * float(index) / 24.0
		var point := origin + velocity * at + Vector2(0, 0.5 * GRAVITY * at * at)
		var impact := _sweep(previous, point)
		_preview.append(impact["position"])
		previous = impact["position"]
		if bool(impact["hit"]):
			break
	_preview_impact = previous


func clear() -> void:
	for pickup in pickups:
		if is_instance_valid(pickup["node"]):
			pickup["node"].free()
	pickups.clear()
	clear_effects()


## 短倒带只清动态烟/弹体；地上尚未拾取的罐子保持，整关重载才恢复地图初始补给。
func clear_effects() -> void:
	grenades.clear()
	clouds.clear()
	_preview.clear()
	_preview_visible = false
	if is_instance_valid(player):
		player.call("set_carried_smoke", false)
		player.call("set_smoke_cover", false)
	queue_redraw()


## 底层薄烟与遮弹/遮视线使用同一个椭圆。出生或附近动态遮挡改变时重建，不逐帧重复64条采样。
func _cloud_outline_points(center: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	if _hard_solid(center):
		return result
	for index in SMOKE_OUTLINE_SEGMENTS:
		var angle := TAU * float(index) / SMOKE_OUTLINE_SEGMENTS
		var ray := Vector2(cos(angle) * SMOKE_RADIUS, sin(angle) * SMOKE_VERTICAL_RADIUS)
		var count := maxi(1, ceili(ray.length() / SWEEP_STEP))
		var safe := center
		for sample in range(1, count + 1):
			var point := center + ray * (float(sample) / count)
			if _hard_solid(point):
				break
			safe = point
		var vertex := safe.round()
		if result.is_empty() or vertex != result[result.size() - 1]:
			result.append(vertex)
	if result.size() > 1 and result[0] == result[result.size() - 1]:
		result.remove_at(result.size() - 1)
	return result


func _door_outline_key(center := Vector2.ZERO) -> int:
	var key := 17
	var radius := Vector2(SMOKE_RADIUS, SMOKE_VERTICAL_RADIUS)
	var cloud_bounds := Rect2(center - radius, radius * 2.0)
	for door in doors:
		if not is_instance_valid(door) or not bool(door.get("locked")) or not door.has_method("body_rect"):
			continue
		# doors也包含移动货梯。只让能影响当前烟椭圆的障碍失效缓存，远房电梯不参与。
		var bounds := (door.call("body_rect") as Rect2).grow(2.0) # 与_hard_solid的2px边缘一致。
		if not cloud_bounds.intersects(bounds, true):
			continue
		var quantized_position := Vector2i(floori(bounds.position.x / SMOKE_OUTLINE_OBSTACLE_QUANTUM),
				floori(bounds.position.y / SMOKE_OUTLINE_OBSTACLE_QUANTUM))
		var quantized_size := Vector2i(floori(bounds.size.x / SMOKE_OUTLINE_OBSTACLE_QUANTUM),
				floori(bounds.size.y / SMOKE_OUTLINE_OBSTACLE_QUANTUM))
		key = hash([key, door.get_instance_id(), quantized_position, quantized_size])
	return key


func _update_cloud_outline(cloud: Dictionary) -> void:
	var key := _door_outline_key(cloud["position"])
	if int(cloud.get("outline_key", key - 1)) == key:
		return
	cloud["outline_points"] = _cloud_outline_points(cloud["position"])
	cloud["outline_key"] = key


func _draw() -> void:
	if _preview_visible and _preview.size() >= 2:
		for index in range(1, _preview.size(), 2):
			draw_line(to_local(_preview[index - 1]).round(), to_local(_preview[index]).round(),
					Color(0.58, 0.94, 0.80, 0.48), 1.0, false)
		var at := to_local(_preview_impact).round()
		draw_rect(Rect2(at - Vector2(5, 2), Vector2(10, 4)), Color(0.68, 1.0, 0.85, 0.75), false, 1.0)
	for grenade in grenades:
		var at := to_local(grenade["position"]).round()
		draw_rect(Rect2(at - Vector2(4, 5), Vector2(8, 10)), Color("#bdddc8"))
		draw_rect(Rect2(at - Vector2(4, 1), Vector2(8, 3)), Color("#347d74"))
	for cloud in clouds:
		var opacity := cloud_opacity(cloud)
		if opacity <= 0.001:
			continue
		var center: Vector2 = cloud["position"]
		_update_cloud_outline(cloud)
		var outline: PackedVector2Array = cloud["outline_points"]
		var local_outline := PackedVector2Array()
		if outline.size() >= 3:
			for point in outline:
				local_outline.append(to_local(point))
			draw_colored_polygon(local_outline, Color(0.40, 0.54, 0.54, opacity * SMOKE_BASE_OPACITY))
		var horizontal_factor := SMOKE_RADIUS / SMOKE_VISUAL_REFERENCE_RADIUS
		# 固定17个阶梯边缘团簇，最多68簇；不逐帧生成纹理、材质或全屏模糊。
		for index in 17:
			var angle := float(index) * 2.39996 + float(int(cloud["id"]) % 5) * 0.24
			var radius := sqrt(float(index) / 17.0)
			var drift := sin(float(cloud["age"]) * 1.2 + index) * 3.0
			var offset := Vector2(cos(angle) * 77.0 * radius * horizontal_factor,
					sin(angle) * 62.0 * radius + drift)
			var position_world := center + offset
			if _hard_solid(position_world) or not _line_open(center, position_world):
				continue
			var extent := Vector2((35.0 + (index % 3) * 3.0) * horizontal_factor,
					28.0 + (index % 4) * 3.0)
			var tint := Color(0.40, 0.54, 0.54, (SMOKE_LOBE_OPACITY + (index % 3) * 0.018) * opacity)
			_draw_pixel_lobe(to_local(position_world).snapped(Vector2(2, 2)), extent, tint, local_outline)
		# 青白小短线给烟区可读边缘，不把角色或房间抹成一块灰板。
		for index in 5:
			var tick := center + Vector2((-65 + index * 31) * horizontal_factor,
					-28 + (index % 3) * 23)
			if not _hard_solid(tick) and _line_open(center, tick):
				draw_rect(Rect2(to_local(tick).round(), Vector2(7 * horizontal_factor, 2)), Color(0.72, 0.84, 0.80, opacity * 0.18))


func _draw_pixel_lobe(center: Vector2, extent: Vector2, tint: Color,
		clip_outline := PackedVector2Array()) -> void:
	var x := extent.x
	var y := extent.y
	var polygon := PackedVector2Array([
		Vector2(-x * 0.5, -y), Vector2(x * 0.5, -y), Vector2(x * 0.5, -y * 0.75),
		Vector2(x, -y * 0.75), Vector2(x, y * 0.5), Vector2(x * 0.65, y * 0.5),
		Vector2(x * 0.65, y), Vector2(-x * 0.65, y), Vector2(-x * 0.65, y * 0.5),
		Vector2(-x, y * 0.5), Vector2(-x, -y * 0.6), Vector2(-x * 0.5, -y * 0.6)])
	for index in polygon.size():
		polygon[index] = (polygon[index] + center).round()
	if clip_outline.size() < 3:
		return
	# 三倍宽团簇边缘也裁在同一可见轮廓内，不能从墙前把一大片灰雾漏进隔壁房。
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon, clip_outline):
		if clipped.size() >= 3:
			draw_colored_polygon(clipped, tint)
