extends Node2D
class_name KairullPlayer
## 玩家（纯球棒高速动作版）。
## 节点 position = 脚底中心。
##
## 操作规则（用户决策 2026-09-02，武士零化）：
##   - 左键 = 棒球棍三连击（后段再点接连击）；枪械/瞄准/换弹已禁用（资产保留）
##   - Shift = 棍影闪现（翻滚中可接）；Ctrl = 翻滚；二者地面可贴阶、空中规则分离
##   - 站立/跑/跳/死亡全部使用持棍新人物素材（hero_* 图集）
##
## 状态机：gun_idle（站立呼吸）/ aim（右键瞄准，LUT 定帧）/ run / dash / roll /
##         slide_start → slide_loop → slide_end / gun_jump_air /
##         gun_reload（换弹）/ death
##
## 物理：网页原型 60fps 逐帧常数 × (dt*60) 折算，帧率无关。

signal fell_out
signal fired(bullet: Dictionary)
signal notice(text: String)
signal dry_fire
signal reload_started          ## 开始换弹（播原速换弹音）
signal reload_interrupted      ## 移动/瞄准打断换弹
signal died
signal death_landed(world_point: Vector2, power: float, direction: float) ## 尸体首次接地，宿主统一生成落地尘土。
signal hurt                    ## 受击（HP-1）
signal bat_swing_started(stage: int)           ## 挥棍动作开始（播挥棒音效）
signal bat_swung(hitbox: Rect2, stage: int)    ## 命中窗口到达，发一次判定盒
signal dashed                                  ## Shift 闪现成功（配冲刺音效）
signal smoke_throw_requested(target_world: Vector2) ## 按住R瞄准、左键确认；成功生成弹体后才由宿主扣除携带物。

const DASH_COOLDOWN_INDICATOR_SCRIPT := preload("res://scripts/dash_cooldown_indicator.gd")
const DEATH_INERTIA_SCRIPT := preload("res://scripts/death_inertia.gd")
const SMOKE_ICON_SCRIPT := preload("res://scripts/smoke_grenade_icon.gd")

const TS := 32
const STAIR_STEP_PX := 16.0     ## 正式工业楼梯固定 32px 前进 / 16px 抬升
const STAIR_SNAP_EPS := 0.35    ## 吸收脚底 -0.1px 锚点与浮点积分误差
const CHAR_SCALE := 0.4        ## 角色缩放 ≈ 2.6 格高
const BAT_SCALE_FACTOR := 0.52 ## H3 原片（gun_jump_air/gun_reload/gun_idle）缩放补偿
const GRAV := 0.72
const GUN_ENABLED := false     ## 枪械总开关（2026-09-02 用户决策：纯棍击，武士零节奏）
const SLIDE_ENABLED := false   ## 滑铲总开关（同上：禁用，Ctrl 不再触发）
const ROLL_ENABLED := true     ## Ctrl 改为翻滚；与旧 slide_* 状态完全分离，不恢复滑铲
const RUN := 5.8               ## 唯一水平移速：奔跑、跳跃惯性、滑铲完全一致（武士零式高速）
const JUMP := -13.2
const SLIDE_SPD := RUN
const BULLET_SPD := 19.0       ## px/帧@60fps
const SLIDE_MAX_T := 0.9       ## 滑铲最大时长，到点自动起身

const GUN_MAG := 8
const RELOAD_TIME := 0.845057  ## 与 11_gun_reload.wav 原始时长逐样对齐；被打断可从断点续
const GUN_RELOAD_FPS_MULT := 5.1667 / RELOAD_TIME  ## 124帧动画压进换弹时长
## H3 原片逐剪辑缩放归一化（以 aim 的角色源高 234px 为基准实测）
const RAW_SCALE := {"gun_idle": 0.495, "gun_reload": 0.493, "gun_jump_air": 0.549,
		"hero_roll": 0.82} ## 翻滚原画人物偏大，六帧统一缩小18%；保留脚底500锚点，不逐帧拉伸。
const STANDING_HURTBOX_SIZE := Vector2(34.0, 82.0)
const ROLL_HURTBOX_SIZE := Vector2(38.0, 34.0)
const HP_MAX := 5
const HURT_INVULN := 0.6       ## 受击无敌时间（秒）
const HURT_KNOCKBACK := 5.0    ## 受击击退 px/帧
const DEATH_INERTIA_STAGE := 1 ## 主角和二段球棒击杀共用同档惯性：向外抛飞、小弧线、一次轻弹。
const DEATH_ANIMATION_DURATION := 0.75 ## 保留原15帧倒地图集，平顺倒下后停在末帧
const TIME_FOCUS_SPEED := 0.55
const TIME_FOCUS_GHOST_INTERVAL := 0.075
const TIME_FOCUS_GHOST_LIFETIME := 0.24
const TIME_FOCUS_TINT := Color(0.52, 0.94, 1.0)
const TIME_FOCUS_GHOST_ALPHA := 0.24

## 双 S 下穿单向台（=）：站在台上 0.28s 内连按两次 S → 0.30s 内单向台不落脚，
## 靠重力穿过台板落到下层（竖井/高台原路可下，playtest round4）。
const DROP_TAP_WINDOW := 0.28  ## 双 S 连击窗口（秒，_input_clock 尺度）
const DROP_THROUGH_TIME := 0.30 ## 下穿期间忽略 = 台的时长（秒）
const DROP_INITIAL_VY := 1.5   ## 下穿起步下落速度（px/帧，立即离台）

## 棒球棍三连击（hero_bat1/2/3）：非瞄准左键挥棍，后段再点接下一击
const BAT_STAGES := ["bat1", "bat2", "bat3"]
## 状态→图集动作：二三段已调换（用户决策 2026-09-02）
const BAT_CLIPS := ["hero_bat1", "hero_bat3", "hero_bat2"]
## 播放倍率：首击 3.4 快起手；动作调换后二段 21 帧用 2.4、三段 8 帧用 1.0 原速
const BAT_FPS_MULTS := [3.4, 2.4, 1.0]
const BAT1_STEP := 1.2 * TS    ## 首击约 38px 前送分摊到前摇，避免起手瞬移后整段站定
const BAT_MOVE_WINDUP := 0.35 ## 前摇允许同向带步，保留挥棒重心而不彻底锁脚
const BAT_MOVE_RECOVERY := 0.78 ## 收招恢复大部分奔跑速度；反向输入在后段可转身离开
const BAT_CANCEL_OPEN := 0.40 ## 真实命中窗口完成后才可接翻滚/冲刺/跳跃
const BAT_TURN_CANCEL_OPEN := 0.60
const BAT_INPUT_BUFFER := 0.10 ## 爆发移动末尾暂存左键，防止落点附近的攻击点按被吞
const IDLE_FPS_MULT := 0.2     ## 持棍待机呼吸放慢到 1/5 速（用户决策：休息帧拉长 5 倍）
const BAT_STEP_GHOST_LIFE := 0.35  ## 首击虚影寿命（短促，读作快冲残影）
const BAT_HIT_AT := 0.30       ## 命中窗口：帧进度越过此值发一次判定盒
const BAT_COMBO_OPEN := 0.50   ## 连招输入窗口（帧进度过半即可接下一击）
const BAT_HITBOX_W := 76.0
const BAT_HITBOX_H := 56.0
const DASH_BAT_FRAME := 12     ## Shift 冲刺轨迹定格 hero_bat3 的伸展帧（棍影冲刺）
const ONION_FRAME_GAP := 2     ## 虚影与主帧的帧距（±1 太贴近，动作糊在一起）
## 洋葱片虚影与 Shift 冲刺同款着色器/配色（彩色剪影，非简单染色）
const ONION_PREV_TINT := Color(0.45, 0.98, 1.00)   ## 上一帧：冲刺青
const ONION_NEXT_TINT := Color(1.00, 0.55, 0.92)   ## 下一帧：冲刺粉
const ONION_PREV_OPACITY := 0.55
const ONION_NEXT_OPACITY := 0.38

## 挥棍斩击弧光（逆向素材 vfx_attack，5 帧 324×324 横条；青色霓虹与液爆同族）
const SLASH_FRAMES := 5
const SLASH_FRAME_W := 324.0
const SLASH_SCALE := 0.42          ## 弧光宽度 ≈ 136px，约 1.4 倍角色高
## 三段统一用 bat2 横挥弧光：同一位置、零倾角（用户决策 2026-09-02）
const SLASH_OFFSET := Vector2(30, -47)   ## 肩线上方（x 随朝向镜像，用户要求再上抬）
const SLASH_DELAY := 0.18     ## 弧光延迟出现：前 18% 帧不出光，挥到点才亮

## 起跳/落地尘土（逆向素材 vfx_jump 5 帧 / vfx_land 2 帧，135×135 横条）
const FX_FRAME_W := 135.0
const FX_SCALE := 0.5
const FX_JUMP_FRAMES := 5
const FX_LAND_FRAMES := 2
const FX_GROUND_RISE := 14.0    ## 尘土中心贴在地面顶面之上

