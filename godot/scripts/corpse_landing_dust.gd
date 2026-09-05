extends Node2D
## 尸体第一次着地的小片像素灰尘：只烘托重量，不抢彩血和原版击杀声。

signal finished(effect: Node2D)

const MIN_PARTICLES := 10
const MAX_PARTICLES := 18
const MIN_PIXEL_SIZE := 3
const MAX_PIXEL_SIZE := 6
const MAX_RECTS_PER_PARTICLE := 3
const DUST_COLORS: Array[Color] = [Color("#bac2b1"), Color("#aab4ac"), Color("#949e9d")]

@export_range(0.25, 0.40, 0.01) var base_duration := 0.32
@export_range(0.15, 0.85, 0.01) var opacity := 0.72

var active := false
var elapsed := 0.0
var duration := 0.32
var _power := 1.0
var _direction := 1.0
var _particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 使用默认 INHERIT：父 FxLayer 禁用处理时，灰尘跟随时停冻结而非穿越时间。
	stop()


func play(power := 1.0, direction := 1.0, seed_value := 1) -> void:
	_power = clampf(power, 0.5, 1.5)
	_direction = -1.0 if direction < 0.0 else 1.0
	_rng.seed = maxi(1, seed_value)
	duration = clampf(base_duration, 0.25, 0.40)
	elapsed = 0.0
	_particles.clear()
	var particle_count := clampi(roundi(14.0 * _power), MIN_PARTICLES, MAX_PARTICLES)
	for i in particle_count:
		# 左右交错，受击方向只略推偏；绝不变成单束横向喷血或高烟柱。
		var side := -1.0 if i % 2 == 0 else 1.0
		var speed := _rng.randf_range(42.0, 98.0) * sqrt(_power)
		var horizontal := side * speed + _direction * speed * 0.15
		_particles.append({
			"origin": Vector2(side * _rng.randf_range(12.0, 22.0), 0.0),
			"velocity": Vector2(horizontal, -_rng.randf_range(18.0, 46.0)),
			"life": duration * _rng.randf_range(0.78, 1.0),
			"size": _rng.randi_range(MIN_PIXEL_SIZE, MAX_PIXEL_SIZE),
			"color": DUST_COLORS[i % DUST_COLORS.size()],
		})
	active = true
	visible = true
	set_process(true)
	queue_redraw()


func stop() -> void:
	active = false
	visible = false
	set_process(false)
	_particles.clear()
	queue_redraw()


func _process(dt: float) -> void:
	if not active:
		return
	elapsed = minf(duration, elapsed + maxf(0.0, dt))
	queue_redraw()
	# 即使落点在镜头外也只有这段有限寿命，回池后不运行任何逐帧逻辑。
	if elapsed >= duration:
		stop()
		finished.emit(self)


func _particle_position(particle: Dictionary) -> Vector2:
	var velocity: Vector2 = particle["velocity"]
	# 阻尼横移 + 极低抛弧；灰尘不钻进地板，也不需要碰撞节点或屏幕采样。
	var point := Vector2(particle["origin"])
	point.x += velocity.x * (1.0 - exp(-elapsed * 4.0)) / 4.0
	point.y = minf(0.0, velocity.y * elapsed + 140.0 * elapsed * elapsed)
	return point.round()


func _draw() -> void:
	if not active:
		return
	for particle in _particles:
		var ratio := elapsed / float(particle["life"])
		if ratio >= 1.0:
			continue
		var color: Color = particle["color"]
		color.a = opacity * (1.0 - smoothstep(0.2, 1.0, ratio))
		var size := float(particle["size"])
		var point := _particle_position(particle)
		# 每粒最多三个小矩形拼成扁尘簇：比散点可读，仍有硬边且不变成模糊大烟团。
		# 中间矩形贴地、上沿留台阶；左右外扩露出尸体边缘，不靠提高图层盖住彩血。
		var width := roundf(size * 1.5)
		var height := maxf(2.0, roundf(size * 0.55))
		var left := point - Vector2(floorf(width * 0.5), height)
		draw_rect(Rect2(left, Vector2(width, height)), color)
		draw_rect(Rect2(left + Vector2(2.0, -2.0), Vector2(maxf(2.0, width - 4.0), 2.0)), color)
		var side := -1.0 if Vector2(particle["velocity"]).x < 0.0 else 1.0
		var chip := point + Vector2(side * (width * 0.5 + 2.0), -2.0)
		draw_rect(Rect2(chip.round(), Vector2(2.0, 2.0)), color)


func debug_stats() -> Dictionary:
	return {"active": active, "elapsed": elapsed, "duration": duration,
			"particles": _particles.size(), "direction": _direction, "power": _power,
			"processing": is_processing(), "size_min": MIN_PIXEL_SIZE,
			"size_max": MAX_PIXEL_SIZE, "max_rects_per_particle": MAX_RECTS_PER_PARTICLE}


func debug_particle_world_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for particle in _particles:
		positions.append(to_global(_particle_position(particle)))
	return positions
