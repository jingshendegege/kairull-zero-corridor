extends Node2D
class_name BloodWallManager
## 世界空间墙面血迹管理器：共享冻结帧图集，最多保留固定数量的独立材质实例。
## 节点没有逐帧逻辑；离屏 Sprite2D 交给渲染器裁剪，避免无意义脚本开销。

const BLOOD_SHADER := preload("res://shaders/blood_wall.gdshader")
const SNAPSHOT_PATH := "res://assets/vfx/blood_wall_snapshot.png"
const CELL_SIZE := Vector2(320.0, 192.0)
const IMPACT_PIVOT := Vector2(40.0, 96.0)
const BASE_DIRECTION := Vector2(1.0, -0.18)
const VARIANT_COUNT := 6

@export_range(1, 256, 1) var max_decals := 128
@export var persistent_enabled := true:
	set(value):
		persistent_enabled = value
		visible = value
@export var inherit_effect_color := true
@export var red_blood_color := Color("#c01630")
@export_range(0.0, 1.0, 0.01) var blood_opacity := 0.86
@export_range(0.0, 2.0, 0.01) var multiply_intensity := 1.55

@export_group("融合开关")
@export var occlusion_enabled := true
@export var darkness_enabled := true
@export var refraction_enabled := true
@export var linear_refraction_enabled := true
@export var normal_lighting_enabled := true
@export var dark_surface_lift_enabled := true

@export_group("融合参数")
@export_range(0.0, 24.0, 0.1) var occlusion_strength := 6.0
@export_range(1, 32, 1) var occlusion_ray_steps := 12
@export_range(0.0, 48.0, 0.5) var occlusion_ray_length := 12.0
@export_range(0.0, 1.0, 0.001) var darkness_threshold := 0.035
@export_range(0.001, 0.25, 0.001) var darkness_softness := 0.025
## 暗墙只混回一部分本次彩色血液；亮墙继续使用原有正片叠底。
@export_range(0.0, 1.0, 0.01) var dark_surface_lift_strength := 0.65
@export_range(0.0, 0.6, 0.01) var dark_surface_lift_start := 0.10
# 中暗蓝灰墙也要进入补色过渡；纯黑区域仍先被 darkness mask 剔除。
@export_range(0.0, 0.6, 0.01) var dark_surface_lift_end := 0.34
@export_range(0.0, 1.0, 0.01) var deformation_strength := 0.25
@export_range(0.0, 12.0, 0.1) var background_bump_strength := 4.0
@export_range(0.0, 12.0, 0.1) var blood_bump_strength := 3.0
@export_range(-180.0, 180.0, 0.1) var light_angle := -45.0
@export_range(0.0, 1.0, 0.01) var ambient_light := 0.72

@export_group("调试")
@export_range(0, 6, 1) var debug_mode := 0
@export var direction_debug_enabled := false
@export_range(-180.0, 180.0, 0.5) var spray_angle_offset := 0.0

var _snapshot_texture: Texture2D
var _slots: Array[Dictionary] = []
var _next_reuse := 0
var _active_count := 0
var _serial := 0


func _ready() -> void:
	visible = persistent_enabled
	_snapshot_texture = load(SNAPSHOT_PATH) as Texture2D
	if _snapshot_texture == null:
		push_warning("墙面血迹图集未生成：%s" % SNAPSHOT_PATH)


## 冻结一次主喷溅。power 是 SlimeRibbonBurst 已换算后的内部强度。
func spawn_snapshot(world_position: Vector2, direction: Vector2, power := 1.0,
		seed := 1, weak := false, progress := 0.0,
		effect_color := Color("#c01630"), extra_flip_h := false,
		extra_flip_v := false) -> Sprite2D:
	if not persistent_enabled or _snapshot_texture == null or max_decals <= 0:
		return null
	_enforce_capacity()
	var spray_direction := direction.normalized()
	if spray_direction == Vector2.ZERO:
		spray_direction = Vector2.RIGHT

	var slot_index := _claim_slot()
	var slot: Dictionary = _slots[slot_index]
	var sprite := slot["sprite"] as Sprite2D
	var material := slot["material"] as ShaderMaterial
	var was_visible := sprite.visible
	_serial += 1

	var flip_h := (spray_direction.x < 0.0) != extra_flip_h
	var flip_v := extra_flip_v
	var visual_direction := BASE_DIRECTION.normalized()
	if flip_h:
		visual_direction.x *= -1.0
	if flip_v:
		visual_direction.y *= -1.0

	sprite.visible = true
	if not was_visible:
		_active_count += 1
	sprite.texture = _snapshot_texture
	sprite.hframes = VARIANT_COUNT
	sprite.vframes = 1
	sprite.frame = posmod(seed, VARIANT_COUNT)
	sprite.flip_h = flip_h
	sprite.flip_v = flip_v
	sprite.offset = _offset_for_flips(flip_h, flip_v)
	sprite.global_position = world_position.round()
	sprite.global_rotation = visual_direction.angle_to(spray_direction)
	var snapshot_scale := clampf(power, 0.45, 1.85)
	sprite.scale = Vector2.ONE * snapshot_scale

	var spray_angle := rad_to_deg(atan2(spray_direction.y, spray_direction.x))
	var resolved_color := effect_color if inherit_effect_color else red_blood_color
	_apply_material(material, spray_angle, resolved_color)
	_slots[slot_index]["serial"] = _serial
	_slots[slot_index]["direction"] = spray_direction
	_slots[slot_index]["spray_angle"] = spray_angle
	_slots[slot_index]["progress"] = clampf(progress, 0.0, 1.0)
	_slots[slot_index]["frame"] = sprite.frame
	_slots[slot_index]["flip_h"] = flip_h
	_slots[slot_index]["flip_v"] = flip_v
	_slots[slot_index]["world_position"] = sprite.global_position
	_slots[slot_index]["world_scale"] = sprite.scale
	_slots[slot_index]["weak"] = weak
	_slots[slot_index]["color"] = resolved_color
	move_child(sprite, get_child_count() - 1)
	queue_redraw()
	return sprite


func _claim_slot() -> int:
	if _slots.size() < max_decals:
		var sprite := Sprite2D.new()
		sprite.name = "BloodWallStain%03d" % _slots.size()
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		var material := ShaderMaterial.new()
		material.shader = BLOOD_SHADER
		material.resource_local_to_scene = true
		sprite.material = material
		add_child(sprite)
		_slots.append({
			"sprite": sprite, "material": material, "serial": 0,
			"direction": Vector2.RIGHT, "spray_angle": 0.0,
			"progress": 0.0, "frame": 0, "flip_h": false,
			"flip_v": false, "world_position": Vector2.ZERO,
			"world_scale": Vector2.ONE, "weak": false,
			"color": red_blood_color,
		})
		return _slots.size() - 1

	# 运行时先降再升容量时，优先启用此前隐藏的槽，避免无谓覆盖仍可见的旧血迹。
	var capacity := mini(maxi(1, max_decals), _slots.size())
	for i in capacity:
		if not (_slots[i]["sprite"] as Sprite2D).visible:
			_next_reuse = (i + 1) % capacity
			return i
	var claimed := _next_reuse
	_next_reuse = (_next_reuse + 1) % capacity
	return claimed


func _enforce_capacity() -> void:
	var capacity := maxi(1, max_decals)
	for i in range(capacity, _slots.size()):
		(_slots[i]["sprite"] as Sprite2D).visible = false
		_slots[i]["serial"] = 0
	_next_reuse %= capacity
	_active_count = 0
	for slot in _slots:
		if (slot["sprite"] as Sprite2D).visible:
			_active_count += 1


func _offset_for_flips(flip_h: bool, flip_v: bool) -> Vector2:
	var half := CELL_SIZE * 0.5
	return Vector2(
			IMPACT_PIVOT.x - half.x if flip_h else half.x - IMPACT_PIVOT.x,
			IMPACT_PIVOT.y - half.y if flip_v else half.y - IMPACT_PIVOT.y)


