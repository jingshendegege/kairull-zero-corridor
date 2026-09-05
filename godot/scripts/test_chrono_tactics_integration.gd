extends SceneTree
## 真M04入口、真实game命中/时间/机关接线；只在fixture里搬动少量演员，不修改地图或生产逻辑。

const SESSION := preload("res://scripts/run_session.gd")
const DATA := preload("res://generated/m04_chrono_freight_data.gd")
const SCENE := "res://scenes/m04_chrono_freight.tscn"
const DT := 1.0 / 60.0
var _pass := 0
var _fail := 0
var game: Node2D
var player: KairullPlayer
var smoke: Node2D
var _origin := Vector2.ZERO
var _expected_enemy_count := 0
var _expected_cargo_count := 0
var _expected_pickup_count := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	_pass += int(value)
	_fail += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func _prepare() -> void:
	game = current_scene.get_node("Game")
	player = game.player
	smoke = game.smoke_tactics
	# 自动节点停住，所有推进由测试显式调用。BGM在root保持独立音频播放。
	current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	game.set_process(false)
	game.set_physics_process(false)
	player.auto_input = false
	player.keys.clear()
	game._sfx.clear()
	game.action_audio_enabled = false
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	if game.action_audio != null:
		game.action_audio.stop_all()


func _boot(difficulty: String) -> void:
	SESSION.begin_run(difficulty)
	var boot := load(SCENE).instantiate() as Node2D
	root.add_child(boot)
	current_scene = boot
	_prepare()
	_origin = player.position


func _run() -> void:
	for item: Dictionary in DATA.ENTITIES:
		_expected_enemy_count += int(item.kind in ["MeleeInspector", "Gunner"])
		_expected_cargo_count += int(item.kind == "BatCargo")
	for item: Dictionary in DATA.TACTICAL_OBJECTS:
		_expected_pickup_count += int(item.type == "smoke_pickup")
	_boot("easy")
	check(game.timeline_enabled and player.hp == 5, "M04简单入口开启时间技能且五格生命")
	check(_hazards("auto_sniper").size() == _configured_hazards("easy", "auto_sniper"), "简单只生成地图允许的非困难限定狙击器")
	check(game.tactical_hazards.size() == _configured_hazards("easy"), "简单按类型筛选机关，不把升降台误当炮")
	current_scene.free()
	await create_timer(0.15).timeout # 给真实音频线程回收上个入口的MP3，不把即时退出误报成资源滞留。
	_boot("hard")
	check(game.timeline_enabled and player.hp == 3 and player.max_hp == 3, "困难真实入口使用3血")
	check(_hazards("auto_sniper").size() == _configured_hazards("hard", "auto_sniper") \
			and game.tactical_hazards.size() == _configured_hazards("hard"),
			"困难只在指定难段增加一台狙击")
	check(game.minions.size() == game.level.enemy_spawns.size() \
			and game.minions.size() == _expected_enemy_count and game.minions.size() >= 32,
			"实体敌人数与最新生成数据一致，不绑定历史32", str([game.minions.size(), _expected_enemy_count]))
	check(_cargo_count() == _expected_cargo_count and _expected_cargo_count == 20,
			"二十个货箱从地图实体生成")
	check(smoke.pickups.size() == _expected_pickup_count and _expected_pickup_count == 6,
			"六个用途明确补给点从地图生成")
	check(game._checkpoint_beacons.size() == 1 and game._checkpoint_index == -1,
			"长关只有一处未激活检查点，初始仍从整关入口重开")
	_test_input_and_time()
	_test_damage_and_cover()
	_test_laser_and_press()
	_test_sniper_and_room_clear()
	_test_cargo_target()
	await _test_death_retry()
	if is_instance_valid(current_scene):
		current_scene.free()
	SESSION.reset_for_tests()
	await create_timer(0.15).timeout
	check(CorridorLevel.active_tactical_objects.is_empty(), "M04卸载清自身战术静态配置不污染旧关")
	print("CHRONO_TACTICS_INTEGRATION_RESULT: %d PASS / %d FAIL" % [_pass, _fail])
	quit(int(_fail > 0))


