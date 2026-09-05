extends Node2D
class_name GruntGunner
## 货运枪手杂兵：使用 8×6 透明图集，保持现有子弹、门、彩血与球棒击退协议。
## 帧窗口仍按 60fps 逻辑 tick 驱动；新增动画态不会拉长旧版约 50 tick 的出弹预警。
##   idle    —— 站岗，玩家进入 480px 且视线无遮挡 → alert
##   alert   —— 品红警示灯亮起，明确告诉玩家敌人已发现目标
##   run     —— 已索敌但距离 > 260px：90px/s 走向玩家（贴地，不撞墙）
##   aim     —— 端枪瞄准；alert + aim + fire 前段合计约 50 tick 后出膛
##   fire    —— 播放四帧开火动作，第 2 张视觉帧只发射一次子弹
##   recover —— 逻辑后摇保持存在，但按用户要求复用 idle；近距复射会重新走 alert
##   dead    —— 一击必杀；播放六帧倒地并停在末帧，尸体留场
##
## 子弹/近战命中由 game 调 take_hit()。接口与 KairullBoss 一致
## （player/dead/state/frame/step/body_rect/take_hit/shoot_orb）。

signal shoot_orb(from_pos: Vector2, velocity: Vector2)

const ATLAS_PATH := "res://assets/enemy/grunt/atlas.png"
const META_PATH := "res://assets/enemy/grunt/atlas.json"
const CELL := Vector2i(256, 256)
const BASELINE_Y := 224.0
const SCALE := 96.0 / 152.0     ## 站姿最高 152px，缩放后仍为 96px，与旧玩法碰撞预算一致。
const BODY_W := 44.0            ## 世界坐标碰撞宽度；不随新美术源像素尺寸变化。
const BODY_H := 96.0            ## 世界坐标碰撞高度；保持现有关卡和球棒判定不漂移。
const AGGRO_RANGE := 480.0
const SHOOT_RANGE := 260.0      ## 进入此距离站定蓄力射击
const RUN_SPEED := 90.0
const BULLET_SPEED := 520.0
const ALERT_TICKS := 18         ## 警戒 + 瞄准 + 开火前段仍合计 50 tick。
const AIM_TICKS := 27
const FIRE_SHOT_TICK := 5       ## 对齐 fire 第 2 帧的枪口焰。
const FIRE_TICKS := 17          ## 四帧约 14fps。
const RECOVER_TICKS := 18       ## 出弹后剩余 fire 12 tick + recover 18 tick = 原 30 tick 后摇。
const DEATH_TICKS := 54         ## 倒地六帧约 6.7fps；仅表现时长，不改死亡结算。
const IDLE_VISUAL_FPS := 2.0    ## 日常再降速：只改显示，移动/攻击/死亡逻辑时钟不变。
const RUN_VISUAL_FPS := 6.0
const MUZZLE := Vector2(44.0, -64.0)   ## 按新图集枪口焰中心校准（随 face 镜像）。

## 深色描边（近黑紫）：与玩家描边同款做法——背后叠一张膨胀剪影。
## 新图集会缩小显示，采样 2 个源 texel 才能稳定读作约 1 个世界像素。
const OUTLINE_TEXEL_STEP := 2.0
const OUTLINE_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(0.09, 0.05, 0.14, 1.0);
uniform float texel_step = 1.0;
uniform vec2 region_min = vec2(0.0);
uniform vec2 region_max = vec2(1.0);
varying vec4 outline_vertex_color;

void vertex() {
	// 保留节点调制，不在fragment重复乘回纹理透明度，否则外扩描边被抵消。
	outline_vertex_color = COLOR;
}

void fragment() {
	vec2 ts = TEXTURE_PIXEL_SIZE * texel_step;
	float a = texture(TEXTURE, UV).a;
	a = max(a, texture(TEXTURE, clamp(UV + vec2(ts.x, 0.0), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV - vec2(ts.x, 0.0), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV + vec2(0.0, ts.y), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV - vec2(0.0, ts.y), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV + ts, region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV - ts, region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV + vec2(ts.x, -ts.y), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV + vec2(-ts.x, ts.y), region_min, region_max)).a);
	vec4 tint = outline_color * outline_vertex_color;
	COLOR = vec4(tint.rgb, tint.a * step(0.05, a));
}
"""

## KZ 式轮廓光：亮青边环（只画剪影外侧 1 texel 膨胀环，不压本体像素）。
## 青色与瞄准品红闪错开（调色板 NEON_CYAN）；中等 alpha，暗墙上把剪影剥出来。
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
	a = max(a, texture(TEXTURE, clamp(UV + ts, region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV - ts, region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV + vec2(ts.x, -ts.y), region_min, region_max)).a);
	a = max(a, texture(TEXTURE, clamp(UV + vec2(-ts.x, ts.y), region_min, region_max)).a);
	float ring = clamp(a - own, 0.0, 1.0) * step(0.05, a);
	vec4 tint = rim_color * COLOR;
	COLOR = vec4(tint.rgb, tint.a * ring);
}
"""

