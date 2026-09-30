extends Node2D
class_name QuarantineHound
## Manual 60 Hz enemy: game owns ticking, damage dispatch and corpse physics.
const ATLAS_PATH := "res://assets/enemy/hound/atlas.png"
const META_PATH := "res://assets/enemy/hound/atlas.json"
const CELL := Vector2i(160, 96)
const BASELINE_Y := 89.0
const SCALE := 1.0
const BODY_W := 56.0
const BODY_H := 48.0
const AGGRO_RANGE := 420.0
const POUNCE_RANGE := 200.0 ## 2026-09-28: ≈ 540px/s × 22 tick 最远 198px，站定玩家一定扑得到
const RUN_SPEED := 150.0
const POUNCE_SPEED := 540.0
const ALERT_TICKS := 14
const WINDUP_TICKS := 24
const POUNCE_TICKS := 22
const RECOVER_TICKS := 36
const COOLDOWN_TICKS := 20
const DEATH_TICKS := 54
const MOTION := preload("res://scripts/death_inertia.gd")
const GRAVITY := MOTION.GRAVITY
const RIM_SHADER_CODE := GruntGunner.RIM_SHADER_CODE
const IDLE_VISUAL_FPS := FreightInspector.IDLE_VISUAL_FPS
const RUN_VISUAL_FPS := FreightInspector.RUN_VISUAL_FPS

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


var velocity := Vector2.ZERO
var pounce_target := Vector2.ZERO
var _pounce_origin := Vector2.ZERO
var _pounce_duration := 0.0
var _pounce_elapsed := 0.0
var _pounce_landed := false
var _attack_spent := false
var _ground_y := 0.0
var _cell := CELL
var _baseline_y := BASELINE_Y
var _pivot_x := CELL.x * 0.5
var _standing_content_height := 0.0
var _death_used_rect := Rect2i()

func _ready() -> void:
	# 新生成 PNG 尚未被编辑器导入时，测试进程直接从文件构造纹理。
	if ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH)
	else:
		var atlas_image := Image.load_from_file(ATLAS_PATH)
		_atlas = ImageTexture.create_from_image(atlas_image)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	if parsed is Dictionary:
		_load_atlas_metadata(parsed)
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
	sprite.position.y = (_cell.y * 0.5 - _baseline_y) * SCALE
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
	return _standing_content_height * SCALE


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


func _load_atlas_metadata(meta: Dictionary) -> void:
	_anims = meta.get("animations", {})
	var size: Array = meta.get("cell_size", [CELL.x, CELL.y])
	_cell = Vector2i(int(size[0]), int(size[1]))
	_baseline_y = float(meta.get("baseline_y", BASELINE_Y))
	_pivot_x = float(meta.get("pivot_x", _cell.x * 0.5))
	_standing_content_height = 0.0
	_death_used_rect = Rect2i()
	var last_death := -1
	for record: Dictionary in meta.get("frames", []):
		var box: Array = record["cell_bbox"]
		var rect := Rect2i(int(box[0]), int(box[1]), int(box[2]), int(box[3]))
		if record["animation"] == "idle":
			_standing_content_height = maxf(_standing_content_height, rect.size.y)
		elif record["animation"] == "death" and int(record["frame"]) > last_death:
			last_death = int(record["frame"])
			_death_used_rect = rect


func corpse_used_rect() -> Rect2i:
	return _death_used_rect


func corpse_scale() -> float:
	return minf(SCALE, GruntGunner.CORPSE_LONGEST / maxf(1.0,
		maxf(_death_used_rect.size.x, _death_used_rect.size.y)))


func corpse_extent() -> float:
	return maxf(_death_used_rect.size.x, _death_used_rect.size.y) * corpse_scale()


func attack_active() -> bool:
	return state == "pounce" and not dead and not _attack_spent


func attack_rect() -> Rect2:
	var size := Vector2(60.0, 40.0)
	var center := position + Vector2(face * BODY_W * 0.5, -BODY_H * 0.5)
	return Rect2(center - size * 0.5, size)


## Successful HP loss consumes the attack; player owns roll/dash invulnerability.
func try_attack(victim: Node2D, hurtbox: Rect2) -> void:
	if not attack_active() or not attack_rect().intersects(hurtbox):
		return
	if _segment_blocked(body_rect().get_center(), hurtbox.get_center()):
		return
	var before: int = victim.hp
	victim.take_damage(1, position.x)
	_attack_spent = victim.hp < before