func _cargo_count() -> int:
	var result := 0
	for prop: Node2D in game.props:
		result += int(prop is PropBatCargo)
	return result


func _configured_hazards(difficulty: String, kind := "") -> int:
	var result := 0
	for item: Dictionary in DATA.TACTICAL_OBJECTS:
		if item.type not in ["auto_sniper", "laser_gate", "press"]:
			continue
		if (kind.is_empty() or item.type == kind) \
				and (difficulty in ["hard", "zero"] or not item.get("hard_only", false)):
			result += 1
	return result


func _hazards(kind: String) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for hazard: Node2D in game.tactical_hazards:
		if hazard.hazard_type == kind:
			result.append(hazard)
	return result


func _place(at: Vector2) -> void:
	game._set_player_time_focus(false)
	game._set_temporal_nodes_paused(false)
	game.time_phase = "playing"
	game.time_charge.reset()
	player.reset_to_spawn()
	# 验多个伤害来源时fixture临时给5血，生产困难的3血已在入口和重开单独检查。
	player.configure_max_health(5)
	player.position = at
	player.on_ground = true
	player.keys.clear()
	player._prev_keys.clear()
	player._sync_sprite()
	game.current_room = game.level.room_at(at.x, at.y - 1)
	game.cam_tl = at - Vector2(460, 610)
	game.enemy_bullets.clear()
	game.level_cleared = false


func _cover(at: Vector2) -> void:
	smoke.deploy_cloud(at)
	game._step_tactics(0.2)
	game._refresh_smoke_cover()


func _test_input_and_time() -> void:
	var pickup: Vector2 = smoke.pickups[0]["position"]
	_place(pickup)
	game._step_tactics(0)
	check(player.carried_smoke and smoke.pickups.size() == _expected_pickup_count - 1,
			"真实game靠近补给自动拾取且只少一颗")
	player.aim_override = pickup + Vector2(275, -20)
	player.keys = {KEY_R: true, KEY_D: true}
	player.step(DT)
	smoke.update_aim_preview()
	check(smoke.grenades.is_empty() and player.carried_smoke and smoke._preview_visible,
			"真实R按住只显示预览，不立即投出或消耗")
	player.keys.erase(KEY_R)
	smoke.update_aim_preview()
	check(not smoke._preview_visible and player.carried_smoke, "松R隐藏轨迹但保留携带图标和烟弹")
	player.keys[KEY_R] = true
	player.keys[MOUSE_BUTTON_LEFT] = true
	player.step(DT)
	check(smoke.grenades.size() == 1 and not player.carried_smoke,
			"真实player按R左键确认经宿主创建弹体且只消耗一次")
	check(not player.batting() and player._bat_input_buffer_t == 0.0 and not player.bat_queued,
			"宿主成功消费背包的同一帧不挥棒、不排队")
	check(player.position.x > pickup.x, "R不锁住同帧奔跑")
	player.step(DT)
	check(smoke.grenades.size() == 1, "持续按住R和左键不会重复生成")
	smoke.deploy_cloud(player.position + Vector2(260, 0))
	game._step_tactics(0.2)
	var grenade: Dictionary = smoke.grenades[0].duplicate(true)
	var cloud_age := float(smoke.clouds[0]["age"])
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	for _i in 30:
		game._physics_process(DT)
	check(game.time_charge.active and player.time_focus_active(), "真实右键入口启动世界时停")
	check(smoke.grenades.size() == 1 and smoke.grenades[0] == grenade,
			"时停主循环真正冻结手雷坐标速度引信")
	check(is_equal_approx(smoke.clouds[0]["age"], cloud_age), "时停同样冻结烟幕寿命")
	player.set_carried_smoke(true)
	player.keys[KEY_R] = true
	player._prev_keys.clear()
	player.step(DT)
	smoke.step(0.0)
	check(smoke.grenades.size() == 1 and player.smoke_aiming() and smoke._preview_visible,
			"时停中按住R也只瞄准，世界暂停不迫使立即投出")
	player.keys[MOUSE_BUTTON_LEFT] = true
	player.step(DT)
	check(smoke.grenades.size() == 2 and not player.carried_smoke,
			"时停中按R再左键确认，弹体创建后留在时间冻结现场")
	var second: Dictionary = smoke.grenades[1].duplicate(true)
	game._physics_process(DT)
	check(smoke.grenades[1] == second, "时停中刚投出的新手雷不会漏走一帧")
	player.keys.clear()
	game._physics_process(DT)
	check(not game.time_charge.active and smoke.grenades[0] != grenade,
			"松开右键后原手雷接着飞不是重置")
	check(smoke.clouds[0]["age"] > cloud_age, "松开后烟幕从原寿命继续消散")
	smoke.clear_effects()