## 本体微提亮（self_modulate，与瞄准品红闪用的 modulate 通道相乘叠合，互不覆盖）
const SELF_LIFT := Color(1.12, 1.12, 1.18)
## 尸体归一化：death 末帧是横躺 sprawl（素材内容约 240×63），
## 独立缩放因子把最长边压到 ≈ 站立身高 96px——尸体不应比活人更抢画面。
## 同时摘掉亮青轮廓光（rim 是活体威胁的可读性辅助，尸体要往后退）。
const CORPSE_LONGEST := 96.0    ## 尸体最长边目标（px，世界坐标）
## 接触阴影：脚下软椭圆（KZ 式角色落地锚定），程序生成径向渐变
const SHADOW_ALPHA := 0.35
const SHADOW_TEX_W := 32
const SHADOW_TEX_H := 12
const SHADOW_SCALE := Vector2(1.7, 1.2)         ## ≈54×14px，略宽于 44px 碰撞体
const CORPSE_SHADOW_SCALE := Vector2(3.1, 1.3)  ## ≈99×16px，跟随横躺尸体宽度

var state := "idle"
var frame := 0                  ## 当前状态已进行的 tick（帧窗口计数器）
var face := -1
var dead := false
var corpse_lift := 0.0          ## 尸体视觉抬升；地面锚点与碰撞盒保持原位。
var corpse_ground_y := 0.0
var corpse_ground_valid := false
var corpse_ground_projected := false ## 真惯性飞行只投地面阴影，不再二次抬高本体。
var hitstop := 0.0
## 兼容既有渲染/测试脚本的旧字段；复射节奏现由 fire/recover/alert/aim 显式窗口控制。
var cooldown := 0
var player: Node2D              ## 由 game 注入
var level: CorridorLevel        ## 由 game 注入（LOS/撞墙查询）
var door_blockers: Array = []   ## 由 game 注入（RoomDoor 列表；锁定时挡 LOS）
var vision_blocker := Callable() ## 可选烟幕视线遮蔽，不改变开火窗口或角色伤害。

var _atlas: Texture2D
var _anims: Dictionary = {}
var _anim_clock := 0.0
var _shot_fired := false
var _standing_content_height := 152.0
var _death_used_rect := Rect2i(8, 161, 240, 63)
var _sprite: Sprite2D
var _outline: Sprite2D
var _rim: Sprite2D       ## 亮青轮廓光环（画在本体上，只显剪影外沿）
var _shadow: Sprite2D    ## 脚下接触阴影（画在最底层）


func _ready() -> void:
	if ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH) as Texture2D
	else:
		# 新增 PNG 尚未生成导入缓存时，无头测试仍可直接读取原图。
		var atlas_image := Image.load_from_file(ATLAS_PATH)
		_atlas = ImageTexture.create_from_image(atlas_image)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	if parsed is Dictionary:
		var meta := parsed as Dictionary
		_anims = meta.get("animations", {}) as Dictionary
		_read_frame_bounds(meta)
	else:
		push_error("枪手图集元数据解析失败：%s" % META_PATH)
	# 绘制顺序（先创建先绘制）：接触阴影 → 深色描边 → 本体 → 亮青轮廓光
	_shadow = Sprite2D.new()
	_shadow.name = "ContactShadow"
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   ## 软渐变允许线性
	_shadow.texture = _make_shadow_texture()
	_shadow.modulate = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
	_shadow.scale = SHADOW_SCALE
	_shadow.position = Vector2(0.0, -1.0)   ## 贴脚底，略抬 1px 防与地板顶沿互咬
	add_child(_shadow)
	# 描边剪影先创建 → 排在本体后面绘制（同 z 按子节点序）
	_outline = _make_region_sprite("Outline")
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("texel_step", OUTLINE_TEXEL_STEP)
	_outline.material = mat
	add_child(_outline)
	_sprite = _make_region_sprite("Sprite")
	_sprite.self_modulate = SELF_LIFT   ## 微提亮；瞄准品红闪走 modulate，两通道相乘
	add_child(_sprite)
	_rim = _make_region_sprite("Rim")
	var rsh := Shader.new()
	rsh.code = RIM_SHADER_CODE
	var rmat := ShaderMaterial.new()
	rmat.shader = rsh
	rmat.set_shader_parameter("texel_step", OUTLINE_TEXEL_STEP)
	_rim.material = rmat
	add_child(_rim)
	_sync_sprite()


