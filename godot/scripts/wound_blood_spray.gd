extends Node2D
class_name WoundBloodSpray
## 伤口附近的短时连续小喷血。
##
## 这是独立于 SlimeRibbonBurst 主液幕的第二层打击反馈：只绘制少量像素血滴，
## 不读取屏幕纹理、不承担持久墙渍，也不会改变主喷溅的节奏。实例播放结束后可回池复用。

signal finished(effect: WoundBloodSpray)

const DEFAULT_BLOOD_COLOR := Color("#ff4fa3")
const MAX_LIVE_DROPLETS := 64   ## 极端 Inspector 参数也不无限累积粒子字典。

@export_category("生命周期")
@export_range(0.10, 0.80, 0.01) var normal_duration := 0.34
@export_range(0.10, 0.80, 0.01) var strong_duration := 0.52
@export_range(0.2, 0.9, 0.01) var emission_fraction := 0.78

@export_category("发射")
@export_range(1.0, 160.0, 1.0) var normal_emission_rate := 64.0
@export_range(1.0, 160.0, 1.0) var strong_emission_rate := 92.0
@export_range(10.0, 260.0, 1.0) var speed_min := 76.0
@export_range(10.0, 320.0, 1.0) var speed_max := 148.0
@export_range(0.0, 1200.0, 10.0) var gravity := 360.0
@export_range(0.0, 45.0, 1.0) var spread_degrees := 23.0
@export_range(0.0, 12.0, 0.5) var wound_radius := 5.0

var active := false
var elapsed := 0.0
var duration := 0.28
var strong_mode := false
var current_color := DEFAULT_BLOOD_COLOR

var _direction := Vector2.RIGHT
var _power := 1.0
var _seed := 1
var _emission_rate := 42.0
var _emit_until := 0.20
var _emit_accumulator := 0.0
var _emitted_total := 0
var _droplets: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _follow_target_ref: WeakRef = null


func _ready() -> void:
	# 即使项目全局已使用 Nearest，也在特效节点上明确锁定像素采样规则。
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stop()


## 播放一次伤口喷血。strong=true 用于强攻击或致命攻击。
## blood_color 由主液幕传入，继续使用同一霓虹色族；follow_target 只移动后续喷口。
func play(power: float = 1.0, direction: Vector2 = Vector2.RIGHT,
		seed: int = 1, strong: bool = false,
		blood_color: Color = DEFAULT_BLOOD_COLOR,
		follow_target: Node2D = null) -> void:
	_power = clampf(power, 0.25, 2.0)
	_direction = direction.normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT
	_seed = seed if seed != 0 else int(Time.get_ticks_usec())
	_rng.seed = _seed
	strong_mode = strong
	current_color = blood_color
	duration = strong_duration if strong else normal_duration
	_emission_rate = strong_emission_rate if strong else normal_emission_rate
	_emit_until = duration * clampf(emission_fraction, 0.2, 0.9)
	_emit_accumulator = 0.0
	_emitted_total = 0
	_droplets.clear()
	_follow_target_ref = weakref(follow_target) if follow_target != null else null
	elapsed = 0.0
	position = position.round()
	active = true
	visible = true
	set_process(true)

	# 首帧先给清楚的彩色血点，后续再连续续喷；致命档加量但仍受单实例上限约束。
	var opening_count := 4 if strong else 2
	for _i in opening_count:
		_emit_droplet()
	queue_redraw()


## 立即停播但不销毁；停用 process，确保对象池中的实例没有空转开销。
func stop() -> void:
	active = false
	visible = false
	set_process(false)
	_droplets.clear()
	# 对象池回收时必须断开弱引用，不能让下一次播放继续追上一只敌人。
	_follow_target_ref = null
	queue_redraw()


func _process(dt: float) -> void:
	if not active:
		return
	_update_follow_anchor()

	var previous_elapsed := elapsed
	elapsed = minf(elapsed + maxf(dt, 0.0), duration)
	# 只累计真实落在发射窗口内的时间；大帧步进也不会漏掉应发射的小血滴。
	var emission_dt := maxf(0.0,
			minf(elapsed, _emit_until) - minf(previous_elapsed, _emit_until))
	_emit_accumulator += emission_dt * _emission_rate
	while _emit_accumulator >= 1.0:
		_emit_accumulator -= 1.0
		_emit_droplet()

	# 倒序更新并回收过期字典，单个实例内不创建额外粒子节点。
	for i in range(_droplets.size() - 1, -1, -1):
		var droplet: Dictionary = _droplets[i]
		droplet["age"] = float(droplet["age"]) + dt
		if float(droplet["age"]) >= float(droplet["life"]):
			_droplets.remove_at(i)
			continue
		var velocity: Vector2 = droplet["velocity"]
		velocity.y += gravity * dt
		droplet["velocity"] = velocity
		# 血滴一旦离开伤口就保存在世界坐标中；敌人被击退时旧滴不会整束平移。
		droplet["world_position"] = Vector2(droplet["world_position"]) + velocity * dt

	queue_redraw()
	if elapsed >= duration:
		stop()
		finished.emit(self)


