extends SceneTree
## M02 playtest 第三轮修复渲染验收（真实窗口跑）：
##   a 事务所：2 活 grunt + 1 尸体 —— 尸体最长边 ≈ 站立身高、摘掉青 rim 往后退
##   b 玩家走过解锁的放大门洞（64×96 门洞 + 200px 门框，不再鼠洞）
##   c 事务所密度：5 grunt（近门/中段/纵深/高台），多只同时品红蓄力闪
##   d grunt 对左侧玩家端枪瞄准 —— 面向玩家、子弹朝玩家飞（flip 修复）
##   e 楼梯间A 东侧原死角（c134-142）已填实，读作建筑体
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_shot6.gd
## 输出：user://shot6_*.png

var _shot_count := 0


func _init() -> void:
	call_deferred("_run")


func _room_grunts(scene: Node2D, room_idx: int) -> Array:
	var out: Array = []
	var rect: Rect2i = scene.level.rooms[room_idx]["rect"]
	for m in scene.minions:
		if is_instance_valid(m):
			var cell := Vector2i(floori(m.position.x / 32.0), floori(m.position.y / 32.0))
			if rect.has_point(cell):
				out.append(m)
	return out


func _run() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M02_TOWER
	CorridorLevel.active_rooms = CorridorLevel.MAP_M02_TOWER_ROOMS
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "tower"}
	CorridorLevel.active_title = "M02 数据塔"
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	# 标题卡走真实时间：回拨起始时间让它立即过期
	scene.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 10.0

	var player: KairullPlayer = scene.player
	player.auto_input = false
	player.hp = 999   ## 摆拍期间挨枪不死

	# ============ 镜头 c：事务所密度（5 grunt，多只蓄力闪）============
	# 玩家站 c50：c46/c58 直接蓄力，c63 跑近后蓄力；c68 高台 / c74 纵深未索敌（层次）
	player.position = Vector2(50 * 32 + 16, 25 * 32 - 0.1)
	player.face = 1
	_move_cam(scene)
	var aiming := 0
	for i in range(600):
		await physics_frame
		aiming = 0
		for m in _room_grunts(scene, 1):
			if not m.dead and m.state == "aim":
				aiming += 1
		if aiming >= 2 and i > 60:
			break
	print("  密度镜头：%d 只 grunt 同时蓄力" % aiming)
	await _shot("shot6_density_office")

	# ============ 镜头 a：2 活 + 1 尸体（尸体归一化 + 摘 rim）============
	var office: Array = _room_grunts(scene, 1)
	# 挑三只排到 c56/c60/c63；前两只冻结成 idle 站姿，第三只处决成尸体
	office.sort_custom(func(a, b): return a.position.x < b.position.x)
	var g_a: GruntGunner = office[0]
	var g_b: GruntGunner = office[1]
	var g_c: GruntGunner = office[2]
	for g in [g_a, g_b]:
		g.player = null
		g._set_state("idle")
		g.cooldown = 0
	g_a.position = Vector2(56 * 32 + 16, 25 * 32 - 0.1)
	g_b.position = Vector2(60 * 32 + 16, 25 * 32 - 0.1)
	g_c.position = Vector2(63 * 32 + 16, 25 * 32 - 0.1)
	g_c.take_hit(g_c.position.x, 1)
	scene.paint_layer.blood_pool(g_c.body_rect().get_center(), 1.0, 0,
			Color(0.45, 0.10, 0.16))   ## 暗红血泊（随机液爆色会读成史莱姆液）
	player.position = Vector2(51 * 32 + 16, 25 * 32 - 0.1)
	player.face = 1
	# 冻结成面向玩家的站姿（player=null 后 step 早退，手动刷一次贴图）
	for g in [g_a, g_b]:
		g.face = -1
		g._sync_sprite()
	_settle_player(player)
	_move_cam(scene)
	for i in range(40):
		await process_frame
	await _shot("shot6_corpse_scale")

	# ============ 镜头 b：玩家走过解锁的放大门洞（事务所门 D c80-81）============
	for m in _room_grunts(scene, 1):
		if not m.dead:
			m.take_hit(m.position.x, 1)
	for i in range(4):
		await physics_frame
	for i in range(40):   ## 门板沉地动画 0.45s 播完
		await process_frame
	# 房框取景会把房间边界上的门压在屏幕边缘——摆拍时临时摘掉房间表让相机跟
	# 人，拍完恢复（摘表期间各门 room_alive_count 返回 -1 会临时解锁，恢复后
	# 由活敌派生自动回锁，不影响后续镜头）
	var saved_rooms: Array = scene.level.rooms
	scene.level.rooms = []
	player.position = Vector2(77 * 32 + 16, 25 * 32 - 0.1)
	player.face = 1
	player.keys.clear()
	player.keys[KEY_D] = true
	# 手动步进让玩家以跑步帧走向门洞（自动输入已关）；
	# 停在门槛线上（x≈2540，门洞左沿 2560）：全身入画且 64×96 门洞完整可见
	for i in range(90):
		player.step(1.0 / 60.0)
		if player.position.x >= 2540.0:
			break
	player.keys.clear()
	for i in range(45):   ## 相机缓动完全就位（10%/帧）
		await process_frame
	await _shot("shot6_door_walkthrough")
	scene.level.rooms = saved_rooms

	# ============ 镜头 d：grunt 对左侧玩家端枪（面向/子弹朝玩家）============
	var fg: GruntGunner
	for m in scene.minions:
		if is_instance_valid(m) and not m.dead:
			fg = m
			break
	fg.position = Vector2(27 * 32 + 16, 25 * 32 - 0.1)
	fg.cooldown = 0
	fg._set_state("idle")
	player.position = Vector2(20 * 32 + 16, 25 * 32 - 0.1)
	player.face = 1
	_settle_player(player)
	_move_cam(scene)
	var fired := false
	fg.shoot_orb.connect(func(_p: Vector2, _v: Vector2) -> void: fired = true)
	for i in range(300):
		await physics_frame
		if fired:
			break
	for i in range(4):   ## 子弹离膛飞一小段，画面上能看到朝左的弹丸
		await physics_frame
	print("  朝向镜头：face=%d flip_h=%s" % [fg.face, str(fg._sprite.flip_h)])
	await _shot("shot6_facing_fix")

	# ============ 镜头 e：楼梯间A 东侧死角已填实 ============
	fg.take_hit(fg.position.x, 1)   ## 收尾，防干扰
	player.position = Vector2(120 * 32 + 16, 25 * 32 - 0.1)
	player.face = 1
	_settle_player(player)
	_move_cam(scene)
	for i in range(30):
		await process_frame
	await _shot("shot6_deadzone_filled")

	print("RENDER_RESULT: PASS")
	quit(0)


## 传送后手动空步几帧：清按键、站回地面、贴图回到 idle 站姿
func _settle_player(player: KairullPlayer) -> void:
	player.keys.clear()
	for i in range(12):
		player.step(1.0 / 60.0)


func _move_cam(scene: Node2D) -> void:
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	# auto_input=false 时 step() 不跑，落地尘土 FX 会冻住——手动清掉
	var player: KairullPlayer = scene.player
	player._land_fx.visible = false
	player._land_fx_t = -1.0
	player._jump_fx.visible = false
	player._jump_fx_t = -1.0


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