func _make_region_sprite(node_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = _atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_filter_clip_enabled = true
	return sprite


func _read_frame_bounds(meta: Dictionary) -> void:
	# 元数据记录实际 Alpha 包围盒，用它保持旧版 96px 站高与尸体尺寸接口。
	var records: Array = meta.get("frames", []) as Array
	var last_death_frame := -1
	for value in records:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var bbox: Array = record.get("cell_bbox", []) as Array
		if bbox.size() != 4:
			continue
		var rect := Rect2i(int(bbox[0]), int(bbox[1]), int(bbox[2]), int(bbox[3]))
		var animation := String(record.get("animation", ""))
		if animation == "idle":
			_standing_content_height = maxf(_standing_content_height, float(rect.size.y))
		elif animation == "death":
			var death_frame := int(record.get("frame", -1))
			if death_frame > last_death_frame:
				last_death_frame = death_frame
				_death_used_rect = rect


## 程序生成椭圆渐变阴影纹理（白底 alpha 渐变，modulate 压黑）
func _make_shadow_texture() -> Texture2D:
	var img := Image.create(SHADOW_TEX_W, SHADOW_TEX_H, false, Image.FORMAT_RGBA8)
	var c := Vector2(SHADOW_TEX_W, SHADOW_TEX_H) * 0.5 - Vector2(0.5, 0.5)
	for y in range(SHADOW_TEX_H):
		for x in range(SHADOW_TEX_W):
			var d: float = clampf(1.0 - Vector2((x - c.x) / (SHADOW_TEX_W * 0.5),
					(y - c.y) / (SHADOW_TEX_H * 0.5)).length(), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, d * d))
	return ImageTexture.create_from_image(img)


func body_rect() -> Rect2:
	return Rect2(position.x - BODY_W * 0.5, position.y - BODY_H, BODY_W, BODY_H)


## 仅移动美术层，击退扫掠继续使用原来的地面碰撞锚点。
func set_corpse_lift(value: float) -> void:
	corpse_lift = maxf(0.0, value)
	corpse_ground_projected = false
	_sync_sprite()


## 接收惯性求解器查到的真实地面；无承接面时不在半空画接触阴影。
func set_corpse_ground(world_y: float, valid := true) -> void:
	corpse_lift = 0.0
	corpse_ground_y = world_y
	corpse_ground_valid = valid
	corpse_ground_projected = true
	_sync_sprite()


## 伤口续喷跟随抬起的尸体，已飞出的血滴仍保留世界坐标。
func wound_anchor_world() -> Vector2:
	return body_rect().get_center() - Vector2(0.0, corpse_lift if dead else 0.0)


## 站立视觉高度（idle 内容高 × SCALE），敌我比例验收用
func standing_height() -> float:
	return _standing_content_height * SCALE


## 尸体内容矩形（源像素），尸体贴地验收用
func corpse_used_rect() -> Rect2i:
	return _death_used_rect


## 尸体缩放因子：最长边压到 CORPSE_LONGEST（与站姿 SCALE 解耦）
func corpse_scale() -> float:
	var u := _death_used_rect
	return CORPSE_LONGEST / maxf(float(u.size.x), float(u.size.y))


## 尸体最长边（世界 px），尸体不占画面验收用
func corpse_extent() -> float:
	var u := _death_used_rect
	return maxf(float(u.size.x), float(u.size.y)) * corpse_scale()


func take_hit(_from_x: float, _damage := 1) -> bool:
	if dead:
		return false
	dead = true
	corpse_lift = 0.0
	corpse_ground_projected = false
	corpse_ground_valid = false
	hitstop = 0.10
	_set_state("dead")
	_sync_sprite()
	return true