func _fire_through_player(damage_type := "gunshot") -> void:
	game.enemy_bullets.append({"x": player.position.x - 80, "y": player.position.y - 72,
			"vx": 3000.0, "vy": 0.0, "life": 1.0, "damage_type": damage_type})
	game._advance_enemy_bullets(0.08)


func _test_damage_and_cover() -> void:
	_place(_origin)
	check(not game.level.solid_at(player.position.x - 80, player.position.y - 72),
			"高速枪伤fixture起点在开放空气，不能用出生左外墙假装烟挡弹")
	_cover(player.position)
	check(game._player_in_smoke() and player.smoke_cover_active(), "烟内枪保护和主角深色剪影使用同一判定")
	var health := player.hp
	_fire_through_player()
	check(player.hp == health and game.enemy_bullets.is_empty(), "3000px每秒枪弹扫过头部时烟内不扣血且弹体终止")
	check(game.ENEMY_BULLET_SWEEP_STEP == 4.0, "枪弹保持原4px连续路径判定不退回单点")
	smoke.clear_effects()
	game._refresh_smoke_cover()
	_fire_through_player()
	check(player.hp == health - 1 and not player.smoke_cover_active(), "离烟后同弹速/同头部路径恢复正常命中")
	_place(_origin)
	_cover(player.position)
	_fire_through_player("laser")
	check(player.hp == 4, "枪弹入口也按伤害类型过滤，不将非枪击误当烟免伤")
	_place(_origin)
	var inspector: Node2D
	var gunner: Node2D
	for enemy: Node2D in game.minions:
		if inspector == null and enemy is FreightInspector:
			inspector = enemy
		if gunner == null and enemy is GruntGunner:
			gunner = enemy
	var saved := {"position": inspector.position, "state": inspector.state,
			"frame": inspector.frame, "hitstop": inspector.hitstop, "face": inspector.face}
	inspector.position = player.position + Vector2(55, 0)
	inspector.face = -1
	inspector.state = "attack"
	inspector.frame = inspector.ATTACK_ACTIVE_FROM
	inspector.hitstop = 1.0
	_cover(player.position)
	var before := player.hp
	game._physics_process(DT)
	check(player.hp == before - 1, "烟内照样被真实game近战攻击有效窗击中")
	for property: String in saved:
		inspector.set(property, saved[property])
	smoke.clear_effects()
	_place(_origin + Vector2(200, 0))
	var gunner_position := gunner.position
	gunner.position = player.position + Vector2(90, 0)
	gunner._sync_sprite()
	game._refresh_smoke_cover()
	var original_tint: Color = gunner._sprite.self_modulate
	var outline_value: Variant = (gunner._outline.material as ShaderMaterial).get_shader_parameter("outline_color")
	check(outline_value is Color and gunner._sprite.has_meta("smoke_base_outline"),
			"敌人原描边缓存显式保存Color，不把shader默认null写成缺失meta")
	# 若生产接线回归，记录明确失败后继续后续断言，不能因Color=null提前中断而假报整组通过。
	var original_outline: Color = outline_value if outline_value is Color else Color(0.09, 0.05, 0.14, 1.0)
	check(gunner.vision_blocker.is_valid() and inspector.vision_blocker.is_valid(), "枪手和近战索敌均接入烟线回调")
	check(gunner._has_los(), "测试枪手无遮挡时能看到玩家")
	_cover(gunner.position)
	check(not gunner._has_los(), "烟幕真正遮住枪手索敌而非仅改颜色")
	var enemy_silhouette: Color = gunner._sprite.self_modulate
	var covered_outline: Color = (gunner._outline.material as ShaderMaterial).get_shader_parameter("outline_color")
	check(enemy_silhouette.r < 0.10 and enemy_silhouette.g < 0.14 and enemy_silhouette.b < 0.16 \
			and is_equal_approx(enemy_silhouette.a, original_tint.a) and not gunner._rim.visible,
			"敌人入烟显示不透明深色剪影并关闭亮边提示")
	check(covered_outline.r < 0.35 and covered_outline.g < 0.4 and covered_outline.b < 0.4,
			"敌人烟内是暗灰轮廓，与主角浅青边区别明确")
	smoke.clear_effects()
	game._refresh_smoke_cover()
	check(gunner._has_los() and gunner._sprite.self_modulate == original_tint and gunner._rim.visible,
			"出烟视线/原色/轮廓同时恢复")
	check((gunner._outline.material as ShaderMaterial).get_shader_parameter("outline_color") == original_outline,
			"敌人离烟后恢复原描边材质参数，不留烟内暗边覆盖")
	gunner.position = gunner_position
	gunner._sync_sprite()


