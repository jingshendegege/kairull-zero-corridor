extends Node2D
## 主场景：关卡 + 玩家 + 相机 + 子弹/特效 + HUD。
## 子节点全部代码构建，tscn 只挂这个脚本，避免场景文件与代码两边漂移。
##
## 操作：A/D 奔跑 · Shift 棍影冲刺（1.5秒CD）· Ctrl 翻滚（空中可用）· W 跳 ·
##       左键挥棍/击飞黄箱 · 右键时停 · Backspace重试 · Esc暂停/继续；F/K调试键默认关闭。

const VW := 1360.0
const VH := 765.0
const FREIGHT_INSPECTOR_SCRIPT := preload("res://scripts/freight_inspector.gd")
const BAT_CARGO_SCRIPT := preload("res://scripts/prop_bat_cargo.gd")
const CHECKPOINT_BEACON_SCRIPT := preload("res://scripts/checkpoint_beacon.gd")
const RUN_CHECKPOINT := preload("res://scripts/run_checkpoint.gd")
const MAX_FLYING_CARGO := 12
@export var bat_cargo_enabled := true ## 快速回退环境击飞玩法；不改变既有爆炸桶/CRT。
const BAT_KNOCKBACK_ENABLED := true   ## 紧急回退只关此开关，不碰纯球棒/翻滚配置。
const BAT_KNOCKBACK_DISTANCES := [80.0, 102.0, 126.0]
const BAT_KNOCKBACK_DURATIONS := [0.22, 0.26, 0.30]
const BAT_KNOCKBACK_SWEEP_STEP := 2.0
const BAT_KNOCKBACK_LETHAL_MULT := 1.18
const BAT_KNOCKBACK_BOSS_MULT := 0.38
const ENEMY_BULLET_SWEEP_STEP := 4.0 ## 敌弹每次最多推进4px，避免大dt/高速弹越过头部和薄遮挡。
const DEATH_INERTIA_SCRIPT := preload("res://scripts/death_inertia.gd")
const SMOKE_TACTICS_SCRIPT := preload("res://scripts/smoke_tactics.gd")
const TACTICAL_HAZARD_SCRIPT := preload("res://scripts/tactical_hazard.gd")
const FREIGHT_LIFT_SCRIPT := preload("res://scripts/freight_lift.gd")
const MAX_CORPSE_IMPACTS := 32
@export var corpse_impact_enabled := true ## 可单独回退尸体腾空/回弹，不动原击退和击杀音。

var db: AtlasDB
var debug := false         ## 保留开发检查API；正常游戏不再由快捷键打开。
@export var debug_hotkeys_enabled := false ## 仅Inspector显式启用时允许F调试/K测试自杀。
var bullets: Array = []
var enemy_bullets: Array = []   ## Boss 法球
var fx: Array = []
var cam_tl := Vector2.ZERO    ## 相机左上角（世界坐标），各层共用

## 音效：12 路 AudioStreamPlayer 轮转；枪声、命中声与液体材质声可并发叠放。
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _sfx := {}               ## 逻辑名 -> AudioStream
var action_audio: Node
@export var action_audio_enabled := true ## 新独立动作音色；可单独静音对照，不覆盖旧素材。
@export var original_combat_audio_enabled := true ## 保留已认可的冲刺/球棒原声；关闭才对照合成版，不影响时间技能音。
@export_range(0.0, 0.04, 0.005) var original_kill_pitch_step := 0.02 ## 连杀每次轻升2%音高；设0只关闭升调，不换掉原声。
@export_range(0.0, 0.015, 0.001) var original_kill_pitch_variation := 0.015 ## 每杀最多±1.5%轻变化；设0回到纯连杀升调。
const ORIGINAL_KILL_CHAIN_WINDOW := 2.4
const ORIGINAL_KILL_MAX_PITCH := 1.08
const ORIGINAL_KILL_VARIATION_LIMIT := 0.015
var _last_original_kill_at := -INF
var _original_kill_streak := 0
var _last_original_kill_pitch := -INF
var _last_original_kill_variation := 0.0
var _original_kill_rng := RandomNumberGenerator.new() ## 独立音色RNG，绝不扰动敌人/掉落等全局随机序列。
var _original_kill_rng_initialized := false
var _sfx_gain := {"slime_hit": -5.5, "slime_death": -3.5,   ## 材质声叠在枪声下方
		"hit6": 3.5, "hit7": 3.5, "hit8": 3.5, "kill": 4.5}   ## Boss 受击/击破：击杀略大于受击，补 BGM 掩蔽

## 关卡 BGM：CorridorLevel.active_bgm 非空时创建循环播放器（信号回放，零依赖导入循环设置）。
## 音量常驻压在音效之下；播放器挂在 game 下，不经过任何随顿帧暂停的路径。
const MUSIC_VOLUME_DB := -14.0
var music: AudioStreamPlayer = null
const CONTINUOUS_MUSIC_NAME := "ContinuousLevelMusic"
var _keep_music_on_exit := false ## 只在同关重开交接播放器；回菜单/退出仍正常收尾。

## 过关转场：CLEAR 卡停留 → 淡黑 → 切下一幕（CorridorLevel.active_next_scene 非空时启用）。
const CLEAR_HOLD := 1.4      ## CLEAR 卡停留秒数
const FADE_TIME := 0.5       ## 淡黑秒数
var _clear_elapsed := -1.0   ## <0 = 未过关
var _fade_k := 0.0           ## 当前淡黑进度 0..1（测试断言用）
var _transitioning := false  ## 已发起切场景（防重入）

var level: CorridorLevel
var player: KairullPlayer
var cam: Camera2D
var minions: Array = []        ## 悬浮小怪（地图 x 刷点）
var props: Array = []          ## 互动物件（B 爆炸桶 / T CRT / C 可击飞货箱）
var doors: Array = []          ## 房间门（地图 D 刷点，RoomDoor）
var decor_nodes: Array = []    ## 房间装饰剪影（RoomDecor，按房间实例化）
var wall_backdrop: WallBackdrop  ## 室内墙面 backdrop（M02 房间系统）
var room_lights: RoomLights      ## L 光条光池 / 地板泛光
var quarantine_architecture: QuarantineArchitecture  ## 正式 M01 可玩剖面后景
var quarantine_foreground: QuarantineArchitecture    ## 正式 M01 稀疏近景遮挡
var current_room := -1         ## 玩家所在房间（level.rooms 下标，-1 = 无房间系统/房间外）
var exit_door: ExitDoor        ## 塔门出口视觉（> 标记处）
var level_cleared := false     ## 玩家触碰出口后：冻结敌人 + HUD 出 CLEAR 卡
var red_boss: Node2D           ## 关底 Boss（Red / Hornet，由 active_boss 选择）
var bg: GameBackground
var paint_layer: SlimePaintLayer
var fx_layer: GameFxLayer
var debug_overlay: GameDebugOverlay
var hud: GameHud
var smoke_tactics: Node2D
var tactical_hazards: Array[Node2D] = [] ## 器械不混入小兵清场计数，也不套彩血和尸体惯性。
var moving_lifts: Array[Node2D] = [] ## 单向货梯单独管理，不能被误判成炮塔或房门。

var camera_trauma := 0.0
var camera_shake_direction := Vector2.ZERO
var camera_shake_time := 0.0
var _cam_room_boost := 0.0   ## 换房后的快速滑镜剩余秒数（≤0.25s 就位）
## 球棒专用的短时水平冲量；独立于敌人 AI，死亡后也能完成尸体滑移。
var _enemy_knockbacks: Array[Dictionary] = []
var _corpse_impacts: Array[Dictionary] = [] ## 仅存半秒内的死亡表现任务，完成后立即移除。
var _bat_prop_origin := Vector2.ZERO
var _bat_prop_origin_valid := false
var _run_elapsed := 0.0
var _visited_rooms: Dictionary = {}
var _campaign_frontier := -1    ## 首次跨过中继站之后，下一战斗段才开始索敌。
var _checkpoint_index := -1
var _checkpoint_name := "安全入口"
var _checkpoint_beacons: Dictionary = {}
var _checkpoint_configs: Dictionary = {} ## 正式挑战只读生成器给出的唯一中段点。
var _campaign_boundaries: Array[int] = [] ## 只控制遭遇唤醒，不再等同于复活记录点。

const RUN_SESSION := preload("res://scripts/run_session.gd")
const CHRONO_CHARGE := preload("res://scripts/chrono_charge.gd")
const ATTEMPT_TIMELINE := preload("res://scripts/attempt_timeline.gd")
const DEATH_HOLD := 0.92
const REWIND_DURATION := 0.65
const INTERFERENCE_DURATION := 0.36
var timeline_enabled := false
var time_charge: RefCounted = CHRONO_CHARGE.new()
var attempt_timeline: RefCounted = ATTEMPT_TIMELINE.new()
var time_phase := "playing"
var rewind_progress := 0.0
var glitch_progress := 0.0
var _death_elapsed := 0.0
var _death_prompt_ready := false
var _rewind_elapsed := 0.0
var _temporal_nodes: Array[Dictionary] = []
var _temporal_paused := false
var _focus_presented := false
var _focus_original_z := 0
var victory_transition: CanvasLayer
var _victory_started := false
const NEXT_LEVEL_DELAY := 2.2 ## 1.4秒渐黑后留白字停顿，再自动接下关，不走死亡花屏。
var pause_controller: Node


func _ready() -> void:
	# 菜单开局才启用新录像循环，旧 M02/单脚本测试继续使用原接口。
	timeline_enabled = RUN_SESSION.timeline_enabled and CorridorLevel.active_campaign_mode
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)   ## 系统光标藏起来，全程用自绘准星
	db = AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json",
	])
	_load_sfx()
	# 新技能/环境声按用途路由；已认可的冲刺、挥棒、命中与击杀优先使用原声。
	action_audio = load("res://scripts/action_sound_router.gd").new()
	action_audio.name = "ActionSoundRouter"
	add_child(action_audio)
	_setup_music()

	bg = GameBackground.new()
	bg.name = "Background"
	bg.host = self
	add_child(bg)

	level = CorridorLevel.new()
	level.name = "Level"
	add_child(level)
	level.build()

	# 正式 M01 直接消费 LDtk 的显式语义层；房间外不铺背景，保留近黑剖面虚空。
	# 旧 M02 仍走原墙面/房名装饰链，避免本轮美术重构影响已验收关卡。
	if CorridorLevel.active_art_style == "quarantine":
		quarantine_architecture = QuarantineArchitecture.new()
		quarantine_architecture.name = "QuarantineArchitecture"
		quarantine_architecture.setup(level, CorridorLevel.active_semantic_layers,
				CorridorLevel.active_semantic_ids, false)
		add_child(quarantine_architecture)
		move_child(quarantine_architecture, level.get_index())

	# M02 房间系统：墙面 backdrop + 房间装饰剪影画在 bg 之后、TileMapLayer 之前
	# （实心 tiles 天然盖住 backdrop 被楼板/墙占住的部分）；L 光池画在 tiles 之上、
	# 油漆层/角色之下——像灯光落在地板顶面。
	elif not level.rooms.is_empty():
		wall_backdrop = WallBackdrop.new()
		wall_backdrop.name = "WallBackdrop"
		wall_backdrop.level = level
		add_child(wall_backdrop)
		move_child(wall_backdrop, level.get_index())
		for room in level.rooms:
			var decor := RoomDecor.new()
			decor.name = "Decor_%s" % room["name"]
			decor.setup(room["name"], room["rect"])
			add_child(decor)
			move_child(decor, level.get_index())
			decor_nodes.append(decor)
		room_lights = RoomLights.new()
		room_lights.name = "RoomLights"
		room_lights.level = level
		add_child(room_lights)
		move_child(room_lights, level.get_index() + 1)

	# 油漆层在地形之后、角色之前：污渍像黏在背景墙上，不盖住人物轮廓。
	paint_layer = SlimePaintLayer.new()
	paint_layer.name = "SlimePaintLayer"
	paint_layer.level = level
	add_child(paint_layer)

	# 互动物件（B 爆炸桶 / T CRT）与出口门：画在油漆层之后、角色之前
	for ps in level.prop_spawns:
		_spawn_prop(ps["kind"], ps["pos"])
	if level.exit_point != Vector2.ZERO:
		exit_door = ExitDoor.new()
		exit_door.name = "ExitDoor"
		exit_door.position = level.exit_point
		add_child(exit_door)

	player = KairullPlayer.new()
	player.name = "Player"
	player.debug_hotkeys_enabled = debug_hotkeys_enabled
	if timeline_enabled:
		player.max_hp = RUN_SESSION.max_health()
		player.rewind_on_fall = true
	player.db = db
	player.level = level
	player.spawn = level.spawn   ## 出生点来自地图 @ 标记
	add_child(player)
	player.fired.connect(_on_player_fired)
	player.fell_out.connect(_on_player_fell_out)
	player.notice.connect(func(t: String) -> void: hud.show_msg(t))
	player.dry_fire.connect(func() -> void: play_sfx("empty"))
	player.reload_started.connect(func() -> void: play_sfx("reload"))
	player.hurt.connect(func() -> void:
		if player.hp > 0:
			play_action("player_hurt"))  # 致命伤只播倒地声，避免受伤/死亡叠成双爆音。
	player.died.connect(_on_player_died)
	player.death_landed.connect(func(at: Vector2, power: float, direction: float) -> void:
		if fx_layer != null:
			fx_layer.spawn_corpse_landing_dust(at, power, direction))
	player.bat_swing_started.connect(_on_bat_swing_started)
	player.bat_swung.connect(_on_player_bat_swung)
	player.smoke_throw_requested.connect(_on_smoke_throw_requested)
	player.dashed.connect(func() -> void: play_action("player_dash"))

	fx_layer = GameFxLayer.new()
	fx_layer.name = "FxLayer"
	fx_layer.host = self
	fx_layer.z_index = 30   ## 子弹与瞬时液爆压住角色；调试层仍在 z=100
	add_child(fx_layer)

	# 角色之上的稀疏前景：正式 M01 用 LDtk 梁/管/链/格栅；旧图沿用视差 L3。
	# 两者都固定 z=10，子弹与瞬时液爆仍在其上。
	if CorridorLevel.active_art_style == "quarantine":
		quarantine_foreground = QuarantineArchitecture.new()
		quarantine_foreground.name = "QuarantineForeground"
		quarantine_foreground.setup(level, CorridorLevel.active_semantic_layers,
				CorridorLevel.active_semantic_ids, true)
		quarantine_foreground.z_index = 10
		add_child(quarantine_foreground)
	else:
		var fg := GameBackground.new()
		fg.name = "Foreground"
		fg.host = self
		fg.front_only = true
		fg.z_index = 10
		add_child(fg)

	cam = Camera2D.new()
	cam.name = "Camera2D"
	add_child(cam)
	cam.make_current()
	# 初始相机直接就位，避免开局长缓动
	cam_tl = _cam_target()
	cam.position = cam_tl + Vector2(VW, VH) * 0.5

	debug_overlay = GameDebugOverlay.new()
	debug_overlay.name = "DebugOverlay"
	debug_overlay.host = self
	debug_overlay.z_index = 100   ## 调试标记必须压住 z=20 的爆炸和后创建的敌人
	add_child(debug_overlay)

	# 小怪：x 沿用 active_minion，m 刷点强制生成近战货运巡检员。
	if CorridorLevel.active_minion != "none":
		for i in level.enemy_spawns.size():
			var sp := level.enemy_spawns[i]
			var spawn_kind := CorridorLevel.active_minion
			if i < level.enemy_spawn_kinds.size() and not level.enemy_spawn_kinds[i].is_empty():
				spawn_kind = level.enemy_spawn_kinds[i]
			var m: Node2D
			if spawn_kind == "grunt":
				var g := GruntGunner.new()
				g.level = level
				m = g
			elif spawn_kind == "melee":
				var melee := FREIGHT_INSPECTOR_SCRIPT.new()
				melee.level = level
				m = melee
			else:
				m = KairullBoss.new()
			m.name = "Minion"
			m.player = player
			m.position = sp
			add_child(m)
			m.set_meta("spawn_cell", Vector2i(floori(sp.x / 32.0), floori(sp.y / 32.0)))
			if m.has_signal("shoot_orb"):
				m.connect("shoot_orb", _on_boss_shoot_orb)
			minions.append(m)

	# 关底 Boss：守在出口（类型由 CorridorLevel.active_boss 选择；"none" 不刷）
	if CorridorLevel.active_boss == "none":
		red_boss = null   ## 各使用点均已判空（_enemies/_physics_process/重置）
	elif CorridorLevel.active_boss == "hornet":
		red_boss = HornetBoss.new()
	else:
		red_boss = RedBoss.new()
	if red_boss != null:
		red_boss.name = "RedBoss"
		red_boss.player = player
		red_boss.level = level
		red_boss.position = level.exit_point if level.exit_point != Vector2.ZERO \
				else Vector2(150 * 32, 19 * 32)
		add_child(red_boss)
		red_boss.boss_died.connect(func() -> void: hud.show_msg("BOSS 击破！过关去 >"))

	# 房间门：D 刷点 → RoomDoor（在 player/minions 之后创建，
	# 保证门 _physics_process 的推出发生在角色移动之后）
	# D 标记在门洞左格；门洞 2 列宽，锚点右移半格（16px）到门洞中心，
	# 房间归属仍按 D 格算（门格属于"要守住的那个房间"）。
	for dp in level.door_spawns:
		var door := RoomDoor.new()
		door.name = "RoomDoor"
		door.room_idx = level.room_at(dp.x, dp.y - 1.0)   # 门格中心偏上 1px 防边界
		door.position = dp + Vector2(16.0, 0.0)
		door.game = self
		add_child(door)
		# 绘制序：压 backdrop/tiles/油漆、让位角色——穿过门洞时角色在黑洞口前
		# 可见；锁定时推出逻辑保证角色不与门板重叠，无需门板压角色
		move_child(door, player.get_index())
		doors.append(door)
	# 锁定门同时阻挡枪手视线和近战兵追击。
	for m in minions:
		if m is GruntGunner or m.has_method("attack_rect"):
			m.door_blockers = doors
	player.death_obstacles = doors  # 主角死亡惯性也要受独立门体阻挡。

	hud = GameHud.new()
	hud.name = "HUD"
	hud.host = self
	add_child(hud)
	_build_campaign_checkpoints()
	_setup_tactics()
	if timeline_enabled:
		var saved := RUN_SESSION.checkpoint_for(CorridorLevel.active_restart_scene)
		if RUN_CHECKPOINT.restore(self, saved):
			hud.show_msg("检查点续行 · %s · 前段进度已保留" % _checkpoint_name)
		elif not saved.is_empty():
			RUN_SESSION.clear_checkpoint() # 旧地图签名不匹配时安全回入口，不套用失效存点。
		var shade: Node2D = load("res://scripts/time_focus_shade.gd").new()
		shade.name = "TimeFocusShade"
		shade.host = self
		add_child(shade)
		var crt: CanvasLayer = load("res://scripts/crt_roll_transition.gd").new()
		crt.name = "CrtRollTransition"
		crt.host = self
		add_child(crt)
		# HUD/录像叠层只读时间数据，独立于被冻结的世界节点。
		var overlay_path := "res://scripts/time_signal_overlay.gd"
		if ResourceLoader.exists(overlay_path):
			var overlay = load(overlay_path).new()
			overlay.name = "TimeSignalOverlay"
			overlay.host = self
			add_child(overlay)
		victory_transition = load("res://scripts/victory_transition.gd").new()
		victory_transition.name = "VictoryTransition"
		victory_transition.host = self
		add_child(victory_transition)
		attempt_timeline.record(self, 0.0, true)
	pause_controller = load("res://scripts/pause_controller.gd").new()
	pause_controller.name = "PauseController"
	pause_controller.host = self
	add_child(pause_controller)


func _unhandled_input(event: InputEvent) -> void:
	# 兼容直接调用宿主输入的测试；正常窗口由PauseController._input先行消费Esc。
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if event.pressed and not event.echo and pause_controller != null:
			pause_controller.toggle_pause()
		return
	if pause_controller != null and pause_controller.active:
		return
	if event is InputEventKey and event.keycode in [KEY_F, KEY_K] and not debug_hotkeys_enabled:
		return
	# 必须是倒地提示出现后的新按下，长按攻击或按键回声不能跳过死亡读帧。
	if timeline_enabled and time_phase == "dying" and _death_prompt_ready:
		var new_press: bool = (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventJoypadButton and event.pressed)
		if new_press and not (event is InputEventKey and event.keycode == KEY_ESCAPE):
			_begin_rewind()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if timeline_enabled:
			if event.keycode == KEY_BACKSPACE:
				if time_phase == "playing" and not _transitioning and not level_cleared:
					_begin_rewind()
				return
			if time_phase != "playing":
				return  # 倒带中不接受旧快速复活，防止重复切场景或敌人不重置。
		if event.keycode == KEY_BACKSPACE:
			player.reset_to_spawn()
			_reset_original_kill_chain()
			_reset_bat_cargo()
			_enemy_knockbacks.clear()
			_clear_corpse_impacts()
			bullets.clear()
			enemy_bullets.clear()
			fx.clear()
			fx_layer.clear_explosions()
			clear_camera_shake()
			level_cleared = false
			_clear_elapsed = -1.0   ## 转场计时复位（未转场时淡黑一起归零）
			_fade_k = 0.0
			if hud != null:
				hud.set_fade(0.0)
			# 房间系统复位：重算所在房间/清房间卡；门状态由活敌派生，随帧自动回锁
			current_room = level.room_at(player.position.x, player.position.y - 1.0)
			if hud != null:
				hud._overlay.reset_room_card()
			# 小怪/道具与小怪尸体一致：不重生（重置只复位玩家与关卡流程）
			# Boss 连带重置：回血、回出口驻守位、清投掷物
			if red_boss != null and is_instance_valid(red_boss) 					and red_boss.has_method("reset_to"):
				red_boss.reset_to(level.exit_point if level.exit_point != Vector2.ZERO
						else Vector2(150 * 32, 19 * 32))
		elif event.keycode == KEY_ENTER and _can_restart_campaign():
			if timeline_enabled:
				if level_cleared:
					RUN_SESSION.clear_checkpoint() # 通关后明确重玩，从入口重新挑战整关。
				RUN_SESSION.next_attempt()
				_keep_music_on_exit = true
			_transitioning = true
			get_tree().call_deferred("change_scene_to_file", CorridorLevel.active_restart_scene)
		elif event.keycode == KEY_R:
			if KairullPlayer.GUN_ENABLED:
				player.start_reload()  # 纯球棒下R由玩家发烟雾投掷信号，宿主不能再投第二次。
		elif event.keycode == KEY_F and debug_hotkeys_enabled:
			debug = not debug


func return_to_main_menu() -> void:
	if _transitioning:
		return
	RUN_SESSION.leave_run() # 仅明确选择返回主菜单才结束挑战/清检查点，Esc本身绝不清档。
	_transitioning = true
	player.set_physics_process(false)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/surveillance_menu.tscn")


func retry_from_pause_menu() -> void:
	if _transitioning:
		return
	if timeline_enabled and not level_cleared:
		if time_phase not in ["rewinding", "interference"]:
			_begin_rewind()
		return # 已在短倒带就继续现有回放，不能重复计轮或提前切关。
	if not CorridorLevel.active_restart_scene.is_empty():
		if timeline_enabled:
			RUN_SESSION.clear_checkpoint()
			RUN_SESSION.next_attempt()
			_keep_music_on_exit = true
		_transitioning = true
		get_tree().call_deferred("change_scene_to_file", CorridorLevel.active_restart_scene)
	else:
		# 非主线老场景仍通过其既有Backspace重试，不改变旧关重生规则。
		var retry := InputEventKey.new()
		retry.keycode = KEY_BACKSPACE
		retry.pressed = true
		_unhandled_input(retry)


func _enemies() -> Array:
	var all: Array = []
	for m in minions:
		if is_instance_valid(m) and not m.dead:
			all.append(m)
	if red_boss != null and not red_boss.dead:
		all.append(red_boss)
	return all


## 新地图才创建战术对象；第一关和旧M02没有配置就不增加机关或补给。
func _setup_tactics() -> void:
	if CorridorLevel.active_tactical_objects.is_empty():
		return
	smoke_tactics = SMOKE_TACTICS_SCRIPT.new()
	smoke_tactics.name = "SmokeTactics"
	add_child(smoke_tactics)
	smoke_tactics.setup(level, doors, player)
	smoke_tactics.grenade_picked_up.connect(func(_at: Vector2) -> void:
		hud.show_msg("烟雾弹已拾取 · 按住 R 瞄准，左键投出"))
	for config: Dictionary in CorridorLevel.active_tactical_objects:
		var raw: Array = config.get("pos", [0, 0])
		if String(config.type) == "smoke_pickup":
			smoke_tactics.spawn_pickup(Vector2(raw[0], raw[1]))
			continue
		if String(config.type) == "freight_lift":
			var lift: Node2D = FREIGHT_LIFT_SCRIPT.new()
			lift.name = "FreightLift_%d" % moving_lifts.size()
			add_child(lift)
			lift.setup(config, level, doors)
			moving_lifts.append(lift)
			continue
		if bool(config.get("hard_only", false)) and RUN_SESSION.difficulty not in ["hard", "zero"]:
			continue
		var hazard: Node2D = TACTICAL_HAZARD_SCRIPT.new()
		hazard.name = "TacticalHazard_%d" % tactical_hazards.size()
		add_child(hazard)
		hazard.setup(config, level, doors)
		hazard.set_meta("room_index", _room_index_for_id(String(config.get("room_id", ""))))
		hazard.projectile_requested.connect(_on_tactical_projectile)
		hazard.sound_requested.connect(_on_tactical_sound)
		hazard.destroyed.connect(func(at: Vector2) -> void:
			fx.append({"x": at.x, "y": at.y, "life": 0.18, "kind": "spark"}))
		tactical_hazards.append(hazard)
	for enemy: Node2D in minions:
		if enemy is GruntGunner or enemy is FreightInspector:
			enemy.vision_blocker = Callable(smoke_tactics, "blocks_segment")
	player.moving_platforms = moving_lifts
	player.death_obstacles = _world_blockers()
	smoke_tactics.doors = _world_blockers()
	for hazard: Node2D in tactical_hazards:
		hazard.door_blockers = _world_blockers()
	if hud != null:
		if CorridorLevel.active_encounter_policy == "same_floor_nearby":
			hud.show_msg("垂直货运井 · 井底起步，逐层上攀 · 中枢检查点 / 塔冠撤离")
		else:
			hud.show_msg("时差货运场 · 按住 R＋左键投烟 · 高光栅可低身翻滚")


func _room_index_for_id(id: String) -> int:
	for index in level.rooms.size():
		if String(level.rooms[index].get("room_id", "")) == id:
			return index
	return -1


func _step_tactics(dt: float) -> void:
	if smoke_tactics == null:
		return
	for lift: Node2D in moving_lifts:
		lift.advance(dt)
		lift.carry_rider(player)
	smoke_tactics.step(dt)
	if not player.dead and not level_cleared:
		smoke_tactics.try_pickup(player)
	var view := Rect2(cam_tl, Vector2(VW, VH))
	for hazard: Node2D in tactical_hazards:
		var room_index: int = hazard.get_meta("room_index", -1)
		# 清房停机是永久状态；不能离开/回来又重启，也不要求把设备计入清敌数。
		if hazard.hazard_type == "auto_sniper" and room_index >= 0 \
				and room_total_count(room_index) > 0 and room_alive_count(room_index) == 0:
			hazard.deactivate_cleared()
		var allowed := not player.dead and not level_cleared and room_index == current_room \
				and view.has_point(hazard.position)
		hazard.set_armed(allowed)
		var obscured: bool = smoke_tactics.contains_actor(player) \
				or smoke_tactics.blocks_segment(hazard.muzzle_position(), _player_hurtbox().get_center())
		hazard.advance(dt, player, obscured)
		if hazard.damage_active() and hazard.damage_rect().intersects(_player_hurtbox()):
			player.take_damage(1, hazard.damage_rect().get_center().x)
			if player.dead:
				break
	_refresh_smoke_cover()


func _on_tactical_projectile(origin: Vector2, velocity: Vector2, damage_type: StringName) -> void:
	enemy_bullets.append({"x": origin.x, "y": origin.y, "vx": velocity.x, "vy": velocity.y,
			"life": 2.0, "damage_type": damage_type, "sniper": true})
	play_sfx("shot_r1") # 用原短促锋利的枪声，不用轻柔合成击杀/提示声冒充狙击触发。


func _on_tactical_sound(event: StringName) -> void:
	if event == &"sniper_lock":
		play_sfx("empty") # 锁定时一个机械卡扣；半秒后独立的强枪声才代表真正出弹。
	else:
		play_action(event)


func _on_smoke_throw_requested(target: Vector2) -> void:
	if smoke_tactics == null or player.dead or level_cleared \
			or (timeline_enabled and time_phase != "playing"):
		return
	smoke_tactics.throw_from(player, target) # 只有成功创建弹体的系统会消费背包，不在信号层扣两次。


func _player_in_smoke() -> bool:
	return smoke_tactics != null and smoke_tactics.contains_actor(player)


func _refresh_smoke_cover() -> void:
	if smoke_tactics == null or player == null:
		return
	player.set_smoke_cover(smoke_tactics.contains_actor(player))
	for enemy: Node2D in minions:
		if not is_instance_valid(enemy) or not (enemy is GruntGunner or enemy is FreightInspector):
			continue
		var sprite: Sprite2D = enemy._sprite
		if not sprite.has_meta("smoke_base_tint"):
			sprite.set_meta("smoke_base_tint", sprite.self_modulate)
		var base: Color = sprite.get_meta("smoke_base_tint")
		var covered: bool = smoke_tactics.contains_actor(enemy)
		# 烟内改成实色深剪影，不靠降低透明度把人抹没；玩家浅青边，敌人暗灰边。
		sprite.self_modulate = base * Color(0.07, 0.11, 0.13, 1.0) if covered else base
		var outline_material := enemy._outline.material as ShaderMaterial
		if not sprite.has_meta("smoke_base_outline"):
			var original_outline: Variant = outline_material.get_shader_parameter("outline_color")
			# shader默认值未写入material时getter可返回null；set_meta(null)会删键，须显式回填原色。
			if original_outline == null:
				original_outline = Color(0.09, 0.05, 0.14, 1.0)
			sprite.set_meta("smoke_base_outline", original_outline)
		outline_material.set_shader_parameter("outline_color", Color(0.25, 0.31, 0.33, 1.0)
				if covered else sprite.get_meta("smoke_base_outline"))
		if covered:
			enemy._rim.visible = false
		elif not enemy.dead:
			enemy._rim.visible = true
	# 主角时停中仍能走进现有烟：取消锁定属于失去目标，不推进机关计时。
	for hazard: Node2D in tactical_hazards:
		if hazard.hazard_type == "auto_sniper" and hazard.state in ["warning", "locked"]:
			if smoke_tactics.contains_actor(player) \
					or smoke_tactics.blocks_segment(hazard.muzzle_position(), _player_hurtbox().get_center()):
				hazard.advance(0.0, player, true)


func _cargo_targets() -> Array:
	var result := _enemies()
	for hazard: Node2D in tactical_hazards:
		if is_instance_valid(hazard) and not hazard.dead and hazard.hazard_type == "auto_sniper":
			result.append(hazard)
	return result


func _world_blockers() -> Array:
	# 电梯的钢台面挡实体弹/抛投/尸体，但不加入按清敌数开关的RoomDoor数组。
	var result: Array = doors.duplicate()
	result.append_array(moving_lifts)
	return result


## 生成一个互动物件并注册进命中/步进循环（测试也可直接调用补道具）
func _spawn_prop(kind: String, pos: Vector2) -> Node2D:
	var pr: Node2D
	if kind == "barrel":
		var b := PropBarrel.new()
		b.exploded.connect(_on_barrel_exploded)
		pr = b
	elif kind == "crt":
		var c := PropCrt.new()
		c.shattered.connect(_on_crt_shattered)
		pr = c
	elif kind == "bat_cargo" and bat_cargo_enabled:
		var cargo := BAT_CARGO_SCRIPT.new()
		cargo.impacted.connect(_on_bat_cargo_impacted)
		pr = cargo
	else:
		return null
	pr.name = "Prop_%s" % kind
	pr.position = pos
	pr.set_meta("checkpoint_key", "%s:%d:%d" % [kind, roundi(pos.x), roundi(pos.y)])
	add_child(pr)
	props.append(pr)
	return pr


## 仅复位新货箱，保留原版重置不复活已清敌人/爆炸桶/CRT 的语义。
func _reset_bat_cargo() -> void:
	_bat_prop_origin_valid = false
	for prop: Node2D in props:
		if is_instance_valid(prop) and prop is PropBatCargo:
			prop.reset_to_spawn()


func _flying_cargo_count() -> int:
	var count := 0
	for prop: Node2D in props:
		if is_instance_valid(prop) and prop is PropBatCargo and prop.flying:
			count += 1
	return count


## 远端命中沿用正式彩色液爆、死亡和击退链，不给远处玩家施加顿帧。
func _on_bat_cargo_impacted(cargo: PropBatCargo, target: Node2D, direction: Vector2) -> void:
	var center := cargo.body_rect().get_center()
	fx.append({"x": center.x, "y": center.y, "life": 0.12, "kind": "spark"})
	play_action("cargo_impact")
	if target == null or not is_instance_valid(target) or target.dead:
		return
	if target.get_script() == TACTICAL_HAZARD_SCRIPT:
		target.take_hit(center.x, 1)
		return  # 自动狙击是可击毁器械，只出金属反馈，不喷生物血/不计小兵。
	var impact: Vector2 = target.body_rect().get_center()
	var before_x: float = target.position.x
	if not target.take_hit(center.x, 1):
		return
	var lethal: bool = target.dead
	var burst := fx_layer.spawn_bat_hit(impact, direction, 1.2 if lethal else 0.9, lethal, target)
	_start_enemy_knockback(target, direction, maxi(1, cargo.launch_stage), lethal,
			target.position.x - before_x)
	if lethal:
		play_action("enemy_kill")
		paint_layer.blood_pool(impact, 1.0, 0, burst.current_color.darkened(0.15))
	else:
		play_action("body_hit")
	# 震屏随距离衰减，屏外碎箱不打断眼前角色的视觉稳定性。
	var proximity := clampf(1.0 - player.position.distance_to(impact) / 700.0, 0.0, 1.0)
	add_camera_shake(direction, 0.4 * proximity)


## 爆炸桶引爆：液爆 + 半径清怪 + 连锁其它桶（短引信错峰）+ 震屏 + 焦痕。
## 武士零惯例：爆炸不伤玩家，这里同样不判玩家伤害。
func _on_barrel_exploded(barrel: PropBarrel) -> void:
	var center := barrel.body_rect().get_center()
	fx_layer.spawn_explosion(center, 1.4)
	add_camera_shake((player.position - center).normalized(), 1.2)
	play_action("explosion")
	# 焦痕：沿用血泊投影约定，压成近黑的烧蚀色（主斑 + 偏移小斑）。
	# 注：stamp_origin_burst 的短边喷射痕经 _roughen 取整后偶发退化多边形
	# （渲染服务器报 triangulation failed），这里改用双血泊避坑。
	paint_layer.blood_pool(center, 1.3, 0, Color("#171014"))
	paint_layer.blood_pool(center + Vector2(14, 0), 0.7, 0, Color("#241a18"))
	for m in minions:
		if not is_instance_valid(m) or m.dead:
			continue
		if m.body_rect().get_center().distance_to(center) > PropBarrel.KILL_RADIUS:
			continue
		if m.take_hit(center.x, 1) and m.dead:
			play_action("enemy_kill")
			_start_corpse_impact(m, 1, signf(m.position.x - center.x))
			var dir: Vector2 = (m.body_rect().get_center() - center).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.UP
			var burst := fx_layer.spawn_bat_hit(m.body_rect().get_center(), dir, 1.0, true, m)
			paint_layer.blood_pool(m.body_rect().get_center(), 1.0, 0,
					burst.current_color.darkened(0.15))
	# 连锁：半径内其它活桶点短引信（≈6 tick 错峰连爆）
	for pr in props:
		if pr is PropBarrel and pr != barrel and not pr.dead:
			if pr.body_rect().get_center().distance_to(center) <= PropBarrel.KILL_RADIUS:
				pr.take_hit(center.x, 1, PropBarrel.CHAIN_FUSE)


## CRT 碎裂：低音玻璃碎响 + 小青渍（碎屑与闪白由 CRT 节点自绘）
func _on_crt_shattered(crt: PropCrt) -> void:
	play_action("glass_break")
	add_camera_shake(Vector2.UP, 0.18)
	paint_layer.blood_pool(crt.body_rect().get_center(), 0.5, 0, Color("#0d3038"))


## 房间内活敌数（room_idx 无效时返回 -1）
func room_alive_count(room_idx: int) -> int:
	if room_idx < 0 or room_idx >= level.rooms.size():
		return -1
	var rect: Rect2i = level.rooms[room_idx]["rect"]
	var alive := 0
	for m in minions:
		if is_instance_valid(m) and not m.dead:
			## 按初始刷点归属（敌人走动跨房间不串计数）
			var cell: Vector2i = m.get_meta("spawn_cell", Vector2i(floori(
					m.position.x / 32.0), floori(m.position.y / 32.0)))
			if rect.has_point(cell):
				alive += 1
	return alive


## 房间内敌人总数（按刷点归属；房间卡 x/N 的分母）
func room_total_count(room_idx: int) -> int:
	if room_idx < 0 or room_idx >= level.rooms.size():
		return -1
	var rect: Rect2i = level.rooms[room_idx]["rect"]
	var total := 0
	for sp in level.enemy_spawns:
		if rect.has_point(Vector2i(floori(sp.x / 32.0), floori(sp.y / 32.0))):
			total += 1
	return total


func _physics_process(dt: float) -> void:
	if pause_controller != null and pause_controller.active:
		return
	if timeline_enabled and level_cleared:
		_begin_victory()
		return # 通关字幕期间不再推进伤害/机关，不能在淡黑中被残弹击杀。
	if timeline_enabled:
		_advance_time_charge(dt)
		if time_charge.active or time_phase != "playing":
			for lift: Node2D in moving_lifts:
				lift.advance(0.0) # 丢弃上一帧承载位移；时停和死亡冻结后不再重复带人。
			if smoke_tactics != null and time_phase == "playing":
				smoke_tactics.step(0.0) # 玩家能在时停中瞄准/捡取，烟与弹的世界寿命不走。
				smoke_tactics.try_pickup(player)
				_refresh_smoke_cover()
			return  # 敌人逻辑 tick、子弹、货箱、伤害与击退全冻结；玩家自身 step 仍运行。
	_step_tactics(dt)
	if timeline_enabled and player.dead:
		return
	# 道具推进（爆炸桶引信 / CRT 碎屑）；过关冻结后依然推进，让余爆播完
	for pr in props:
		if is_instance_valid(pr):
			if bool(pr.get_meta("checkpoint_spent", false)):
				continue
			if pr is PropBatCargo:
				pr.highlighted = not player.dead and not level_cleared \
						and not player.batting() and not player.rolling() and not player.dashing() \
						and absf(player.position.x - pr.position.x) < 112.0 \
						and absf(player.position.y - pr.position.y) < 48.0
			pr.step(dt)
			if pr is PropBatCargo and pr.flying:
				pr.advance(dt, level, _cargo_targets(), _world_blockers())
	# 敌人推进 + 近战火拼判定（过关后冻结活体 AI，已死亡者仍播完倒地收尾）
	if not level_cleared:
		for m in minions:
			if is_instance_valid(m):
				if bool(m.get_meta("checkpoint_cleared", false)):
					continue # 已清前半段仍计入清敌分母，但不复活、播尸体或执行离屏脚本。
				if not _campaign_enemy_released(m):
					# 未进入下段时仅播慢呼吸，不让隔壁近战兵提前冲进补给房。
					if m is GruntGunner or m is FreightInspector:
						m._anim_clock += dt
						m._sync_sprite()
					continue
				m.step(dt)
				# 新近战兵只用短攻击盒有效窗；旧敌人保留原身体碰撞兼容分支。
				if m.has_method("attack_active") and m.has_method("attack_rect"):
					if m.attack_active() and m.attack_rect().intersects(_player_hurtbox()):
						player.take_damage(1, m.position.x)
				elif m.state == "attack" and m.frame >= 4 and not m.dead:
					if m.body_rect().intersects(_player_hurtbox()):
						player.take_damage(1, m.position.x)
				if timeline_enabled and player.dead:
					return  # 致死信号已冻结世界，不再推进同帧排在后面的敌人/弹道。
		if red_boss != null:
			red_boss.step(dt)
			if red_boss.attack_active() and not red_boss.dead:
				if red_boss.body_rect().intersects(_player_hurtbox()):
					player.take_damage(1, red_boss.position.x)
			if timeline_enabled and player.dead:
				return
	else:
		for m in minions:
			if is_instance_valid(m) and m.dead:
				m.step(dt)
	# 放在敌人 AI 之后推进：活体不会抵消受击方向，尸体也不受 dead 早退影响。
	_update_enemy_knockbacks(dt)
	_refresh_smoke_cover()
	# 玩家子弹推进 + 撞地形/敌人
	for b in bullets:
		b["x"] += b["vx"] * dt
		b["y"] += b["vy"] * dt
		b["life"] -= dt
		var hit := false
		for e in _enemies():
			if e.body_rect().has_point(Vector2(b["x"], b["y"])):
				hit = true
				if e.take_hit(b["x"], 1):
					var force_direction := Vector2(b["vx"], b["vy"]).normalized()
					if e.dead:
						play_sfx("gkill%d" % (randi() % 4 + 1))
						play_sfx("slime_death")
						# 受力方向取致命子弹速度；关底 Boss 使用更大液爆强度。
						var blast_power := 1.55 if e == red_boss else 1.0
						var burst := fx_layer.spawn_slime_burst(
								e.body_rect().get_center(), force_direction, blast_power)
						# 地面留泊与本次爆裂同色相（略压暗，像积液）
						paint_layer.blood_pool(e.body_rect().get_center(), 1.0, 0,
								burst.current_color.darkened(0.15))
					else:
						play_sfx("ghit%d" % (randi() % 4 + 1))
						play_sfx("slime_hit")
						fx_layer.spawn_slime_hit(Vector2(b["x"], b["y"]), force_direction, 0.22)
				break
		if hit or level.solid_at(b["x"], b["y"]):
			b["life"] = 0.0
			fx.append({"x": b["x"], "y": b["y"], "life": 0.16, "kind": "spark"})
	bullets = bullets.filter(func(b: Dictionary) -> bool: return b["life"] > 0.0)
	if _advance_enemy_bullets(dt):
		return  # 与原逻辑一致：时停循环内致死后不再推进同帧余下弹道。
	for f in fx:
		f["life"] -= dt
	fx = fx.filter(func(f: Dictionary) -> bool: return f["life"] > 0.0)
	# 出口判定：玩家站在塔门口地面层 → 过关（冻结敌人 + HUD CLEAR 卡，Backspace 可重置）
	# trigger_rect = 门宽×64px 贴地紧矩形（不用 92px 全高视觉体，隔空/高台不触发）
	# 清场闸门（active_exit_requires_boss）：小怪未清 / Boss 存活时出口锁定不放行，
	# 门体亮暗红边光；解锁瞬间播一声金属回响（RoomDoor 同款升调）。
	if exit_door != null:
		var gated := _exit_gated()
		if gated != exit_door.locked:
			exit_door.locked = gated
			if not gated:
				play_action("door_unlock")
	if not level_cleared and exit_door != null and not player.dead \
			and not _exit_gated():
		if exit_door.trigger_rect().intersects(_player_rect()):
			level_cleared = true
			_clear_elapsed = 0.0
			_begin_victory()


## 出口清场闸门：仅 active_exit_requires_boss 开启时生效（HK 竞技场 Boss 必打）。
## 放行条件 = 所有小怪死亡/缺席（竞技场 minion=none 即天然满足）
## 且关底 Boss（hornet/red，若本场景刷了）已死。默认关/M02 该开关为 false，
## 出口维持旧行为（到门即过关；M02 的清怪由房门各自强制）。
func _exit_gated() -> bool:
	if not CorridorLevel.active_exit_requires_boss:
		return false
	for m in minions:
		if is_instance_valid(m) and not m.dead:
			return true
	if red_boss != null and is_instance_valid(red_boss) and not red_boss.dead:
		return true
	return false


func _player_rect() -> Rect2:
	# 这是行走物理盒；出口/门仍使用原尺寸，不能被站立头部受击范围扩大。
	return Rect2(player.position.x - player.w / 2, player.position.y - player.h,
			player.w, player.h)


func _player_hurtbox() -> Rect2:
	return player.hurtbox_rect()  # 站立覆盖头部，翻滚只保留贴地低框；不改地图物理预算。


## Boss法球/枪手弹共用连续扫掠：每个小步先墙、锁门、油桶，再检查角色。
## 仍交给take_damage处理冲刺/翻滚无敌，不把视觉低姿态等同于全程无敌。
func _advance_enemy_bullets(dt: float) -> bool:
	for orb in enemy_bullets:
		if float(orb["life"]) <= 0.0:
			continue
		var origin := Vector2(orb["x"], orb["y"])
		var travel_dt := minf(maxf(dt, 0.0), float(orb["life"]))
		var displacement := Vector2(orb["vx"], orb["vy"]) * travel_dt
		var substeps := maxi(1, ceili(displacement.length() / ENEMY_BULLET_SWEEP_STEP))
		orb["life"] -= dt
		for index in range(1, substeps + 1):
			var point := origin + displacement * (float(index) / float(substeps))
			orb["x"] = point.x
			orb["y"] = point.y
			var blocked := level.solid_at(point.x, point.y)
			if not blocked:
				for door in _world_blockers():
					if is_instance_valid(door) and door.locked and door.body_rect().has_point(point):
						blocked = true
						break
			if not blocked:
				for prop in props:
					if prop is PropBarrel and not prop.dead and prop.body_rect().grow(2.0).has_point(point):
						prop.take_hit(origin.x, 1)
						blocked = true
						break
			if blocked:
				orb["life"] = 0.0
				fx.append({"x": point.x, "y": point.y, "life": 0.14, "kind": "spark"})
				break
			if _player_hurtbox().has_point(point):
				orb["life"] = 0.0
				# 用本帧起点判定受力侧；弹道不能先越过角色中心再反向击退。
				# 烟幕只保护枪击；近战/压机/激光仍走各自伤害入口，绝不变成全伤害无敌。
				if String(orb.get("damage_type", "gunshot")) != "gunshot" or not _player_in_smoke():
					player.take_damage(1, origin.x)
				if timeline_enabled and player.dead:
					enemy_bullets = enemy_bullets.filter(func(item: Dictionary) -> bool: return item["life"] > 0.0)
					return true
				break
	enemy_bullets = enemy_bullets.filter(func(item: Dictionary) -> bool: return item["life"] > 0.0)
	return false


func _on_boss_shoot_orb(from_pos: Vector2, velocity: Vector2) -> void:
	enemy_bullets.append({"x": from_pos.x, "y": from_pos.y,
			"vx": velocity.x, "vy": velocity.y, "life": 3.0})
	play_action("enemy_shot")  # 枪口出膛是短促机械爆破，不能拿肉体受伤声代替。


func _process(dt: float) -> void:
	if pause_controller != null and pause_controller.active:
		return
	if timeline_enabled and level_cleared:
		_begin_victory()
		_update_victory_next_level()
		return # 胜利黑幕由独立CanvasLayer按真实时间渐入；旧CLEAR卡/转场不叠播。
	_refresh_smoke_cover()
	if timeline_enabled and time_phase in ["rewinding", "interference"]:
		_advance_rewind(dt)
		return
	_update_room_state()
	_update_campaign_progress(dt)
	_update_clear_transition(dt)
	var target := _cam_target()
	# 换房滑镜：0.25s 内快速就位；平时保持原 0.10 缓动
	var lerp_k := 0.10
	if _cam_room_boost > 0.0:
		_cam_room_boost -= dt
		lerp_k = clampf(dt / 0.25 * 3.0, 0.10, 0.35)
	cam_tl += (target - cam_tl) * lerp_k
	# 像素对齐：相机位置取整，跑动时人物边缘不再 1px 抖动发虚
	cam.position = (cam_tl + Vector2(VW, VH) * 0.5).round()
	_update_camera_shake(dt)
	_sync_temporal_projection()
	if timeline_enabled and not level_cleared:
		# 死亡提示等待期间不继续录空白，避免长时间等待把整轮动作抽稀。
		if not _death_prompt_ready:
			attempt_timeline.record(self, dt)
		if time_phase == "dying":
			_death_elapsed += dt
			if _death_elapsed >= DEATH_HOLD:
				_death_prompt_ready = true


## 房间系统：跟踪玩家所在房间；换房时弹房间卡 + 相机快速滑镜。
## 门的锁定状态由各 RoomDoor 每帧自查（room_alive_count 派生）。
func _update_room_state() -> void:
	if level.rooms.is_empty():
		return
	var prev := current_room
	current_room = level.room_at(player.position.x, player.position.y - 1.0)
	if current_room == prev:
		return
	if current_room >= 0:
		_visited_rooms[current_room] = true
		_campaign_frontier = maxi(_campaign_frontier, current_room)
		_cam_room_boost = 0.25
		var total := room_total_count(current_room)
		var alive := room_alive_count(current_room)
		if hud != null:
			hud._overlay.show_room_card(level.rooms[current_room]["name"], alive, total)


## 新关卡返回点由 LDtk 房间元数据给出；不复制一份硬编码的坐标表。
func _build_campaign_checkpoints() -> void:
	if not CorridorLevel.active_campaign_mode:
		return
	# 新长关只需要遭遇段边界，不借记录点/补血字段实现唤醒控制。
	for boundary in CorridorLevel.active_encounter_boundaries:
		if not _campaign_boundaries.has(int(boundary)):
			_campaign_boundaries.append(int(boundary))
	for index in level.rooms.size():
		var raw: Array = level.rooms[index].get("checkpoint_cell", [])
		if raw.size() != 2:
			continue
		_campaign_boundaries.append(index)
		if timeline_enabled:
			continue  # 旧房间字段仅保留遭遇边界；正式单检查点由独立元数据定义。
		var beacon := CHECKPOINT_BEACON_SCRIPT.new()
		beacon.name = "Checkpoint_%d" % index
		beacon.position = Vector2(int(raw[0]) * 32 + 16, (int(raw[1]) + 1) * 32 - 0.1)
		add_child(beacon)
		move_child(beacon, player.get_index())
		_checkpoint_beacons[index] = beacon
	if timeline_enabled:
		for config: Dictionary in CorridorLevel.active_checkpoints:
			var index := int(config.room_index)
			var cell: Array = config.cell
			var beacon := CHECKPOINT_BEACON_SCRIPT.new()
			beacon.name = "RunCheckpoint_%d" % index
			beacon.run_checkpoint = true
			if CorridorLevel.active_encounter_policy == "same_floor_nearby":
				beacon.locked_hint = "清下半塔后解锁" # 中枢就在出生层，明确B3～B1先清再回来记录。
			beacon.position = Vector2(int(cell[0]) * 32 + 16, (int(cell[1]) + 1) * 32 - .1)
			add_child(beacon)
			move_child(beacon, player.get_index())
			_checkpoint_beacons[index] = beacon
			_checkpoint_configs[index] = config.duplicate(true)


func _run_checkpoint_unlocked(config: Dictionary) -> bool:
	for room: int in config.required_clear_rooms:
		if room_alive_count(room) != 0:
			return false
	return true


func _rooms_before_cleared(room_index: int) -> bool:
	for index in range(room_index + 1):
		if room_alive_count(index) > 0:
			return false
	return true


## 安全中继站是遭遇段边界，不是隐形碰撞墙。进入下段后即永久唤醒，退回不能睡掉追兵。
func _campaign_enemy_released(enemy: Node2D) -> bool:
	if not CorridorLevel.active_campaign_mode or enemy.dead:
		return true
	var cell: Vector2i = enemy.get_meta("spawn_cell", Vector2i(-1, -1))
	if CorridorLevel.active_encounter_policy == "same_floor_nearby":
		if bool(enemy.get_meta("spatial_awake", false)):
			return true
		var spawn_feet := Vector2(cell.x * 32.0 + 16.0, (cell.y + 1) * 32.0 - 0.1)
		var nearby := absf(spawn_feet.y - player.position.y) <= 160.0 \
				and absf(spawn_feet.x - player.position.x) <= 900.0
		if nearby:
			enemy.set_meta("spatial_awake", true) # 首次接近才醒；退回/换层不能让追兵强制睡掉。
		return nearby
	var spawn_room := level.room_at(cell.x * 32 + 16, cell.y * 32 + 16)
	for checkpoint_room: int in _campaign_boundaries:
		if spawn_room > checkpoint_room and _campaign_frontier <= checkpoint_room:
			return false
	return true


## 前段清场后站近终端才记录返回点；越过敌人不能免费跳过整段战斗。
func _update_campaign_progress(dt: float) -> void:
	if pause_controller != null and pause_controller.active:
		return
	if not player.dead and not level_cleared:
		_run_elapsed += maxf(0.0, dt)
	if not CorridorLevel.active_campaign_mode:
		return
	for key: int in _checkpoint_beacons:
		var beacon: Node2D = _checkpoint_beacons[key]
		var unlocked := _run_checkpoint_unlocked(_checkpoint_configs[key]) if timeline_enabled \
				else _rooms_before_cleared(key)
		beacon.set_status(unlocked, key <= _checkpoint_index)
		if key <= _checkpoint_index or not unlocked or player.dead or level_cleared \
				or (timeline_enabled and time_phase != "playing"):
			continue
		if player.on_ground and absf(player.position.x - beacon.position.x) <= 72.0 \
				and absf(player.position.y - beacon.position.y) <= 12.0:
			var nearby_enemy := false
			for enemy: Node2D in minions:
				if is_instance_valid(enemy) and not enemy.dead and absf(enemy.position.x - beacon.position.x) < 160.0 \
						and absf(enemy.position.y - beacon.position.y) < 120.0:
					nearby_enemy = true
			if timeline_enabled and nearby_enemy:
				continue # 追兵进入终端旁时暂不保存，不能把重生点设在贴脸攻击中。
			_checkpoint_index = key
			_checkpoint_name = String(level.rooms[key].get("name", "补给点"))
			player.spawn = beacon.position
			player.hp = player.max_hp
			player.invuln_t = maxf(player.invuln_t, 0.6)
			if timeline_enabled:
				# 时停中到达存点只补容量，不偷清active；否则松键时会漏掉统一解冻/音乐复原沿。
				if time_charge.active:
					time_charge.energy = CHRONO_CHARGE.MAX_DURATION
				else:
					time_charge.reset()
				RUN_SESSION.save_checkpoint(CorridorLevel.active_restart_scene,
						RUN_CHECKPOINT.capture(self, _checkpoint_configs[key], beacon.position))
			beacon.set_status(true, true)
			play_action("checkpoint")
			if hud != null:
				hud.show_msg("检查点已激活 · 生命/时停补满 · 失败从此续行" if timeline_enabled else "补给完成 · 返回点已同步")


## UI 只读接口：计数按出生房间归属，不因敌人移动跨房导致进度跳变。
func run_progress() -> Dictionary:
	var defeated := 0
	for enemy: Node2D in minions:
		if not is_instance_valid(enemy) or enemy.dead:
			defeated += 1
	var completed := 0
	var completed_rooms: Array[int] = []
	for index in level.rooms.size():
		var cleared := false
		if room_total_count(index) > 0:
			cleared = room_alive_count(index) == 0
		else:
			cleared = _visited_rooms.has(index)
		if cleared:
			completed += 1
			completed_rooms.append(index)
	return {"elapsed": _run_elapsed, "enemies_total": minions.size(),
		"enemies_defeated": defeated, "rooms_total": level.rooms.size(),
		"rooms_cleared": completed, "rooms_completed": completed_rooms,
		"checkpoint": _checkpoint_name if _checkpoint_index >= 0 else "关卡入口",
		"checkpoint_index": _checkpoint_index, "is_extended": CorridorLevel.active_campaign_mode}


func _can_restart_campaign() -> bool:
	if not victory_next_scene().is_empty():
		return false # 第一/二关等待自动接续，Enter不抢先把当前关重开。
	if timeline_enabled and level_cleared and victory_transition != null and not victory_transition.is_ready():
		return false
	return CorridorLevel.active_campaign_mode and not CorridorLevel.active_restart_scene.is_empty() \
			and (player.dead or level_cleared) and not _transitioning


func victory_next_scene() -> String:
	if not timeline_enabled or not level_cleared:
		return ""
	return RUN_SESSION.next_scene_after(CorridorLevel.active_restart_scene)


func _update_victory_next_level() -> void:
	if _transitioning or (pause_controller != null and pause_controller.active) \
			or victory_transition == null or victory_transition.elapsed < NEXT_LEVEL_DELAY:
		return
	var target := victory_next_scene()
	if target.is_empty():
		return
	_transitioning = true # 先锁住，再延迟切关，防止同帧多次请求。
	RUN_SESSION.enter_next_level(target)
	_keep_music_on_exit = true # 三关同曲沿用原播放器/Playback，不归零。
	get_tree().call_deferred("change_scene_to_file", target)


func _begin_victory() -> void:
	if not timeline_enabled or not level_cleared or _victory_started:
		return
	_victory_started = true
	# 成功结尾不是死亡：不启动倒带/故障、不停音乐，只停止角色和伤害并让画面慢慢入黑。
	time_charge.cancel()
	_set_player_time_focus(false)
	_set_temporal_nodes_paused(false)
	if music != null:
		music.pitch_scale = 1.0
	hud.visible = false
	var signal_overlay := get_node_or_null("TimeSignalOverlay")
	if signal_overlay != null:
		signal_overlay.set_process(false)
		signal_overlay.visible = false
	player.keys.clear()
	player._prev_keys.clear()
	player.set_physics_process(false)
	clear_camera_shake()
	for hazard: Node2D in tactical_hazards:
		hazard.set_armed(false)


## 过关转场：CLEAR 卡停留 CLEAR_HOLD 秒 → FADE_TIME 秒淡黑 → 切下一幕。
## active_next_scene 为空时保持旧行为（CLEAR 卡常驻，不淡出不转场）。
## 计时走 _process 的 dt 累加（无头测试可手动步进），不依赖真实墙钟。
func _update_clear_transition(dt: float) -> void:
	if _clear_elapsed < 0.0 or _transitioning:
		return
	if CorridorLevel.active_next_scene.is_empty():
		return
	_clear_elapsed += dt
	if _clear_elapsed < CLEAR_HOLD:
		return
	_fade_k = clampf((_clear_elapsed - CLEAR_HOLD) / FADE_TIME, 0.0, 1.0)
	if hud != null:
		hud.set_fade(_fade_k)
	if _fade_k >= 1.0:
		_transitioning = true
		# 延迟到帧末切场景：避免在 game 自身方法栈里立即 memdelete 整棵子树
		get_tree().call_deferred("change_scene_to_file", CorridorLevel.active_next_scene)


## 屏幕震荡保留致命受力方向：先向反方向踉跄，再叠加短促高频抖动。
func add_camera_shake(force_direction: Vector2, power := 1.0) -> void:
	var direction := force_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	camera_shake_direction = direction
	camera_trauma = clampf(camera_trauma + 0.52 * clampf(power, 0.10, 2.0), 0.0, 1.0)
	camera_shake_time = 0.0


func _update_camera_shake(dt: float) -> void:
	if camera_trauma <= 0.0:
		cam.offset = Vector2.ZERO
		return
	camera_shake_time += dt
	camera_trauma = maxf(0.0, camera_trauma - dt * 2.35)
	var envelope := camera_trauma * camera_trauma
	var directional_kick := -camera_shake_direction * camera_trauma * 11.0
	var jitter := Vector2(
		sin(camera_shake_time * 73.0) * 8.0,
		sin(camera_shake_time * 97.0 + 1.3) * 5.5) * envelope
	cam.offset = (directional_kick + jitter).round()


func clear_camera_shake() -> void:
	camera_trauma = 0.0
	camera_shake_direction = Vector2.ZERO
	if cam != null:
		cam.offset = Vector2.ZERO


## 网页版同款相机目标：朝向侧多留视野，钳制在世界边界内；
## 有房间表时再钳进当前房间（房间小于视口则居中——房框取景，武士零式）
func _cam_target() -> Vector2:
	var tx: float = player.position.x - VW * 0.42 * (1.0 if player.face > 0 else 0.9) - VW * 0.06
	var ty: float = player.position.y - VH * 0.62
	var max_tx := maxf(0.0, level.world_w - VW)
	var max_ty := maxf(0.0, level.world_h - VH)
	if current_room >= 0 and current_room < level.rooms.size():
		var rr: Rect2i = level.rooms[current_room]["rect"]
		var r_min := Vector2(rr.position.x * CorridorLevel.TS, rr.position.y * CorridorLevel.TS)
		var r_max := Vector2(rr.end.x * CorridorLevel.TS, rr.end.y * CorridorLevel.TS)
		tx = _clamp_room_axis(tx, r_min.x, r_max.x, VW)
		ty = _clamp_room_axis(ty, r_min.y, r_max.y, VH)
	return Vector2(clampf(tx, 0.0, max_tx), clampf(ty, 0.0, max_ty))


## 单轴房框钳制：房间比视口宽则正常 clamp；比视口窄则居中
func _clamp_room_axis(v: float, r_min: float, r_max: float, view: float) -> float:
	if r_max - r_min <= view:
		return r_min - (view - (r_max - r_min)) * 0.5
	return clampf(v, r_min, r_max - view)


## 登记一次球棒击退。三连段逐段加力，关底 Boss 保留抗击退；同一敌人重入时
## 替换旧冲量而不是叠加，避免高频命中把目标无限加速。
func _start_enemy_knockback(target: Node2D, force_direction: Vector2, stage: int,
		lethal: bool, already_displaced_x := 0.0) -> void:
	if not BAT_KNOCKBACK_ENABLED or target == null or not is_instance_valid(target):
		return
	if lethal:
		if _start_corpse_impact(target, stage, force_direction.x):
			return  # 实际弹道已接管X/Y，绝不能再叠加旧水平ease-out造成双倍位移。
	var stage_idx := clampi(stage, 0, BAT_KNOCKBACK_DISTANCES.size() - 1)
	var push_sign := 1.0 if force_direction.x >= 0.0 else -1.0
	var distance: float = BAT_KNOCKBACK_DISTANCES[stage_idx]
	if target == red_boss:
		distance *= BAT_KNOCKBACK_BOSS_MULT
	if lethal:
		distance *= BAT_KNOCKBACK_LETHAL_MULT
	# 兼容旧悬浮怪 take_hit() 的 26px 即时位移，但只抵扣同方向分量。
	var already_in_direction := maxf(0.0, already_displaced_x * push_sign)
	distance = maxf(0.0, distance - already_in_direction)
	if distance <= 0.01:
		return
	var duration: float = BAT_KNOCKBACK_DURATIONS[stage_idx] + (0.03 if lethal else 0.0)
	# 非 Red 敌人都有 hitstop；覆盖到滑移结束，避免 Hornet 冲撞 AI 在中途抵消击退。
	# Red 保留现有“攻击中不被打断”设计，只应用较小的物理推移。
	if not target is RedBoss:
		target.set("hitstop", maxf(float(target.get("hitstop")), duration))
	var entry := {
		"target": weakref(target),
		"direction": push_sign,
		"velocity": distance * 2.0 / duration,
		"deceleration": distance * 2.0 / (duration * duration),
		"time_left": duration,
		"distance_left": distance,
		"lethal": lethal,
		"require_support": _enemy_knockback_starts_grounded(target),
	}
	for i in _enemy_knockbacks.size():
		var old_ref: WeakRef = _enemy_knockbacks[i]["target"]
		if old_ref != null and old_ref.get_ref() == target:
			_enemy_knockbacks[i] = entry
			return
	_enemy_knockbacks.append(entry)


## 独立推进死亡目标，避免被各敌人 step() 的 dead 早退截断。
func _update_enemy_knockbacks(dt: float) -> void:
	_update_corpse_impacts(dt)
	var safe_dt := maxf(dt, 0.0)
	for i in range(_enemy_knockbacks.size() - 1, -1, -1):
		var entry: Dictionary = _enemy_knockbacks[i]
		var target_ref: WeakRef = entry["target"]
		var target := target_ref.get_ref() as Node2D if target_ref != null else null
		if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
			_enemy_knockbacks.remove_at(i)
			continue
		var time_left := float(entry["time_left"])
		var step_dt := minf(safe_dt, time_left)
		var velocity := float(entry["velocity"])
		var deceleration := float(entry["deceleration"])
		var motion := maxf(0.0, velocity * step_dt - 0.5 * deceleration * step_dt * step_dt)
		motion = minf(motion, float(entry["distance_left"]))
		var moved := _sweep_enemy_knockback(target,
				motion * float(entry["direction"]), bool(entry["lethal"]),
				bool(entry["require_support"]))
		entry["distance_left"] = maxf(0.0,
				float(entry["distance_left"]) - absf(moved))
		entry["velocity"] = maxf(0.0, velocity - deceleration * step_dt)
		entry["time_left"] = maxf(0.0, time_left - step_dt)
		# 碰墙、锁门或到悬崖边时立即吞掉剩余冲量，下一帧不能继续穿过去。
		var blocked := absf(moved) + 0.01 < motion
		if blocked or float(entry["time_left"]) <= 0.0 \
				or float(entry["distance_left"]) <= 0.01:
			_enemy_knockbacks.remove_at(i)


## 最多 2px 一步扫掠敌人身体前缘；单向平台侧面不当墙，地面敌人不被推下悬崖。
func _sweep_enemy_knockback(target: Node2D, amount: float, lethal: bool,
		require_support: bool) -> float:
	if is_zero_approx(amount):
		return 0.0
	var move_sign := 1.0 if amount > 0.0 else -1.0
	var remaining := absf(amount)
	var moved := 0.0
	while remaining > 0.001:
		var step_size := minf(BAT_KNOCKBACK_SWEEP_STEP, remaining)
		var step_x := move_sign * step_size
		if _enemy_knockback_blocked(target, step_x, lethal, require_support):
			break
		target.position.x += step_x
		moved += step_x
		remaining -= step_size
	return moved


func _enemy_knockback_blocked(target: Node2D, step_x: float, lethal: bool,
		require_support: bool) -> bool:
	if level == null or not target.has_method("body_rect"):
		return false
	var body: Rect2 = target.body_rect()
	# 尸体姿态普遍比站立碰撞盒宽，横向留边避免倒地帧半截嵌墙。
	var corpse_margin := 26.0 if lethal else 0.0
	body = Rect2(body.position - Vector2(corpse_margin, 0.0),
			body.size + Vector2(corpse_margin * 2.0, 0.0))
	var candidate := Rect2(body.position + Vector2(step_x, 0.0), body.size)
	if candidate.position.x < 0.0 or candidate.end.x > level.world_w:
		return true
	var move_sign := 1.0 if step_x > 0.0 else -1.0
	var probe_x := candidate.end.x + 0.5 if move_sign > 0.0 \
			else candidate.position.x - 0.5
	for probe_y in [candidate.position.y + 4.0, candidate.get_center().y,
			candidate.end.y - 4.0]:
		if level.solid_at(probe_x, probe_y) and not level.is_platform(probe_x, probe_y):
			return true
	for door in doors:
		if is_instance_valid(door) and door.locked \
				and door.body_rect().intersects(candidate):
			return true
	if require_support and not level.solid_at(probe_x, candidate.end.y + 4.0):
		return true
	return false


func _enemy_knockback_starts_grounded(target: Node2D) -> bool:
	# Kairull/Hornet 可悬空；枪手、巡检员与 Red 只有起击时已着地才启用防坠探针。
	var ground_bound := target is GruntGunner or target is RedBoss \
			or target.has_method("_move_horizontal")
	if not ground_bound or level == null or not target.has_method("body_rect"):
		return false
	var body: Rect2 = target.body_rect()
	return level.solid_at(body.get_center().x, body.end.y + 4.0)


## 无头测试只读接口。
func debug_enemy_knockback_count() -> int:
	return _enemy_knockbacks.size() + _corpse_impacts.size()


## 两类小兵实际世界位移；主角使用同一求解器，不再靠美术抬升伪造抛物线。
func _start_corpse_impact(target: Node2D, stage: int, direction: float) -> bool:
	if not corpse_impact_enabled or target == null or not is_instance_valid(target) \
			or not target.has_method("set_corpse_ground") or not target.dead:
		return false
	var motion := DEATH_INERTIA_SCRIPT.new()
	motion.launch(target.position, direction, stage)
	var entry := {"target": weakref(target), "motion": motion,
			"power": 0.9 + 0.15 * clampi(stage, 0, 2), "direction": 1.0 if direction >= 0.0 else -1.0}
	for index in _corpse_impacts.size():
		if _corpse_impacts[index].target.get_ref() == target:
			_corpse_impacts[index] = entry
			return true
	if _corpse_impacts.size() >= MAX_CORPSE_IMPACTS:
		var oldest: Dictionary = _corpse_impacts.pop_front()
		var previous: Node2D = oldest.target.get_ref()
		if is_instance_valid(previous):
			previous.set_corpse_lift(0.0)
	_corpse_impacts.append(entry)
	target.set_corpse_ground(target.position.y, _corpse_contact_y(target) < INF)
	return true


func _update_corpse_impacts(dt: float) -> void:
	if not corpse_impact_enabled:
		_clear_corpse_impacts()
		return
	for index in range(_corpse_impacts.size() - 1, -1, -1):
		var entry: Dictionary = _corpse_impacts[index]
		var target: Node2D = entry.target.get_ref()
		if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.dead:
			if is_instance_valid(target):
				target.set_corpse_lift(0.0)
			_corpse_impacts.remove_at(index)
			continue
		var motion: RefCounted = entry.motion
		var body: Rect2 = target.body_rect()
		# 倒地帧比站立宽，沿用原26px横向留边；根坐标飞行、阴影投地，美术不再二次抬升。
		var contact: bool = motion.advance(dt, level, body.size.x * 0.5 + 26.0, body.size.y, _world_blockers())
		target.position = motion.position
		target.set_corpse_ground(motion.ground_y, motion.ground_valid)
		if contact and fx_layer != null:
			fx_layer.spawn_corpse_landing_dust(motion.landing_position, entry.power, entry.direction)
		if not motion.active:
			_corpse_impacts.remove_at(index)


func _corpse_contact_y(target: Node2D) -> float:
	if level == null:
		return INF
	var feet: Vector2 = target.position
	var surface := level.stair_surface_near(feet.x, feet.y, 2.0, 4.0)
	if level.solid_at(feet.x, feet.y + 3.0):
		surface = minf(surface, floorf((feet.y + 3.0) / CorridorLevel.TS) * CorridorLevel.TS)
	return surface


func _clear_corpse_impacts() -> void:
	for entry: Dictionary in _corpse_impacts:
		var target: Node2D = entry.target.get_ref()
		if is_instance_valid(target):
			# 调试关开关/旧快速重置时安全收尾到已有承接面，不能留下永久悬空尸体。
			if entry.motion.ground_valid:
				target.position.y = entry.motion.ground_y - 0.1
				target.set_corpse_ground(entry.motion.ground_y, true)
			target.set_corpse_lift(0.0)
	_corpse_impacts.clear()


## 棍击命中窗口：判定盒扫过所有敌人与互动物件；命中发近战液爆 + 顿帧 + 震屏
func _on_player_bat_swung(hitbox: Rect2, stage: int) -> void:
	var hit_any := false
	var hit_enemy := false
	# 首击有连续前送：小箱可能已滑到角色身后，仍须保留起手扫过的接触范围。
	# 仅作用于新货箱，不扩大现有敌人/B/T 的伤害盒；障碍另做明确遮挡校验。
	var cargo_hitbox := hitbox
	if _bat_prop_origin_valid:
		cargo_hitbox = cargo_hitbox.merge(Rect2(hitbox.position + _bat_prop_origin - player.position, hitbox.size))
	_bat_prop_origin_valid = false
	for e in _enemies():
		if not e.body_rect().intersects(hitbox):
			continue
		hit_any = true
		hit_enemy = true
		var force_direction := Vector2(player.face, -0.18).normalized()
		var impact_point: Vector2 = e.body_rect().get_center()
		var before_hit_x: float = e.position.x
		if e.take_hit(player.position.x, 1):
			var lethal: bool = e.dead
			var burst_power := 1.35 if lethal else 0.8 + 0.15 * stage
			var burst := fx_layer.spawn_bat_hit(impact_point, force_direction,
					burst_power, lethal, e)
			# 老悬浮怪 take_hit 内已有 26px 瞬移；扣掉它，避免叠成双倍击退。
			_start_enemy_knockback(e, force_direction, stage, lethal,
					e.position.x - before_hit_x)
			if lethal:
				play_action("enemy_kill")
				paint_layer.blood_pool(impact_point, 1.0, 0,
						burst.current_color.darkened(0.15))
			else:
				play_action("body_hit")
			add_camera_shake(force_direction, 0.55)
	for hazard: Node2D in tactical_hazards:
		if is_instance_valid(hazard) and not hazard.dead and hazard.body_rect().intersects(hitbox):
			hit_any = hazard.take_hit(player.position.x, 1) or hit_any
	# 互动物件：爆炸桶点引信（金属回响），CRT 即碎（碎裂音效走 shattered 回调）
	for pr in props:
		if not is_instance_valid(pr) or pr.dead:
			continue
		if pr is PropBatCargo:
			if pr.body_rect().intersects(cargo_hitbox) and not _cargo_strike_blocked(pr) \
					and _flying_cargo_count() < MAX_FLYING_CARGO and pr.launch(player.face, stage):
				hit_any = true
				play_action("cargo_launch")
				add_camera_shake(Vector2(player.face, 0), 0.2)
			continue
		if not pr.body_rect().intersects(hitbox):
			continue
		hit_any = true
		if pr.take_hit(player.position.x, 1):
			var c: Vector2 = pr.body_rect().get_center()
			fx.append({"x": c.x, "y": c.y, "life": 0.16, "kind": "spark"})
			if pr is PropBarrel:
				play_action("metal_impact")
				add_camera_shake(Vector2(player.face, 0.0), 0.25)
	if hit_any:
		# 轻量接触约 1–2 帧，肉体重击约 2–3 帧；取消长停顿但保留棒球棍重量。
		player.hitstop = maxf(player.hitstop, 0.04 if hit_enemy else 0.025)


func _on_bat_swing_started(_stage: int) -> void:
	_bat_prop_origin = player.position
	_bat_prop_origin_valid = true
	play_action("bat_swing", 1.0 + _stage * 0.025)


func _cargo_strike_blocked(cargo: PropBatCargo) -> bool:
	var start := player.position - Vector2(0, player.h * 0.55)
	var end := cargo.body_rect().get_center()
	var steps := maxi(1, ceili(start.distance_to(end) / 2.0))
	for i in range(steps + 1):
		var point := start.lerp(end, float(i) / steps)
		if level.solid_at(point.x, point.y) and not level.is_platform(point.x, point.y):
			return true
		for door: Node2D in doors:
			if is_instance_valid(door) and door.locked and door.body_rect().has_point(point):
				return true
	return false


func _on_player_fired(b: Dictionary) -> void:
	bullets.append(b)
	fx.append({"x": b["x"], "y": b["y"], "life": 0.09, "kind": "flash"})
	# 枪声按剩余弹药分档（gun-sfx 设计意图：残弹 2/1 发时音色不同）
	if player.gun_ammo == 2:
		play_sfx("shot_r2")
	elif player.gun_ammo == 1:
		play_sfx("shot_r1")
	else:
		play_sfx("shot%d" % (randi() % 7 + 1))


func _on_player_fell_out() -> void:
	_reset_bat_cargo()
	_clear_corpse_impacts()
	bullets.clear()
	fx.clear()
	_enemy_knockbacks.clear()
	fx_layer.clear_explosions()
	clear_camera_shake()


# ---------- 时间挑战：55%慢动作主角 / 冻结世界 / 短倒带与电视失步 ----------

func _advance_time_charge(dt: float) -> void:
	if pause_controller != null and pause_controller.active:
		return
	var before: bool = time_charge.active
	var held := player.time_focus_input_held() # 与恢复后的输入隔离共用门禁，菜单右键不能偷启动时停。
	time_charge.advance(dt, held, time_phase == "playing" and not player.dead and not level_cleared)
	_set_player_time_focus(time_charge.active)
	if before != time_charge.active:
		_set_temporal_nodes_paused(time_charge.active or time_phase != "playing")
		play_action("time_stop_start" if time_charge.active else "time_stop_end")
		if music != null:
			music.pitch_scale = 0.78 if time_charge.active else 1.0


func _set_player_time_focus(active: bool) -> void:
	if player.has_method("set_time_focus"):
		player.set_time_focus(active)
	if active == _focus_presented:
		return
	_focus_presented = active
	if active:
		_focus_original_z = player.z_index
		player.z_index = 50  # 世界压暗在40层，主角与同款虚影在其上，HUD仍在独立CanvasLayer。
	else:
		player.z_index = _focus_original_z


func _set_temporal_nodes_paused(paused: bool) -> void:
	if paused == _temporal_paused:
		return
	_temporal_paused = paused
	if paused:
		_temporal_nodes.clear()
		# 世界粒子/动态建筑与世界物理一起冻结；主角、菜单、HUD不属于这一时间域。
		var world_nodes: Array = [bg, quarantine_architecture, quarantine_foreground, paint_layer, fx_layer,
				room_lights, exit_door]
		world_nodes.append_array(doors)
		world_nodes.append_array(_checkpoint_beacons.values())
		for node in world_nodes:
			if node != null and is_instance_valid(node):
				_temporal_nodes.append({"ref": weakref(node), "mode": node.process_mode})
				node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		for entry: Dictionary in _temporal_nodes:
			var node: Node = entry["ref"].get_ref()
			if node != null and is_instance_valid(node):
				node.process_mode = entry["mode"]
		_temporal_nodes.clear()


func _sync_temporal_projection() -> void:
	if not _temporal_paused:
		return
	# 冻结的是世界时间，不是相机投影；背景必须跟随镜头铺满，避免倒带时露出灰块。
	if bg != null:
		bg._process(0.0)
	if fx_layer != null:
		fx_layer.queue_redraw()  # 冻结弹道仍需绘制，并允许时停中新增命中特效首次显形。


func _on_player_died() -> void:
	_reset_original_kill_chain()
	_set_player_time_focus(false)
	play_action("player_death")
	if not timeline_enabled:
		if hud != null:
			hud.show_msg("倒下了 · Backspace 重来")
		return
	if time_phase != "playing" or _transitioning:
		return
	time_charge.cancel()
	time_phase = "dying"
	_death_elapsed = 0.0
	_death_prompt_ready = false
	_set_temporal_nodes_paused(true)
	# 主角继续死亡位移/动画，其余世界停在致命瞬间；录入这段动作供真正倒放。
	clear_camera_shake()
	if music != null:
		music.pitch_scale = 0.68


func _begin_rewind() -> void:
	if not timeline_enabled or time_phase in ["rewinding", "interference"] or _transitioning:
		return
	attempt_timeline.record(self, 0.0, true)
	_set_player_time_focus(false)
	time_charge.cancel()
	time_phase = "rewinding"
	_death_prompt_ready = false
	_rewind_elapsed = 0.0
	rewind_progress = 0.0
	glitch_progress = 0.0
	level_cleared = false
	_set_temporal_nodes_paused(true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.keys.clear()
	player._prev_keys.clear()
	# 倒带用姿态记录重绘，清掉无法逐粒子反演的临时特效，不继续制造新血迹。
	fx.clear()
	fx_layer.clear_explosions()
	if smoke_tactics != null:
		smoke_tactics.clear_effects()
		_refresh_smoke_cover()
	for hazard: Node2D in tactical_hazards:
		hazard.visible = false  # 短倒带不重演机关/抛投事件，新轮从地图配置完整重建。
	for voice: AudioStreamPlayer in _sfx_pool:
		voice.stop()
	if action_audio != null:
		action_audio.stop_all()
	play_action("rewind")
	if music != null:
		music.pitch_scale = 0.48


func _advance_rewind(dt: float) -> void:
	if pause_controller != null and pause_controller.active:
		return
	if _transitioning:
		return
	_rewind_elapsed += maxf(0.0, dt)
	rewind_progress = clampf(_rewind_elapsed / REWIND_DURATION, 0.0, 1.0)
	attempt_timeline.apply_rewind(self, rewind_progress)
	_sync_temporal_projection()
	if _rewind_elapsed >= REWIND_DURATION:
		# 只倒带最近一小段，再短花屏重建；中段快照独立保存，不拉长死亡回放。
		if time_phase != "interference":
			play_action("tv_fault")  # 失锁杂音只在故障进入沿播放一次，不每帧重复触发。
		time_phase = "interference"
		glitch_progress = clampf((_rewind_elapsed - REWIND_DURATION) / INTERFERENCE_DURATION, 0.0, 1.0)
		# 老电视失步由更上层重新采样整张画面；不再叠加早版彩色横线假花屏。
		get_node("TimeSignalOverlay").visible = false
	if _rewind_elapsed >= REWIND_DURATION + INTERFERENCE_DURATION:
		_transitioning = true
		RUN_SESSION.next_attempt()
		_keep_music_on_exit = true
		# 全场重新实例化后才应用存点进度；失败后的敌弹/烟幕/预瞄准绝不沿用。
		get_tree().call_deferred("change_scene_to_file", CorridorLevel.active_restart_scene)


func timeline_view_model() -> Dictionary:
	return {"enabled": timeline_enabled, "active": time_charge.active,
		"energy_ratio": time_charge.ratio(), "remaining": time_charge.energy,
		"max_duration": CHRONO_CHARGE.MAX_DURATION, "lockout": time_charge.lockout,
		"phase": time_phase, "rewind_progress": rewind_progress,
		"glitch_progress": glitch_progress,
		"death_prompt_ready": _death_prompt_ready,
		"difficulty": RUN_SESSION.difficulty, "attempt": RUN_SESSION.attempt}


# ---------- 音效与近战事件 ----------

func play_action(event: StringName, pitch := 1.0) -> Dictionary:
	# 用户确认原重击与液爆叠层才有爽感：恢复原素材、原音量。
	# 击杀轻变调叠在原连杀基准上，两层只采样一次同步播放；不降增益、不换素材。
	if original_combat_audio_enabled:
		var keys: Array[String] = []
		match event:
			&"player_dash": keys = ["enemy_dash"]
			&"bat_swing": keys = ["swing%d" % (randi() % 5 + 1)]
			&"body_hit": keys = ["hit%d" % (randi() % 3 + 6)]
			&"enemy_kill": keys = ["kill", "slime_death"]
		if not keys.is_empty():
			for key: String in keys:
				if _sfx.get(key) == null:
					return {"played": false, "event": event, "reason": "missing_original_stream"}
			var original_pitch := _next_original_kill_pitch(Time.get_ticks_usec() / 1000000.0) \
					if event == &"enemy_kill" else 1.0
			for key: String in keys:
				play_sfx(key, original_pitch)
			return {"played": true, "event": event, "bank": "original", "keys": keys,
					"pitch": original_pitch, "kill_streak": _original_kill_streak}
	if not action_audio_enabled or action_audio == null:
		return {"played": false, "event": event}
	return action_audio.play_event(event, pitch)


func _next_original_kill_pitch(now: float) -> float:
	# 用真实时间，时停不让连杀窗口无限延长；音高封顶，避免连杀越多越尖。
	_original_kill_streak = mini(32, _original_kill_streak + 1) \
			if now - _last_original_kill_at <= ORIGINAL_KILL_CHAIN_WINDOW else 1
	_last_original_kill_at = now
	var base_pitch := minf(ORIGINAL_KILL_MAX_PITCH, 1.0 + maxf(0.0, original_kill_pitch_step) * (_original_kill_streak - 1))
	var variation := clampf(original_kill_pitch_variation, 0.0, ORIGINAL_KILL_VARIATION_LIMIT)
	var result := base_pitch
	if variation > 0.0:
		if not _original_kill_rng_initialized:
			_original_kill_rng.randomize()
			_original_kill_rng_initialized = true
		var lower := maxf(1.0 - ORIGINAL_KILL_VARIATION_LIMIT, base_pitch - variation)
		var upper := minf(ORIGINAL_KILL_MAX_PITCH + ORIGINAL_KILL_VARIATION_LIMIT, base_pitch + variation)
		result = _original_kill_rng.randf_range(lower, upper)
		var separation := minf(0.003, variation * 0.25)
		# 限次重采样，极端重复时选择更远端点；不靠循环无限抽到“合适音色”。
		for _attempt in 4:
			if absf(result - _last_original_kill_pitch) >= separation:
				break
			result = _original_kill_rng.randf_range(lower, upper)
		if absf(result - _last_original_kill_pitch) < separation:
			result = lower if absf(lower - _last_original_kill_pitch) > absf(upper - _last_original_kill_pitch) else upper
	_last_original_kill_variation = result - base_pitch
	_last_original_kill_pitch = result
	return result


func set_original_kill_variation_seed(value: int) -> void:
	# 仅给可重复试听/测试注入seed；生产默认独立randomize，不改任何玩法随机数。
	_original_kill_rng.seed = value
	_original_kill_rng_initialized = true


func _reset_original_kill_chain() -> void:
	_last_original_kill_at = -INF
	_original_kill_streak = 0
	_last_original_kill_pitch = -INF
	_last_original_kill_variation = 0.0


func _load_sfx() -> void:
	for i in range(12):
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_sfx_pool.append(p)
	var dir := "res://assets/sfx/"
	for i in range(1, 6):
		_sfx["swing%d" % i] = load(dir + "%02d_bat_swing.wav" % i)
	for i in range(6, 9):
		_sfx["hit%d" % i] = load(dir + "%02d_bat_hit_normal.wav" % i)
	_sfx["kill"] = load(dir + "09_bat_hit_kill.wav")
	_sfx["wall"] = load(dir + "10_bat_hit_wall_rebound.wav")
	# 枪声（deliverables/gun-sfx）：1-7 普通枪声、剩余 2/1 发分档、空仓、装填、击杀/命中（P1 用）
	var gdir := "res://assets/sfx/gun/"
	for i in range(1, 8):
		_sfx["shot%d" % i] = load(gdir + "%02d_gunshot.wav" % i)
	_sfx["shot_r2"] = load(gdir + "08_gunshot_remaining_2.wav")
	_sfx["shot_r1"] = load(gdir + "09_gunshot_remaining_1.wav")
	_sfx["empty"] = load(gdir + "10_gunshot_empty.wav")
	_sfx["reload"] = load(gdir + "11_gun_reload.wav")  ## 原始速度；时长与 RELOAD_TIME 一致
	for i in range(12, 16):
		_sfx["gkill%d" % (i - 11)] = load(gdir + "%02d_gun_kill.wav" % i)
	for i in range(16, 20):
		_sfx["ghit%d" % (i - 15)] = load(gdir + "%02d_gun_hit.wav" % i)
	# 史莱姆材质声与枪械命中声叠放：短湿拍用于受击，长爆裂用于死亡。
	var slime_dir := "res://assets/sfx/slime/"
	_sfx["slime_hit"] = load(slime_dir + "slime_hit_wet.wav")
	_sfx["slime_death"] = load(slime_dir + "slime_death_burst.wav")
	# 大黄蜂 Boss 技能音（HollowKatana 移植）：冲撞/投剑/丝线/棘刺/受伤变体
	var hk_dir := "res://assets/sfx/hk/"
	_sfx["enemy_dash"] = load(hk_dir + "enemy_dash.mp3")
	_sfx["enemy_run"] = load(hk_dir + "enemy_run.mp3")
	_sfx["enemy_throw_sword"] = load(hk_dir + "enemy_throw_sword.mp3")
	_sfx["enemy_throw_silk"] = load(hk_dir + "enemy_throw_silk.mp3")
	_sfx["enemy_throw_barbs"] = load(hk_dir + "enemy_throw_barbs.mp3")
	for i in range(1, 4):
		_sfx["enemy_hurt_%d" % i] = load(hk_dir + "enemy_hurt_%d.mp3" % i)
	_sfx["bullet_time"] = load(hk_dir + "bullet_time.mp3")


func play_sfx(key: String, pitch := 1.0) -> void:
	var stream: AudioStream = _sfx.get(key)
	if stream == null:
		return
	var p := _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = sfx_gain_db(key)
	p.pitch_scale = pitch
	p.play()


func sfx_gain_db(key: String) -> float:
	return float(_sfx_gain.get(key, 0.0))


## 关卡 BGM：active_bgm 非空才创建播放器。循环走 finished 信号回放
## （不依赖 mp3 导入的 loop 设置；接缝处理论上有极小间隙，可接受）。
## 总线优先 Music（工程未配该总线时回退 Master）；音量取 CorridorLevel.active_bgm_db
## （默认 MUSIC_VOLUME_DB，明显压在音效之下）。顿帧只冻结玩家物理，不碰音频节点，BGM 持续播放。
func _setup_music() -> void:
	var path := CorridorLevel.active_bgm
	if path.is_empty():
		return
	if timeline_enabled:
		var previous := get_tree().root.get_node_or_null(CONTINUOUS_MUSIC_NAME) as AudioStreamPlayer
		if previous != null and not previous.is_queued_for_deletion() and previous.get_meta("track_path", "") == path:
			# 同一播放器从始至终留在根节点：不reparent、不play、不seek，音频进度连续。
			music = previous
			music.pitch_scale = 1.0
			music.volume_db = CorridorLevel.active_bgm_db
			return
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("BGM 加载失败: " + path)
		return
	if timeline_enabled:
		var previous := get_tree().root.get_node_or_null(CONTINUOUS_MUSIC_NAME) as AudioStreamPlayer
		if previous != null and not previous.is_queued_for_deletion():
			# 只有跨关换曲才停止旧曲；复用唯一播放器，避免异曲时留下两首同时响。
			# 同曲死亡/检查点重试已在上方直接返回，绝不在这里重新播放。
			music = previous
			music.stop()
			music.stream = stream
			music.set_meta("track_path", path)
			music.pitch_scale = 1.0
			music.volume_db = CorridorLevel.active_bgm_db
			music.stream_paused = false
			music.play()
			return
	music = AudioStreamPlayer.new()
	music.name = "Music"
	music.stream = stream
	if AudioServer.get_bus_index("Music") >= 0:
		music.bus = "Music"
	music.volume_db = CorridorLevel.active_bgm_db
	music.finished.connect(music.play)   ## 播完立即回放 = 循环
	if timeline_enabled:
		music.name = CONTINUOUS_MUSIC_NAME
		music.set_meta("track_path", path)
		get_tree().root.add_child(music)
	else:
		add_child(music)  # 旧关卡及独立测试保留原场景内音乐生命周期。
	music.play()


func _exit_tree() -> void:
	if is_instance_valid(music) and music.get_parent() != self and not _keep_music_on_exit:
		# 返回菜单/退出或普通卸载停止音乐；死亡重开只交接引用，音乐不重置。
		music.stop()
		music.queue_free()

## 当前近战走 bat_swing_started/bat_swung；旧枪械接口只保留兼容，不代表玩家启用枪械。
