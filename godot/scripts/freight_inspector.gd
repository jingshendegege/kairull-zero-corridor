extends Node2D
class_name FreightInspector
## 货运巡检员：主线基础近战兵，正式 M01 与后续货运区均可复用。
## 伤害只来自可读的攻击有效帧，身体接触不扣血。
## 用户透明母表经 Python 隔离串格毛边/统一基线，运行时使用 37 张像素帧。

const ATLAS_PATH := "res://assets/enemy/freight_inspector/atlas.png"
const META_PATH := "res://assets/enemy/freight_inspector/atlas.json"
const SCALE := 1.15
const CELL := Vector2i(128, 96)
const BASELINE_Y := 90.0
const BODY_W := 42.0
const BODY_H := 96.0
const AGGRO_RANGE := 360.0
const ATTACK_RANGE := 88.0
const RUN_SPEED := 118.0
const LUNGE_SPEED := 420.0
const ALERT_TICKS := 18
const WINDUP_TICKS := 26
const ATTACK_TICKS := 8
const ATTACK_ACTIVE_FROM := 2
const ATTACK_ACTIVE_TO := 6
const RECOVER_TICKS := 33
const COOLDOWN_TICKS := 18
const DEATH_TICKS := 54          ## 仅放慢尸体落地，不延迟死亡/击退结算。
const IDLE_VISUAL_FPS := 2.0 ## 日常呼吸减速，攻击/前摇/死亡不改。
const RUN_VISUAL_FPS := 6.0

