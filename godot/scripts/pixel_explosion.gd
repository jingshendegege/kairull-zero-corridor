extends Node2D
class_name PixelExplosion
## Peacekeeper 身份色的像素粒子爆炸。
## 三层 CPUParticles2D 负责高速火花、能量碎片与余烟；核心闪光和冲击环由本节点绘制。

signal finished(effect: PixelExplosion)

const TOTAL_LIFETIME := 0.95
const CORE_TIME := 0.10
const WAVE_TIME := 0.34

var active := false
var elapsed := 0.0
var strength := 1.0

var _layers: Array[CPUParticles2D] = []
var _sparks: CPUParticles2D
var _fragments: CPUParticles2D
var _smoke: CPUParticles2D


func _ready() -> void:
	# 爆炸覆盖角色和敌人；HUD 使用 CanvasLayer，仍会保持在最上层。
	z_index = 20
	_build_particles()
	stop()


## 重新播放同一实例，供 GameFxLayer 对象池复用。
func play(power := 1.0) -> void:
	strength = clampf(power, 0.55, 2.0)
	position = position.round()
	scale = Vector2.ONE * strength
	elapsed = 0.0
	active = true
	visible = true
	set_process(true)
	for particles in _layers:
		particles.emitting = true
		particles.restart()
	queue_redraw()


## 停止但不销毁；对象池会在下一次爆炸时重新播放。
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
	queue_redraw()
	if elapsed >= TOTAL_LIFETIME:
		stop()
		finished.emit(self)


func _draw() -> void:
	if not active:
		return

	# 前 0.1 秒只给一次短促白芯，避免持续发亮削弱爆点。
	if elapsed < CORE_TIME:
		var core_t := clampf(elapsed / CORE_TIME, 0.0, 1.0)
		var core_alpha := 1.0 - core_t
		var core_radius := lerpf(17.0, 5.0, core_t)
		var core_color := Color(0.92, 0.99, 1.0, core_alpha)
		var diamond := PackedVector2Array([
			Vector2(0, -core_radius), Vector2(core_radius, 0),
			Vector2(0, core_radius), Vector2(-core_radius, 0),
		])
		draw_colored_polygon(diamond, core_color)
		draw_rect(Rect2(-core_radius * 1.7, -2.0, core_radius * 3.4, 4.0), core_color)
		draw_rect(Rect2(-2.0, -core_radius * 1.7, 4.0, core_radius * 3.4), core_color)

	# 八边形冲击环保持硬边，不使用平滑圆形，和像素画角色同一视觉语言。
	if elapsed < WAVE_TIME:
		var wave_t := clampf(elapsed / WAVE_TIME, 0.0, 1.0)
		var wave_alpha := pow(1.0 - wave_t, 1.7)
		var wave_radius := lerpf(9.0, 62.0, wave_t)
		_draw_octagon(wave_radius, Color(0.22, 0.86, 1.0, wave_alpha),
				lerpf(4.0, 1.0, wave_t))
		if wave_t < 0.68:
			_draw_octagon(wave_radius * 0.62, Color(0.75, 0.97, 1.0, wave_alpha * 0.65), 2.0)