func _emit_droplet() -> void:
	if _droplets.size() >= MAX_LIVE_DROPLETS:
		return
	var spread := deg_to_rad(spread_degrees * (1.18 if strong_mode else 1.0))
	var shot_direction := _direction.rotated(_rng.randf_range(-spread, spread))
	var speed := _rng.randf_range(speed_min, speed_max)
	if strong_mode:
		speed *= 1.14
	var perpendicular := Vector2(-_direction.y, _direction.x)
	# 发射点围绕伤口轻微抖动，而不是所有血滴从同一个亚像素点重叠出现。
	var origin := perpendicular * _rng.randf_range(-wound_radius, wound_radius)
	origin += _direction * _rng.randf_range(-1.5, 2.0)
	var life := _rng.randf_range(0.16, 0.28) * (1.15 if strong_mode else 1.0)
	var size := _rng.randf_range(1.5, 3.0) * sqrt(_power)
	var shade := current_color.lightened(_rng.randf_range(0.0, 0.24))
	_droplets.append({
		"world_position": to_global(origin),
		"velocity": shot_direction * speed * sqrt(_power),
		"age": 0.0,
		"life": life,
		"size": size,
		"color": shade,
	})
	_emitted_total += 1


## 只让伤口喷口追随敌人身体中心。目标死亡但尸体仍在树中时继续追随；
## queue_free 后安全脱离，余下血滴仍按世界弹道播完。
func _update_follow_anchor() -> void:
	if _follow_target_ref == null:
		return
	var target := _follow_target_ref.get_ref() as Node2D
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		_follow_target_ref = null
		return
	var next_world := target.global_position
	if target.has_method("wound_anchor_world"):
		# 新尸体抬升只作用于视觉层；续喷口明确跟随视觉锚点，旧血滴不平移。
		next_world = Vector2(target.wound_anchor_world())
	elif target.has_method("body_rect"):
		next_world = Vector2(target.body_rect().get_center())
	global_position = next_world.round()


## 前半段保持实色可读，后半段渐隐；避免血点出生后马上变暗形成闪烁噪点。
func droplet_alpha(age_ratio: float) -> float:
	return 1.0 - smoothstep(0.45, 1.0, clampf(age_ratio, 0.0, 1.0))


func _draw() -> void:
	if not active:
		return
	for droplet in _droplets:
		var age_ratio := clampf(float(droplet["age"]) / float(droplet["life"]), 0.0, 1.0)
		var color: Color = droplet["color"]
		color.a = droplet_alpha(age_ratio)
		var point := to_local(Vector2(droplet["world_position"])).round()
		var velocity := Vector2(droplet["velocity"])
		var size := maxf(1.0, roundf(float(droplet["size"])))
		# 短拖尾和方形血滴都关闭抗锯齿，保持硬边像素感。
		var tail := -velocity.normalized() * minf(4.0, size * 1.7)
		draw_line(point, (point + tail).round(), color, size, false)
		draw_rect(Rect2((point - Vector2.ONE * size * 0.5).round(),
				Vector2.ONE * size), color)


## 无头测试与后续性能面板读取；不依赖渲染后端。
func debug_stats() -> Dictionary:
	return {
		"active": active,
		"strong": strong_mode,
		"direction": _direction,
		"duration": duration,
		"elapsed": elapsed,
		"emission_rate": _emission_rate,
		"emitted": _emitted_total,
		"live_droplets": _droplets.size(),
		"processing": is_processing(),
		"seed": _seed,
		"color": current_color,
		"following": _follow_target_ref != null and _follow_target_ref.get_ref() != null,
	}


## 测试只读接口：确认移动喷口不会把已经飞出的血滴一起拖走。
func debug_droplet_world_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for droplet in _droplets:
		result.append(Vector2(droplet["world_position"]))
	return result