## Shift 闪现保留已认可的位移手感：冷却缩为 1.5 秒，便于长关卡连续交战。
const DASH_DISTANCE := 5.5 * TS
const DASH_DURATION := 0.11
const DASH_SWEEP_STEP := 2.0
const DASH_TRAIL_INTERVAL := 0.018
const DASH_COOLDOWN := 1.5
const DASH_GHOST_LIFETIME := 0.48
const DASH_LIVE_ALPHA := 0.72
const DASH_GHOST_ALPHA := 0.46
## 六帧翻滚降到 18fps，约 0.33s；6 格长位移仍明显慢于闪现。
const ROLL_FRAME_COUNT := 6
const ROLL_FPS_MULT := 0.75
const ROLL_DURATION := float(ROLL_FRAME_COUNT) / (24.0 * ROLL_FPS_MULT)
const ROLL_DISTANCE := 6.0 * TS
const ROLL_COOLDOWN := 0.26
const ROLL_INVULN_TIME := 0.14
const ROLL_TRAIL_INTERVAL := 0.034
const ROLL_GHOST_LIFETIME := 0.36
## 翻滚使用独立生成器产物；运行时按需登记，避免改变既有 hero_atlas 的稳定动作集合。
const ROLL_ACTION := {
	"file": "hero/hero_roll.png", "frames": ROLL_FRAME_COUNT,
	"fw": 512, "fh": 512, "cols": ROLL_FRAME_COUNT, "rows": 1,
	"foot_y": 500.0, "body_cx": 256.0,
}
const DASH_TINTS := [
	Color(1.00, 1.00, 1.00),
	Color(0.45, 0.98, 1.00),
	Color(0.25, 0.65, 1.00),
	Color(0.58, 0.45, 1.00),
	Color(1.00, 0.55, 0.92),
]
const DASH_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint_color : source_color = vec4(1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 pixel = texture(TEXTURE, UV) * COLOR;
	pixel.rgb = mix(pixel.rgb, tint_color.rgb, tint_mix);
	pixel.a *= tint_color.a * opacity;
	COLOR = pixel;
}
"""

## 可读性描边（武士零式角色勾边）：背后叠一张 8 向膨胀的深色剪影。
## 近黑紫描边衬白发角色；texel_step 2.5 ≈ 屏幕 1px（CHAR_SCALE 0.4 下采样）。
## region_min/max 把采样钳在图集帧内，防止吃到相邻帧像素。
const OUTLINE_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(0.09, 0.05, 0.14, 1.0);
uniform float texel_step = 2.5;
uniform vec2 region_min = vec2(0.0);
uniform vec2 region_max = vec2(1.0);
varying vec4 outline_vertex_color;

void vertex() {
	// 描边外扩像素不能再次乘透明纹理Alpha；独立传递节点颜色以保留受伤闪烁。
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
const OUTLINE_TEXEL_STEP := 2.5
## 冷白背晕：把角色从暗墙面上微微托起（很淡，不读作发光体）
const HALO_COLOR := Color(0.75, 0.86, 1.0, 0.12)
const HALO_TEX_SIZE := 64
const HALO_SCALE := 2.3          ## 直径 ≈147px ≈ 1.5× 角色视觉高
## 脚下接触阴影（KZ 式角色落地锚定）：软椭圆，与 grunt 同款做法
const SHADOW_ALPHA := 0.35
const SHADOW_TEX_W := 32
const SHADOW_TEX_H := 12
const SHADOW_SCALE := Vector2(1.1, 1.0)   ## ≈35×12px，略宽于 22px 碰撞体

const CLIP := {
	"gun_idle": {"loop": true},
	"aim": {"mouse": true},
	"run": {"loop": true},
	"slide_start": {"next": "slide_loop"},
	"slide_loop": {"loop": true},
	"slide_end": {"next": "gun_idle"},
	"gun_jump_air": {"loop": true},
	"gun_reload": {},
	"death": {},
	"dash": {},
	"roll": {},
	"bat1": {"next": "gun_idle"},
	"bat2": {"next": "gun_idle"},
	"bat3": {"next": "gun_idle"},
}

var db: AtlasDB
var level: CorridorLevel
var death_obstacles: Array = [] ## 宿主传入关卡门列表；死亡惯性也必须受独立门体阻挡。
var moving_platforms: Array = [] ## 动态货梯只扩展脚底支撑，不改变22×52通行盒与受击框。
var auto_input := true
var debug_hotkeys_enabled := false ## 默认关K测试自杀；force_death仍供真实伤害/测试调用。
var _pause_blocked_inputs: Dictionary = {} ## 菜单里新按住的动作必须松开再用，避免继续按钮投烟/挥棒。
@export var rewind_on_fall := false ## 正式回溯关由宿主开启；旧地图保留掉落立即复位

var vx := 0.0
var vy := 0.0
var face := 1
var on_ground := false
var air_bat_used := false       ## 空中挥棍一次制：离地后只能起手一次，落地重置
var state := "gun_idle"
var frame := 0
var t := 0.0
var aim_deg := 0.0
var aiming := false            ## 右键按住中
var slide_held := false
var pending_end := false
var fire_cd := 0.0
var dead := false
var w := 22.0
var h := 52.0
var spawn := Vector2(8 * TS, 11 * TS)

var hitstop := 0.0
var slide_time := 0.0
var gun_ammo := GUN_MAG
var reloading := false
var reload_t := 0.0            ## 剩余秒数（HUD 显示用）
var reload_elapsed := 0.0      ## 已进行的换弹进度（被打断时保留，可续弹）
var max_hp := HP_MAX           ## 难度只改变生命上限，不改已认可的动作物理
var hp := HP_MAX
var invuln_t := 0.0
var _death_elapsed := 0.0
var _death_motion_applied := 0.0
var _death_direction := 0
var _death_inertia: RefCounted
var _death_ground_y := INF
var _death_ground_valid := false
var _death_inertia_active := false
var _time_focus_active := false
var _time_focus_material: ShaderMaterial
var _time_focus_ghost_accum := 0.0
var _time_focus_last_position := Vector2.ZERO
var carried_smoke := false
var _smoke_cover_active := false
var _smoke_carry_ui: Node2D

var keys: Dictionary = {}
var aim_override: Variant = null

var _prev_keys: Dictionary = {}
var _sprite: Sprite2D
var _outline: Sprite2D            ## 深色描边剪影（画在本体下）
var _outline_mat: ShaderMaterial
var _halo: Sprite2D               ## 冷白背晕（画在描边下）
var _shadow: Sprite2D             ## 脚下接触阴影（画在最底层）
var _dash_trail_root: Node2D
var _dash_cooldown_ui: Node2D
var _dash_shader: Shader
var _dash_material: ShaderMaterial
var _dash_ghosts: Array[Dictionary] = []
var dash_cooldown_t := 0.0
var dash_flash_t := 0.0
var _dash_elapsed := 0.0
var _dash_start_x := 0.0
var _dash_target_x := 0.0
var _dash_dir := 1
var _dash_follow_ground := true
var roll_cooldown_t := 0.0
var roll_invuln_t := 0.0
var _roll_elapsed := 0.0
var _roll_start_x := 0.0
var _roll_target_x := 0.0
var _roll_dir := 1
var _roll_follow_ground := true
var _motion_ghost_accum := 0.0
var bat_hit_done := false      ## 本次挥棍是否已发出命中判定
var bat_queued := false        ## 连招：本击后段是否已点下一击
var _bat_lunge_applied := 0.0   ## 首击已经消费的前送量；撞墙也消费，不能积攒后突然穿出
var _bat_ground_lunge := false
var _bat_input_buffer_t := 0.0
var _onion_prev: Sprite2D
var _onion_next: Sprite2D
var _onion_mat_prev: ShaderMaterial
var _onion_mat_next: ShaderMaterial
var _slash: Sprite2D
var _slash_tex_right: Texture2D
var _slash_tex_left: Texture2D
var _jump_fx: Sprite2D
var _land_fx: Sprite2D
var _fx_jump_tex: Texture2D
var _fx_land_tex: Texture2D
var _jump_fx_t := -1.0            ## >=0 表示起跳尘土播放中（秒）
var _land_fx_t := -1.0
var _input_clock := 0.0        ## 步进累计时钟（秒）：手动 step 的测试也可用
var _s_tap_t := -1.0           ## 上一次 S 按下时刻（<0 = 无待配对点按）
var _drop_t := 0.0             ## 下穿剩余时长（>0 时 = 单向台不落脚）


func _ready() -> void:
	_ensure_roll_action()
	_ensure_visual_nodes()
	position = spawn
	configure_max_health(max_hp)


func _ensure_roll_action() -> void:
	if db != null and not db.actions.has("hero_roll"):
		db.actions["hero_roll"] = ROLL_ACTION.duplicate(true)


## 无头逻辑测试会在 _ready 前手动 step；节点与材质因此按需、幂等创建。
func _ensure_visual_nodes() -> void:
	# 顶层残影容器不继承玩家位移，并排在本体 Sprite 前面绘制。
	if _dash_trail_root == null:
		_dash_trail_root = Node2D.new()
		_dash_trail_root.name = "DashTrail"
		_dash_trail_root.top_level = true
		add_child(_dash_trail_root)

	# 洋葱片虚影（先于本体 Sprite 创建 → 排在本体后面绘制）
	if _onion_prev == null:
		_onion_prev = Sprite2D.new()
		_onion_prev.name = "OnionPrev"
		_onion_prev.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_onion_prev.visible = false
		add_child(_onion_prev)
	if _onion_next == null:
		_onion_next = Sprite2D.new()
		_onion_next.name = "OnionNext"
		_onion_next.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_onion_next.visible = false
		add_child(_onion_next)

	# 可读性层：接触阴影 → 背晕 → 描边 → 本体（先创建的先绘制，压在本体下）
	if _shadow == null:
		_shadow = Sprite2D.new()
		_shadow.name = "ContactShadow"
		_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   ## 软渐变允许线性
		_shadow.texture = _make_shadow_texture()
		_shadow.modulate = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
		_shadow.scale = SHADOW_SCALE
		add_child(_shadow)
	if _halo == null:
		_halo = Sprite2D.new()
		_halo.name = "Halo"
		_halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   ## 软渐变允许线性
		_halo.texture = _make_halo_texture()
		_halo.modulate = HALO_COLOR
		_halo.scale = Vector2.ONE * HALO_SCALE
		add_child(_halo)
	if _outline == null:
		_outline = Sprite2D.new()
		_outline.name = "Outline"
		_outline.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_outline.centered = false
		_outline.region_enabled = true
		var osh := Shader.new()
		osh.code = OUTLINE_SHADER_CODE
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = osh
		_outline_mat.set_shader_parameter("texel_step", OUTLINE_TEXEL_STEP)
		_outline.material = _outline_mat
		add_child(_outline)

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)

	# 斩击弧光：画在本体之上（z 序靠后创建）
	if _slash == null:
		_slash = Sprite2D.new()
		_slash.name = "Slash"
		_slash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_slash.region_enabled = true
		_slash.visible = false
		add_child(_slash)
	if _slash_tex_right == null:
		_slash_tex_right = load("res://assets/vfx/vfx_attack_right.png")
		_slash_tex_left = load("res://assets/vfx/vfx_attack_left.png")

	# 起跳/落地尘土（一次性播放，画在本体之上）
	if _jump_fx == null:
		_jump_fx = Sprite2D.new()
		_jump_fx.name = "JumpFx"
		_jump_fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_jump_fx.region_enabled = true
		_jump_fx.visible = false
		add_child(_jump_fx)
		_land_fx = Sprite2D.new()
		_land_fx.name = "LandFx"
		_land_fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_land_fx.region_enabled = true
		_land_fx.visible = false
		add_child(_land_fx)
	if _fx_jump_tex == null:
		_fx_jump_tex = load("res://assets/vfx/vfx_jump.png")
		_fx_land_tex = load("res://assets/vfx/vfx_land.png")

	if _dash_shader == null:
		_dash_shader = Shader.new()
		_dash_shader.code = DASH_SHADER_CODE
	if _dash_material == null:
		_dash_material = ShaderMaterial.new()
		_dash_material.shader = _dash_shader
	if _time_focus_material == null:
		# 固定参数的独立材质；历史姿势持有引用也不会被下次开关或冲刺改色。
		_time_focus_material = ShaderMaterial.new()
		_time_focus_material.shader = _dash_shader
		_time_focus_material.set_shader_parameter("tint_color", TIME_FOCUS_TINT)
		_time_focus_material.set_shader_parameter("tint_mix", 0.23)
		_time_focus_material.set_shader_parameter("opacity", 1.0)
	if _onion_mat_prev == null:
		_onion_mat_prev = ShaderMaterial.new()
		_onion_mat_prev.shader = _dash_shader
		_onion_mat_prev.set_shader_parameter("tint_color", ONION_PREV_TINT)
		_onion_mat_prev.set_shader_parameter("tint_mix", 0.96)
		_onion_mat_prev.set_shader_parameter("opacity", ONION_PREV_OPACITY)
		_onion_mat_next = ShaderMaterial.new()
		_onion_mat_next.shader = _dash_shader
		_onion_mat_next.set_shader_parameter("tint_color", ONION_NEXT_TINT)
		_onion_mat_next.set_shader_parameter("tint_mix", 0.96)
		_onion_mat_next.set_shader_parameter("opacity", ONION_NEXT_OPACITY)
	if _dash_cooldown_ui == null:
		# 跟随玩家而非顶层残影容器；高于本体绘制且不继承闪现白化材质。
		_dash_cooldown_ui = DASH_COOLDOWN_INDICATOR_SCRIPT.new()
		_dash_cooldown_ui.name = "DashCooldownUI"
		_dash_cooldown_ui.z_index = 40
		add_child(_dash_cooldown_ui)
		_sync_dash_cooldown_ui()
	if _smoke_carry_ui == null:
		_smoke_carry_ui = SMOKE_ICON_SCRIPT.new()
		_smoke_carry_ui.name = "SmokeCarryUI"
		_smoke_carry_ui.z_index = 40
		add_child(_smoke_carry_ui)
		_sync_smoke_carry_ui()


func _physics_process(dt: float) -> void:
	if not auto_input or db == null:
		return
	_collect_input()
	step(dt)


func _collect_input() -> void:
	keys.clear()
	for k in [KEY_A, KEY_D, KEY_W, KEY_SPACE, KEY_S, KEY_SHIFT, KEY_CTRL, KEY_K, KEY_R]:
		if Input.is_key_pressed(k):
			keys[k] = true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		keys[MOUSE_BUTTON_LEFT] = true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		keys[MOUSE_BUTTON_RIGHT] = true
	if not debug_hotkeys_enabled:
		keys.erase(KEY_K)
	for code in _pause_blocked_inputs.keys():
		if not keys.has(code):
			_pause_blocked_inputs.erase(code)
		else:
			keys.erase(code)


func pause_input_snapshot() -> Dictionary:
	if auto_input:
		_collect_input()
	return keys.duplicate()


func sync_input_after_pause(before: Dictionary) -> void:
	if auto_input:
		_collect_input()
	# 连续方向可直接继续；菜单期间新按的跳/滚/冲/瞄准/鼠标动作要释放，已有动作时序不清空。
	for code in [KEY_W, KEY_SPACE, KEY_S, KEY_SHIFT, KEY_CTRL, KEY_R, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if keys.has(code) and not before.has(code):
			_pause_blocked_inputs[code] = true
	for code in _pause_blocked_inputs:
		keys.erase(code)
	_prev_keys = keys.duplicate() # 不能clear，否则菜单确认键会变成新攻击边缘。


func time_focus_input_held() -> bool:
	if not auto_input:
		return keys.has(MOUSE_BUTTON_RIGHT)
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _pause_blocked_inputs.has(MOUSE_BUTTON_RIGHT):
		if not held:
			_pause_blocked_inputs.erase(MOUSE_BUTTON_RIGHT)
		return false
	return held


func _aim_point() -> Vector2:
	if aim_override != null:
		return aim_override as Vector2
	if get_viewport() == null:
		return position + Vector2(300.0 * face, -50.0)
	return get_global_mouse_position()


func set_state(s: String) -> void:
	if state != s:
		state = s
		frame = 0
		t = 0.0


func sliding() -> bool:
	return state == "slide_start" or state == "slide_loop"


func batting() -> bool:
	return state in BAT_STAGES


func reset_to_spawn() -> void:
	set_time_focus(false)
	set_carried_smoke(false)
	set_smoke_cover(false)
	position = spawn
	vx = 0.0
	vy = 0.0
	dead = false
	slide_held = false
	pending_end = false
	hitstop = 0.0
	bat_hit_done = false
	bat_queued = false
	_bat_lunge_applied = 0.0
	_bat_ground_lunge = false
	_bat_input_buffer_t = 0.0
	air_bat_used = false
	gun_ammo = GUN_MAG
	reloading = false
	reload_elapsed = 0.0
	hp = max_hp
	invuln_t = 0.0
	_death_elapsed = 0.0
	_death_motion_applied = 0.0
	_death_direction = 0
	_death_inertia = null
	_death_ground_y = INF
	_death_ground_valid = false
	_death_inertia_active = false
	_s_tap_t = -1.0
	_drop_t = 0.0
	_clear_dash_visual()
	set_state("gun_idle")


## 切换难度/重开时由宿主调用；改变生命值不触发 hurt/died，也不代替复活流程。
func configure_max_health(value: int, refill := true) -> void:
	max_hp = maxi(1, value)
	hp = max_hp if refill else clampi(hp, 0, max_hp)


func death_animation_finished() -> bool:
	return dead and _death_elapsed >= DEATH_ANIMATION_DURATION


## 时停只降低主角模拟速度；能量由宿主计时，冷却在step里保留真实秒数。
func set_time_focus(active: bool) -> void:
	var wanted := active and not dead
	if wanted == _time_focus_active:
		return
	_time_focus_active = wanted
	_time_focus_ghost_accum = 0.0
	_time_focus_last_position = position
	_ensure_visual_nodes()
	if not dashing():
		_sprite.material = _time_focus_material if wanted else null
	_sync_motion_trail_z()


func time_focus_active() -> bool:
	return _time_focus_active


## 携带槽只存一颗；不会恢复旧枪械/换弹，也不改变已有动作状态机。
func set_carried_smoke(active: bool) -> void:
	carried_smoke = active and not dead
	_sync_smoke_carry_ui()


## 只有持有烟雾弹且按住R才处于投掷瞄准；不沿用旧枪械aiming状态，也不锁住移动/跳跃。
func smoke_aiming() -> bool:
	return carried_smoke and not dead and keys.has(KEY_R)


func _sync_smoke_carry_ui() -> void:
	if _smoke_carry_ui == null:
		return
	# 比SHIFT冷却条再高28px，头顶清楚亮出罐体，两个提示不会互相盖住。
	_smoke_carry_ui.position = Vector2(0.0, -visual_height() - 42.0).round()
	_smoke_carry_ui.visible = carried_smoke and not dead
	_smoke_carry_ui.queue_redraw()


## 这里只提供烟内外观反馈；枪弹免伤必须由宿主在敌弹命中处判定，近战/陷阱照常伤人。
func set_smoke_cover(active: bool) -> void:
	_smoke_cover_active = active and not dead
	if _sprite != null:
		# 烟内改为不透明的深色剪影，不把人物淡成难辨的透明影；浅青边线保留主角位置。
		# self_modulate不覆盖时停/冲刺材质；受伤闪烁仍由modulate.a单独驱动。
		_sprite.self_modulate = Color(0.08, 0.13, 0.16, 1.0) if _smoke_cover_active else Color.WHITE
	if _outline_mat != null:
		_outline_mat.set_shader_parameter("outline_color",
				Color(0.59, 0.91, 0.92, 0.92) if _smoke_cover_active else Color(0.09, 0.05, 0.14, 1.0))


func smoke_cover_active() -> bool:
	return _smoke_cover_active


func _sync_motion_trail_z() -> void:
	if _dash_trail_root != null:
		# top_level残影不依赖父级绘制顺序；显式跟随宿主抬高后的主角，仍先于本体画。
		_dash_trail_root.z_as_relative = false
		_dash_trail_root.z_index = z_index


func _update_time_focus_trail(real_dt: float) -> void:
	if real_dt <= 0.0 or not _time_focus_active or dead or _sprite.texture == null:
		return
	var delta_position := position - _time_focus_last_position
	_time_focus_last_position = position
	if delta_position.length_squared() < 0.0001:
		_time_focus_ghost_accum = 0.0
		return   ## 静止时不反复叠亮同一个轮廓
	var emit_at := TIME_FOCUS_GHOST_INTERVAL - _time_focus_ghost_accum
	while emit_at <= real_dt + 0.000001:
		var ghost_transform := _sprite.global_transform
		ghost_transform.origin -= delta_position * (1.0 - clampf(emit_at / real_dt, 0.0, 1.0))
		ghost_transform.origin = ghost_transform.origin.round()
		_spawn_dash_afterimage(TIME_FOCUS_TINT, ghost_transform, TIME_FOCUS_GHOST_LIFETIME)
		var ghost_data: Dictionary = _dash_ghosts.back()
		ghost_data["base_alpha"] = TIME_FOCUS_GHOST_ALPHA
		ghost_data["age"] = maxf(0.0, real_dt - emit_at)
		ghost_data["sprite"].modulate.a = TIME_FOCUS_GHOST_ALPHA
		emit_at += TIME_FOCUS_GHOST_INTERVAL
	_time_focus_ghost_accum = fmod(_time_focus_ghost_accum + real_dt, TIME_FOCUS_GHOST_INTERVAL)


## 死亡由同款世界空间惯性求解器独占积分，不能再叠加活体重力或插值位移。
func _advance_death_motion(dt: float) -> void:
	_death_elapsed += dt
	if _death_inertia == null:
		return
	var previous_x := position.x
	var first_landing: bool = _death_inertia.advance(dt, level, w * 0.5, h, death_obstacles)
	position = _death_inertia.position
	vx = _death_inertia.velocity.x / 60.0
	vy = _death_inertia.velocity.y / 60.0
	on_ground = _death_inertia.grounded
	_death_inertia_active = _death_inertia.active
	_death_ground_y = _death_inertia.ground_y
	_death_ground_valid = _death_inertia.ground_valid
	_death_motion_applied += absf(position.x - previous_x)
	if first_landing:
		death_landed.emit(_death_inertia.landing_position, 1.0, float(_death_direction))


## 只推进死亡动作和既存短特效；不处理活体按键、台阶吸附或第二次重力。
func _step_dead(dt: float) -> void:
	_advance_death_motion(dt)
	if level != null and position.y > level.world_h + 200.0 and not rewind_on_fall:
		# 非回溯旧场景仍保留越界复位；正式关只等待宿主短倒带，不跳过死亡现场。
		reset_to_spawn()
		fell_out.emit()
	_advance_frame(dt)
	_prev_keys = keys.duplicate()
	_sync_sprite()
	_sync_dash_cooldown_ui()
	_update_dash_visual(dt)
	_advance_step_fx(dt)


## 回溯只记录呈现数据：不克隆纹理，不恢复生命/CD/按键，不重放任何战斗信号。
func capture_timeline_pose() -> Dictionary:
	_ensure_visual_nodes()
	var visuals := {}
	for entry in _timeline_visual_nodes():
		var sprite: Sprite2D = entry[1]
		visuals[entry[0]] = {
			"texture": sprite.texture, "region_enabled": sprite.region_enabled,
			"region_rect": sprite.region_rect, "centered": sprite.centered,
			"offset": sprite.offset, "flip_h": sprite.flip_h, "flip_v": sprite.flip_v,
			"transform": sprite.transform, "modulate": sprite.modulate,
			"self_modulate": sprite.self_modulate, "visible": sprite.visible,
			"material": sprite.material,
		}
	return {"position": position, "face": face, "state": state, "frame": frame,
		"t": t, "dead": dead, "time_focus": _time_focus_active, "visuals": visuals,
		"ground_y": _death_ground_y if dead else position.y,
		"ground_valid": _death_ground_valid if dead else true}


## 宿主回放期间必须暂停 step；这里只摆回姿势，结束后由宿主统一 reset_to_spawn。
func apply_timeline_pose(pose: Dictionary) -> void:
	if pose.is_empty():
		return
	_ensure_visual_nodes()
	position = pose.get("position", position)
	face = int(pose.get("face", face))
	state = str(pose.get("state", state))
	frame = int(pose.get("frame", frame))
	t = float(pose.get("t", t))
	var visuals: Dictionary = pose.get("visuals", {})
	for entry in _timeline_visual_nodes():
		if not visuals.has(entry[0]):
			continue
		var sprite: Sprite2D = entry[1]
		var data: Dictionary = visuals[entry[0]]
		for property: String in data:
			sprite.set(property, data[property])
		# 宿主可以插值世界位置，但显示仍沿用正常游戏的整数像素锚点。
		sprite.global_position = sprite.global_position.round()
	# 世界脚底高度可插值，但影子必须留在历史地面；不重放接地信号或物理。
	if pose.has("ground_y"):
		_shadow.visible = bool(pose.get("ground_valid", false))
		if _shadow.visible:
			_shadow.global_position = Vector2(position.x, float(pose["ground_y"]) - 1.0).round()
	# 描边材质被所有历史姿势引用，帧范围需按本次恢复的本体重新校准。
	if _sprite.texture != null:
		var texture_size := Vector2(_sprite.texture.get_size())
		_outline_mat.set_shader_parameter("region_min", _sprite.region_rect.position / texture_size)
		_outline_mat.set_shader_parameter("region_max", _sprite.region_rect.end / texture_size)
	_dash_trail_root.visible = false
	_dash_cooldown_ui.visible = false
	if _smoke_carry_ui != null:
		_smoke_carry_ui.visible = false ## 回放不补发投掷或显示已经消耗的携带物。


func _timeline_visual_nodes() -> Array:
	return [["sprite", _sprite], ["outline", _outline], ["halo", _halo], ["shadow", _shadow],
		["onion_prev", _onion_prev], ["onion_next", _onion_next], ["slash", _slash],
		["jump_fx", _jump_fx], ["land_fx", _land_fx]]


## 当前状态实际使用的图集动作名
## 站立未瞄准时 aim 态播 gun_idle 呼吸；右键瞄准时才是 LUT 的 aim
func current_clip() -> String:
	if batting():
		return BAT_CLIPS[_bat_stage()]
	match state:
		"dash":
			return "hero_bat3"
		"roll":
			return "hero_roll"
		"gun_idle", "aim", "gun_reload":
			return "hero_idle"    ## 持棍站立（枪械禁用后的默认姿态）
		"run":
			return "hero_run"
		"gun_jump_air":
			return "hero_jump"
		"death":
			return "hero_death"
	return state   ## slide_* 仅在 SLIDE_ENABLED 重开时可达


func start_reload() -> void:
	if not GUN_ENABLED:
		return
	if reloading or gun_ammo >= GUN_MAG or dead:
		return
	if not on_ground or moving() or aiming:
		notice.emit("站稳不动才能换弹")
		return
	reloading = true
	set_state("gun_reload")
	# 断点续弹：上次被打断的进度保留在 reload_elapsed，动画从对应帧继续
	t = reload_elapsed * GUN_RELOAD_FPS_MULT
	reload_t = RELOAD_TIME - reload_elapsed
	reload_started.emit()

func _finish_reload_interruption() -> void:
	if reloading:
		reloading = false
		reload_interrupted.emit()
		notice.emit("换弹被打断")


func moving() -> bool:
	return keys.has(KEY_A) or keys.has(KEY_D)


## 闪现现在有极短持续时间；返回值同时供输入锁与本体白化读取。
func dashing() -> bool:
	return state == "dash"


func rolling() -> bool:
	return state == "roll"

## 测试辅助：直接把玩家放回一段干净的移动状态。
func _test_clean_motion_state() -> void:
	position.x = 400.0
	position.y = 19 * 32 - 0.1
	vx = 0.0
	vy = 0.0
	on_ground = false
	slide_held = false
	pending_end = false
	reloading = false
	reload_elapsed = 0.0
	state = "gun_idle"
	_dash_elapsed = 0.0
	_dash_follow_ground = true
	_roll_elapsed = 0.0
	_roll_follow_ground = true
	_motion_ghost_accum = 0.0
	_bat_input_buffer_t = 0.0
	_bat_lunge_applied = 0.0
	_bat_ground_lunge = false


## 给无头测试/调试面板读取，避免依赖内部节点结构。
func dash_afterimage_count() -> int:
	return _dash_ghosts.size()


## 测试/调试读取：UI 是玩家普通子节点，会跟随角色且只在冲刺冷却中出现。
func dash_cooldown_ui_visible() -> bool:
	return _dash_cooldown_ui != null and _dash_cooldown_ui.visible


func _sync_dash_cooldown_ui() -> void:
	if _dash_cooldown_ui == null:
		return
	_dash_cooldown_ui.position = Vector2(0.0, -visual_height() - 12.0).round()
	_dash_cooldown_ui.call("set_cooldown", dash_cooldown_t, DASH_COOLDOWN, not dead)


## 受击：HP-1 + 击退 + 短暂无敌；归零进死亡
func take_damage(dmg: int, from_x: float) -> void:
	if dead or dashing() or invuln_t > 0.0 or roll_invuln_t > 0.0:
		return
	hp = maxi(0, hp - dmg)
	invuln_t = HURT_INVULN
	vx = HURT_KNOCKBACK * (1.0 if position.x > from_x else -1.0)
	hurt.emit()
	if hp <= 0:
		force_death(from_x)


## 跌落/调试死亡也走同一路径；只跳过无敌检查，不重复发出死亡事件。
func force_death(from_x: float) -> void:
	if dead:
		return
	set_time_focus(false)
	set_carried_smoke(false)
	set_smoke_cover(false)
	hp = 0
	dead = true
	_death_elapsed = 0.0
	_death_motion_applied = 0.0
	_death_direction = 1 if position.x > from_x else -1
	_death_ground_y = position.y if on_ground else INF
	_death_ground_valid = on_ground
	_death_inertia = DEATH_INERTIA_SCRIPT.new()
	_death_inertia.launch(position, float(_death_direction), DEATH_INERTIA_STAGE)
	_death_inertia_active = true
	on_ground = false
	face = -_death_direction   ## 面向伤害来源，倒地朝相反方向滑出
	invuln_t = 0.0             ## 死亡不继续无敌闪烁，保证倒地姿势可读
	_bat_input_buffer_t = 0.0
	bat_queued = false
	reloading = false
	set_state("death")
	died.emit()


# ---------- 主步进 ----------

func step(dt: float) -> void:
	if is_inside_tree() and get_tree().paused:
		return
	if dead and dt > 1.0 / 60.0 + 0.000001:
		# 低帧率尸体仍用小物理步推进重力/落地，避免一次长dt跨过薄地板。
		var remaining := dt
		while remaining > 0.000001:
			var substep := minf(remaining, 1.0 / 60.0)
			step(substep)
			remaining -= substep
		return
	var real_dt := dt
	if _time_focus_active and not dead:
		dt *= TIME_FOCUS_SPEED
	_ensure_roll_action()
	_ensure_visual_nodes()
	_input_clock += dt
	_bat_input_buffer_t = maxf(0.0, _bat_input_buffer_t - dt)
	_drop_t = maxf(0.0, _drop_t - dt)
	fire_cd = maxf(0.0, fire_cd - dt)
	invuln_t = maxf(0.0, invuln_t - dt)
	dash_cooldown_t = maxf(0.0, dash_cooldown_t - real_dt)
	roll_cooldown_t = maxf(0.0, roll_cooldown_t - real_dt)
	roll_invuln_t = maxf(0.0, roll_invuln_t - dt)
	if reloading:
		reload_elapsed += dt
		reload_t = maxf(0.0, RELOAD_TIME - reload_elapsed)
		if reload_elapsed >= RELOAD_TIME:
			reloading = false
			reload_elapsed = 0.0
			reload_t = 0.0
			gun_ammo = GUN_MAG
			set_state("aim" if aiming else "gun_idle")
	else:
		reload_t = maxf(0.0, RELOAD_TIME - reload_elapsed)
	var s: float = dt * 60.0

	if not dead:
		# 宿主可先carry_rider；平台按advance幂等去重，此处也可供独立step测试安全承载。
		for platform in moving_platforms:
			if is_instance_valid(platform):
				platform.carry_rider(self)
	_update_aim()
	_handle_edges()
	if dead:
		_step_dead(real_dt) ## 即使时停中本帧死亡，也按真实秒播倒地，不重复慢放。
		return

	# 换弹打断：移动/瞄准/跳跃立即中断，弹药不补
	if reloading and (moving() or aiming or not on_ground):
		_finish_reload_interruption()
		set_state("aim" if aiming else ("run" if moving() else "gun_idle"))

	# 水平速度：挥棒允许同向带步；伤害停顿只短暂压住挥棒位移，不吞输入。
	if reloading:
		vx = 0.0
	elif dashing() or rolling():
		vx = 0.0   ## 两种爆发移动由碰撞安全的专用插值推进，不走普通奔跑积分
	elif batting():
		var wanted := _movement_direction()
		var move_ratio := BAT_MOVE_RECOVERY if _bat_progress() >= BAT_COMBO_OPEN \
				else BAT_MOVE_WINDUP
		vx = RUN * face * move_ratio if wanted == face and hitstop <= 0.0 else 0.0
	elif sliding():
		vx = SLIDE_SPD * face
	elif aiming:
		vx = 0.0   ## 瞄准时必须静止
	else:
		var has_input: bool = keys.has(KEY_A) or keys.has(KEY_D)
		if not on_ground and not has_input:
			pass   ## 空中无输入保持惯性（滑铲跳/起跳 momentum 不丢）
		else:
			vx = 0.0
			if keys.has(KEY_A):
				vx -= RUN
			if keys.has(KEY_D):
				vx += RUN

	# 逐轴碰撞（先 x 后 y）；闪现/翻滚按持续时间推进，并沿途按时生成虚影。
	var horizontal_from_x := position.x
	var horizontal_started_grounded := on_ground
	var dash_was_active := dashing()
	if dash_was_active or rolling():
		_advance_burst_motion(dt)
	elif batting():
		_advance_bat_motion(dt)
	else:
		position.x += vx * s
	var half_w := w / 2.0
	if vx != 0.0 and not dashing() and not rolling() and not batting():
		var side: float = position.x + (half_w if vx > 0.0 else -half_w)
		for oy in [position.y - h + 6.0, position.y - h / 2.0, position.y - 3.0]:
			if level.solid_at(side, oy) and not level.is_platform(side, oy):
				var col := floori(side / TS)
				position.x = col * TS - half_w - 0.1 if vx > 0.0 else (col + 1) * TS + half_w + 0.1
				vx = 0.0
				break
	# 低空侧入时未必已有on_ground；楼梯不在实心网格里，必须另查踏面侧缘。
	# 地面步行可按原16px预算抬阶，下降中的空中步行停在侧缘，不能先钻入再靠跳跃脱困。
	if not dead and not dashing() and not rolling() and not batting() and vy >= 0.0 \
			and not is_equal_approx(position.x, horizontal_from_x):
		var walk_origin := Vector2(horizontal_from_x, position.y)
		if _stair_side_blocks(walk_origin, position):
			var walk_dir := 1 if position.x > horizontal_from_x else -1
			position = _sweep_burst_path(walk_origin, walk_dir,
					absf(position.x - horizontal_from_x), horizontal_started_grounded)
	# 普通走路在跨入下一踏板时最多抬/降 16px；跳跃已经把 on_ground 清掉，不会被吸回楼梯。
	if horizontal_started_grounded and on_ground and vy >= 0.0 \
			and not dashing() and not rolling() and not batting() \
			and not is_equal_approx(position.x, horizontal_from_x):
		_snap_walk_to_stair(horizontal_from_x)

	var was_air := not on_ground
	if dash_was_active:
		# 冲刺期间冻结竖直积分：空中保持高度，地面则由 2px 路径主动贴阶。
		if _dash_follow_ground:
			vy = 0.0
			on_ground = true
		else:
			on_ground = false
	else:
		var fall_from_y := position.y
		vy += GRAV * s
		position.y += vy * s
		on_ground = false
		if vy >= 0.0:
			# 楼梯是独立单向高度场：只在脚底从上往下跨过踏面时接住，不封闭楼梯下方。
			var stair_landing := INF
			for ox in [position.x - half_w + 3.0, position.x, position.x + half_w - 3.0]:
				stair_landing = minf(stair_landing,
						level.stair_surface_crossed(ox, fall_from_y, position.y))
			# 与楼梯、网格地面择先接住：不能先落到更低的电梯，再穿过上方静态楼板。
			var moving_landing := _moving_platform_surface_crossed(fall_from_y, position.y)
			if moving_landing < INF:
				stair_landing = minf(stair_landing, moving_landing)
				for ox in [position.x - half_w + 3.0, position.x, position.x + half_w - 3.0]:
					if level.solid_at(ox, position.y) \
							and not (_drop_t > 0.0 and level.is_platform(ox, position.y)):
						stair_landing = minf(stair_landing, floorf(position.y / TS) * TS)
			if stair_landing < INF and _body_clear_at(position.x, stair_landing - 0.1):
				position.y = stair_landing - 0.1
				vy = 0.0
				on_ground = true
			else:
				for ox in [position.x - half_w + 3.0, position.x, position.x + half_w - 3.0]:
					# 下穿窗口内 = 单向台不落脚（# 实心/W 外墙照常接住）
					if level.solid_at(ox, position.y) \
							and not (_drop_t > 0.0 and level.is_platform(ox, position.y)):
						position.y = floori(position.y / TS) * TS - 0.1
						vy = 0.0
						on_ground = true
						break
		else:
			for ox in [position.x - half_w + 3.0, position.x, position.x + half_w - 3.0]:
				var hy: float = position.y - h
				if level.solid_at(ox, hy) and not level.is_platform(ox, hy):
					position.y = (floori(hy / TS) + 1) * TS + h
					vy = 0.0
					break
		if rolling():
			# 空中翻滚落地后可继续贴阶；滚出平台则下一帧保持空中下落。
			_roll_follow_ground = on_ground

	if was_air and on_ground and not dead:
		air_bat_used = false   ## 落地重置空中挥棍次数
		_play_land_fx()
	position.x = clampf(position.x, 20.0, level.world_w - 20.0)
	if position.y > level.world_h + 200.0:
		if rewind_on_fall:
			# 宿主用最近有效姿势回溯；保持死亡现场，不抢先传送或重复触发事件。
			force_death(position.x + face)
		else:
			reset_to_spawn()
			fell_out.emit()

	# 状态机
	if sliding():
		slide_time += dt
		if state == "slide_loop" and slide_time >= SLIDE_MAX_T:
			slide_held = false
			set_state("slide_end")
	_update_state(dt)

	# 帧推进
	if hitstop > 0.0 and not dead:
		hitstop -= dt
	else:
		_advance_frame(dt)
	_consume_bat_input_buffer()

	_prev_keys = keys.duplicate()
	_sync_sprite()
	_sync_dash_cooldown_ui()
	_update_dash_visual(real_dt)
	_update_time_focus_trail(real_dt)
	_advance_step_fx(dt)


func _update_state(_dt: float) -> void:
	if dead:
		return
	match state:
		"dash", "roll":
			pass   ## 位移和收尾由 _advance_burst_motion / _advance_frame 驱动
		"gun_jump_air":
			if on_ground:
				set_state("run" if (absf(vx) > 0.1 or moving()) else "gun_idle")
		"slide_start", "slide_loop":
			# 滑铲状态由 _rel_slide（松开 Ctrl）与 SLIDE_MAX_T 时长逻辑接管，
			# 默认分支不得插手；只有滑出平台边缘悬空时才转跳跃空中态。
			if not on_ground:
				slide_held = false
				pending_end = false
				set_state("gun_jump_air")
		"slide_end":
			if moving():
				set_state("run")
		"gun_reload":
			pass   ## 由 reloading 或外部逻辑决定退出，状态机本身不会提前打回站立
		"bat1", "bat2", "bat3":
			pass   ## 挥棍播完由 _advance_frame 收尾（next 或连招），状态机不插手
		_:
			if not on_ground:
				set_state("gun_jump_air")
			elif aiming:
				set_state("aim")
			elif absf(vx) > 0.1:
				set_state("run")
			else:
				set_state("gun_idle")


func _advance_frame(dt: float) -> void:
	if dead and state == "death":
		# 死亡计时独立于挥棒hitstop；尸体移动时动画仍连续，末帧停驻等待宿主回溯。
		t = _death_elapsed
		var count := int(db.actions["hero_death"]["frames"])
		frame = mini(count - 1, floori(clampf(t / DEATH_ANIMATION_DURATION, 0.0, 1.0) * count))
		return
	var clip_name := current_clip()
	var cfg: Dictionary = CLIP[state]
	var act: Dictionary = db.actions[clip_name]
	if dashing():
		frame = DASH_BAT_FRAME   ## 闪现全程定格为伸展棍影，不混入奔跑帧
		return
	# LUT 定帧只在瞄准态；gun_idle/其他按时间走
	if cfg.get("mouse", false) and aiming:
		frame = int(db.lut_entries[db.lut_index(aim_deg)]["f"])
		return

	var fps_mult := 1.0
	if state == "gun_reload":
		fps_mult = GUN_RELOAD_FPS_MULT
	elif batting():
		fps_mult = BAT_FPS_MULTS[_bat_stage()]
	elif rolling():
		fps_mult = ROLL_FPS_MULT
	elif clip_name == "hero_idle":
		fps_mult = IDLE_FPS_MULT
	t += dt * fps_mult
	var fi := int(floor(t * db.fps))
	if fi >= int(act["frames"]):
		if cfg.get("loop", false):
			t -= float(act["frames"]) / db.fps   ## 回绕一个循环时长
			frame = 0
		else:
			frame = int(act["frames"]) - 1
			if state == "roll":
				_finish_roll()
			elif state == "slide_start":
				if pending_end:
					pending_end = false
					set_state("slide_end")
				else:
					set_state("slide_loop")
			elif cfg.has("next"):
				if batting() and bat_queued:
					_start_bat(_bat_stage() + 1)
				else:
					set_state(str(cfg["next"]))
	else:
		frame = fi

	# 挥棍命中窗口：帧进度越过阈值时发一次判定盒
	if batting() and not bat_hit_done and _bat_progress() >= BAT_HIT_AT:
		bat_hit_done = true
		bat_swung.emit(_bat_hitbox(), _bat_stage())


func _handle_edges() -> void:
	var just := func(k: int) -> bool:
		return keys.has(k) and not _prev_keys.has(k)
	if dead:
		_bat_input_buffer_t = 0.0
		bat_queued = false
		return
	var throw_consumed: bool = smoke_aiming() and just.call(MOUSE_BUTTON_LEFT)
	if throw_consumed:
		# 确认投掷优先消费这一记左键；信号可能立即扣掉背包，故必须预先锁定本帧消费结果。
		# 清理尚未执行的棍击输入，不在同帧补挥或排队；已起手动作/位移不强制中断。
		_bat_input_buffer_t = 0.0
		bat_queued = false
		smoke_throw_requested.emit(_aim_point())
	if dashing() or rolling():
		if just.call(MOUSE_BUTTON_LEFT) and not throw_consumed:
			_bat_input_buffer_t = BAT_INPUT_BUFFER
	if dashing():
		return
	if rolling():
		# 翻滚仍只由 Shift 提前取消；左键只暂存到翻滚自然结束，不提前跳过动作。
		if just.call(KEY_SHIFT):
			_try_dash()
		return
	if batting() and _bat_progress() >= BAT_TURN_CANCEL_OPEN \
			and _movement_direction() == -face and hitstop <= 0.0:
		# 收招后段按反向键即可转身走开；前摇不翻转整张攻击图，也不出现倒滑挥棒。
		_cancel_bat()
		face = _movement_direction()
		set_state("run" if on_ground else "gun_jump_air")

	if just.call(MOUSE_BUTTON_LEFT) and not reloading and not throw_consumed:
		if GUN_ENABLED and aiming:
			var b := try_shoot()
			if not b.is_empty():
				fired.emit(b)
		elif batting():
			# 连招全程缓冲：挥棍中任何时刻点左键都排队，播完自动接下一击（狂点可三连）
			# 空中攻击为一次制：离地时不排队续段
			if _bat_stage() < BAT_STAGES.size() - 1 and on_ground:
				bat_queued = true
		else:
			_try_bat()
	if reloading:
		var jump_pressed := (keys.has(KEY_W) and not _prev_keys.has(KEY_W)) \
				or (keys.has(KEY_SPACE) and not _prev_keys.has(KEY_SPACE))
		if jump_pressed and (sliding() or on_ground):
			_finish_reload_interruption()
			vy = JUMP          ## 与普通跳跃同速，不能换状态不跳起来
			on_ground = false
			set_state("gun_jump_air")
			return

	var w_pressed := (keys.has(KEY_W) and not _prev_keys.has(KEY_W)) \
			or (keys.has(KEY_SPACE) and not _prev_keys.has(KEY_SPACE))
	if just.call(KEY_SHIFT):
		_try_dash()
		if dashing():
			return
	if w_pressed and (sliding() or on_ground) and (not batting() or _can_cancel_bat()):
		if batting():
			_cancel_bat()
		# 滑铲中可接跳跃：起跳速度与奔跑速度一致
		if sliding():
			slide_held = false
			pending_end = false
			vx = RUN * face
		vy = JUMP
		on_ground = false
		set_state("gun_jump_air")
		_play_jump_fx()
	if debug_hotkeys_enabled and just.call(KEY_K):
		force_death(position.x + face)

	# 双 S 下穿单向台：0.28s 窗口内第二次按下 S 才触发；单按只记录时刻
	if just.call(KEY_S):
		if _s_tap_t >= 0.0 and _input_clock - _s_tap_t <= DROP_TAP_WINDOW:
			_s_tap_t = -1.0
			_try_drop_through()
		else:
			_s_tap_t = _input_clock

	if ROLL_ENABLED and just.call(KEY_CTRL):
		_try_roll()
	elif SLIDE_ENABLED:
		var ctrl_now: bool = keys.has(KEY_CTRL)
		var ctrl_prev: bool = _prev_keys.has(KEY_CTRL)
		if ctrl_now and not ctrl_prev:
			_try_slide()
		if ctrl_prev and not ctrl_now:
			_rel_slide()


## Shift 闪现：在 0.11s 内沿地面/楼梯安全跨越，途中逐个留下定时消散虚影。
func _try_dash() -> void:
	if dash_cooldown_t > 0.0 or dead or aiming or reloading \
			or sliding() or dashing() or (batting() and not _can_cancel_bat()):
		return
	var canceling_roll := rolling()
	var follow_ground := on_ground
	var dir := face
	if keys.has(KEY_A) and not keys.has(KEY_D):
		dir = -1
	elif keys.has(KEY_D) and not keys.has(KEY_A):
		dir = 1
	var to_x := _dash_end_x(dir, follow_ground)
	var delta_x := to_x - position.x
	if absf(delta_x) < DASH_SWEEP_STEP:
		return
	if batting():
		_cancel_bat()
	if canceling_roll:
		# 只有确认前方可冲刺后才结束翻滚，避免撞墙按 Shift 反而丢失原动作。
		_roll_elapsed = ROLL_DURATION
		roll_invuln_t = 0.0
	face = dir
	_dash_dir = dir
	_dash_start_x = position.x
	_dash_target_x = to_x
	_dash_elapsed = 0.0
	_dash_follow_ground = follow_ground
	_motion_ghost_accum = 0.0
	set_state("dash")
	# 起点先留一张完整棍影，后续虚影随实际移动时刻依次生成。
	_apply_sprite("hero_bat3", DASH_BAT_FRAME)
	_spawn_dash_afterimage(_dash_color_at(0.0), _sprite.global_transform,
			DASH_GHOST_LIFETIME)
	dash_cooldown_t = DASH_COOLDOWN
	dash_flash_t = DASH_DURATION
	dashed.emit()


func _dash_end_x(dir: int, follow_ground: bool) -> float:
	return _sweep_burst_path(position, dir, DASH_DISTANCE, follow_ground).x


## Ctrl 翻滚：六帧长位移、短暂无敌；地面贴阶、空中随重力下落。
func _try_roll() -> void:
	if not ROLL_ENABLED or roll_cooldown_t > 0.0 or dead \
			or aiming or reloading or sliding() or dashing() or rolling() \
			or (batting() and not _can_cancel_bat()):
		return
	var dir := face
	if keys.has(KEY_A) and not keys.has(KEY_D):
		dir = -1
	elif keys.has(KEY_D) and not keys.has(KEY_A):
		dir = 1
	var follow_ground := on_ground
	var to_x := _sweep_burst_path(position, dir, ROLL_DISTANCE, follow_ground).x
	if absf(to_x - position.x) < DASH_SWEEP_STEP:
		return
	if batting():
		_cancel_bat()
	face = dir
	_roll_dir = dir
	_roll_start_x = position.x
	_roll_target_x = to_x
	_roll_elapsed = 0.0
	_roll_follow_ground = follow_ground
	_motion_ghost_accum = 0.0
	roll_cooldown_t = ROLL_COOLDOWN
	roll_invuln_t = ROLL_INVULN_TIME
	set_state("roll")
	_apply_sprite("hero_roll", 0)
	_spawn_dash_afterimage(_dash_color_at(0.0), _sprite.global_transform,
			ROLL_GHOST_LIFETIME)


## 闪现和翻滚共用的持续位移；每帧仍按 2px 扫描，才能稳定贴合 16px 楼梯。
func _advance_burst_motion(dt: float) -> void:
	var start_transform := _sprite.global_transform
	if dashing():
		var old_progress := clampf(_dash_elapsed / DASH_DURATION, 0.0, 1.0)
		_dash_elapsed = minf(_dash_elapsed + dt, DASH_DURATION)
		var new_progress := clampf(_dash_elapsed / DASH_DURATION, 0.0, 1.0)
		var desired_x := lerpf(_dash_start_x, _dash_target_x, new_progress)
		var from_position := position
		position = _sweep_burst_path(position, _dash_dir,
				absf(desired_x - position.x), _dash_follow_ground)
		_spawn_timed_motion_trail(start_transform, position - from_position,
				old_progress, new_progress, dt, DASH_TRAIL_INTERVAL,
				DASH_GHOST_LIFETIME)
		dash_flash_t = maxf(0.0, DASH_DURATION - _dash_elapsed)
		if _dash_elapsed >= DASH_DURATION or absf(position.x - _dash_target_x) < 0.01:
			_finish_dash()
	elif rolling():
		var old_progress := clampf(_roll_elapsed / ROLL_DURATION, 0.0, 1.0)
		_roll_elapsed = minf(_roll_elapsed + dt, ROLL_DURATION)
		var new_progress := clampf(_roll_elapsed / ROLL_DURATION, 0.0, 1.0)
		var desired_x := lerpf(_roll_start_x, _roll_target_x, new_progress)
		var from_position := position
		position = _sweep_burst_path(position, _roll_dir,
				absf(desired_x - position.x), _roll_follow_ground)
		_spawn_timed_motion_trail(start_transform, position - from_position,
				old_progress, new_progress, dt, ROLL_TRAIL_INTERVAL,
				ROLL_GHOST_LIFETIME)


func _finish_dash() -> void:
	dash_flash_t = 0.0
	set_state("run" if moving() else "gun_idle")


func _finish_roll() -> void:
	_roll_elapsed = ROLL_DURATION
	set_state("run" if moving() else "gun_idle")


func _moving_platform_surface_crossed(from_y: float, to_y: float) -> float:
	var best := INF
	for platform in moving_platforms:
		if not is_instance_valid(platform):
			continue
		var surface: Rect2 = platform.top_rect()
		var left := position.x - w * 0.5 + 3.0
		var right := position.x + w * 0.5 - 3.0
		if right <= surface.position.x or left >= surface.end.x:
			continue
		# 相对运动跨越：上升台面可接住下落角色，从下向上起跳则不调用这一分支。
		var previous_surface: float = platform.previous_top_y
		if from_y <= maxf(previous_surface, surface.position.y) + 0.5 \
				and to_y >= surface.position.y - 0.1:
			best = minf(best, surface.position.y)
	return best


## 三脚探针取身体覆盖范围内最高的可达踏板；后脚会在下楼时自然保留上一级支撑。
func _stair_support_for_body(test_x: float, feet_y: float, max_up: float,
		max_down: float) -> float:
	if level == null or level.stairs.is_empty():
		return INF
	var half_w := w * 0.5
	var best := INF
	for ox in [test_x - half_w + 3.0, test_x, test_x + half_w - 3.0]:
		best = minf(best, level.stair_surface_near(ox, feet_y, max_up, max_down))
	return best


## 只检查角色实际身体矩形，不把脚底踏面本身算作障碍；用于上台阶前的头部净空。
func _body_clear_at(test_x: float, feet_y: float) -> bool:
	if level == null:
		return true
	var half_w := w * 0.5
	for ox in [test_x - half_w + 3.0, test_x, test_x + half_w - 3.0]:
		for oy in [feet_y - h + 2.0, feet_y - h * 0.5, feet_y - 2.0]:
			if level.solid_at(ox, oy) and not level.is_platform(ox, oy):
				return false
	return true


## 地面步行跨越楼梯边界：净空不足时退回上一安全 X，不能钻进踏板或天花板。
func _snap_walk_to_stair(previous_x: float) -> void:
	var surface_y := _stair_support_for_body(position.x, position.y,
			STAIR_STEP_PX + STAIR_SNAP_EPS, STAIR_STEP_PX + STAIR_SNAP_EPS)
	if surface_y == INF:
		# 走出最低一级时，楼梯表面刚好比下层整格地面高 16px；主动贴合避免一帧悬空。
		var came_from_stair := _stair_support_for_body(previous_x, position.y,
				STAIR_SNAP_EPS, STAIR_SNAP_EPS) < INF
		if came_from_stair:
			var probe_y := position.y + STAIR_STEP_PX + STAIR_SNAP_EPS
			var grid_surface := INF
			var half_w := w * 0.5
			for ox in [position.x - half_w + 3.0, position.x, position.x + half_w - 3.0]:
				if level.solid_at(ox, probe_y):
					grid_surface = minf(grid_surface, floorf(probe_y / TS) * TS)
			if grid_surface < INF and _body_clear_at(position.x, grid_surface - 0.1):
				position.y = grid_surface - 0.1
				vy = 0.0
				on_ground = true
		return
	var target_feet := surface_y - 0.1
	if not _body_clear_at(position.x, target_feet):
		position.x = previous_x
		vx = 0.0
		return
	position.y = target_feet
	vy = 0.0
	on_ground = true


## 调试辅助：判断脚底是否正贴着开放式楼梯踏面。
func _standing_on_stair() -> bool:
	var surface_y := _stair_support_for_body(position.x, position.y,
			STAIR_SNAP_EPS, STAIR_SNAP_EPS)
	return surface_y < INF


## 冲刺/翻滚/挥棒带步共用路径：地面态贴阶，空中态保持当前 Y。
func _sweep_burst_path(origin: Vector2, dir: int, dist: float,
		follow_ground: bool) -> Vector2:
	if level == null:
		return origin
	var target_x := clampf(origin.x + dist * dir, 20.0, level.world_w - 20.0)
	var safe := origin
	while absf(target_x - safe.x) > 0.001:
		var next_x := safe.x + clampf(target_x - safe.x, -DASH_SWEEP_STEP, DASH_SWEEP_STEP)
		var candidate_y := _burst_ground_feet_y(safe, next_x) if follow_ground else safe.y
		var candidate := Vector2(next_x, candidate_y)
		var side := candidate.x + (w / 2.0 if dir > 0 else -w / 2.0)
		var blocked := not _body_clear_at(candidate.x, candidate.y)
		# 空中冲刺保持Y但不能横穿楼梯侧缘；上升跳跃/翻滚仍保留单向梯下跳穿。
		if not blocked and (follow_ground or dashing() or vy >= 0.0):
			blocked = _stair_side_blocks(safe, candidate)
		if not blocked:
			for oy in [candidate.y - h + 6.0, candidate.y - h / 2.0,
					candidate.y - 3.0]:
				if level.solid_at(side, oy) and not level.is_platform(side, oy):
					blocked = true
					break
		if blocked:
			break
		safe = candidate
	return safe


## 只检查朝高端跨过的16px立面，不把整个梯下楔形补成实心墙或远距离吸到踏面。
## 与贴阶共用前脚探针，避免比贴阶早3px撞停；已安全抬到踏面上的地面路径自然放行。
func _stair_side_blocks(from_position: Vector2, to_position: Vector2) -> bool:
	if level == null or is_equal_approx(from_position.x, to_position.x):
		return false
	var dir := 1 if to_position.x > from_position.x else -1
	var leading := (w * 0.5 - 3.0) * dir
	var from_probe := from_position.x + leading
	var to_probe := to_position.x + leading
	for stair: Dictionary in level.stairs:
		if int(stair["rise_dir"]) != dir:
			continue
		var left := float(int(stair["left_c"]) * TS)
		var steps := int(stair["steps"])
		for index in steps:
			var edge_x := left + (index if dir > 0 else index + 1) * TS
			# 左升梯的right_x是开区间：只接触边界时先放行，跨入后才能取到同一踏面。
			if (edge_x - from_probe) * dir < -0.001 or (to_probe - edge_x) * dir <= 0.0:
				continue
			var rank := index + 1 if dir > 0 else steps - index
			var surface_y := float(int(stair["bottom_row"]) * TS) - rank * STAIR_STEP_PX
			if to_position.y > surface_y + STAIR_SNAP_EPS \
					and to_position.y - h < surface_y + STAIR_STEP_PX:
				return true
	return false


## 每个 2px 子步最多贴合一级 16px 高差；离开楼梯时主动接回上下平台。
func _burst_ground_feet_y(from_position: Vector2, next_x: float) -> float:
	var surface_y := _stair_support_for_body(next_x, from_position.y,
			STAIR_STEP_PX + STAIR_SNAP_EPS, STAIR_STEP_PX + STAIR_SNAP_EPS)
	if surface_y < INF:
		return surface_y - 0.1
	var came_from_stair := _stair_support_for_body(from_position.x, from_position.y,
			STAIR_SNAP_EPS, STAIR_SNAP_EPS) < INF
	if not came_from_stair:
		return from_position.y
	var probe_y := from_position.y + STAIR_STEP_PX + STAIR_SNAP_EPS
	var grid_surface := INF
	var half_w := w * 0.5
	for ox in [next_x - half_w + 3.0, next_x, next_x + half_w - 3.0]:
		if level.solid_at(ox, probe_y):
			grid_surface = minf(grid_surface, floorf(probe_y / TS) * TS)
	return grid_surface - 0.1 if grid_surface < INF else from_position.y


## 首击前送专用固定 Y 扫描：2px 步长防穿墙，单向平台不阻挡横移。
func _sweep_x(dir: int, dist: float) -> float:
	if level == null:
		return position.x
	var target := clampf(position.x + dist * dir, 20.0, level.world_w - 20.0)
	var safe_x := position.x
	while absf(target - safe_x) > 0.001:
		var next_x := safe_x + clampf(target - safe_x, -DASH_SWEEP_STEP, DASH_SWEEP_STEP)
		var side := next_x + (w / 2.0 if dir > 0 else -w / 2.0)
		var blocked := false
		for oy in [position.y - h + 6.0, position.y - h / 2.0, position.y - 3.0]:
			if level.solid_at(side, oy) and not level.is_platform(side, oy):
				blocked = true
				break
		# 首击前送保持固定 Y；遇到 16px 高差即停，避免挥棍动作自动爬楼。
		var stair_y := _stair_support_for_body(next_x, position.y,
				STAIR_STEP_PX + STAIR_SNAP_EPS, STAIR_STEP_PX + STAIR_SNAP_EPS)
		if stair_y < INF and absf(stair_y - position.y) > 0.75:
			blocked = true
		if blocked:
			break
		safe_x = next_x
	return safe_x


## 按实际经过的时间采样虚影；每张图有独立出生时刻，因此会从旧到新自然消散。
func _spawn_timed_motion_trail(start_transform: Transform2D, delta_position: Vector2,
		progress_from: float, progress_to: float, dt: float, interval: float,
		lifetime: float) -> void:
	if dt <= 0.0 or delta_position.is_zero_approx():
		return
	var carried := _motion_ghost_accum
	var emit_at := interval - carried
	while emit_at <= dt + 0.00001:
		var local_progress := clampf(emit_at / dt, 0.0, 1.0)
		var ghost_transform := start_transform
		ghost_transform.origin += delta_position * local_progress
		var action_progress := lerpf(progress_from, progress_to, local_progress)
		_spawn_dash_afterimage(_dash_color_at(action_progress), ghost_transform, lifetime)
		emit_at += interval
	_motion_ghost_accum = fmod(carried + dt, interval)


## 左键挥棍：地面可三连起手；空中只允许起手一次（一段，无突进、不续段），落地重置
func _try_bat() -> void:
	if dead or reloading or aiming or sliding() or batting() or dashing() or rolling():
		return
	if not on_ground:
		if air_bat_used:
			return
		air_bat_used = true
	_start_bat(0)


func _start_bat(stage: int) -> void:
	stage = clampi(stage, 0, BAT_STAGES.size() - 1)
	bat_hit_done = false
	bat_queued = false
	_bat_input_buffer_t = 0.0
	_bat_lunge_applied = 0.0
	_bat_ground_lunge = stage == 0 and on_ground
	set_state(BAT_STAGES[stage])
	if _bat_ground_lunge:
		# 连续前送由物理步进接管；这里只留下起手虚影，绝不直接跳到终点。
		_ensure_visual_nodes()
		if _sprite.texture != null:
			_spawn_dash_afterimage(Color(0.45, 0.98, 1.00), _sprite.global_transform,
					BAT_STEP_GHOST_LIFE)
	bat_swing_started.emit(stage)


func _movement_direction() -> int:
	return int(keys.has(KEY_D)) - int(keys.has(KEY_A))


## 带步与前送全部逐 2px 检查身体净空、墙面和楼梯，低帧率也不靠瞬移跨障碍。
func _advance_bat_motion(dt: float) -> void:
	if hitstop > 0.0:
		return
	var lunge := 0.0
	if _bat_ground_lunge and on_ground:
		var act: Dictionary = db.actions[BAT_CLIPS[_bat_stage()]]
		var next_t := t + dt * float(BAT_FPS_MULTS[_bat_stage()])
		var progress := clampf(next_t * db.fps / float(maxi(1, int(act["frames"]) - 1)) \
				/ BAT_HIT_AT, 0.0, 1.0)
		# 二次缓出：起手立即有动量，命中前平顺落定，不再一帧传送 38px。
		var desired_lunge := BAT1_STEP * (1.0 - pow(1.0 - progress, 2.0))
		lunge = maxf(0.0, desired_lunge - _bat_lunge_applied)
		_bat_lunge_applied = desired_lunge
	elif not on_ground:
		_bat_ground_lunge = false
	var distance := lunge + absf(vx) * dt * 60.0
	if distance > 0.0:
		position = _sweep_burst_path(position, face, distance, on_ground)


func _can_cancel_bat() -> bool:
	return batting() and bat_hit_done and _bat_progress() >= BAT_CANCEL_OPEN \
			and hitstop <= 0.0


func _cancel_bat() -> void:
	bat_queued = false
	_bat_ground_lunge = false
	_bat_lunge_applied = BAT1_STEP
	_bat_input_buffer_t = 0.0


func _consume_bat_input_buffer() -> void:
	if _bat_input_buffer_t <= 0.0 or dead or batting() or dashing() or rolling():
		return
	# 只消费一次；仍须通过空中一次制与其他起手规则，不能攒成自动连击。
	_bat_input_buffer_t = 0.0
	_try_bat()


func _bat_stage() -> int:
	return BAT_STAGES.find(state)


func _bat_progress() -> float:
	if not batting() or db == null:
		return 0.0
	var act: Dictionary = db.actions[BAT_CLIPS[_bat_stage()]]
	return float(frame) / float(maxi(1, int(act["frames"]) - 1))


## 命中判定盒：面前约 76×56，跟随朝向
func _bat_hitbox() -> Rect2:
	var cx: float = position.x + face * (w / 2.0 + BAT_HITBOX_W / 2.0 - 6.0)
	var cy: float = position.y - h * 0.55
	return Rect2(cx - BAT_HITBOX_W / 2.0, cy - BAT_HITBOX_H / 2.0,
			BAT_HITBOX_W, BAT_HITBOX_H)


func _try_slide() -> void:
	if not on_ground or slide_held or dead:
		return
	if not moving():
		notice.emit("需在奔跑中滑铲")
		return
	slide_held = true
	pending_end = false
	slide_time = 0.0
	set_state("slide_start")


func _rel_slide() -> void:
	if not slide_held:
		return
	slide_held = false
	if state == "slide_start":
		pending_end = true
	elif state == "slide_loop":
		set_state("slide_end")


## 双 S 下穿：仅当脚下支撑全部来自 = 单向台时触发（# 实地不可下穿）。
## 触发后 0.30s 内落地判定忽略 = 台（见 step 的 vy>=0 分支），
## 脚尖先压过台面 + 起步下落速度，重力接管落到下层。
func _try_drop_through() -> void:
	if dead or not on_ground or reloading or sliding() or batting() or dashing() or rolling():
		return
	if not _standing_on_platform():
		return
	_drop_t = DROP_THROUGH_TIME
	on_ground = false
	vy = maxf(vy, DROP_INITIAL_VY)
	position.y += 2.0
	set_state("gun_jump_air")
	_play_jump_fx()   ## 下穿提示尘土（复用起跳尘，5 帧比落地尘 2 帧更读得出）


## 脚下支撑检测（与落地判定同 3 探针）：有支撑且所有支撑格都是 = 台
func _standing_on_platform() -> bool:
	if level == null:
		return false
	var half_w := w / 2.0
	var supported := false
	for ox in [position.x - half_w + 3.0, position.x, position.x + half_w - 3.0]:
		if level.solid_at(ox, position.y + 2.0):
			supported = true
			if not level.is_platform(ox, position.y + 2.0):
				return false
	return supported


func _update_aim() -> void:
	if dead:
		aiming = false
		return   ## 死后键盘不能转动尸体或改变已锁定的受击方向
	aiming = GUN_ENABLED and keys.has(MOUSE_BUTTON_RIGHT) and not dead
	if aiming:
		# 精细瞄准：鼠标决定朝向和仰角
		var mw := _aim_point()
		var a: Dictionary = db.actions["aim"]
		var ay: float = position.y + (126.0 - float(a["foot_y"])) * CHAR_SCALE
		var dx: float = maxf(18.0, absf(mw.x - position.x))
		aim_deg = clampf(rad_to_deg(atan2(-(mw.y - ay), dx)), db.angle_min, db.angle_max)
		face = 1 if mw.x >= position.x else -1
	else:
		# 非瞄准：水平开火姿态，朝向由移动方向决定（鼠标不影响）
		aim_deg = 0.0
		if batting():
			return   ## 出棒至收招保持同一朝向；后段反向取消由输入处理显式接管。
		if keys.has(KEY_A) and not keys.has(KEY_D):
			face = -1
		elif keys.has(KEY_D) and not keys.has(KEY_A):
			face = 1


## 枪口/握把（世界坐标）+ 膛线方向。
## 非瞄准时取 LUT 0° 档（水平），瞄准时取实测角档。
func gun_pose() -> Dictionary:
	if db == null or dead:
		return {}
	var deg: float = aim_deg if aiming else 0.0
	var idx := db.lut_index(deg)
	var e: Dictionary = db.lut_entries[idx]
	var a: Dictionary = db.actions["aim"]
	var bcx: float = a["body_cx"]
	var fy: float = a["foot_y"]
	var to_w := func(p: Vector2) -> Vector2:
		return Vector2(position.x + (p.x - bcx) * CHAR_SCALE * face,
				position.y + (p.y - fy) * CHAR_SCALE)
	var m: Vector2 = to_w.call(e["muzzle"])
	var g: Vector2 = to_w.call(e["grip"])
	var rad: float
	if aiming:
		rad = atan2(m.y - g.y, m.x - g.x)
	else:
		rad = 0.0 if face > 0 else PI   ## 水平直射
	return {"muzzle": m, "grip": g, "rad": rad, "frame": e["f"], "idx": idx}


## 射击：静止站立可精细/水平射；移动中可水平直射（用户决策）；空中/滑铲/换弹不行。
func try_shoot() -> Dictionary:
	if not GUN_ENABLED:
		return {}
	if dead or fire_cd > 0.0 or sliding() or reloading:
		return {}
	if state != "aim" and state != "gun_idle" and state != "run":
		return {}
	if not on_ground:
		return {}
	if gun_ammo <= 0:
		fire_cd = 0.25
		dry_fire.emit()
		return {}
	var gp := gun_pose()
	if gp.is_empty():
		return {}
	fire_cd = 0.13
	gun_ammo -= 1
	return {"x": gp["muzzle"].x, "y": gp["muzzle"].y,
			"vx": cos(gp["rad"]) * BULLET_SPD * 60.0,
			"vy": sin(gp["rad"]) * BULLET_SPD * 60.0,
			"life": 1.6}


# ---------- 渲染 ----------

func _sync_sprite() -> void:
	if _sprite == null or db == null:
		return
	var clip_name := current_clip()
	_apply_sprite(clip_name, frame)
	_sync_onion(clip_name, db.actions[clip_name])
	_sync_slash()


## 把任意图集动作的一帧贴到本体 Sprite（棍影冲刺定格等也走这里）
func _apply_sprite(clip_name: String, f: int) -> void:
	if _sprite == null:
		return
	var act: Dictionary = db.actions[clip_name]
	_sprite.texture = db.texture_for(clip_name)
	_sprite.region_enabled = true
	_sprite.region_rect = db.frame_rect(clip_name, f)
	_sprite.centered = false
	# H3 原片逐剪辑缩放归一化（以 aim 的角色源高 234px 实测对齐）；预处理素材系数 1.0
	var eff_scale: float = CHAR_SCALE * float(RAW_SCALE.get(clip_name, 1.0))
	_sprite.scale = Vector2.ONE * eff_scale
	var fw: float = act["fw"]
	var bcx: float = act["body_cx"]
	var fy: float = act["foot_y"]
	var dx: float
	if face > 0:
		_sprite.flip_h = false
		dx = -bcx * eff_scale
	else:
		_sprite.flip_h = true
		dx = -(fw - bcx) * eff_scale
	# 受击无敌期闪烁
	_sprite.modulate.a = 0.45 if invuln_t > 0.0 and int(invuln_t * 20) % 2 == 0 else 1.0
	# 像素对齐：位置取整到像素网格，奔跑/相机缓动时不再 1px 抖动发虚
	var target := position + Vector2(dx, -fy * eff_scale)
	_sprite.global_position = target.round()
	_sync_readability()


## 可读性层同步：描边贴同一帧同一锚点（深色剪影膨胀 1px），背晕跟身且贴像素网格
func _sync_readability() -> void:
	if _outline != null and _sprite.texture != null:
		_outline.visible = true
		_outline.texture = _sprite.texture
		_outline.region_rect = _sprite.region_rect
		_outline.flip_h = _sprite.flip_h
		_outline.scale = _sprite.scale
		_outline.global_position = _sprite.global_position
		_outline.modulate.a = _sprite.modulate.a   ## 受击闪烁同步
		var ts := Vector2(_sprite.texture.get_size())
		var rr: Rect2 = _sprite.region_rect
		_outline_mat.set_shader_parameter("region_min", rr.position / ts)
		_outline_mat.set_shader_parameter("region_max", rr.end / ts)
	if _halo != null:
		_halo.visible = not dead   ## 尸体不再背光，横躺读作静态场景物
		_halo.global_position = (position + Vector2(0.0, -h * 0.9)).round()
	if _shadow != null:
		# 抛飞移动的是整个尸体；接触阴影单独投在地面，空洞下方没有地面则隐藏。
		_shadow.visible = not dead or _death_ground_valid
		var shadow_y := _death_ground_y if dead and _death_ground_valid else position.y
		_shadow.global_position = Vector2(position.x, shadow_y - 1.0).round()
		var lift := maxf(0.0, shadow_y - position.y) if dead else 0.0
		_shadow.scale = SHADOW_SCALE * clampf(1.0 - lift / 180.0, 0.65, 1.0)


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


## 程序生成径向渐变背晕纹理（64px，平方衰减；软渐变、不做像素化）
func _make_halo_texture() -> Texture2D:
	var img := Image.create(HALO_TEX_SIZE, HALO_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2(HALO_TEX_SIZE, HALO_TEX_SIZE) * 0.5 - Vector2(0.5, 0.5)
	for y in range(HALO_TEX_SIZE):
		for x in range(HALO_TEX_SIZE):
			var d: float = clampf(1.0 - Vector2(x, y).distance_to(c) / (HALO_TEX_SIZE * 0.5),
					0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, d * d))
	return ImageTexture.create_from_image(img)


## 站立视觉高度（源高 234 × CHAR_SCALE），敌我比例验收用
func visual_height() -> float:
	return 234.0 * CHAR_SCALE


## 受击框与22×52移动碰撞分离：站立包住头部，翻滚压低；头发/狐耳/球棒不算受击体。
## 保持脚底锚定，不增大地图通行碰撞，也不改变既有翻滚前0.14秒无敌窗口。
func hurtbox_rect() -> Rect2:
	var low := rolling()
	var size := ROLL_HURTBOX_SIZE if low else STANDING_HURTBOX_SIZE
	var center_x := position.x + (0.0 if low else 6.0 * face)
	return Rect2(Vector2(center_x - size.x * 0.5, position.y - size.y), size)


## 洋葱片：挥棍时主帧前后各叠一帧虚影（参考洋葱皮模式），其余状态隐藏
func _sync_onion(clip_name: String, act: Dictionary) -> void:
	if _onion_prev == null or _onion_next == null:
		return
	if not batting():
		_onion_prev.visible = false
		_onion_next.visible = false
		return
	var total: int = int(act["frames"])
	if state == "bat2" and frame >= total - 2:
		# 第二段收尾 2 帧干净收棍，不加任何虚影（用户决策）
		_onion_prev.visible = false
		_onion_next.visible = false
		return
	var specs := [
		[_onion_prev, frame - ONION_FRAME_GAP, _onion_mat_prev],
		[_onion_next, frame + ONION_FRAME_GAP, _onion_mat_next],
	]
	for spec in specs:
		var sp: Sprite2D = spec[0]
		var f: int = clampi(int(spec[1]), 0, total - 1)
		if f == frame:
			sp.visible = false
			continue
		sp.visible = true
		sp.texture = _sprite.texture
		sp.region_enabled = true
		sp.region_rect = db.frame_rect(clip_name, f)
		sp.centered = false
		sp.flip_h = _sprite.flip_h
		sp.scale = _sprite.scale
		sp.modulate = Color(1.0, 1.0, 1.0, 1.0)
		sp.material = spec[2]   ## 冲刺同款剪影着色器，透明度在 opacity 参数里
		sp.global_position = _sprite.global_position


## 挥棍斩击弧光：帧进度驱动 5 帧弧光，跟随朝向镜像，各段有倾角
func _sync_slash() -> void:
	if _slash == null:
		return
	if not batting():
		_slash.visible = false
		return
	var prog := _bat_progress()
	if prog < SLASH_DELAY:
		_slash.visible = false   ## 起手阶段不出光
		return
	_slash.visible = true
	_slash.texture = _slash_tex_right if face > 0 else _slash_tex_left
	var sp := (prog - SLASH_DELAY) / (1.0 - SLASH_DELAY)
	var f: int = clampi(floori(sp * SLASH_FRAMES), 0, SLASH_FRAMES - 1)
	_slash.region_rect = Rect2(f * SLASH_FRAME_W, 0, SLASH_FRAME_W, SLASH_FRAME_W)
	_slash.scale = Vector2.ONE * SLASH_SCALE
	_slash.rotation = 0.0
	_slash.global_position = (position + Vector2(
			SLASH_OFFSET.x * face, SLASH_OFFSET.y)).round()


## 起跳尘土：起跳瞬间在脚底播放（5 帧一次性）
func _play_jump_fx() -> void:
	_ensure_visual_nodes()
	_jump_fx.texture = _fx_jump_tex
	_jump_fx.scale = Vector2.ONE * FX_SCALE
	_jump_fx.global_position = _fx_ground_pos()
	_jump_fx.visible = true
	_jump_fx_t = 0.0


## 尘土锚点：吸附到脚下方格顶面，留在地面而不是脚上
func _fx_ground_pos() -> Vector2:
	var gy := floori((position.y + 2.0) / TS) * TS
	return Vector2(position.x, gy - FX_GROUND_RISE).round()


## 落地尘土：落地瞬间在脚底播放（2 帧一次性）
func _play_land_fx() -> void:
	_ensure_visual_nodes()
	_land_fx.texture = _fx_land_tex
	_land_fx.scale = Vector2.ONE * FX_SCALE
	_land_fx.global_position = _fx_ground_pos()
	_land_fx.visible = true
	_land_fx_t = 0.0


## 尘土帧推进（24fps，播完自动隐藏）
func _advance_step_fx(dt: float) -> void:
	if _jump_fx != null and _jump_fx_t >= 0.0:
		_jump_fx_t += dt
		var f := floori(_jump_fx_t * 24.0)
		if f >= FX_JUMP_FRAMES:
			_jump_fx.visible = false
			_jump_fx_t = -1.0
		else:
			_jump_fx.region_rect = Rect2(f * FX_FRAME_W, 0, FX_FRAME_W, FX_FRAME_W)
	if _land_fx != null and _land_fx_t >= 0.0:
		_land_fx_t += dt
		var f2 := floori(_land_fx_t * 24.0)
		if f2 >= FX_LAND_FRAMES:
			_land_fx.visible = false
			_land_fx_t = -1.0
		else:
			_land_fx.region_rect = Rect2(f2 * FX_FRAME_W, 0, FX_FRAME_W, FX_FRAME_W)


## ---------- Shift 闪现轨迹视觉 ----------

func _dash_color_at(progress: float) -> Color:
	var p := clampf(progress, 0.0, 1.0) * float(DASH_TINTS.size() - 1)
	var i0 := mini(floori(p), DASH_TINTS.size() - 1)
	var i1 := mini(i0 + 1, DASH_TINTS.size() - 1)
	return DASH_TINTS[i0].lerp(DASH_TINTS[i1], p - floorf(p))


func _update_dash_visual(dt: float) -> void:
	_sync_motion_trail_z()
	if dashing():
		# 闪现本体短促白化；身后虚影各自按出生时间衰减，不再整排同步消失。
		_dash_material.set_shader_parameter("tint_color", Color.WHITE)
		_dash_material.set_shader_parameter("tint_mix", 0.96)
		_dash_material.set_shader_parameter("opacity", DASH_LIVE_ALPHA)
		_sprite.material = _dash_material
	else:
		_sprite.material = _time_focus_material if _time_focus_active and not dead else null

	# 闪现结束后继续推进旧轨迹，保证落点显形后轨迹独立渐隐。
	for i in range(_dash_ghosts.size() - 1, -1, -1):
		var data: Dictionary = _dash_ghosts[i]
		var ghost: Sprite2D = data["sprite"]
		var lifetime := float(data.get("lifetime", DASH_GHOST_LIFETIME))
		var age := float(data["age"]) + dt
		if age >= lifetime or not is_instance_valid(ghost):
			if is_instance_valid(ghost):
				ghost.free()
			_dash_ghosts.remove_at(i)
			continue
		data["age"] = age
		_dash_ghosts[i] = data
		var remain := 1.0 - age / lifetime
		ghost.modulate = Color(1.0, 1.0, 1.0, float(data.get("base_alpha", DASH_GHOST_ALPHA)) * remain * remain)


func _spawn_dash_afterimage(tint: Color, ghost_transform: Transform2D,
		lifetime := DASH_GHOST_LIFETIME) -> void:
	if _dash_trail_root == null or _sprite.texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.name = "DashAfterimage"
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.texture = _sprite.texture
	ghost.region_enabled = _sprite.region_enabled
	ghost.region_rect = _sprite.region_rect
	ghost.centered = _sprite.centered
	ghost.flip_h = _sprite.flip_h
	ghost.flip_v = _sprite.flip_v
	ghost.modulate = Color(1.0, 1.0, 1.0, DASH_GHOST_ALPHA)

	var mat := ShaderMaterial.new()
	mat.shader = _dash_shader
	mat.set_shader_parameter("tint_color", tint)
	mat.set_shader_parameter("tint_mix", 0.96)
	mat.set_shader_parameter("opacity", 1.0)
	ghost.material = mat

	_dash_trail_root.add_child(ghost)
	ghost.global_transform = ghost_transform
	_dash_ghosts.append({"sprite": ghost, "age": 0.0, "lifetime": lifetime})


func _clear_dash_visual() -> void:
	if _dash_trail_root != null:
		_dash_trail_root.visible = true  ## 回溯曾隐藏旧残影容器；新一轮恢复正常绘制
	for data in _dash_ghosts:
		var ghost: Sprite2D = data["sprite"]
		if is_instance_valid(ghost):
			ghost.free()
	_dash_ghosts.clear()
	dash_cooldown_t = 0.0
	dash_flash_t = 0.0
	_dash_elapsed = 0.0
	_dash_follow_ground = true
	roll_cooldown_t = 0.0
	roll_invuln_t = 0.0
	_roll_elapsed = 0.0
	_roll_follow_ground = true
	_motion_ghost_accum = 0.0
	_sync_dash_cooldown_ui()
	if _sprite != null:
		_sprite.material = null