func _test_laser_and_press() -> void:
	var laser: Node2D = _hazards("laser_gate")[0]
	_place(Vector2(laser.position.x + 40, laser.position.y + 54 - 0.1))
	game._step_tactics(0.01)
	check(laser.armed and laser.state == "warning", "光栅必须当前房且真视口中才进入预警")
	_cover(player.position)
	var before := player.hp
	game._step_tactics(laser.warning_duration)
	check(laser.damage_active() and player.hp == before - 1, "站立烟内仍会被真实高光栅伤害")
	smoke.clear_effects()
	_place(Vector2(laser.position.x - 24, laser.position.y + 54 - 0.1))
	laser._change_state("warning")
	game._step_tactics(laser.warning_duration)
	check(laser.damage_active() and player.hp == 5, "翻滚测试从光束左侧安全位置起步")
	player.keys = {KEY_CTRL: true}
	player.step(DT)
	player.keys.clear()
	player.roll_invuln_t = 0.0 # 只验低框，不借最初0.14秒无敌窗蒙混过关。
	var entered_live_beam := false
	for _i in 17:
		player.step(DT)
		player.roll_invuln_t = 0.0
		game._step_tactics(DT)
		entered_live_beam = entered_live_beam or (laser.damage_active() \
				and player.position.x >= laser.position.x and player.position.x <= laser.position.x + laser.span)
	check(entered_live_beam and player.hp == 5, "真实Ctrl翻滚穿过已开启光栅，去掉无敌仍凭低框避开")
	check(player.position.x > laser.position.x + laser.span, "六格翻滚实际越过128px束线而非只站在边上")
	_place(Vector2(laser.position.x + 40, laser.position.y + 54 - 0.1))
	var laser_phase := float(laser.phase_time)
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	game._physics_process(0.15)
	check(game.time_charge.active and player.hp == 5 and laser.phase_time == laser_phase,
			"真实时停期间站在已开光栅中也不吃世界伤害，机关相位冻结")
	player.keys.clear()
	game._advance_time_charge(0.0)
	game._step_tactics(0.01)
	check(player.hp == 4, "松开时停仍站在通电光栅里会恢复受伤，不能永久冻结免伤")
	var press: Node2D = _hazards("press")[0]
	_place(Vector2(press.position.x + press.width * 0.5, press.floor_y - 0.1))
	game._step_tactics(0.01)
	_cover(player.position)
	before = player.hp
	game._step_tactics(press.warning_duration)
	game._step_tactics(0.14)
	check(press.damage_active() and player.hp == before - 1, "烟内真实压机下降扫掠仍击中头身")
	check(press.damage_rect().intersects(player.hurtbox_rect()), "压机伤害实际来自扫过的板体区域")
	smoke.clear_effects()


