extends SceneTree
## 正式game伤害链无头回归：头部、翻滚低框、敌弹扫掠、遮挡优先级和时间冻结。
const GAME := preload("res://scripts/game.gd")
const FEET := Vector2(640.0, 383.9)
const DT := 1.0 / 60.0
var passed := 0
var failed := 0
var game: Node2D
var player: KairullPlayer
var level: CorridorLevel
var atlas: AtlasDB

class MeleeProbe extends Node2D:
	var dead := false
	var state := "attack"
	var frame := 4
	func step(_dt: float) -> void:
		pass
	func attack_active() -> bool:
		return true
	func attack_rect() -> Rect2:
		return Rect2(position + Vector2(-8, -78), Vector2(16, 12))
	func body_rect() -> Rect2:
		return attack_rect()


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	atlas = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
			"res://assets/clips/hero/hero_atlas.json"])
	level = CorridorLevel.new()
	_arena()
	player = KairullPlayer.new()
	player.auto_input = false
	player.db = atlas
	player.level = level
	player.spawn = FEET
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	# 不启动game的场景构建，仅注入真实玩家/碰撞网格，直接运行生产物理函数。
	game = GAME.new()
	game.level = level
	game.player = player
	game.action_audio_enabled = false
	_test_boxes()
	_test_head_and_sweep()
	_test_roll()
	_test_blockers()
	_test_melee_and_time()
	game.free()
	player.free()
	level.free()
	atlas = null
	await process_frame
	print("=== %d 通过, %d 失败 ===" % [passed, failed])
	print("TEST_RESULT: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)


func _arena(wall_col := -1) -> void:
	var rows := PackedStringArray()
	for y in 14:
		var row := "#".repeat(40) if y == 12 else ".".repeat(40)
		if wall_col >= 0 and y < 12:
			row = row.substr(0, wall_col) + "#" + row.substr(wall_col + 1)
		rows.append(row)
	level.grid = rows
	level.map_w = 40
	level.map_h = 14
	level.world_w = 1280
	level.world_h = 448
	level.stairs = []


func _reset() -> void:
	player.reset_to_spawn()
	player.position = FEET
	player.face = 1
	player.on_ground = true
	player.invuln_t = 0.0
	player.roll_invuln_t = 0.0
	player.keys.clear()
	player._prev_keys.clear()
	game.enemy_bullets.clear()
	game.fx.clear()
	game.timeline_enabled = false
	game.time_phase = "playing"
	game.time_charge.reset()
	_arena()


func _fire(origin: Vector2, velocity: Vector2, life := 3.0) -> void:
	game._on_boss_shoot_orb(origin, velocity)
	game.enemy_bullets[-1]["life"] = life


func _test_boxes() -> void:
	_reset()
	var physical: Rect2 = game._player_rect()
	var standing: Rect2 = game._player_hurtbox()
	check(physical.size == Vector2(22, 52), "地图移动/出口物理框仍为22×52")
	check(standing.size == Vector2(34, 82), "站立受击框34×82覆盖头部")
	check(is_equal_approx(standing.end.y, FEET.y), "站立框贴合脚底锚点")
	check(is_equal_approx(standing.get_center().x, FEET.x + 6), "朝右站立框跟随前倾身体6px")
	player.face = -1
	check(is_equal_approx(player.hurtbox_rect().get_center().x, FEET.x - 6), "朝左站立框镜像偏移")
	check(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED, "保持纯球棒、不恢复枪械或滑铲")
	player.set_state("roll")
	check(game._player_hurtbox().size == Vector2(38, 34), "翻滚受击框降低为38×34")
	check(game._player_rect() == physical, "翻滚低框不挤改通行/门口物理框")
	check(is_equal_approx(player.hurtbox_rect().get_center().x, FEET.x), "翻滚低框无左右偏移")
	check(is_equal_approx(player.hurtbox_rect().end.y, FEET.y), "翻滚框仍贴地、不悬浮")
	player._finish_roll()
	check(game._player_hurtbox().size == standing.size, "翻滚结束立即恢复站立高度")


func _test_head_and_sweep() -> void:
	_reset()
	var head_y := FEET.y - 72
	check(not game._player_rect().has_point(Vector2(FEET.x, head_y)), "头部用例确实位于旧物理框之外")
	_fire(Vector2(FEET.x - 16, head_y), Vector2(360, 0))
	game._physics_process(DT)
	check(player.hp == player.max_hp - 1, "普通速度敌弹打中头部扣血")
	check(game.enemy_bullets.is_empty(), "头部命中后弹丸消失")
	check(player.vx > 0, "左侧来弹将角色向右击退")
	_reset()
	_fire(Vector2(FEET.x - 150, head_y), Vector2(6000, 0))
	game._physics_process(0.05)
	check(player.hp == player.max_hp - 1 and game.enemy_bullets.is_empty(), "单帧300px高速弹不跨过头部")
	check(player.vx > 0, "高速穿越候选终点不反转击退方向")
	_reset()
	_fire(Vector2(FEET.x + 150, head_y), Vector2(-1200, 0))
	game._physics_process(0.25)
	check(player.hp == player.max_hp - 1 and player.vx < 0, "大dt右侧来弹仍先击中并向左击退")
	_reset()
	_fire(Vector2(FEET.x - 100, FEET.y - 120), Vector2(1200, 600))
	game._physics_process(0.2)
	check(player.hp == player.max_hp - 1, "斜向高速敌弹按路径而非终点检测")
	_reset()
	_fire(Vector2(FEET.x + 6, FEET.y - 180), Vector2(0, 1600))
	game._physics_process(0.15)
	check(player.hp == player.max_hp - 1, "向下敌弹先接触头顶而非穿头落地")
	_reset()
	_fire(Vector2(FEET.x - 180, head_y), Vector2(1200, 0), 0.05)
	game._physics_process(0.2)
	check(player.hp == player.max_hp and game.enemy_bullets.is_empty(), "寿命到期的子弹不再超时飞行造成隔空伤害")


func _test_roll() -> void:
	_reset()
	player.set_state("roll")
	player.roll_invuln_t = 0.0
	_fire(Vector2(FEET.x - 70, FEET.y - 60), Vector2(1200, 0))
	game._physics_process(0.12)
	check(player.hp == player.max_hp and game.enemy_bullets.size() == 1,
			"翻滚无敌窗过后仍可凭低姿态躲过高弹")
	game.enemy_bullets.clear()
	_fire(Vector2(FEET.x - 70, FEET.y - 18), Vector2(1200, 0))
	game._physics_process(0.12)
	check(player.hp == player.max_hp - 1 and game.enemy_bullets.is_empty(),
			"翻滚无敌窗过后低弹真实命中，不变成全程无敌")
	_reset()
	player.keys = {KEY_CTRL: true}
	player.step(DT)
	check(player.rolling() and player.roll_invuln_t > 0, "真实Ctrl起滚保留原短无敌窗")
	var roll_pos := player.position
	_fire(roll_pos + Vector2(-40, -18), Vector2(1200, 0))
	game._physics_process(0.06)
	check(player.hp == player.max_hp, "翻滚短无敌窗内低弹不扣血")
	player.keys.clear()
	for index in 30:
		player.step(DT)
	check(not player.rolling() and player.hurtbox_rect().size == Vector2(34, 82),
			"真实翻滚动画播放结束后受击框自动还原")
	game.enemy_bullets.clear()
	_fire(player.position + Vector2(-40, -72), Vector2(1200, 0))
	game._physics_process(0.06)
	check(player.hp == player.max_hp - 1, "起身后同样高度子弹重新能打中头部")
	_reset()
	player.set_state("dash")
	_fire(FEET + Vector2(-60, -72), Vector2(1200, 0))
	game._physics_process(0.1)
	check(player.hp == player.max_hp, "冲刺仍沿用原本免伤语义")
	_reset()
	player.invuln_t = 0.4
	_fire(FEET + Vector2(-60, -72), Vector2(1200, 0))
	game._physics_process(0.1)
	check(player.hp == player.max_hp, "受伤后保护期不因新受击框而丢失")


func _test_blockers() -> void:
	_reset()
	_arena(18) # x576..607的墙位于弹起点与玩家之间。
	_fire(FEET + Vector2(-140, -72), Vector2(2000, 0))
	game._physics_process(0.12) # 小于0.14秒火花寿命，才能在物理帧末检查拦截位置。
	check(player.hp == player.max_hp and game.enemy_bullets.is_empty(), "高速敌弹先被墙挡住，不穿墙伤头")
	check(game.fx.size() == 1 and game.fx[0]["x"] < FEET.x - 32,
			"撞墙火花留在真实拦截位置而非弹道终点")
	_reset()
	var door := RoomDoor.new()
	door.position = FEET + Vector2(-65, 0)
	door.locked = true
	game.doors.append(door)
	_fire(FEET + Vector2(-140, -72), Vector2(2000, 0))
	game._physics_process(0.15)
	check(player.hp == player.max_hp and game.enemy_bullets.is_empty(), "锁定门位于弹道前段时先挡敌弹")
	door.locked = false
	_fire(FEET + Vector2(-140, -72), Vector2(2000, 0))
	game._physics_process(0.15)
	check(player.hp == player.max_hp - 1, "解锁门不再拦截头部弹道")
	game.doors.clear()
	door.free()
	_reset()
	var barrel := PropBarrel.new()
	barrel.position = FEET + Vector2(-60, 0)
	game.props.append(barrel)
	_fire(FEET + Vector2(-140, -18), Vector2(2000, 0))
	game._physics_process(0.15)
	check(barrel.fusing and player.hp == player.max_hp, "薄油桶先吸收高速弹并点燃引信")
	check(game.enemy_bullets.is_empty(), "撞油桶后不会继续打中其后玩家")
	game.props.clear()
	barrel.free()


func _test_melee_and_time() -> void:
	_reset()
	var enemy := MeleeProbe.new()
	enemy.position = FEET + Vector2(-2, 0)
	game.minions.append(enemy)
	game._physics_process(DT)
	check(player.hp == player.max_hp - 1, "近战同样使用站立头部受击框")
	_reset()
	player.set_state("roll")
	game._physics_process(DT)
	check(player.hp == player.max_hp, "高位近战攻击可被无敌窗后的翻滚低框躲开")
	game.minions.clear()
	enemy.free()
	_reset()
	game.timeline_enabled = true
	player.keys[MOUSE_BUTTON_RIGHT] = true
	_fire(FEET + Vector2(-40, -72), Vector2(2000, 0))
	var old_orb: Dictionary = game.enemy_bullets[0].duplicate(true)
	game._physics_process(0.1)
	check(game.time_charge.active and game.enemy_bullets[0] == old_orb,
			"时停继续冻结敌弹坐标和寿命，不偷偷执行子步")
	check(player.hp == player.max_hp, "时停冻结期间不产生子弹伤害")
	player.keys.clear()
	game._physics_process(0.1)
	check(not game.time_charge.active and player.hp == player.max_hp - 1,
			"松开时停后敌弹继续扫掠并能击中头部")
	_reset()
	game.timeline_enabled = true
	player.hp = 1
	_fire(FEET + Vector2(-40, -72), Vector2(2000, 0))
	_fire(FEET + Vector2(140, -72), Vector2(-2000, 0))
	var later_orb: Dictionary = game.enemy_bullets[1].duplicate(true)
	var killed: bool = game._advance_enemy_bullets(0.1)
	check(killed and player.dead and game.enemy_bullets.size() == 1,
			"最后一滴血致死后立即结束本帧敌弹循环")
	check(game.enemy_bullets[0] == later_orb, "致死后的余下子弹保持未推进状态供死亡冻结")