func step(dt: float) -> void:
	if dt <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	_anim_clock += dt
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - dt)
		if dead:
			frame += 1
		_sync_sprite()
		return
	frame += 1
	if dead or player == null:
		_sync_sprite()
		return
	var dx := player.position.x - position.x
	var dist := absf(dx)
	if dist > 1.0 and state in ["idle", "run", "cooldown"]:
		face = 1 if dx > 0.0 else -1
	match state:
		"idle":
			velocity = Vector2.ZERO
			if dist <= AGGRO_RANGE and _has_los():
				_set_state("alert")
		"alert":
			if not _has_los() or dist > AGGRO_RANGE:
				_set_state("idle")
			elif frame >= ALERT_TICKS:
				_set_state("run" if dist > POUNCE_RANGE else "windup")
		"run":
			if not _has_los():
				velocity = Vector2.ZERO
				_set_state("idle")
			elif dist <= POUNCE_RANGE:
				velocity = Vector2.ZERO
				_set_state("windup")
			else:
				var before := position
				_move_horizontal(face * RUN_SPEED * dt)
				velocity = (position - before) / dt
		"windup":
			if not _has_los():
				_set_state("idle")
			elif frame >= WINDUP_TICKS:
				_begin_pounce()
				_advance_pounce(dt) # Launch is the first active tick, not an extra tick 0.
		"pounce":
			if _pounce_landed:
				_set_state("recover")
			else:
				_advance_pounce(dt)
		"recover":
			# Reuse corpse ground friction for the harmless landing skid.
			velocity.x = move_toward(velocity.x, 0.0, MOTION.GROUND_FRICTION * dt)
			_move_horizontal(velocity.x * dt, _ground_y)
			if position.y < _ground_y:
				_move_vertical(velocity.y * dt + GRAVITY * dt * dt * 0.5)
				velocity.y += GRAVITY * dt
			if frame >= RECOVER_TICKS:
				velocity = Vector2.ZERO
				cooldown = COOLDOWN_TICKS
				_set_state("cooldown")
		"cooldown":
			cooldown = maxi(0, COOLDOWN_TICKS - frame)
			if frame >= COOLDOWN_TICKS:
				_set_state("idle" if dist > AGGRO_RANGE or not _has_los()
					else ("run" if dist > POUNCE_RANGE else "alert"))
	_sync_sprite()


func _begin_pounce() -> void:
	# Sample ONCE at the END of windup, never in flight.
	pounce_target = player.position
	_pounce_origin = position
	_ground_y = position.y
	var dx := pounce_target.x - position.x
	if not is_zero_approx(dx):
		face = 1 if dx > 0.0 else -1
	_pounce_duration = clampf(absf(dx) / POUNCE_SPEED, 1.0 / 60.0, POUNCE_TICKS / 60.0)
	_pounce_elapsed = 0.0
	_pounce_landed = false
	_attack_spent = false
	# Aim at the locked feet in both axes. Ground support still limits horizontal travel.
	var landing_y := minf(pounce_target.y, _ground_y)
	velocity = Vector2(face * minf(POUNCE_SPEED, absf(dx) / _pounce_duration),
		(landing_y - position.y) / _pounce_duration - GRAVITY * _pounce_duration * 0.5)
	_set_state("pounce")


func _advance_pounce(dt: float) -> void:
	var remaining := minf(dt, _pounce_duration - _pounce_elapsed)
	while remaining > 0.000001:
		var tick := minf(remaining, MOTION.MAX_STEP)
		var before_x := position.x
		_move_horizontal(velocity.x * tick, _ground_y)
		if is_equal_approx(position.x, before_x):
			velocity.x = 0.0
		var dy := velocity.y * tick + GRAVITY * tick * tick * 0.5
		velocity.y += GRAVITY * tick
		_move_vertical(dy)
		_pounce_elapsed += tick
		remaining -= tick
	if _pounce_elapsed >= _pounce_duration - 0.000001 or frame >= POUNCE_TICKS:
		_pounce_landed = true # Final flight sample still participates in game's damage check.


func _move_vertical(amount: float) -> void:
	if amount > 0.0:
		amount = minf(amount, _ground_y - position.y)
	var steps := maxi(1, ceili(absf(amount) / MOTION.SWEEP_STEP))
	var dy := amount / steps
	for i in steps:
		var candidate := Rect2(body_rect().position + Vector2(0, dy), body_rect().size)
		if _body_blocked(candidate):
			velocity.y = 0.0
			return
		# Match ground enemies' launch surface; never fall through it or a higher one-way top.
		if dy > 0.0 and level != null:
			for x in [candidate.position.x, candidate.get_center().x, candidate.end.x]:
				var top := floorf(candidate.end.y / CorridorLevel.TS) * CorridorLevel.TS
				if level.is_platform(x, candidate.end.y) and position.y <= top:
					position.y = top - 0.1
					_ground_y = position.y
					velocity.y = 0.0
					return
		position.y = minf(position.y + dy, _ground_y)
		if position.y >= _ground_y:
			velocity.y = 0.0


func _body_blocked(body: Rect2) -> bool:
	if level != null:
		for x in [body.position.x, body.get_center().x, body.end.x]:
			for y in [body.position.y, body.get_center().y, body.end.y - 0.1]:
				if level.solid_at(x, y) and not level.is_platform(x, y):
					return true
	for door in door_blockers:
		if is_instance_valid(door) and door.locked and door.body_rect().intersects(body):
			return true
	return false


func _move_horizontal(amount: float, support_y := INF) -> void:
	if is_zero_approx(amount):
		return
	var floor_y := position.y if support_y == INF else support_y
	var steps := maxi(1, ceili(absf(amount) / MOTION.SWEEP_STEP))
	var dx := amount / steps
	var direction := signf(dx)
	for i in steps:
		var candidate := _body_rect_at(position.x + dx)
		var probe_x := candidate.get_center().x + direction * BODY_W * 0.5
		if _body_blocked(candidate):
			return
		if level != null and not level.solid_at(probe_x, floor_y + 4.0):
			return
		position.x += dx


func _segment_blocked(a: Vector2, b: Vector2) -> bool:
	# Reuse the 2px sweep spacing to catch existing thin glass panels too.
	var steps := maxi(1, ceili(a.distance_to(b) / MOTION.SWEEP_STEP))
	for i in range(steps + 1):
		var sample := a.lerp(b, float(i) / steps)
		if level != null and level.solid_at(sample.x, sample.y):
			return true
		for door in door_blockers:
			if is_instance_valid(door) and door.locked and door.body_rect().has_point(sample):
				return true
	return false


func _has_los() -> bool:
	if player == null:
		return false
	var a := body_rect().get_center()
	var b := player.position - Vector2(0, BODY_H * 0.5)
	return not (vision_blocker.is_valid() and vision_blocker.call(a, b)) \
		and not _segment_blocked(a, b)


func capture_combat_state() -> Dictionary:
	return {"velocity": velocity, "pounce_target": pounce_target,
		"_pounce_origin": _pounce_origin, "_pounce_duration": _pounce_duration,
		"_pounce_elapsed": _pounce_elapsed, "_pounce_landed": _pounce_landed,
		"_attack_spent": _attack_spent, "_ground_y": _ground_y,
		"hitstop": hitstop, "cooldown": cooldown}


func apply_combat_state(pose: Dictionary) -> void:
	for key: String in pose:
		set(key, pose[key])


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
		"pounce": POUNCE_TICKS,
		"cooldown": COOLDOWN_TICKS,
		"recover": RECOVER_TICKS,
		"dead": DEATH_TICKS,
	}.get(state, 1)


func _anim_frame(anim: Dictionary) -> int:
	var count := int(anim["frames"])
	if state == "pounce":
		return mini(count - 1, floori(clampf(_pounce_elapsed / maxf(_pounce_duration, 0.000001), 0.0, 1.0) * count))
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
	var anim_name := "death" if state == "dead" else ("idle" if state == "cooldown" else state)
	if _sprite == null or not _anims.has(anim_name):
		return
	var anim: Dictionary = _anims[anim_name]
	var rect := Rect2(_anim_frame(anim) * _cell.x, int(anim["row"]) * _cell.y,
		_cell.x, _cell.y)
	var visual_lift := corpse_lift if dead else 0.0
	var sprite_scale := lerpf(SCALE, corpse_scale(), float(_anim_frame(anim) + 1) / int(anim["frames"])) if dead else SCALE
	var sprites: Array[Sprite2D] = [_outline, _sprite, _rim]
	for sprite in sprites:
		sprite.region_rect = rect
		sprite.flip_h = face < 0
		# 每次从原基线计算，不能重复减偏移造成尸体逐帧上飘。
		sprite.scale = Vector2.ONE * sprite_scale
		sprite.position = Vector2((_cell.x * 0.5 - _pivot_x) * face * sprite_scale,
			(_cell.y * 0.5 - _baseline_y) * sprite_scale - visual_lift)
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