func _aim_fixture(sniper: Node2D) -> void:
	_place(sniper.position + Vector2(-300, 0))
	game.current_room = int(sniper.get_meta("room_index"))
	game.cam_tl = sniper.position - Vector2(800, 600)
	game.enemy_bullets.clear()


func _test_sniper_and_room_clear() -> void:
	var sniper: Node2D = _hazards("auto_sniper")[0]
	_aim_fixture(sniper)
	game._step_tactics(DT)
	check(sniper.armed and sniper.state == "warning", "指定难房内可见狙击开始真实跟踪")
	var original_target: Vector2 = sniper.last_target
	player.position.x -= 35
	game._step_tactics(0.95)
	check(sniper.state == "warning" and sniper.last_target != original_target and sniper.shot_count == 0,
			"前0.95秒持续追踪移动玩家且绝不提前出弹")
	game._step_tactics(0.1)
	check(sniper.aim_line_fast_flashing() and sniper.aim_line_alpha() >= 0.28,
			"预射末一秒红线快闪但暗相仍可见")
	game._step_tactics(0.451)
	check(sniper.state == "locked" and sniper.shot_count == 0, "1.5秒跟踪结束只锁方向不立即射击")
	var locked_target: Vector2 = sniper.last_target
	var locked_direction: Vector2 = sniper.aim_direction
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	game._physics_process(0.2)
	check(sniper.state == "locked" and is_zero_approx(sniper.phase_time) and sniper.shot_count == 0,
			"真实时停冻结最后半秒狙击锁定，炮不会绕过世界停表开枪")
	player.keys.clear()
	game._advance_time_charge(0.0)
	player.position.x += 100
	game._step_tactics(0.24)
	check(sniper.last_target == locked_target and sniper.aim_direction == locked_direction \
			and sniper.shot_count == 0, "锁向前0.24秒玩家移动不再带着红线追踪")
	_cover(player.position)
	check(sniper.state == "idle" and sniper.last_target == Vector2.ZERO and sniper.trace_end == Vector2.ZERO \
			and sniper.shot_count == 0 and game.enemy_bullets.is_empty(),
			"最后半秒已锁定时进烟也立即失锁，清红线与旧目标且取消发射")
	game._step_tactics(0.8)
	check(sniper.state == "idle" and sniper.shot_count == 0, "留在烟内超过旧发射时刻也不会补射")
	smoke.clear_effects()
	game._step_tactics(DT)
	check(sniper.state == "warning" and is_zero_approx(sniper.phase_time), "离烟重新启动完整1.5秒预警，不保留旧半秒")
	game._step_tactics(1.49)
	check(sniper.state == "warning" and sniper.shot_count == 0, "重新出烟后1.49秒仍不锁定或开枪")
	game._step_tactics(0.02)
	check(sniper.state == "locked" and sniper.shot_count == 0, "重新跟踪满1.5秒后才进入新锁定")
	# 已存在的烟停在玩家左侧；真实A+右键慢速走入，world dt为0时也必须取消锁定。
	smoke.deploy_cloud(player.position + Vector2(-400, 0))
	smoke.step(0.2)
	var held_cloud_age: float = smoke.clouds[0]["age"]
	game.time_charge.reset()
	player.keys = {MOUSE_BUTTON_RIGHT: true, KEY_A: true}
	for _i in 40:
		game._physics_process(DT)
		player.step(DT)
	check(game.time_charge.active and smoke.contains_actor(player) \
			and sniper.state == "idle" and sniper.trace_end == Vector2.ZERO and sniper.shot_count == 0,
			"真实时停中走入既存烟幕，0dt被动刷新仍立即取消锁定红线")
	check(is_equal_approx(smoke.clouds[0]["age"], held_cloud_age), "烟中失锁不偷偷推进冻结烟雾的寿命")
	player.keys.clear()
	game._advance_time_charge(0.0)
	smoke.clear_effects()
	game._step_tactics(DT)
	game._step_tactics(1.51)
	game._step_tactics(0.49)
	check(sniper.state == "locked" and sniper.shot_count == 0, "再次离烟重走1.5秒加0.49秒，不能解冻即偷射")
	game._step_tactics(0.02)
	check(sniper.shot_count == 1 and sniper.state == "recovery" and game.enemy_bullets.size() == 1,
			"重新完整1.5秒+半秒流程结束，经宿主只产生一发高速弹")
	if not game.enemy_bullets.is_empty():
		var shot: Dictionary = game.enemy_bullets[0]
		check(Vector2(shot.vx, shot.vy).length() >= 2400.0 and shot.damage_type == &"gunshot" and shot.sniper,
				"机关出弹是真正高速枪击类型而非绕过烟免疫的特殊伤害")
	game._step_tactics(1.48)
	check(sniper.state == "recovery" and sniper.shot_count == 1, "开枪后1.48秒持续冷却不连射")
	game._step_tactics(0.03)
	check(sniper.state == "idle" and sniper.shot_count == 1, "1.5秒冷却结束回空闲，必须重新完整预警")
	_cover(player.position)
	game._step_tactics(0.1)
	check(sniper.state == "idle", "烟中玩家不被未锁定狙击自动索敌")
	smoke.clear_effects()
	game._step_tactics(0.02)
	check(sniper.state == "warning", "离烟重新看见后从完整1.5秒警告开始")
	game.cam_tl += Vector2(3000, 0)
	game._step_tactics(DT)
	check(not sniper.armed and sniper.state == "idle", "离开屏幕取消旧锁定不隔屏狙击")
	game.cam_tl -= Vector2(3000, 0)
	game._step_tactics(DT)
	check(sniper.state == "warning" and is_zero_approx(sniper.phase_time), "再次进入视口不能沿用剩余半秒偷射")
	var room_index := int(sniper.get_meta("room_index"))
	var room: Rect2i = game.level.rooms[room_index].rect
	var changed: Array[Node2D] = []
	for enemy: Node2D in game.minions:
		if room.has_point(enemy.get_meta("spawn_cell")) and not enemy.dead:
			enemy.dead = true
			changed.append(enemy)
	game._step_tactics(DT)
	check(not changed.is_empty() and sniper.cleared_disabled and not sniper.armed,
			"当前房小兵清空后炮台永久停机，无需额外寻找一名器械敌人")
	for enemy in changed:
		enemy.dead = false # 只还原fixture标记，检查永久停机不因下一帧重算又唤醒。
	game._step_tactics(DT)
	check(sniper.cleared_disabled and not sniper.armed, "清房停机不会被可见性激活覆盖")
	game.enemy_bullets.clear()


func _test_cargo_target() -> void:
	var sniper: Node2D = _hazards("auto_sniper")[1]
	_aim_fixture(sniper)
	var cargo: PropBatCargo
	for prop: Node2D in game.props:
		if prop is PropBatCargo and not prop.dead:
			cargo = prop
			break
	var old_position := cargo.position
	cargo.position = sniper.position + Vector2(-170, -1)
	player.position = cargo.position + Vector2(-48, 0)
	player.face = 1
	player.on_ground = true
	# 最终交叉火力场原本有人站在箱旁；本用例仅验炮台材质反馈，把这几个演员临时移出轨迹。
	var relocated: Array[Dictionary] = []
	var test_lane := Rect2(cargo.position + Vector2(-80, -140), Vector2(330, 200))
	for enemy: Node2D in game.minions:
		if test_lane.intersects(enemy.body_rect()):
			relocated.append({"actor": enemy, "position": enemy.position})
			enemy.position -= Vector2(700, 0)
	var enemies: int = game.minions.size()
	var live_enemies: int = game._enemies().size()
	var splats: int = game.paint_layer.splat_count()
	var fx_children: int = game.fx_layer.get_child_count()
	check(game._cargo_targets().has(sniper) and not game._enemies().has(sniper),
			"可击飞物目标包含炮台但普通清敌列表不包含器械")
	game._on_player_bat_swung(cargo.body_rect(), 1)
	check(cargo.flying, "真实球棒命中链成功发射现场货箱")
	for _i in 30:
		if cargo.dead:
			break
		game._physics_process(DT)
	check(sniper.dead and cargo.dead, "飞行货箱连续扫掠命中并摧毁自动狙击器")
	check(game.minions.size() == enemies and game._enemies().size() == live_enemies,
			"击毁炮台不污染最新地图小兵分母/存活数")
	check(game.paint_layer.splat_count() == splats and game.fx_layer.get_child_count() == fx_children,
			"器械毁坏只走金属火花，不生成生物血池/喷血实例")
	for entry in relocated:
		entry.actor.position = entry.position
	cargo.position = old_position