func step(dt: float) -> void:
	_anim_clock += dt
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - dt)
		# 敌人 hitstop 同时承担击退期间的 AI 锁定；尸体仍在移动，死亡帧必须继续倒下。
		if dead:
			frame += 1
		_sync_sprite()
		return
	frame += 1
	if dead:
		_sync_sprite()
		return
	if player == null:
		_sync_sprite()
		return
	var dx: float = player.position.x - position.x
	var dist := absf(dx)
	# 警戒阶段仍可转身；瞄准和开火锁朝向，让玩家绕背有确定收益。
	if dist > 1.0 and state not in ["aim", "fire"]:
		face = 1 if dx > 0 else -1

	match state:
		"idle":
			if dist < AGGRO_RANGE and _has_los():
				_set_state("alert")
		"alert":
			if not _has_los() or dist >= AGGRO_RANGE * 1.2:
				_set_state("idle")
			elif frame >= ALERT_TICKS:
				_set_state("run" if dist > SHOOT_RANGE else "aim")
		"run":
			if dist <= SHOOT_RANGE or not _has_los():
				_set_state("aim" if _has_los() else "idle")
			else:
				_move_horizontal(face * RUN_SPEED * dt)
		"aim":
			if not _has_los() or dist >= AGGRO_RANGE * 1.2:
				_set_state("idle")
			elif frame >= AIM_TICKS:
				_set_state("fire")
		"fire":
			# 枪口焰出现的视觉帧只结算一次发射，不能因掉帧重复生成子弹。
			if not _shot_fired and frame >= FIRE_SHOT_TICK:
				_fire()
				_shot_fired = true
			if frame >= FIRE_TICKS:
				_set_state("recover")
		"recover":
			if frame >= RECOVER_TICKS:
				# 仍锁定目标时统一重走警戒；否则 260px 外会绕过 18 tick 预警，形成射速断崖。
				_set_state("idle" if dist > AGGRO_RANGE or not _has_los() else "alert")
	_sync_sprite()