func _draw_octagon(radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(9):
		var angle := TAU * float(i % 8) / 8.0
		points.append((Vector2(cos(angle), sin(angle)) * radius).round())
	draw_polyline(points, color, width, false)


func _build_particles() -> void:
	if not _layers.is_empty():
		return

	_sparks = _make_layer("Sparks", 34, 0.46,
			_make_pixel_texture(["##", "##", "##", "##", "##", "##"]), true)
	_sparks.direction = Vector2.RIGHT
	_sparks.spread = 180.0
	_sparks.gravity = Vector2(0, 360)
	_sparks.initial_velocity_min = 180.0
	_sparks.initial_velocity_max = 370.0
	_sparks.angular_velocity_min = -240.0
	_sparks.angular_velocity_max = 240.0
	_sparks.scale_amount_min = 0.65
	_sparks.scale_amount_max = 1.25
	_sparks.scale_amount_curve = _make_curve([
		Vector2(0.0, 1.0), Vector2(0.58, 0.82), Vector2(1.0, 0.0)])
	_sparks.color_ramp = _make_gradient(
		PackedFloat32Array([0.0, 0.18, 0.62, 1.0]),
		PackedColorArray([
			Color("#efffff"), Color("#60e8ff"),
			Color(0.08, 0.47, 1.0, 0.85), Color(0.02, 0.18, 0.5, 0.0),
		]))
	_sparks.particle_flag_align_y = true

	_fragments = _make_layer("EnergyFragments", 20, 0.38,
			_make_pixel_texture([".#.", "###", ".#."]), true)
	_fragments.direction = Vector2.RIGHT
	_fragments.spread = 180.0
	_fragments.gravity = Vector2(0, 170)
	_fragments.initial_velocity_min = 90.0
	_fragments.initial_velocity_max = 235.0
	_fragments.angular_velocity_min = -720.0
	_fragments.angular_velocity_max = 720.0
	_fragments.scale_amount_min = 0.85
	_fragments.scale_amount_max = 1.65
	_fragments.scale_amount_curve = _make_curve([
		Vector2(0.0, 0.45), Vector2(0.12, 1.0), Vector2(0.72, 0.75), Vector2(1.0, 0.0)])
	_fragments.color_ramp = _make_gradient(
		PackedFloat32Array([0.0, 0.22, 0.72, 1.0]),
		PackedColorArray([
			Color("#ffffff"), Color("#87f1ff"),
			Color(0.08, 0.55, 1.0, 0.92), Color(0.03, 0.22, 0.55, 0.0),
		]))

	_smoke = _make_layer("EnergySmoke", 12, 0.84,
			_make_pixel_texture([".###.", "#####", "#####", "#####", ".###."]), false)
	_smoke.direction = Vector2.UP
	_smoke.spread = 78.0
	_smoke.gravity = Vector2(0, -34)
	_smoke.initial_velocity_min = 18.0
	_smoke.initial_velocity_max = 62.0
	_smoke.angular_velocity_min = -90.0
	_smoke.angular_velocity_max = 90.0
	_smoke.scale_amount_min = 0.9
	_smoke.scale_amount_max = 1.8
	_smoke.scale_amount_curve = _make_curve([
		Vector2(0.0, 0.25), Vector2(0.16, 0.85), Vector2(0.72, 1.25), Vector2(1.0, 0.0)])
	_smoke.color_ramp = _make_gradient(
		PackedFloat32Array([0.0, 0.18, 0.66, 1.0]),
		PackedColorArray([
			Color(0.36, 0.9, 1.0, 0.42), Color(0.08, 0.46, 0.75, 0.40),
			Color(0.04, 0.17, 0.34, 0.23), Color(0.02, 0.08, 0.18, 0.0),
		]))


func _make_layer(layer_name: String, particle_count: int, particle_lifetime: float,
		texture: Texture2D, additive: bool) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = layer_name
	particles.emitting = false
	particles.amount = particle_count
	particles.lifetime = particle_lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.12
	particles.fixed_fps = 60
	particles.fract_delta = false
	particles.local_coords = true
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.texture = texture
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


func _make_gradient(offsets: PackedFloat32Array, colors: PackedColorArray) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	return gradient


func _make_curve(points: Array[Vector2]) -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 1.5
	for point in points:
		curve.add_point(point)
	return curve


## 无头测试读取，不依赖渲染后端。
func debug_stats() -> Dictionary:
	var particle_count := 0
	for particles in _layers:
		particle_count += particles.amount
	return {
		"active": active,
		"layers": _layers.size(),
		"particles": particle_count,
		"duration": TOTAL_LIFETIME,
	}