func _test_death_retry() -> void:
	_place(_origin)
	player.configure_max_health(1)
	player.set_carried_smoke(true)
	_cover(player.position)
	player.set_carried_smoke(true)
	var music_id: int = game.music.get_instance_id()
	await create_timer(0.12).timeout
	game.music.play(7.0)
	await create_timer(0.12).timeout
	var playback_id: int = game.music.get_stream_playback().get_instance_id()
	var old_scene_id: int = current_scene.get_instance_id()
	var music_position: float = game.music.get_playback_position()
	player.force_death(player.position.x - 60)
	check(game.time_phase == "dying" and not player.carried_smoke and not player._smoke_carry_ui.visible,
			"真正主角死亡立即收起携带图标而非留在尸体头顶")
	game._begin_rewind()
	check(game.time_phase == "rewinding" and smoke.clouds.is_empty() and smoke.grenades.is_empty(),
			"死亡短倒带入口清掉烟雾和飞行手雷，不重放抛投")
	var pending_count: int = smoke.pickups.size()
	check(pending_count == _expected_pickup_count - 1, "倒带清动态特效不擅自回填已拾取补给")
	player.set_carried_smoke(true)
	game._on_smoke_throw_requested(player.position + Vector2(200, 0))
	check(smoke.grenades.is_empty(), "倒带阶段宿主拒绝投掷请求")
	game._advance_rewind(game.REWIND_DURATION + game.INTERFERENCE_DURATION + 0.01)
	for _i in 4:
		await process_frame
	check(is_instance_valid(current_scene) and current_scene.get_instance_id() != old_scene_id \
			and current_scene.has_node("Game"), "故障收尾经生产change_scene真正重建M04关卡")
	_prepare()
	await create_timer(0.12).timeout
	check(game.minions.size() == _expected_enemy_count and game._enemies().size() == _expected_enemy_count \
			and _cargo_count() == _expected_cargo_count, "重开恢复全部最新敌人和20货箱")
	check(smoke.pickups.size() == _expected_pickup_count and smoke.grenades.is_empty() \
			and smoke.clouds.is_empty() and not player.carried_smoke, "重开完整恢复6补给但不继承烟雾手雷或背包")
	check(not player.dead and player.hp == 3 and player.max_hp == 3 and SESSION.attempt == 2,
			"困难3血和新轮次数由生产会话恢复，不保留fixture临时血量")
	check(_hazards("auto_sniper")[0].cleared_disabled == false and not _hazards("auto_sniper")[1].dead,
			"新一轮停机/毁坏炮台按地图完整重置")
	check(game.music.get_instance_id() == music_id \
			and game.music.get_stream_playback().get_instance_id() == playback_id,
			"长关死亡重开沿用同一个BGM节点和底层Playback")
	check(game.music.playing and game.music.get_playback_position() >= music_position - 0.05 \
			and game.music.get_playback_position() >= 7.0,
			"长关BGM不中断不归零，播放进度正常延续")