func _apply_material(material: ShaderMaterial, spray_angle: float,
		resolved_color: Color) -> void:
	material.set_shader_parameter("blood_color", resolved_color)
	material.set_shader_parameter("blood_opacity", blood_opacity)
	material.set_shader_parameter("multiply_intensity", multiply_intensity)
	material.set_shader_parameter("spray_angle", wrapf(
			spray_angle + spray_angle_offset, -180.0, 180.0))
	material.set_shader_parameter("enable_occlusion", occlusion_enabled)
	material.set_shader_parameter("enable_darkness", darkness_enabled)
	material.set_shader_parameter("enable_refraction", refraction_enabled)
	material.set_shader_parameter("use_linear_refraction", linear_refraction_enabled)
	material.set_shader_parameter("enable_normal_lighting", normal_lighting_enabled)
	material.set_shader_parameter("enable_dark_surface_lift", dark_surface_lift_enabled)
	material.set_shader_parameter("occlusion_strength", occlusion_strength)
	material.set_shader_parameter("occlusion_ray_steps", occlusion_ray_steps)
	material.set_shader_parameter("occlusion_ray_length", occlusion_ray_length)
	material.set_shader_parameter("darkness_threshold", darkness_threshold)
	material.set_shader_parameter("darkness_softness", darkness_softness)
	material.set_shader_parameter("dark_surface_lift_strength", dark_surface_lift_strength)
	material.set_shader_parameter("dark_surface_lift_start", dark_surface_lift_start)
	material.set_shader_parameter("dark_surface_lift_end", dark_surface_lift_end)
	material.set_shader_parameter("luminance_deformation_strength", deformation_strength)
	material.set_shader_parameter("background_bump_strength", background_bump_strength)
	material.set_shader_parameter("blood_bump_strength", blood_bump_strength)
	material.set_shader_parameter("light_angle", light_angle)
	material.set_shader_parameter("ambient_light", ambient_light)
	material.set_shader_parameter("debug_mode", debug_mode)


## Inspector/实验室改参数后统一同步；不在每帧重复写 uniform。
func apply_settings() -> void:
	visible = persistent_enabled
	_enforce_capacity()
	for slot in _slots:
		var material := slot["material"] as ShaderMaterial
		_apply_material(material, float(slot["spray_angle"]), slot["color"] as Color)
	queue_redraw()


func set_debug_mode(value: int) -> void:
	debug_mode = clampi(value, 0, 6)
	apply_settings()


## 暗墙补色是独立回退开关；关闭后立即恢复旧版纯正片叠底。
func set_dark_surface_lift_enabled(value: bool) -> void:
	dark_surface_lift_enabled = value
	apply_settings()


func set_persistent_enabled(value: bool) -> void:
	persistent_enabled = value
	apply_settings()


func clear_all() -> void:
	for i in _slots.size():
		(_slots[i]["sprite"] as Sprite2D).visible = false
		_slots[i]["serial"] = 0
	_active_count = 0
	_next_reuse = 0
	queue_redraw()


func active_count() -> int:
	return _active_count


func slot_count() -> int:
	return _slots.size()


func debug_snapshot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _slots.size():
		return {}
	return _slots[slot_index].duplicate()


func debug_stats() -> Dictionary:
	var material_rids: Array[int] = []
	var visible_count := 0
	for slot in _slots:
		var sprite := slot["sprite"] as Sprite2D
		# 统计最终树可见性；父管理器关闭后不能误报为仍在屏幕绘制。
		if sprite.is_visible_in_tree():
			visible_count += 1
		material_rids.append((slot["material"] as ShaderMaterial).get_rid().get_id())
	return {
		"active": _active_count,
		"visible": visible_count,
		"slots": _slots.size(),
		"max_decals": max_decals,
		"next_reuse": _next_reuse,
		"serial": _serial,
		"material_rids": material_rids,
	}


func _draw() -> void:
	if not direction_debug_enabled:
		return
	for slot in _slots:
		var sprite := slot["sprite"] as Sprite2D
		if not sprite.visible:
			continue
		var direction := slot["direction"] as Vector2
		draw_line(sprite.position, sprite.position + direction * 72.0,
				Color("#ffe45c"), 2.0, false)
		draw_circle(sprite.position + direction * 72.0, 3.0, Color("#ff4fa3"))
