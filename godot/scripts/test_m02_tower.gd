extends SceneTree
## M02 数据塔无头单测：地图解析 / 房间表校验 / 标记归属 / 跳跃图可达性（穿门洞）/
## 门锁定-解锁流程 / 相机房框钳制 / 调色板明度阶梯。
## 跑法：godot --headless --path godot --script scripts/test_m02_tower.gd

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


## 站立格：自身非实心、脚下 1 格实心（与网页版 solidAt 同语义）
func _is_stand(lv: CorridorLevel, c: int, r: int) -> bool:
	return not lv.is_solid_char(lv.tile_at(c, r)) \
		and lv.is_solid_char(lv.tile_at(c, r + 1))


func _run() -> void:
	print("== M02 地图解析 ==")
	CorridorLevel.active_map = CorridorLevel.MAP_M02_TOWER
	CorridorLevel.active_rooms = CorridorLevel.MAP_M02_TOWER_ROOMS
	var level := CorridorLevel.new()
	level.build(false)
	ok(level.map_h == 34, "地图 34 行（3 层塔）", str(level.map_h))
	ok(level.map_w == 144, "地图 144 列", str(level.map_w))
	var uniform := true
	for row in level.grid:
		if row.length() != level.map_w:
			uniform = false
	ok(uniform, "各行宽度一致")
	ok(level.rooms.size() == 8, "8 个房间", str(level.rooms.size()))

	print("== 标记提取 ==")
	ok(level.spawn == Vector2(4 * 32 + 16, 25 * 32 - 0.1), "出生点 @ c4 r24", str(level.spawn))
	ok(level.exit_point == Vector2(135 * 32 + 16, 8 * 32 - 0.1), "出口 > c135 r7",
		str(level.exit_point))
	ok(level.enemy_spawns.size() == 19, "19 个敌人刷点（5+3+6+5，大堂/楼梯间 0）",
		str(level.enemy_spawns.size()))
	ok(level.door_spawns.size() == 5, "5 个房门 D", str(level.door_spawns.size()))
	ok(level.prop_spawns.size() == 5, "5 个道具（3 桶 + 2 CRT）",
		str(level.prop_spawns.size()))
	# D 标记已抹成空格（碰撞由 RoomDoor 节点提供）
	var d_erased := true
	for dp in level.door_spawns:
		var dc := floori(dp.x / 32.0)
		var dr := floori((dp.y + 0.2) / 32.0) - 1
		if level.tile_at(dc, dr) != ".":
			d_erased = false
	ok(d_erased, "D 标记解析后从网格抹除")

	print("== 房间表校验 ==")
	# 不重叠
	var overlap := false
	for i in level.rooms.size():
		for j in range(i + 1, level.rooms.size()):
			if (level.rooms[i]["rect"] as Rect2i).intersects(level.rooms[j]["rect"]):
				overlap = true
				print("    重叠: ", level.rooms[i]["name"], " x ", level.rooms[j]["name"])
	ok(not overlap, "房间两两不重叠")
	# 覆盖游玩区：每个非边框空气格都落在某个房间内
	var covered := true
	for r in level.map_h:
		for c in level.map_w:
			if level.tile_at(c, r) != ".":
				continue
			if c == 0 or c == level.map_w - 1 or r == 0:
				continue
			if level.room_at(c * 32 + 16, r * 32 + 16) < 0:
				covered = false
				print("    未覆盖空气格: c%d r%d" % [c, r])
	ok(covered, "房间覆盖全部游玩区空气格")
	# 每个标记恰好在一个房间内（> 出口含塔心；D 门格归属明确）
	var marks: Array = [level.spawn, level.exit_point]
	marks.append_array(level.enemy_spawns)
	marks.append_array(level.door_spawns)
	var unique_mark := true
	for mp in marks:
		var hits := 0
		for room in level.rooms:
			if (room["rect"] as Rect2i).has_point(
					Vector2i(floori(mp.x / 32.0), floori(mp.y / 32.0))):
				hits += 1
		if hits != 1:
			unique_mark = false
			print("    标记房间归属=%d: %s" % [hits, mp])
	ok(unique_mark, "@/>/x/D 每个标记恰好归属一个房间")

	print("== 刷点脚下有地面 ==")
	var all_floored := true
	for sp in level.enemy_spawns:
		var c := floori(sp.x / 32.0)
		var r := floori(sp.y / 32.0)
		var found := false
		for dr in range(1, 4):
			if level.is_solid_char(level.tile_at(c, r + dr)):
				found = true
				break
		if not found:
			all_floored = false
			print("    无地面刷点: c%d r%d" % [c, r])
	ok(all_floored, "每个 x 脚下 3 格内有地面")

	print("== 跳跃图可达性（rise≤3，D 门洞按可通过处理）==")
	# 与 test_m01_level 同预算 BFS；D 已抹成空格天然可通过。
	var start := Vector2i(4, 24)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for c2 in range(maxi(0, p.x - 8), mini(level.map_w, p.x + 9)):
			for r2 in range(maxi(0, p.y - 3), mini(level.map_h, p.y + 20)):
				var q := Vector2i(c2, r2)
				if seen.has(q) or not _is_stand(level, c2, r2):
					continue
				var rise: int = p.y - r2
				var dc: int = absi(c2 - p.x)
				if rise >= 0:
					var budget: int = {0: 8, 1: 6, 2: 5, 3: 3}.get(rise, -1)
					if dc > budget:
						continue
				elif dc > 8:
					continue
				seen[q] = true
				queue.append(q)
	ok(seen.has(Vector2i(135, 7)), "出口可达（塔心）")
	var all_reach := true
	for sp in level.enemy_spawns:
		var cell := Vector2i(floori(sp.x / 32.0), floori(sp.y / 32.0))
		if not seen.has(cell):
			all_reach = false
			print("    不可达刷点: ", cell)
	ok(all_reach, "全部 19 个刷点可达（跨房间穿门洞）")

	print("== 游戏场景：门/房间/相机 ==")
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
	ok(scene.doors.size() == 5, "5 个 RoomDoor 已生成", str(scene.doors.size()))
	ok(scene.minions.size() == 19, "19 只 grunt 已生成", str(scene.minions.size()))
	ok(scene.red_boss == null, "active_boss=\"none\" 不刷 Boss")

	# 门锁定 ⇔ 房内活敌：大堂门（D c40，锚点 = 门洞中心 41*32）常开；
	# 事务所门（D c80，锚点 81*32）锁
	var door_lobby: RoomDoor
	var door_office: RoomDoor
	for d in scene.doors:
		if absf(d.position.x - 41.0 * 32.0) < 1.0:
			door_lobby = d
		elif absf(d.position.x - 81.0 * 32.0) < 1.0:
			door_office = d
	ok(door_lobby != null and door_office != null, "找到大堂/事务所门（锚点 = 门洞中心）")
	for i in range(3):
		await physics_frame
	ok(not door_lobby.locked, "大堂门常开（0 敌房间）")
	ok(door_office.locked, "事务所门锁定（5 敌存活）")
	ok(scene.room_alive_count(1) == 5, "事务所活敌计数 5", str(scene.room_alive_count(1)))
	ok(scene.room_alive_count(0) == 0, "大堂活敌计数 0")

	# 锁门挡人：玩家撞门被推出
	scene.player.position = Vector2(door_office.position.x - 8, door_office.position.y)
	await physics_frame
	ok(scene.player.position.x < door_office.position.x - 40.0,
		"锁定门把玩家推出（64px 宽门体）", str(scene.player.position.x))

	# 锁定门挡枪手 LOS：把一只 grunt 摆到事务所 c74，玩家隔门站 c82
	var los_grunt: Node2D = scene.minions[0]
	los_grunt.position = Vector2(74 * 32 + 16, 25 * 32 - 0.1)
	scene.player.position = Vector2(82 * 32 + 16, 25 * 32 - 0.1)
	ok(door_office.locked, "LOS 前置：事务所门仍锁定")
	ok(not los_grunt._has_los(), "锁定门挡枪手视线（LOS 采样点被门体拦截）")

	# 门体几何：碰撞恰好覆盖 2 列 × 3 格门洞（64×96），三格全挡 LOS/子弹
	var drect: Rect2 = door_office.body_rect()
	ok(drect.size.is_equal_approx(Vector2(64, 96)), "锁定碰撞 = 64×96 覆盖 2×3 门洞",
		str(drect))
	ok(drect.has_point(door_office.position + Vector2(0, -16)),
		"门洞下格（D 格）被碰撞覆盖")
	ok(drect.has_point(door_office.position + Vector2(0, -48)),
		"门洞中格被碰撞覆盖")
	ok(drect.has_point(door_office.position + Vector2(0, -80)),
		"门洞上格被碰撞覆盖")
	ok(drect.has_point(door_office.position + Vector2(-20, -16))
			and drect.has_point(door_office.position + Vector2(20, -16)),
		"门洞左右两列都被碰撞覆盖（64px 宽）")
	# 门人比例：视觉总高（含墙面门框/门楣）≈200px，显著高于玩家
	var dh: float = door_office.visual_height()
	var ph: float = scene.player.visual_height()
	ok(dh >= 190.0 and dh <= 210.0, "门视觉总高 190-210px", "door=%.1f" % dh)
	ok(dh / ph >= 2.0, "门 ≥2× 玩家身高", "door=%.1f player=%.1f ratio=%.2f"
		% [dh, ph, dh / ph])

	# 杀光事务所 5 只 grunt → 门解锁
	for m in scene.minions:
		if is_instance_valid(m) and not m.dead:
			var cell := Vector2i(floori(m.position.x / 32.0), floori(m.position.y / 32.0))
			if (level.rooms[1]["rect"] as Rect2i).has_point(cell):
				m.take_hit(m.position.x, 1)
	for i in range(3):
		await physics_frame
	ok(not door_office.locked, "事务所清空后门解锁")
	ok(door_lobby.locked == false, "大堂门仍常开")
	ok(los_grunt._has_los(), "解锁后同一视线恢复通畅")

	print("== grunt 朝向 / 子弹方向（round3 修复：素材朝右画，flip 反转 bug）==")
	# 找一只活 grunt 摆到大堂，玩家分站左右两侧：面朝玩家 + 子弹飞向玩家
	var fg: GruntGunner
	for m in scene.minions:
		if is_instance_valid(m) and not m.dead:
			fg = m
			break
	ok(fg != null, "找到活体 grunt 做朝向测试")
	fg.position = Vector2(24 * 32 + 16, 25 * 32 - 0.1)
	var shot_vels: Array = []
	var shot_froms: Array = []
	fg.shoot_orb.connect(func(from_pos: Vector2, vel: Vector2) -> void:
		shot_froms.append(from_pos)
		shot_vels.append(vel))
	# 玩家在左：face=-1、sprite 镜像（素材原生朝右）、子弹 vx<0、枪口在左侧
	scene.player.position = fg.position + Vector2(-200, 0)
	fg.cooldown = 0
	fg._set_state("idle")
	for i in range(200):
		fg.step(1.0 / 60.0)
		if not shot_vels.is_empty():
			break
	ok(not shot_vels.is_empty(), "玩家在左 → grunt 开火")
	ok(fg.face == -1, "玩家在左 → face=-1", str(fg.face))
	ok(fg._sprite.flip_h, "玩家在左 → sprite 镜像朝左（素材原生朝右）")
	ok(shot_vels.size() > 0 and shot_vels[0].x < 0.0, "子弹向左飞（vx<0）",
		str(shot_vels[0]) if shot_vels.size() > 0 else "no shot")
	ok(shot_froms.size() > 0 and shot_froms[0].x < fg.position.x,
		"枪口出弹点在 grunt 左侧")
	# 玩家在右：face=+1、sprite 不镜像、子弹 vx>0
	scene.player.position = fg.position + Vector2(200, 0)
	fg.cooldown = 0
	fg._set_state("idle")
	shot_vels.clear()
	shot_froms.clear()
	for i in range(200):
		fg.step(1.0 / 60.0)
		if not shot_vels.is_empty():
			break
	ok(not shot_vels.is_empty(), "玩家在右 → grunt 开火")
	ok(fg.face == 1, "玩家在右 → face=+1", str(fg.face))
	ok(not fg._sprite.flip_h, "玩家在右 → sprite 不镜像（朝右）")
	ok(shot_vels.size() > 0 and shot_vels[0].x > 0.0, "子弹向右飞（vx>0）",
		str(shot_vels[0]) if shot_vels.size() > 0 else "no shot")
	ok(shot_froms.size() > 0 and shot_froms[0].x > fg.position.x,
		"枪口出弹点在 grunt 右侧")
	fg.take_hit(fg.position.x, 1)   ## 收尾：避免后续段落被这只 grunt 干扰
	scene.enemy_bullets.clear()

	# 相机房框钳制：大堂（c1-40, 宽 1280 < VW 1360）应水平居中
	scene.player.position = level.spawn
	await process_frame
	scene._update_room_state()
	ok(scene.current_room == 0, "出生在大堂（room 0）", str(scene.current_room))
	var tgt: Vector2 = scene._cam_target()
	# 大堂 rect c1-40 r18-24 → x 居中 (32+1312)/2-680=-8 → 世界钳到 0；y 居中 (576+800)/2-382.5=305.5
	ok(absf(tgt.x - 0.0) < 1.0, "大堂相机 x 钳到世界左界（房间比视口窄→居中）",
		str(tgt.x))
	ok(absf(tgt.y - 305.5) < 1.0, "大堂相机 y 居房间中", str(tgt.y))
	# 服务器厅（c72-142 宽 2272 > VW）：正常 clamp 在房框内
	scene.player.position = Vector2(100 * 32, 15 * 32)
	scene._update_room_state()
	ok(scene.current_room == 5, "服务器厅（room 5）", str(scene.current_room))
	var tgt2: Vector2 = scene._cam_target()
	var srv: Rect2i = level.rooms[5]["rect"]
	ok(tgt2.x >= srv.position.x * 32 - 0.01
			and tgt2.x <= srv.end.x * 32 - 1360.0 + 0.01,
		"服务器厅相机 x 钳在房框内", str(tgt2.x))

	# Backspace 重置：房间/门状态复位（门由活敌派生自动回锁）
	scene._unhandled_input(_make_key(KEY_BACKSPACE))
	ok(scene.current_room == 0, "重置后回到大堂")

	print("== 墙面 backdrop / 房间装饰 / 光影 ==")
	ok(scene.wall_backdrop != null, "WallBackdrop 已生成")
	ok(scene.room_lights != null, "RoomLights 已生成")
	# 每个房间行走排中点都有 backdrop 覆盖（房间矩形 = 室内空气区）
	var all_covered := true
	for room in level.rooms:
		var rect: Rect2i = room["rect"]
		var wx: float = (rect.position.x + rect.size.x / 2) * 32.0 + 16.0
		var wy: float = (rect.end.y - 1) * 32.0 + 16.0
		if not scene.wall_backdrop.has_backdrop_at(wx, wy):
			all_covered = false
			print("    无 backdrop: ", room["name"], " @ ", wx, ",", wy)
	ok(all_covered, "backdrop 覆盖全部 8 个房间室内")
	ok(not scene.wall_backdrop.has_backdrop_at(50 * 32 + 16, 26 * 32 + 16),
		"楼板实体内部（r26）无 backdrop（房间外虚空不糊墙）")
	# 房间装饰：8 房间各有陈设（无头模式不跑 _draw，计数在 setup 阶段算出）
	ok(scene.decor_nodes.size() == 8, "8 个 RoomDecor 已生成", str(scene.decor_nodes.size()))
	var decor_ok := true
	for d in scene.decor_nodes:
		if d.decor_count <= 0:
			decor_ok = false
			print("    无陈设: ", d.room_name)
	ok(decor_ok, "每个房间装饰件数 > 0")
	# 光影：每个 L 光条对应一个地板光池（F1×10 + F2×12 + F3×8 = 30）
	var l_count := 0
	for r in level.map_h:
		for c in level.map_w:
			if level.tile_at(c, r) == "L":
				l_count += 1
	ok(l_count == 30, "地图 30 条 L 光条", str(l_count))
	ok(scene.room_lights.pools.size() == l_count, "每条光条都有光池",
		str(scene.room_lights.pools.size()))

	print("== 调色板明度阶梯 ==")
	# 规则：背景 < 玩法层墙体 < 玩法层亮顶沿；交互色饱和度全场最高
	var lum_bg := _lum(KZPalette.BG_PANEL)
	var lum_wall := _lum(KZPalette.WALL_PANEL)
	var lum_floor := _lum(KZPalette.FLOOR_SIDE)
	var lum_top := _lum(KZPalette.FLOOR_TOP)
	ok(lum_bg < lum_wall, "背景面板 < 玩法墙", "%.3f vs %.3f" % [lum_bg, lum_wall])
	ok(lum_wall < lum_floor, "玩法墙 < 地板侧面", "%.3f vs %.3f" % [lum_wall, lum_floor])
	ok(lum_floor < lum_top, "地板侧面 < 亮顶沿", "%.3f vs %.3f" % [lum_floor, lum_top])
	ok(lum_bg < 0.08 and lum_top > 0.35, "背景极暗 / 顶沿高亮",
		"bg=%.3f top=%.3f" % [lum_bg, lum_top])
	ok(KZPalette.NEON_MAGENTA.s > 0.6 and KZPalette.NEON_CYAN.s > 0.4,
		"霓虹交互色保持高饱和")
	# backdrop 全系 + 楼层色带必须低于玩法墙（背景 < 玩法层铁律，task B 扩展）
	var backdrop_cols: Array = [
		["BACKDROP_BASE", KZPalette.BACKDROP_BASE],
		["BACKDROP_F1", KZPalette.BACKDROP_F1],
		["BACKDROP_F2", KZPalette.BACKDROP_F2],
		["BACKDROP_F3", KZPalette.BACKDROP_F3],
		["BACKDROP_SEAM", KZPalette.BACKDROP_SEAM],
		["BACKDROP_PILASTER", KZPalette.BACKDROP_PILASTER],
		["BACKDROP_BASEBOARD", KZPalette.BACKDROP_BASEBOARD],
		["BACKDROP_HI", KZPalette.BACKDROP_HI],
		["BAND_F1", KZPalette.BAND_F1],
		["BAND_F2", KZPalette.BAND_F2],
		["BAND_F3", KZPalette.BAND_F3],
	]
	var ladder_ok := true
	for bc in backdrop_cols:
		var l := _lum(bc[1])
		if l >= lum_wall:
			ladder_ok = false
			print("    超阶梯: ", bc[0], " lum=%.3f >= 墙 %.3f" % [l, lum_wall])
	ok(ladder_ok, "backdrop/色带 11 色全部 < 玩法墙明度")
	# 装饰剪影主体色同样压暗（LED/售货机辉光/警示纹等小信号色除外——交互语义允许亮）
	var decor_cols: Array = [
		["DECOR_BODY", KZPalette.DECOR_BODY],
		["DECOR_FACE", KZPalette.DECOR_FACE],
		["DECOR_EDGE", KZPalette.DECOR_EDGE],
		["WARN_DARK", KZPalette.WARN_DARK],
	]
	var decor_lum_ok := true
	for dc in decor_cols:
		var l2 := _lum(dc[1])
		if l2 >= lum_wall:
			decor_lum_ok = false
			print("    超阶梯: ", dc[0], " lum=%.3f" % l2)
	ok(decor_lum_ok, "装饰剪影主体 5 色全部 < 玩法墙明度")

	scene.queue_free()
	await process_frame
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_title = ""
	GameBackground.active_cfg = []

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


## 相对感知亮度（Rec.601）
func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func _make_key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev
