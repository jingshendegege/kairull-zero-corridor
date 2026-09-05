extends SceneTree
## 正式第一关端到端时间域、死亡等待、整场重载；旧测试不启用 Session，继续原行为。
const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func _quiet(game: Node2D) -> void:
	if game.music != null:
		game.music.stop()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	game._sfx.clear()
	game.action_audio_enabled = false
	if game.get("action_audio") != null:
		game.action_audio.stop_all()

func _prepare(game: Node2D) -> void:
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.keys.clear()
	_quiet(game)

func _press(key: Key, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	event.echo = echo
	return event

func _run() -> void:
	check(SESSION.DIFFICULTIES == ["easy", "hard", "zero"], "会话固定简单/困难/武士零三档")
	check(SESSION.health_for_difficulty("easy") == 5 and SESSION.health_for_difficulty("hard") == 3 \
		and SESSION.health_for_difficulty("zero") == 1, "难度到生命值映射严格为5/3/1")
	check(SESSION.normalize_difficulty("unknown") == "easy" \
		and SESSION.name_for_difficulty("zero") == "武士零", "未知难度安全回简单，一血档有独立名称")
	SESSION.begin_run("easy")
	var boot := load("res://scenes/m01_protocol_quarantine.tscn").instantiate() as Node2D
	root.add_child(boot)
	current_scene = boot
	var game: Node2D = boot.get_node("Game")
	_prepare(game)
	check(game.timeline_enabled and game.player.hp == 5 and game.player.max_hp == 5, "简单模式 5 血并开启录像")
	check(game.has_node("TimeSignalOverlay"), "信号层已在正式运行时接入")
	check(not game.get_node("CrtRollTransition").effect_state().active, "正常游戏不运行全屏电视采样")
	check(Engine.time_scale == 1.0, "没有修改全局时间倍率")
	var origin: Vector2 = game.player.position
	var enemy: Node2D = game.minions[0]
	var enemy_pos: Vector2 = enemy.position
	var enemy_clock: float = enemy._anim_clock
	var cargo: PropBatCargo
	for prop: Node2D in game.props:
		if prop is PropBatCargo:
			cargo = prop
			break
	cargo.launch(1)
	var cargo_pos := cargo.position
	# 此处只验冻结/恢复坐标，避开扩大后的站立框；头部伤害由test_player_hurtbox独立覆盖。
	game.enemy_bullets.append({"x": origin.x + 180.0, "y": origin.y - 38.0,
		"vx": -180.0, "vy": 0.0, "life": 3.0})
	var projectile: Dictionary = game.enemy_bullets[0].duplicate(true)
	var old_bg_mode: int = game.bg.process_mode
	game.player.keys[MOUSE_BUTTON_RIGHT] = true
	game.player.keys[KEY_D] = true
	for i in 30:
		game._physics_process(DT)
		game.player.step(DT)
		game._process(DT)
	check(game.time_charge.active and is_equal_approx(game.time_charge.energy, 1.5), "右键冻结半秒精确消耗能量")
	check(game.player.position.x > origin.x + 50.0, "世界冻结时主角仍能正常移动")
	check(game.player.position.x < origin.x + 115.0 and game.player.time_focus_active(), "主角实际以55%慢动作移动而非完全停住")
	var shade: Node2D = game.get_node("TimeFocusShade")
	shade._process(0.1)
	check(shade.visible and shade.opacity > 0.4 and shade.z_index == 40 and game.player.z_index == 50,
		"暗层压住世界，主角高亮层在其上")
	check(game.player.dash_afterimage_count() > 0, "时停移动会留下同款限时虚影")
	check(enemy.position == enemy_pos and enemy._anim_clock == enemy_clock, "敌人位置和动画一起冻结")
	check(cargo.position == cargo_pos and cargo.flying, "飞行箱暂停而非销毁")
	check(game.enemy_bullets[0] == projectile and game.player.hp == 5, "敌弹位置寿命与伤害均暂停")
	check(game.bg.process_mode == Node.PROCESS_MODE_DISABLED and game.fx_layer.process_mode == Node.PROCESS_MODE_DISABLED,
		"动态建筑与粒子属于冻结世界")
	check(game.player.process_mode != Node.PROCESS_MODE_DISABLED, "主角未被暂停世界父节点连带冻结")
	check(game.bg.position == game.cam_tl, "时停移动镜头时背景仍铺满屏幕")
	game.player.keys.erase(KEY_D)
	game._on_player_bat_swung(enemy.body_rect(), 2)
	# 致死弹道已从旧水平列表分离；检查统一任务计数及实际位置，不能绑定内部容器名。
	check(enemy.dead and game.debug_enemy_knockback_count() > 0 and enemy.position == enemy_pos,
			"时停中可挥棒命中，尸体击退留待恢复")
	game.player.keys.clear()
	game._physics_process(DT)
	check(not game.time_charge.active and game.bg.process_mode == old_bg_mode, "松开后恢复节点原处理模式")
	shade._process(0.1)
	check(not game.player.time_focus_active() and game.player.z_index == 0 and not shade.visible,
		"松开后恢复角色速度、层级与场景亮度")
	check(cargo.position != cargo_pos and game.enemy_bullets[0] != projectile, "恢复后飞行箱和子弹继续推进")
	check(enemy.position != enemy_pos, "恢复后死亡击退继续执行")
	game.time_charge.reset()
	game.player.keys[MOUSE_BUTTON_RIGHT] = true
	for i in 121:
		game._physics_process(DT)
	check(not game.time_charge.active and game.time_charge.require_release, "持续按住耗尽后强制解除，不自动连闪")
	check(game.bg.process_mode == old_bg_mode, "耗尽同样还原世界节点模式")
	game.player.keys.clear()
	for i in 360:
		game._advance_time_charge(DT)
	check(is_equal_approx(game.time_charge.energy, 2.0), "短恢复延迟后五秒补满能量")
	# 每关只有一处记录台；未清前半时不能激活，和独立的遭遇唤醒边界不是同一件事。
	check(game._checkpoint_beacons.size() == 1 and game._checkpoint_index == -1 \
		and game._campaign_boundaries.size() == 2, "一处检查点初始未激活，保留独立遭遇唤醒边界")
	var checkpoint_node: Node2D = game._checkpoint_beacons.values()[0]
	game.player.position = checkpoint_node.position
	game.player.on_ground = true
	game.player.hp = 2
	game._update_campaign_progress(DT)
	check(game._checkpoint_index == -1 and game.player.spawn == origin and game.player.hp == 2,
		"前半尚未清完时走到检查点不补血、不修改出生点")
	game.player.position = origin + Vector2(250, 0)
	for e: Node2D in game.minions:
		e.dead = true # 远离未激活记录台后布置失败现场；整关重开仍须还原全部敌人。
	game.player._sync_sprite()
	game.attempt_timeline.record(game, 0.5, true)
	game.paint_layer.spawn_wall_snapshot(origin + Vector2(200, -60), Vector2.RIGHT, 1.0, 7, false, 0.2, Color.CYAN)
	game.player.invuln_t = 0
	game.player.roll_invuln_t = 0
	game.player.take_damage(5, game.player.position.x - 100)
	check(game.time_phase == "dying" and game.player.dead and not game._death_prompt_ready, "致命伤先进入倒地，不立即回溯")
	var death_start: Vector2 = game.player.position
	game._unhandled_input(_press(KEY_ENTER))
	check(game.time_phase == "dying", "倒地动作完成前按键不会跳过")
	for i in 60:
		game.player.step(DT)
		game._process(DT)
	check(game.player.position.x > death_start.x + 90.0 and game.player.death_animation_finished(), "主角完成击退与15帧倒地")
	check(game._death_prompt_ready and game.time_phase == "dying", "倒地后显示提示并等待新输入")
	var frame_count: int = game.attempt_timeline.frames.size()
	game._process(20)
	check(game.attempt_timeline.frames.size() == frame_count, "死亡等待不继续录空帧")
	game._unhandled_input(_press(KEY_ENTER, true))
	check(game.time_phase == "dying", "按键长按回声不会误触重开")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	game._unhandled_input(mouse)
	check(game.time_phase == "rewinding" and not game._death_prompt_ready, "鼠标新按下启动倒带并隐藏死亡字幕")
	check(game.player.process_mode == Node.PROCESS_MODE_DISABLED, "回放期间不再执行活体或尸体物理")
	game.attempt_timeline.apply_rewind(game, 1.0)
	game._sync_temporal_projection()
	check(game.bg.position == game.cam_tl, "倒带相机投影同步，不露出默认灰色清屏")
	check(game.player.position.x > origin.x + 100, "短倒带只恢复近期，不一路倒放回整关起点")
	game._advance_rewind(game.REWIND_DURATION + 0.03)
	check(game.time_phase == "interference" and not game._transitioning, "短倒带后先出现花屏，不提前切关")
	var crt: CanvasLayer = game.get_node("CrtRollTransition")
	crt._process(0.0)
	check(crt.effect_state().active and crt.effect_state().copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT
		and not game.get_node("TimeSignalOverlay").visible, "转场复制最终画面滚屏，不再叠早版假彩条")
	game._advance_rewind(game.INTERFERENCE_DURATION)
	_quiet(game)
	for i in 4:
		await process_frame
	check(is_instance_valid(current_scene) and current_scene != boot, "倒带后真正重新实例化整个场景")
	game = current_scene.get_node("Game")
	_prepare(game)
	check(SESSION.attempt == 2 and game.player.hp == 5 and game.timeline_enabled, "重开保留难度且轮次递增")
	check(game.player.position.distance_to(origin) < 1.0 and game._enemies().size() == 20, "出生位置和20名敌人全部重置")
	var intact := 0
	for prop: Node2D in game.props:
		if prop is PropBatCargo and not prop.dead and not prop.flying:
			intact += 1
	check(intact == 11, "11只货箱重新可用")
	check(game.enemy_bullets.is_empty() and game.paint_layer.blood_wall_manager.active_count() == 0
		and game.paint_layer.splats.is_empty() and game.paint_layer.flecks.is_empty(), "子弹与彩色血迹全部清空")
	check(game.time_charge.energy == 2.0 and game.time_phase == "playing" and not game._temporal_paused,
		"新场景时间能量全满，暂停状态无残留")
	check(game.get_node("CrtRollTransition").effect_state().copy_mode == BackBufferCopy.COPY_MODE_DISABLED,
		"新场景关闭屏幕复制与旧电视材质")
	_quiet(game)
	SESSION.begin_run("hard")
	change_scene_to_file("res://scenes/m01_protocol_quarantine.tscn")
	for i in 4:
		await process_frame
	game = current_scene.get_node("Game")
	_prepare(game)
	check(game.player.hp == 3 and game.player.max_hp == 3, "困难模式现在初始化3血")
	game.player.take_damage(1, game.player.position.x + 100)
	check(game.player.hp == 2 and not game.player.dead, "困难第一次有效受击剩2血而不死亡")
	game.player.invuln_t = 0.0
	game.player.take_damage(1, game.player.position.x + 100)
	check(game.player.hp == 1 and not game.player.dead, "困难第二次有效受击剩1血而不死亡")
	game.player.invuln_t = 0.0
	game.player.take_damage(1, game.player.position.x + 100)
	check(game.player.dead and game.time_phase == "dying", "困难第三次有效受击才进入死亡回溯")
	_quiet(game)
	SESSION.begin_run("zero")
	change_scene_to_file("res://scenes/m01_protocol_quarantine.tscn")
	for i in 4:
		await process_frame
	game = current_scene.get_node("Game")
	_prepare(game)
	check(game.player.hp == 1 and game.player.max_hp == 1, "武士零模式初始化只有1血")
	game.player.take_damage(1, game.player.position.x + 100)
	check(game.player.dead and game.time_phase == "dying", "武士零一次有效伤害即死亡")
	game._begin_rewind()
	game._advance_rewind(game.REWIND_DURATION + game.INTERFERENCE_DURATION)
	_quiet(game)
	for i in 4:
		await process_frame
	game = current_scene.get_node("Game")
	_prepare(game)
	check(game.player.hp == 1 and SESSION.difficulty == "zero" and SESSION.attempt == 2,
		"武士零模式未激活检查点时重开仍1血，不偷偷补成3/5血")
	var paused_scene_id: int = current_scene.get_instance_id()
	var paused_position: Vector2 = game.player.position
	var paused_attempt: int = SESSION.attempt
	var escape_release := _press(KEY_ESCAPE)
	escape_release.pressed = false
	game.pause_controller._input(_press(KEY_ESCAPE))
	game.pause_controller._input(escape_release)
	check(game.pause_controller.active and paused and current_scene.get_instance_id() == paused_scene_id \
		and SESSION.timeline_enabled, "Esc打开暂停，保留原场景和当前挑战而非返回主菜单")
	game.pause_controller._input(_press(KEY_ESCAPE))
	game.pause_controller._input(escape_release)
	check(not game.pause_controller.active and not paused \
		and current_scene.get_instance_id() == paused_scene_id and game.player.position == paused_position \
		and SESSION.attempt == paused_attempt, "再按Esc原地继续，不重载、不复活、不增加轮次")
	game.pause_controller._input(_press(KEY_ESCAPE))
	game.pause_controller._input(escape_release)
	game.pause_controller.return_to_main_menu() # 等价于用户明确选择暂停菜单的返回主菜单按钮。
	for i in 4:
		await process_frame
	check(current_scene.get_script() == load("res://scripts/surveillance_menu.gd") \
		and not SESSION.timeline_enabled and not paused, "明确选择返回主菜单才退出录像，且不遗留全局暂停")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Engine.time_scale == 1.0, "回菜单鼠标可用且全局时钟正常")
	current_scene.free()
	SESSION.reset_for_tests()
	await create_timer(0.15).timeout
	print("TIME_LOOP_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