func _move_horizontal(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var nx: float = position.x + amount
	var probe_x := nx + face * 18.0
	# 保留已验证补丁：撞墙停步，同时禁止枪手走出平台悬空漂移。
	var blocked := level != null and level.solid_at(probe_x, position.y - 40.0)
	if not blocked and level != null and not level.solid_at(probe_x, position.y + 4.0):
		blocked = true
	if not blocked:
		position.x = nx


func _fire() -> void:
	if player == null:
		return
	var from := position + Vector2(MUZZLE.x * face, MUZZLE.y)
	# 瞄准已锁朝向：玩家绕背时不能让子弹从枪口反向折返。
	var target := player.position + Vector2(0, -46.0)
	var aim_delta := target - from
	aim_delta.x = absf(aim_delta.x) * face
	var dir := aim_delta.normalized()
	shoot_orb.emit(from, dir * BULLET_SPEED)


func _set_state(s: String) -> void:
	if s != "dead":
		corpse_lift = 0.0
		corpse_ground_projected = false
		corpse_ground_valid = false
	if state != s:
		state = s
		frame = 0
		_anim_clock = 0.0
		_shot_fired = false
		if _sprite != null:
			_sprite.modulate = Color.WHITE


## 视线检测：沿连线每 8px 采样，碰实心即遮挡（逆向：敌我 x 比较 + 遮挡判定）。
## 锁定房门同样挡视线（门格在网格里是空的，由 RoomDoor 节点提供遮挡语义）。
func _has_los() -> bool:
	if vision_blocker.is_valid() and player != null \
			and vision_blocker.call(position + Vector2(0, -46), player.position + Vector2(0, -46)):
		return false
	if level == null:
		return true
	var a := position + Vector2(0, -46.0)
	var b := player.position + Vector2(0, -46.0)
	var d := b - a
	var steps := int(d.length() / 8.0)
	for i in range(1, steps):
		var p := a + d * (float(i) / steps)
		if level.solid_at(p.x, p.y):
			return false
		for door in door_blockers:
			if door.locked and door.body_rect().has_point(p):
				return false
	return true


func _animation_name() -> String:
	match state:
		"alert": return "alert"
		"run": return "run"
		"aim": return "aim"
		"fire": return "fire"
		"dead": return "death"
		# 用户指定后摇不另造动作，直接复用待机呼吸行。
		"recover": return "idle"
	return "idle"


func _state_duration() -> int:
	return {
		"alert": ALERT_TICKS,
		"aim": AIM_TICKS,
		"fire": FIRE_TICKS,
		"dead": DEATH_TICKS,
	}.get(state, 1)


func _animation_frame(anim_name: String) -> int:
	var value: Variant = _anims.get(anim_name, {})
	if not value is Dictionary:
		return 0
	var anim := value as Dictionary
	var count := maxi(1, int(anim.get("frames", 1)))
	if bool(anim.get("loop", false)):
		var fps := IDLE_VISUAL_FPS if anim_name == "idle" else RUN_VISUAL_FPS
		# 呼吸往返播放，避免最后一帧直接跳回首帧导致肩膀抽动。
		if anim_name == "idle" and count > 1:
			var phase := floori(_anim_clock * fps) % (2 * count - 2)
			return phase if phase < count else 2 * count - 2 - phase
		return floori(_anim_clock * fps) % count
	var duration := maxi(1, _state_duration())
	var progress := clampf(float(frame) / maxf(1.0, float(duration - 1)), 0.0, 1.0)
	if anim_name in ["alert", "aim"]:
		# 警觉/举枪只保留起势和就绪，减少切帧；索敌/开火预警总时长不缩短。
		return 0 if progress < 0.6 else count - 1
	return mini(count - 1, floori(progress * count))


## 无头测试只读接口：避免测试硬编码 Sprite2D 的 region_rect。
func debug_animation_name() -> String:
	return _animation_name()


func debug_animation_frame() -> int:
	return _animation_frame(_animation_name())


func _sync_sprite() -> void:
	if _sprite == null or _outline == null or _rim == null or _atlas == null:
		return
	var anim_name := _animation_name()
	var value: Variant = _anims.get(anim_name, {})
	if not value is Dictionary:
		return
	var anim := value as Dictionary
	var anim_frame := _animation_frame(anim_name)
	var rect := Rect2(anim_frame * CELL.x,
			int(anim.get("row", 0)) * CELL.y, CELL.x, CELL.y)
	# 所有格子的有效像素底线统一为 y=224；不再按各帧包围盒造成脚底跳动。
	var sprite_scale := SCALE
	if dead:
		# 倒地过程中逐帧收敛到最终尸体宽度，避免命中瞬间从 96px 突然缩成约 60px。
		var death_frame_count := maxi(1, int(anim.get("frames", 1)))
		var death_progress := float(anim_frame + 1) / float(death_frame_count)
		sprite_scale = lerpf(SCALE, corpse_scale(), death_progress)
	var visual_lift := corpse_lift if dead else 0.0
	var sprite_position := Vector2(0.0, (CELL.y * 0.5 - BASELINE_Y) * sprite_scale - visual_lift).round()
	var sprites: Array[Sprite2D] = [_outline, _sprite, _rim]
	for sprite in sprites:
		sprite.region_rect = rect
		sprite.flip_h = face < 0
		sprite.position = sprite_position
		sprite.scale = Vector2.ONE * sprite_scale

	var atlas_size := Vector2(_atlas.get_width(), _atlas.get_height())
	var region_min := rect.position / atlas_size
	var region_max := rect.end / atlas_size
	var effect_sprites: Array[Sprite2D] = [_outline, _rim]
	for sprite in effect_sprites:
		var material := sprite.material as ShaderMaterial
		material.set_shader_parameter("region_min", region_min)
		material.set_shader_parameter("region_max", region_max)

	# 瞄准只做轻微品红脉冲，主要预警仍来自图集中头灯的逐帧动作。
	if state == "aim":
		# 单次平滑提亮代替高频全身闪烁；抬枪与出弹时机完全不变。
		var aim_progress := clampf(float(frame) / AIM_TICKS, 0.0, 1.0)
		var warn := 1.0 + 0.22 * sin(aim_progress * PI * 0.5)
		_sprite.modulate = Color(warn, 1.0 / warn, warn)
	else:
		_sprite.modulate = Color.WHITE
	# 亮青轮廓只标记活体威胁；尸体与旧实现一致退回背景。
	_rim.visible = not dead
	# 世界位置已经包含抛物线；只有阴影反向补偿高度，不能再挪动本体。
	var projected := dead and corpse_ground_projected
	var ground_height := maxf(0.0, corpse_ground_y - global_position.y) if projected else visual_lift
	_shadow.position = Vector2(0.0, corpse_ground_y - global_position.y - 1.0) if projected and corpse_ground_valid else Vector2(0.0, -1.0)
	_shadow.visible = not projected or corpse_ground_valid
	var shadow_lift := clampf(ground_height / 48.0, 0.0, 1.0)
	_shadow.scale = (CORPSE_SHADOW_SCALE if dead else SHADOW_SCALE) * (1.0 - 0.22 * shadow_lift)
	_shadow.modulate.a = SHADOW_ALPHA * (1.0 - 0.45 * shadow_lift)
