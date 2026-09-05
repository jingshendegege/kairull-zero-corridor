extends SceneTree
## 无头逻辑单测（v2：枪械专精 + 右键瞄准 + Boss 战）。
## 跑法：godot --headless --path godot --import 之后
##       godot --headless --path godot --script scripts/test_game_logic.gd

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func approx(a: float, b: float, tol := 0.5) -> bool:
	return absf(a - b) <= tol


func _init() -> void:
	print("== AtlasDB ==")
	var db := AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json",
	])
	# 7 基础（aim/run/slide×3/death）+ 9 bat 追加 + 8 hero 追加 = 24；roll 由玩家按需登记。
	ok(db.actions.size() == 24, "基础图集 24 动作", str(db.actions.size()))
	ok(int(db.actions["gun_jump_air"]["frames"]) == 34, "枪械跳跃空中段 34 帧")
	ok(int(db.actions["gun_reload"]["frames"]) == 124, "换弹动画 124 帧")
	ok(int(db.actions["gun_idle"]["frames"]) == 124, "站立呼吸 124 帧（真·呼吸视频）")

	print("== CorridorLevel ==")
	var level := CorridorLevel.new()
	level.build(false)
	ok(level.map_w == 160 and level.map_h == 24, "地图 160×24")
	ok(approx(level.spawn.x, 4 * 32 + 16, 0.1), "出生点解析")
	ok(level.enemy_spawns.size() == 5, "5 个敌人刷点")
	ok(level.solid_at(5.5 * 32, 19.5 * 32), "地面实心")
	ok(level.is_platform(43.5 * 32, 16.5 * 32), "单向平台")
	# 表面分类：飞溅特效的接触判断
	var surf_floor: Dictionary = level.surface_at(5.5 * 32, 19.5 * 32)
	ok(surf_floor["kind"] == "floor" and surf_floor["normal"] == Vector2.UP,
		"地面顶面判为 floor", str(surf_floor))
	var surf_wall: Dictionary = level.surface_at(42.9 * 32, 13.5 * 32)
	ok(surf_wall["kind"] == "wall" and surf_wall["normal"] == Vector2.RIGHT,
		"竖井侧壁判为 wall 且法线朝开放侧", str(surf_wall))
	var surf_plat: Dictionary = level.surface_at(43.5 * 32, 16.5 * 32)
	ok(surf_plat["kind"] == "platform" and surf_plat["material"] == "metal",
		"单向台判为 platform/metal", str(surf_plat))
	ok(level.surface_at(10.0 * 32, 5.0 * 32)["kind"] == "none", "空气判为 none")

	print("== 玩家基础 ==")
	var player := KairullPlayer.new()
	player.auto_input = false
	player.db = db
	player.level = level
	get_root().add_child(player)
	player.spawn = level.spawn
	player.reset_to_spawn()
	for i in range(30):
		player.step(1.0 / 60)
	ok(db.actions.has("hero_roll") and int(db.actions["hero_roll"]["frames"]) == 6,
			"玩家步进前登记翻滚六帧图集")
	ok(player.on_ground and player.state == "gun_idle", "出生站立 gun_idle", player.state)
	ok(player.current_clip() == "hero_idle", "站立播持棍待机", player.current_clip())

	print("== Shift 闪现、Ctrl 翻滚与时间型虚影 ==")
	# 闪现不再单帧瞬移：约 0.11s 走完 5.5 格；翻滚放慢到约 0.33s、加长到 6 格。
	var dash_api: bool = player.has_method("dashing") and player.has_method("rolling") \
			and player.has_method("dash_afterimage_count") \
			and player.has_method("dash_cooldown_ui_visible")
	ok(dash_api, "玩家已接入闪现/翻滚 API")
	if dash_api:
		ok(approx(KairullPlayer.DASH_COOLDOWN, 1.5, 0.001), "闪现冷却固定为 1.5 秒")
		player.position = Vector2(64, 19 * 32 - 0.1)
		player.vy = 0.0
		player.on_ground = true
		player.keys = {KEY_D: true}
		player.step(1.0 / 60)
		var run_vx: float = player.vx
		ok(approx(run_vx, KairullPlayer.RUN, 0.01), "普通奔跑使用唯一水平速度", str(run_vx))

		var dash_from_x: float = player.position.x
		player.keys = {KEY_D: true, KEY_SHIFT: true}
		player._prev_keys = {}
		player.step(1.0 / 60)
		var dash_step_distance: float = player.position.x - dash_from_x
		ok(dash_step_distance > 0.0 and dash_step_distance < KairullPlayer.DASH_DISTANCE,
				"Shift 首帧开始高速位移但不再瞬移到终点", str(dash_step_distance))
		ok(bool(player.call("dashing")) and player.current_clip() == "hero_bat3",
				"闪现期间保持伸展棍影", player.current_clip())
		var dash_ui := player.get_node("DashCooldownUI") as Node2D
		ok(player.dash_cooldown_ui_visible() and dash_ui.get_parent() == player \
				and not dash_ui.top_level, "冷却 UI 只在冷却中显示并作为玩家子节点跟随")
		ok(approx(player.dash_cooldown_t, 1.5, 0.01), "冲刺起步立即进入 1.5 秒冷却",
				str(player.dash_cooldown_t))
		var hp_before_dash := player.hp
		player.take_damage(1, player.position.x - 100.0)
		ok(player.hp == hp_before_dash, "闪现途中保持无敌")
		var dash_peak_ghosts := int(player.call("dash_afterimage_count"))
		var dash_ticks := 1
		while player.dashing() and dash_ticks < 20:
			player.keys = {KEY_D: true, KEY_SHIFT: true}
			player.step(1.0 / 60)
			dash_ticks += 1
			dash_peak_ghosts = maxi(dash_peak_ghosts,
					int(player.call("dash_afterimage_count")))
		ok(dash_ticks >= 6 and dash_ticks <= 8, "闪现约 0.11s 完成", str(dash_ticks))
		ok(approx(player.position.x - dash_from_x, KairullPlayer.DASH_DISTANCE, 2.0),
				"闪现距离轻降为 5.5 格", str(player.position.x - dash_from_x))
		ok(dash_peak_ghosts >= 5, "闪现移动过程中依次生成虚影", str(dash_peak_ghosts))
		var sprite: Sprite2D = player.get_node("Sprite")
		ok(sprite.material == null, "闪现结束后本体恢复原色")
		ok(player.dash_cooldown_ui_visible() and player.dash_cooldown_t > 1.3,
				"冲刺结束后 CD 提示继续显示", str(player.dash_cooldown_t))
		for i in range(24):
			player.keys = {KEY_D: true, KEY_SHIFT: true}
			player.step(1.0 / 60)
		var fading_ghosts := int(player.call("dash_afterimage_count"))
		ok(fading_ghosts > 0 and fading_ghosts < dash_peak_ghosts,
				"闪现虚影按各自出生时间依次消散", "%d/%d" % [fading_ghosts, dash_peak_ghosts])

		# 制造新的 Shift 边沿：冷却未完不能再次冲刺；归零后 UI 隐藏且可再次启动。
		player.keys = {}
		player.step(1.0 / 60)
		var cooldown_block_x := player.position.x
		player.keys = {KEY_SHIFT: true}
		player.step(1.0 / 60)
		ok(not player.dashing() and approx(player.position.x, cooldown_block_x, 0.01),
				"1.5 秒 CD 内新的 Shift 不会再次冲刺")
		player.keys = {}
		while player.dash_cooldown_t > 0.0:
			player.step(1.0 / 60)
		ok(not player.dash_cooldown_ui_visible(), "CD 归零后头顶提示自动隐藏")
		player.keys = {KEY_SHIFT: true}
		player._prev_keys = {}
		player.step(1.0 / 60)
		ok(player.dashing(), "1.5 秒 CD 结束后可再次冲刺")

		# Ctrl 使用新翻滚，不会重新启用旧 slide_*；翻滚速度低于闪现。
		player.reset_to_spawn()
		player.position = Vector2(400, 19 * 32 - 0.1)
		player.vy = 0.0
		player.on_ground = true
		player.keys = {KEY_D: true, KEY_CTRL: true}
		player._prev_keys = {}
		var roll_from_x := player.position.x
		var hp_before_roll := player.hp
		player.step(1.0 / 60)
		ok(player.rolling() and player.current_clip() == "hero_roll", "Ctrl 进入六帧翻滚",
				player.state)
		player.take_damage(1, player.position.x - 100.0)
		ok(player.hp == hp_before_roll, "翻滚前段无敌")
		var roll_peak_ghosts := player.dash_afterimage_count()
		var roll_ticks := 1
		while player.rolling() and roll_ticks < 30:
			player.keys = {KEY_D: true, KEY_CTRL: true}
			player.step(1.0 / 60)
			roll_ticks += 1
			roll_peak_ghosts = maxi(roll_peak_ghosts, player.dash_afterimage_count())
		ok(roll_ticks >= 19 and roll_ticks <= 21, "翻滚放慢到约 0.33s", str(roll_ticks))
		ok(approx(player.position.x - roll_from_x, KairullPlayer.ROLL_DISTANCE, 2.0),
				"翻滚位移加长为 6 格", str(player.position.x - roll_from_x))
		ok(KairullPlayer.DASH_DISTANCE / KairullPlayer.DASH_DURATION \
				> KairullPlayer.ROLL_DISTANCE / KairullPlayer.ROLL_DURATION,
				"翻滚速度低于闪现")
		ok(roll_peak_ghosts >= 5, "翻滚复用同款时间型虚影", str(roll_peak_ghosts))
		ok(not player.sliding(), "旧滑铲仍禁用", player.state)

		# 翻滚期间的新 Shift 边沿可取消成冲刺；旧翻滚无敌不能叠加到冲刺后。
		player.reset_to_spawn()
		player.position = Vector2(400, 19 * 32 - 0.1)
		player.vy = 0.0
		player.on_ground = true
		player.keys = {KEY_D: true, KEY_CTRL: true}
		player._prev_keys = {}
		player.step(1.0 / 60)
		player.keys = {KEY_D: true}
		player.step(1.0 / 60)
		var kept_roll_cd := player.roll_cooldown_t
		player.keys = {KEY_D: true, KEY_SHIFT: true}
		player.step(1.0 / 60)
		ok(player.dashing(), "翻滚中按 Shift 可立即转冲刺", player.state)
		ok(player.roll_invuln_t == 0.0 and player.roll_cooldown_t > 0.0 \
				and player.roll_cooldown_t <= kept_roll_cd,
				"转冲刺时清除翻滚无敌并保留翻滚 CD")

		# 空中翻滚继续受重力；空中冲刺只在动作期间冻结高度，结束后恢复下落。
		player.reset_to_spawn()
		# y=544 位于中层楼板下方、底层地面上方的明确净空带，不能把身体塞进 r12-13 楼板。
		player.position = Vector2(400, 19 * 32 - 64.0)
		player.vy = 4.0
		player.on_ground = false
		player.set_state("gun_jump_air")
		player.keys = {KEY_D: true, KEY_CTRL: true}
		player._prev_keys = {}
		var air_roll_y := player.position.y
		player.step(1.0 / 60)
		ok(player.rolling() and player.position.y > air_roll_y and player.vy > 4.0,
				"空中翻滚保持重力下落", "pos=%s vy=%.2f" % [player.position, player.vy])

		player.reset_to_spawn()
		player.position = Vector2(400, 19 * 32 - 64.0)
		player.vy = 4.0
		player.on_ground = false
		player.set_state("gun_jump_air")
		player.keys = {KEY_D: true, KEY_SHIFT: true}
		player._prev_keys = {}
		var air_dash_y := player.position.y
		var air_dash_stable := true
		player.step(1.0 / 60)
		var air_dash_started := player.dashing()
		var air_dash_ticks := 1
		while player.dashing() and air_dash_ticks < 20:
			player.keys = {KEY_D: true, KEY_SHIFT: true}
			player.step(1.0 / 60)
			air_dash_stable = air_dash_stable and approx(player.position.y, air_dash_y, 0.01)
			air_dash_ticks += 1
		ok(air_dash_started and air_dash_stable, "空中冲刺全程锁住高度",
				"started=%s dy=%.2f" % [air_dash_started, player.position.y - air_dash_y])
		player.keys = {}
		player.step(1.0 / 60)
		ok(player.position.y > air_dash_y, "空中冲刺结束后恢复下落", str(player.position.y))

		# 普通跳跃仍只继承奔跑水平速度，不受两种爆发移动影响。
		player.keys = {}
		player.step(1.0 / 60)
		player.position = Vector2(400, 19 * 32 - 0.1)
		player.vy = 0.0
		player.on_ground = true
		player.set_state("gun_idle")
		player.keys = {KEY_D: true, KEY_W: true}
		player._prev_keys = {}
		player.step(1.0 / 60)
		ok(player.state == "gun_jump_air" and approx(absf(player.vx), run_vx, 0.01),
				"跳跃水平速度与奔跑一致", str(player.vx))

		player.keys = {}
		for i in range(40):
			player.step(1.0 / 60)
		ok(int(player.call("dash_afterimage_count")) == 0, "不足一秒后全部移动虚影清理")

	# 后续规则测试从稳定站立状态开始，避免冲刺位移串扰。
	player.keys = {}
	player.vx = 0.0
	player.set_state("gun_idle")

	print("== 右键瞄准规则 ==")
	# 非瞄准：鼠标在右上也不影响朝向/仰角
	player.aim_override = player.position + Vector2(300, -200)
	player.step(1.0 / 60)
	ok(player.aim_deg == 0.0, "非瞄准仰角恒 0", str(player.aim_deg))
	# 朝向由移动方向决定
	player.keys = {KEY_A: true}
	player.step(1.0 / 60)
	ok(player.face == -1, "按 A 朝左（不管鼠标）")
	player.keys = {KEY_D: true}
	player.step(1.0 / 60)
	ok(player.face == 1, "按 D 朝右")
	# 右键按住：精细瞄准 + 锁移动（枪械禁用后右键不再瞄准）
	player.keys = {KEY_D: true, MOUSE_BUTTON_RIGHT: true}
	player.aim_override = player.position + Vector2(300, -200)
	player.step(1.0 / 60)
	if KairullPlayer.GUN_ENABLED:
		ok(player.aiming and player.state == "aim", "右键进入瞄准态", player.state)
		ok(player.aim_deg > 20.0, "瞄准仰角跟随鼠标", str(player.aim_deg))
		ok(player.vx == 0.0, "瞄准时锁移动", str(player.vx))
		ok(player.face == 1, "瞄准时鼠标定朝向")
		player.keys = {}
		player.step(1.0 / 60)
		ok(player.state == "gun_idle", "松右键回站立", player.state)
	else:
		ok(not player.aiming and player.state != "aim", "枪械禁用：右键不进瞄准态", player.state)
		ok(player.vx != 0.0, "枪械禁用：右键不锁移动", str(player.vx))
		player.keys = {}
		player.step(1.0 / 60)

	print("== 射击规则 ==")
	if KairullPlayer.GUN_ENABLED:
		# 移动中水平直射（非瞄准也可以开火，用户决策）
		player.keys = {KEY_D: true}
		player.step(1.0 / 60)
		var b: Dictionary = player.try_shoot()
		ok(not b.is_empty() and b["vy"] == 0.0, "移动中水平直射")
		player.keys = {}
		for i in range(10):
			player.step(1.0 / 60)
		# 静止水平开火
		b = player.try_shoot()
		ok(not b.is_empty() and b["vy"] == 0.0 and absf(b["vx"]) > 1000, "静止水平直射")
		# 瞄准开火按膛线飞
		player.keys = {MOUSE_BUTTON_RIGHT: true}
		player.aim_override = player.position + Vector2(300, -200)
		player.step(1.0 / 60)
		for i in range(10):
			player.step(1.0 / 60)   # 等冷却
		b = player.try_shoot()
		ok(not b.is_empty() and b["vy"] < 0.0, "瞄准斜射", str(Vector2(b["vx"], b["vy"])))
		player.keys = {}
	else:
		ok(player.try_shoot().is_empty(), "枪械禁用：try_shoot 恒空")
		ok(player.gun_pose().is_empty() == false, "瞄准 LUT 机制保留（资产留存）")

	print("== 换弹规则 ==")
	player.gun_ammo = 3
	if KairullPlayer.GUN_ENABLED:
		# 移动中不能开始换弹
		player.keys = {KEY_D: true}
		player.start_reload()
		ok(not player.reloading, "移动中不能开始换弹")
		player.keys = {}
		# 瞄准中不能开始
		player.keys = {MOUSE_BUTTON_RIGHT: true}
		player.step(1.0 / 60)
		player.start_reload()
		ok(not player.reloading, "瞄准中不能开始换弹")
		# 静止站立可以
		player.keys = {}
		player.step(1.0 / 60)
		player.start_reload()
		ok(player.reloading and player.state == "gun_reload", "静止开始换弹")
		ok(approx(player.reload_t, 0.845057, 0.001), "换弹时长与原始音效一致", str(player.reload_t))
		# 移动打断
		player.keys = {KEY_D: true}
		player.step(1.0 / 60)
		player.keys = {}
		ok(not player.reloading and player.gun_ammo == 3, "移动打断换弹且不补弹")
		# 断点续弹：打断时已走 1 步，重来后续到完成总耗时 < 全程
		var interrupted_progress: float = player.reload_elapsed
		ok(interrupted_progress > 0.0, "打断保留进度", str(interrupted_progress))
		player.start_reload()
		ok(player.reload_t < KairullPlayer.RELOAD_TIME, "续弹从断点计时", str(player.reload_t))
		for i in range(200):
			player.step(1.0 / 60)
		ok(not player.reloading and player.gun_ammo == 8, "续弹完成弹药回满",
			str(player.gun_ammo))
		ok(player.reload_elapsed == 0.0, "完成后进度清零")
	else:
		player.keys = {}
		player.step(1.0 / 60)
		player.start_reload()
		ok(not player.reloading, "枪械禁用：换弹不启动")
		ok(player.state != "gun_reload", "枪械禁用：不进换弹态", player.state)

	print("== 旧滑铲保持禁用 ==")
	if KairullPlayer.SLIDE_ENABLED:
		player.position = Vector2(64, 19 * 32 - 0.1)
		player.vy = 0.0
		player.on_ground = true
		player.keys = {KEY_D: true, KEY_CTRL: true}
		player.step(1.0 / 60)
		ok(player.state == "slide_start", "奔跑中滑铲", player.state)
		for i in range(40):
			player.step(1.0 / 60)
		ok(player.state == "slide_loop", "滑铲循环", player.state)
		# 滑铲接跳
		player.keys = {KEY_D: true, KEY_CTRL: true, KEY_W: true}
		player.step(1.0 / 60)
		player.keys = {}
		ok(player.state == "gun_jump_air" and not player.sliding(), "滑铲接跳", player.state)
		for i in range(200):
			player.step(1.0 / 60)
			if player.on_ground:
				break
		ok(player.on_ground, "落地零僵直")
		# 滑铲最大时长自动起身
		player.position = Vector2(64, 19 * 32 - 0.1)
		player.vy = 0.0
		player.on_ground = true
		player.keys = {KEY_D: true, KEY_CTRL: true}
		player.step(1.0 / 60)
		ok(player.sliding(), "自动起身前置：确实进入了滑铲", player.state)
		for i in range(120):
			player.step(1.0 / 60)
		ok(not player.sliding(), "滑铲到时自动起身", player.state)
		player.keys = {}
	else:
		player.position = Vector2(64, 19 * 32 - 0.1)
		player.vy = 0.0
		player.on_ground = true
		player.set_state("gun_idle")
		player.keys = {KEY_D: true, KEY_CTRL: true}
		player._prev_keys = {}
		player.step(1.0 / 60)
		ok(not player.sliding() and player.rolling(), "滑铲禁用：Ctrl 已改为翻滚", player.state)
		player.keys = {}

	print("== 玩家生命 ==")
	player.position = Vector2(800, 19 * 32 - 0.1)
	for i in range(30):
		player.step(1.0 / 60)
	player.take_damage(1, player.position.x - 100)
	ok(player.hp == 4, "受击 -1", str(player.hp))
	ok(player.vx > 0, "受击击退向右（伤害来自左侧）")
	var hp_before: int = player.hp
	player.take_damage(1, 0.0)
	ok(player.hp == hp_before, "无敌帧内不重复掉血")
	for i in range(40):
		player.step(1.0 / 60)   # 过无敌帧
	for i in range(4):   # 再 4 击打空（5-1-4=0）
		player.take_damage(1, 0.0)
		for j in range(40):
			player.step(1.0 / 60)
	ok(player.dead and player.state == "death", "HP 打空死亡", player.state)
	player.reset_to_spawn()
	ok(not player.dead and player.hp == 5, "重置回满血")

	print("== 小怪（悬浮法球）与 Red Boss ==")
	var boss := KairullBoss.new()
	get_root().add_child(boss)
	var orbs: Array = []
	boss.shoot_orb.connect(func(fp: Vector2, v: Vector2) -> void: orbs.append([fp, v]))
	boss.player = player
	boss.position = Vector2(player.position.x + 900, 19 * 32 - 96)
	for i in range(30):
		boss.step(1.0 / 60)
	ok(boss.state == "idle", "小怪远距离待机", boss.state)
	boss.position = Vector2(player.position.x + 300, 19 * 32 - 96)
	for i in range(80):
		boss.step(1.0 / 60)
	ok(orbs.size() >= 1, "小怪远程出弹", str(orbs.size()))
	boss.take_hit(player.position.x, 1)
	boss.take_hit(player.position.x, 1)
	boss.take_hit(player.position.x, 1)
	ok(boss.dead, "小怪 3 血打空即死")
	boss.queue_free()

	# Red Boss：100 血、地面追击、攻击欲望强
	var red := RedBoss.new()
	get_root().add_child(red)
	red.player = player
	red.level = level
	red.position = Vector2(900, 19 * 32 - 0.1)
	ok(red.hp == 100, "Red Boss 100 血")
	for i in range(30):
		red.step(1.0 / 60)
	ok(red.state == "idle", "Red 远距离待机（玩家在 700px 外）", red.state)
	# 玩家在 600：距离 300 < 700，Red 应快速逼近并在贴脸后进连击
	player.position = Vector2(600, 19 * 32 - 0.1)
	var x0: float = red.position.x
	var attacked := false
	for i in range(90):
		red.step(1.0 / 60)
		if red.state == "attack1" or red.state == "attack2":
			attacked = true
			break
	ok(red.position.x < x0 - 100, "Red 快速逼近玩家",
		"x0=%.0f→%.0f" % [x0, red.position.x])
	ok(attacked, "逼近后进入连击（攻击欲望）", red.state)
	red.queue_free()

	print("== Boss 连带重置 ==")
	var hornet := HornetBoss.new()
	get_root().add_child(hornet)
	hornet.player = player
	hornet.level = level
	hornet.position = Vector2(900, 19 * 32)
	hornet.hp = 3
	hornet.dead = true
	hornet.state = "dead"
	hornet.reset_to(Vector2(1000, 19 * 32))
	ok(hornet.hp == HornetBoss.HP_MAX and not hornet.dead and hornet.state == "idle",
		"Boss 重置回血回 idle")
	ok(hornet.position == Vector2(1000, 19 * 32), "Boss 重置回驻守位")
	hornet.queue_free()

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
