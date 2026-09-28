extends Node2D
class_name BeatWarden
signal boss_died
var hp := 160
var max_hp := 160
var dead := false
var exposed := false
var state := "idle"
var frame := 0
var anim_time := 0.0
var flash := 0.0
var metadata: Dictionary
var sprite: Sprite2D
var _beat := 0.0

func setup(atlas_path: String, health: int) -> void:
	metadata = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
	max_hp = health
	sprite = Sprite2D.new()
	sprite.texture = load(atlas_path.get_basename() + ".png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	sprite.flip_h = true
	var cell: Array = metadata.cell_size
	sprite.position = Vector2(float(metadata.pivot_x) - float(cell[0]) * 0.5,
			float(cell[1]) * 0.5 - float(metadata.baseline_y))
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float flash = 0.0; void fragment() { COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash); }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	sprite.material = mat
	add_child(sprite)
	reset()

func anchor(key: String) -> Vector2:
	var offset: Array = metadata[key]
	return position + Vector2(-float(offset[0]), float(offset[1]))

func target_point() -> Vector2:
	return anchor("core_world") if exposed else position + Vector2(0, -110)

func hurtbox_rect() -> Rect2:
	return Rect2(target_point() - Vector2(36, 36), Vector2(72, 72))

func reset() -> void:
	hp = max_hp
	dead = false
	exposed = false
	flash = 0.0
	_beat = 0.0
	_set_state("idle")
	_sync_sprite()

func fire(lane: String) -> void:
	if not dead and state not in ["expose", "hurt"]:
		_set_state("fire_" + lane)

func expose() -> void:
	if not exposed and not dead:
		exposed = true
		_set_state("expose")

func take_reflected_hit(damage: int) -> void:
	if dead:
		return
	hp = maxi(0, hp - damage)
	flash = 0.12
	if hp == 0:
		dead = true
		_set_state("death")
		boss_died.emit()
	elif state != "expose":
		_set_state("hurt")
	_sync_sprite()

func step(dt: float, beat: float) -> void:
	_beat = beat
	anim_time += dt
	flash = maxf(0.0, flash - dt)
	if state not in ["idle", "core", "death"]:
		if anim_time >= float(metadata.animations[state].frames) / 12.0:
			_set_state("core" if exposed else "idle")
	_sync_sprite()

func _set_state(value: String) -> void:
	state = value
	anim_time = 0.0
	frame = 0

func _sync_sprite() -> void:
	var animation: Dictionary = metadata.animations[state]
	var count := int(animation.frames)
	frame = mini(count - 1, floori(anim_time * 12.0))
	if state in ["idle", "core"]:
		frame = floori(fposmod(_beat, 1.0) * count)
	var cell := Vector2(float(metadata.cell_size[0]), float(metadata.cell_size[1]))
	sprite.region_rect = Rect2(Vector2(frame * cell.x, int(animation.row) * cell.y), cell)
	(sprite.material as ShaderMaterial).set_shader_parameter("flash", clampf(flash / 0.12, 0.0, 1.0))