const RIM_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 rim_color : source_color = vec4(0.49, 0.78, 1.0, 0.60);
uniform float texel_step = 1.0;
uniform vec2 region_min = vec2(0.0);
uniform vec2 region_max = vec2(1.0);
void fragment() {
	vec2 ts = TEXTURE_PIXEL_SIZE * texel_step;
	float own = texture(TEXTURE, UV).a;
	float a = 0.0;
	a = max(a, texture(TEXTURE, clamp(UV + vec2(ts.x, 0.0), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV - vec2(ts.x, 0.0), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV + vec2(0.0, ts.y), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV - vec2(0.0, ts.y), region_min, region_max)).a);
	float ring = clamp(a - own, 0.0, 1.0) * step(0.05, a);
	vec4 tint = rim_color * COLOR;
	COLOR = vec4(tint.rgb, tint.a * ring);
}
"""

var state := "idle"
var frame := 0                    ## 当前状态 tick；game/debug 接口沿用现有命名
var face := -1
var dead := false
var corpse_lift := 0.0          ## 尸体视觉抬升；不挪动地面锚点和近战碰撞盒。
var corpse_ground_y := 0.0
var corpse_ground_valid := false
var corpse_ground_projected := false ## 真惯性只投地面阴影，根位置负责实际抛物线。
var hitstop := 0.0
var cooldown := 0
var player: Node2D
var level: CorridorLevel
var door_blockers: Array = []
var vision_blocker := Callable() ## 烟雾遮蔽新索敌；已进入挥击有效窗仍可以伤人。

var _atlas: Texture2D
var _anims: Dictionary
var _anim_clock := 0.0
var _sprite: Sprite2D
var _outline: Sprite2D
var _rim: Sprite2D
var _shadow: Sprite2D


func _ready() -> void:
	# 新生成 PNG 尚未被编辑器导入时，测试进程直接从文件构造纹理。
	if ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH)
	else:
		var atlas_image := Image.load_from_file(ATLAS_PATH)
		_atlas = ImageTexture.create_from_image(atlas_image)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	_anims = parsed["animations"] if parsed is Dictionary else {}
	_shadow = Sprite2D.new()
	_shadow.name = "ContactShadow"
	_shadow.texture = _make_shadow_texture()
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shadow.modulate = Color(0.0, 0.0, 0.0, 0.34)
	_shadow.scale = Vector2(1.8, 1.2)
	_shadow.position = Vector2(0.0, -1.0)
	add_child(_shadow)

	_outline = _make_region_sprite("Outline")
	var outline_shader := Shader.new()
	outline_shader.code = GruntGunner.OUTLINE_SHADER_CODE
	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = outline_shader
	_outline.material = outline_mat
	add_child(_outline)

	_sprite = _make_region_sprite("Sprite")
	_sprite.self_modulate = GruntGunner.SELF_LIFT
	add_child(_sprite)

	_rim = _make_region_sprite("Rim")
	var rim_shader := Shader.new()
	rim_shader.code = RIM_SHADER_CODE
	var rim_mat := ShaderMaterial.new()
	rim_mat.shader = rim_shader
	_rim.material = rim_mat
	add_child(_rim)
	_sync_sprite()


func _make_region_sprite(node_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = _atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	sprite.scale = Vector2.ONE * SCALE
	sprite.position.y = (CELL.y * 0.5 - BASELINE_Y) * SCALE
	return sprite


func _make_shadow_texture() -> Texture2D:
	var img := Image.create(32, 12, false, Image.FORMAT_RGBA8)
	var center := Vector2(15.5, 5.5)
	for y in range(12):
		for x in range(32):
			var d := clampf(1.0 - Vector2((x - center.x) / 16.0,
					(y - center.y) / 6.0).length(), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, d * d))
	return ImageTexture.create_from_image(img)


func body_rect() -> Rect2:
	return _body_rect_at(position.x)


## 仅抬升美术层，地面支持与墙体扫掠仍读原 body_rect。
func set_corpse_lift(value: float) -> void:
	corpse_lift = maxf(0.0, value)
	corpse_ground_projected = false
	_sync_sprite()


## 求解器提供落点下方地面；悬崖无承接面时隐藏接触阴影。
func set_corpse_ground(world_y: float, valid := true) -> void:
	corpse_lift = 0.0
	corpse_ground_y = world_y
	corpse_ground_valid = valid
	corpse_ground_projected = true
	_sync_sprite()


## 连续喷血使用视觉伤口锚点，避免身体抬起后喷口仍留在下方。
func wound_anchor_world() -> Vector2:
	return body_rect().get_center() - Vector2(0.0, corpse_lift if dead else 0.0)


func _body_rect_at(px: float) -> Rect2:
	return Rect2(px - BODY_W * 0.5, position.y - BODY_H, BODY_W, BODY_H)


func standing_height() -> float:
	return BODY_H


## 攻击盒只在短有效窗参与伤害；不再使用整个身体做持续接触伤害。
func attack_active() -> bool:
	return state == "attack" and frame >= ATTACK_ACTIVE_FROM \
		and frame <= ATTACK_ACTIVE_TO and not dead


func attack_rect() -> Rect2:
	var size := Vector2(84.0, 58.0)
	var center := position + Vector2(face * 52.0, -54.0)
	return Rect2(center - size * 0.5, size)


func take_hit(_from_x: float, _damage := 1) -> bool:
	if dead:
		return false
	dead = true
	corpse_lift = 0.0
	corpse_ground_projected = false
	corpse_ground_valid = false
	hitstop = 0.08
	_set_state("dead")
	_sync_sprite()
	return true


func step(dt: float) -> void:
	_anim_clock += dt
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - dt)
		# 击退锁 AI 不锁尸体动画；与枪手一致，避免首个倒地姿势直立滑行。
		if dead:
			frame += 1
		_sync_sprite()
		return
	frame += 1
	if dead:
		_sync_sprite()
		return
	if player == null:
		return
	if cooldown > 0:
		cooldown -= 1

	var dx := player.position.x - position.x
	var dist := absf(dx)
	# 前摇与挥击期间锁朝向，让玩家绕背有确定收益。
	if dist > 1.0 and state not in ["windup", "attack"]:
		face = 1 if dx > 0.0 else -1

	match state:
		"idle":
			if dist <= AGGRO_RANGE and _has_los():
				_set_state("alert")
		"alert":
			if frame >= ALERT_TICKS:
				_set_state("run")
		"run":
			if not _has_los():
				_set_state("idle")
			elif dist <= ATTACK_RANGE and cooldown <= 0:
				_set_state("windup")
			else:
				_move_horizontal(face * RUN_SPEED * dt)
		"windup":
			if frame >= WINDUP_TICKS:
				_set_state("attack")
		"attack":
			if frame <= ATTACK_ACTIVE_TO:
				_move_horizontal(face * LUNGE_SPEED * dt)
			if frame >= ATTACK_TICKS:
				_set_state("recover")
		"recover":
			if frame >= RECOVER_TICKS:
				cooldown = COOLDOWN_TICKS
				_set_state("idle" if dist > AGGRO_RANGE or not _has_los() else "run")
	_sync_sprite()


func _move_horizontal(amount: float) -> void:
	if level == null or is_zero_approx(amount):
		return
	var nx := position.x + amount
	var dir := 1 if amount > 0.0 else -1
	var probe_x := nx + dir * BODY_W * 0.5
	var blocked := false
	for oy in [position.y - BODY_H + 6.0, position.y - BODY_H * 0.5, position.y - 3.0]:
		if level.solid_at(probe_x, oy) and not level.is_platform(probe_x, oy):
			blocked = true
			break
	# 与枪手一致：平台边缘停步；攻击突进也不能冲下悬崖。
	if not blocked and not level.solid_at(probe_x, position.y + 4.0):
		blocked = true
	if not blocked:
		var next_body := _body_rect_at(nx)
		for door in door_blockers:
			if door.locked and door.body_rect().intersects(next_body):
				blocked = true
				break
	if not blocked:
		position.x = nx


func _has_los() -> bool:
	if vision_blocker.is_valid() and player != null \
			and vision_blocker.call(position + Vector2(0, -46), player.position + Vector2(0, -46)):
		return false
	if level == null or player == null:
		return true
	var a := position + Vector2(0.0, -48.0)
	var b := player.position + Vector2(0.0, -48.0)
	var delta := b - a
	var steps := maxi(1, int(delta.length() / 8.0))
	for i in range(1, steps):
		var sample := a + delta * (float(i) / steps)
		if level.solid_at(sample.x, sample.y):
			return false
		for door in door_blockers:
			if door.locked and door.body_rect().has_point(sample):
				return false
	return true


func _set_state(next: String) -> void:
	if next != "dead":
		corpse_lift = 0.0
		corpse_ground_projected = false
		corpse_ground_valid = false
	if state == next:
		return
	state = next
	frame = 0
	_anim_clock = 0.0
	if _sprite != null:
		_sprite.modulate = Color.WHITE


func _state_duration() -> int:
	return {
		"alert": ALERT_TICKS,
		"windup": WINDUP_TICKS,
		"attack": ATTACK_TICKS,
		"recover": RECOVER_TICKS,
		"dead": DEATH_TICKS,
	}.get(state, 1)


func _anim_frame(anim: Dictionary) -> int:
	var count := int(anim["frames"])
	if bool(anim["loop"]):
		var fps := IDLE_VISUAL_FPS if state == "idle" else RUN_VISUAL_FPS
		# 呼吸往返、跑步降速；不改移动速度与攻击逻辑 tick。
		if state == "idle" and count > 1:
			var phase := floori(_anim_clock * fps) % (2 * count - 2)
			return phase if phase < count else 2 * count - 2 - phase
		return floori(_anim_clock * fps) % count
	var progress := clampf(float(frame) / maxf(1.0, float(_state_duration() - 1)), 0.0, 1.0)
	if state in ["alert", "recover"]:
		# 警觉/收招延长关键姿势停留；完整攻击前摇、挥击和死亡动作保持原帧节奏。
		return 0 if progress < 0.6 else count - 1
	return mini(count - 1, floori(progress * count))


func _sync_sprite() -> void:
	# 逻辑状态沿用项目统一的 dead；素材动作行命名为 death。
	var anim_name := "death" if state == "dead" else state
	if _sprite == null or not _anims.has(anim_name):
		return
	var anim: Dictionary = _anims[anim_name]
	var rect := Rect2(_anim_frame(anim) * CELL.x, int(anim["row"]) * CELL.y,
		CELL.x, CELL.y)
	var visual_lift := corpse_lift if dead else 0.0
	var sprites: Array[Sprite2D] = [_outline, _sprite, _rim]
	for sprite in sprites:
		sprite.region_rect = rect
		sprite.flip_h = face < 0
		# 每次从原基线计算，不能重复减偏移造成尸体逐帧上飘。
		sprite.position.y = (CELL.y * 0.5 - BASELINE_Y) * SCALE - visual_lift
	var atlas_size := Vector2(_atlas.get_width(), _atlas.get_height())
	var region_min := rect.position / atlas_size
	var region_max := rect.end / atlas_size
	var effect_sprites: Array[Sprite2D] = [_outline, _rim]
	for sprite in effect_sprites:
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("region_min", region_min)
		mat.set_shader_parameter("region_max", region_max)

	# 警戒先亮青、前摇转品红快速闪，动作语义不依赖文字。
	if state == "alert":
		# 警戒仅一次轻微提亮，攻击前摇的危险预警保持原样。
		var alert_pulse := 1.0 + 0.12 * sin(clampf(float(frame) / ALERT_TICKS, 0.0, 1.0) * PI)
		_sprite.modulate = Color(1.0, alert_pulse, alert_pulse)
	elif state == "windup":
		var warn := 1.0 + 0.65 * absf(sin(frame * 0.65))
		_sprite.modulate = Color(warn, 1.0 / warn, 1.0 + 0.18 * (warn - 1.0))
	else:
		_sprite.modulate = Color.WHITE
	_rim.visible = not dead
	# 本体随根节点飞行；仅将阴影投回实际地面，避免影子跟着尸体飘。
	var projected := dead and corpse_ground_projected
	var ground_height := maxf(0.0, corpse_ground_y - global_position.y) if projected else visual_lift
	_shadow.position = Vector2(0.0, corpse_ground_y - global_position.y - 1.0) if projected and corpse_ground_valid else Vector2(0.0, -1.0)
	_shadow.visible = not projected or corpse_ground_valid
	var shadow_lift := clampf(ground_height / 48.0, 0.0, 1.0)
	_shadow.scale = (Vector2(2.6, 1.2) if dead else Vector2(1.8, 1.2)) * (1.0 - 0.22 * shadow_lift)
	_shadow.modulate.a = 0.34 * (1.0 - 0.45 * shadow_lift)
