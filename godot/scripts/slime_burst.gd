extends Node2D
class_name SlimeBurst
## 受力定向的彩虹史莱姆爆裂：高速液柱、黏液块和细雾三层粒子。

signal finished(effect: SlimeBurst)
signal paint_requested(world_position: Vector2, direction: Vector2, power: float, seed: int)

const TOTAL_LIFETIME := 0.98
const PAINT_DELAY := 0.12

var active := false
var elapsed := 0.0
var strength := 1.0
var force_direction := Vector2.RIGHT
var paint_seed := 0

var _paint_sent := false
var _layers: Array[CPUParticles2D] = []
var _jets: CPUParticles2D
var _chunks: CPUParticles2D
var _mist: CPUParticles2D


func _ready() -> void:
	z_index = 20
	_build_particles()
	stop()


## direction 使用伤害来源的速度方向；零向量退化为向右，避免粒子停在原点。
func play(power := 1.0, direction := Vector2.RIGHT, seed := 0) -> void:
	strength = clampf(power, 0.55, 2.0)
	force_direction = direction.normalized()
	if force_direction == Vector2.ZERO:
		force_direction = Vector2.RIGHT
	paint_seed = seed if seed != 0 else int(Time.get_ticks_usec())
	position = position.round()
	scale = Vector2.ONE * strength
	elapsed = 0.0
	_paint_sent = false
	active = true
	visible = true
	set_process(true)

	_jets.direction = force_direction
	_chunks.direction = force_direction
	_mist.direction = force_direction
	for particles in _layers:
		particles.emitting = true
		particles.restart()
	queue_redraw()


func stop() -> void:
	active = false
	visible = false
	set_process(false)
	for particles in _layers:
		particles.emitting = false
	queue_redraw()


func _process(dt: float) -> void:
	if not active:
		return
	elapsed += dt
	if not _paint_sent and elapsed >= PAINT_DELAY:
		_paint_sent = true
		paint_requested.emit(global_position.round(), force_direction, strength, paint_seed)
	queue_redraw()
	if elapsed >= TOTAL_LIFETIME:
		stop()
		finished.emit(self)


func _draw() -> void:
	if not active or elapsed >= 0.16:
		return
	var t := clampf(elapsed / 0.16, 0.0, 1.0)
	var alpha := 1.0 - t
	var direction := force_direction
	var perpendicular := Vector2(-direction.y, direction.x)
	var length := lerpf(34.0, 10.0, t)
	var width := lerpf(17.0, 5.0, t)
	var crown := PackedVector2Array([
		-direction * length * 0.35,
		perpendicular * width,
		direction * length,
		-perpendicular * width,
	])
	draw_colored_polygon(crown, Color(0.82, 1.0, 1.0, alpha))
	# 核心的三块彩色液面让首帧也能读出“彩虹油漆”，不是普通白色爆炸。
	for i in 3:
		var petal_dir := direction.rotated(deg_to_rad(float(i - 1) * 34.0))
		var center := petal_dir * lerpf(13.0, 5.0, t)
		var color: Color = SlimePaintLayer.PALETTE[(i * 2 + 1) % SlimePaintLayer.PALETTE.size()]
		color.a = alpha
		draw_rect(Rect2((center - Vector2(4, 4)).round(), Vector2(8, 8)), color)


func _build_particles() -> void:
	if not _layers.is_empty():
		return

	_jets = _make_layer("LiquidJets", 30, 0.62,
			_make_pixel_texture([".#.", "###", "###", "###", "###", ".#."]), false)
	_jets.spread = 46.0
	_jets.gravity = Vector2(0, 510)
	_jets.initial_velocity_min = 185.0
	_jets.initial_velocity_max = 390.0
	_jets.angular_velocity_min = -120.0
	_jets.angular_velocity_max = 120.0
	_jets.scale_amount_min = 0.72
	_jets.scale_amount_max = 1.38
	_jets.scale_amount_curve = _make_curve([
		Vector2(0.0, 0.55), Vector2(0.10, 1.0), Vector2(0.72, 0.82), Vector2(1.0, 0.0)])
	_jets.particle_flag_align_y = true

	_chunks = _make_layer("SlimeChunks", 18, 0.78,
			_make_pixel_texture([".###.", "#####", "#####", "#####", ".###."]), false)
	_chunks.spread = 76.0
	_chunks.gravity = Vector2(0, 650)
	_chunks.initial_velocity_min = 95.0
	_chunks.initial_velocity_max = 255.0
	_chunks.angular_velocity_min = -420.0
	_chunks.angular_velocity_max = 420.0
	_chunks.scale_amount_min = 0.95
	_chunks.scale_amount_max = 1.85
	_chunks.scale_amount_curve = _make_curve([
		Vector2(0.0, 0.42), Vector2(0.12, 1.0), Vector2(0.76, 0.92), Vector2(1.0, 0.0)])

	_mist = _make_layer("PaintMist", 26, 0.30,
			_make_pixel_texture(["##", "##"]), false)
	_mist.spread = 112.0
	_mist.gravity = Vector2(0, 160)
	_mist.initial_velocity_min = 80.0
	_mist.initial_velocity_max = 285.0
	_mist.scale_amount_min = 0.48
	_mist.scale_amount_max = 1.10
	_mist.scale_amount_curve = _make_curve([
		Vector2(0.0, 0.72), Vector2(0.62, 1.0), Vector2(1.0, 0.0)])


func _make_layer(layer_name: String, particle_count: int, particle_lifetime: float,
		texture: Texture2D, additive: bool) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = layer_name
	particles.emitting = false
	particles.amount = particle_count
	particles.lifetime = particle_lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.16
	particles.fixed_fps = 60
	particles.fract_delta = false
	particles.local_coords = true
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.texture = texture
	particles.color_initial_ramp = _rainbow_gradient()
	particles.color_ramp = _fade_gradient()
	if additive:
		var canvas_material := CanvasItemMaterial.new()
		canvas_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particles.material = canvas_material
	add_child(particles)
	_layers.append(particles)
	return particles


func _make_pixel_texture(rows: Array[String]) -> ImageTexture:
	var width := rows[0].length()
	var image := Image.create(width, rows.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in rows.size():
		for x in width:
			if rows[y].substr(x, 1) == "#":
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _rainbow_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.19, 0.38, 0.57, 0.78, 1.0])
	gradient.colors = PackedColorArray(SlimePaintLayer.PALETTE)
	return gradient


func _fade_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.74, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.82), Color.WHITE, Color(1, 1, 1, 0.92), Color(1, 1, 1, 0.0),
	])
	return gradient


func _make_curve(points: Array[Vector2]) -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 1.6
	for point in points:
		curve.add_point(point)
	return curve


func debug_stats() -> Dictionary:
	var particle_count := 0
	for particles in _layers:
		particle_count += particles.amount
	return {
		"active": active,
		"layers": _layers.size(),
		"particles": particle_count,
		"direction": force_direction,
		"duration": TOTAL_LIFETIME,
	}
