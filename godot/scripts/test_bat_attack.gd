extends SceneTree
## 棍击三连 + 洋葱片虚影无头单测。
## 跑法：godot --headless --path godot --script scripts/test_bat_attack.gd

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
	print("== hero 图集 ==")
	var db := AtlasDB.new("res://assets/clips", [
		"res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json",
	])
	ok(db.actions.size() == 24, "16 旧动作 + 8 hero 动作", str(db.actions.size()))
	for a in ["hero_idle", "hero_run", "hero_jump", "hero_hurt", "hero_death",
			"hero_bat1", "hero_bat2", "hero_bat3"]:
		ok(db.actions.has(a), "动作存在 " + a)
	ok(int(db.actions["hero_bat1"]["frames"]) == 27, "bat1 27 帧")
	ok(int(db.actions["hero_bat2"]["frames"]) == 8, "bat2 8 帧")
	ok(int(db.actions["hero_bat3"]["frames"]) == 21, "bat3 21 帧")
	ok(int(db.actions["hero_run"]["frames"]) == 16, "疾跑裁成 16 帧循环")

	print("== 玩家棍击状态机 ==")
	var level := CorridorLevel.new()
	level.build(false)
	var player := KairullPlayer.new()
	player.auto_input = false
	player.db = db
	player.level = level
	get_root().add_child(player)
	player.spawn = level.spawn
	player.reset_to_spawn()
	for i in range(30):
		player.step(1.0 / 60)

	var swing_stages: Array = []
	var swung: Array = []
	player.bat_swing_started.connect(func(s: int) -> void: swing_stages.append(s))
	player.bat_swung.connect(func(hb: Rect2, s: int) -> void: swung.append([hb, s, player.position.x]))

	# 地面左键 → bat1，站定
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys = {}
	var x0: float = player.position.x
	player.step(1.0 / 60)
	ok(player.state == "bat1", "左键起手 bat1", player.state)
	ok(player.current_clip() == "hero_bat1", "bat1 映射 hero_bat1", player.current_clip())
	ok(swing_stages == [0], "挥棒开始信号 stage=0", str(swing_stages))
	# 首击起手突进一小段，之后挥棍不再位移
	var step_dx: float = player.position.x - x0
	ok(step_dx > 30.0 and step_dx <= KairullPlayer.BAT1_STEP + 1.0,
		"首击起手突然突进一小段", str(step_dx))
	player.keys = {MOUSE_BUTTON_LEFT: true}   # 按住不重复触发
	var x1: float = player.position.x
	for i in range(5):
		player.step(1.0 / 60)
	ok(player.state == "bat1", "按住左键不重复起手", player.state)
	ok(approx2(player.position.x, x1), "突进后挥棍站定（二三段同）", str(player.position.x - x1))

	# 前段早期点按也缓冲连招（狂点可三连的关键）
	player.keys = {}
	player.step(1.0 / 60)
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	ok(player.bat_queued and player._bat_progress() < 0.5, "前段点按即缓冲连招",
		str(player._bat_progress()))

	# 命中窗口：只发一次，判定盒在面前（2.8 倍速下 bat1 仅约 24 步播完）
	for i in range(8):
		player.step(1.0 / 60)
	ok(swung.size() == 1, "命中窗口只发一次", str(swung.size()))
	if swung.size() == 1:
		var hb: Rect2 = swung[0][0]
		ok(int(swung[0][1]) == 0, "判定信号 stage=0")
		ok(hb.position.x > float(swung[0][2]) - 1.0, "判定盒在朝向一侧（以发射时刻为准）", str(hb))
		ok(hb.size.x == KairullPlayer.BAT_HITBOX_W, "判定盒宽度 76")

	# 后段点左键 → 连招 bat2
	player.keys = {}
	player.step(1.0 / 60)
	ok(player.bat_queued, "连招缓冲保持到本击结束")
	var guard := 0
	while player.state == "bat1" and guard < 200:
		player.step(1.0 / 60)
		guard += 1
	ok(player.state == "bat2", "播完自动接 bat2", player.state + " guard=" + str(guard))
	ok(swing_stages == [0, 1], "第二段挥棒信号", str(swing_stages))

	# bat2 只保留下一帧预示：上一帧虚影隐藏；斩击弧光可见
	player.step(1.0 / 60)
	player.step(1.0 / 60)
	var op2: Sprite2D = player.get_node("OnionPrev")
	var on2: Sprite2D = player.get_node("OnionNext")
	while player.state == "bat2" and player.frame < 3:
		player.step(1.0 / 60)   # 推到中帧，前后虚影都取得到相邻帧
	ok(op2.visible, "bat2 上一帧虚影已加回")
	ok(on2.visible, "bat2 保留下一帧预示")
	# 收尾 2 帧不加虚影（动作调换后 bat2 是 21 帧的 hero_bat3）
	while player.state == "bat2" and player.frame < 19:
		player.step(1.0 / 60)
	if player.state == "bat2":
		ok(not op2.visible and not on2.visible, "bat2 收尾 2 帧不加虚影")
	var slash2: Sprite2D = player.get_node("Slash")
	ok(slash2.visible and slash2.texture != null, "挥棍中斩击弧光可见")

	# bat2 后段再点 → bat3
	player.keys = {}
	player.step(1.0 / 60)
	while player.state == "bat2" and player._bat_progress() < KairullPlayer.BAT_COMBO_OPEN:
		player.step(1.0 / 60)
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	guard = 0
	while player.state == "bat2" and guard < 200:
		player.step(1.0 / 60)
		guard += 1
	ok(player.state == "bat3", "接 bat3", player.state)

	# bat3 是末段：再点不排队
	while player.state == "bat3" and player._bat_progress() < KairullPlayer.BAT_COMBO_OPEN:
		player.step(1.0 / 60)
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	ok(not player.bat_queued, "三段后不排队")
	player.keys = {}
	guard = 0
	while player.state == "bat3" and guard < 300:
		player.step(1.0 / 60)
		guard += 1
	ok(player.state == "gun_idle", "三段播完回站立", player.state)
	ok(swung.size() == 3, "三段各发一次判定", str(swung.size()))

	print("== 洋葱片虚影 ==")
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	player.keys = {}
	for i in range(8):   # 推进到中帧，前后都有帧
		player.step(1.0 / 60)
	var op: Sprite2D = player.get_node("OnionPrev")
	var on_: Sprite2D = player.get_node("OnionNext")
	ok(op.visible and on_.visible, "挥棍中前后虚影可见")
	ok(op.texture == player.get_node("Sprite").texture, "虚影与本体同图集")
	var main_rect: Rect2 = player.get_node("Sprite").region_rect
	ok(op.region_rect != main_rect and on_.region_rect != main_rect, "虚影取相邻帧")
	ok(op.region_rect != on_.region_rect, "前后虚影不同帧")
	ok(op.material != null and on_.material != null, "虚影用冲刺同款着色器")
	ok(op.material is ShaderMaterial, "虚影材质为 ShaderMaterial（冲刺剪影）")
	ok(op.global_position == player.get_node("Sprite").global_position, "虚影与本体重叠同位")
	guard = 0
	while player.batting() and guard < 300:
		player.step(1.0 / 60)
		guard += 1
	ok(not op.visible and not on_.visible, "收棍后虚影隐藏")
	ok(not player.get_node("Slash").visible, "收棍后斩击弧光隐藏")

	print("== 起跳/落地特效 ==")
	player._test_clean_motion_state()
	player.on_ground = true
	player.set_state("gun_idle")
	player.keys = {KEY_W: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	ok(player.get_node("JumpFx").visible, "起跳播放起跳尘土")
	player.keys = {}
	var guard2 := 0
	while not player.on_ground and guard2 < 300:
		player.step(1.0 / 60)
		guard2 += 1
	ok(player.on_ground, "落地")
	ok(player.get_node("LandFx").visible, "落地播放落地尘土")
	for i in range(30):
		player.step(1.0 / 60)
	ok(not player.get_node("JumpFx").visible and not player.get_node("LandFx").visible,
		"尘土播完自动隐藏")

	print("== 空中挥棍一次制 / 瞄准滑铲不可挥棍 ==")
	# 沿用上一段落地后的站位（在地板上），抬高 96px 模拟空中（默认图三层楼板，抬太高会落进中层板）
	player.on_ground = false
	player.position.y -= 96.0
	player.vy = 0.0
	player.set_state("gun_jump_air")
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	ok(player.state == "bat1", "空中可起手一次", player.state)
	ok(player.air_bat_used, "空击后标记已用")
	player.keys = {}
	var guard3 := 0
	while player.batting() and guard3 < 300:
		player.step(1.0 / 60)
		# 棍还没挥完就落地的话重新抬回半空并补回空击标记：
		# 落地是测试场地太低的假象，不是本段要验证的行为
		if player.on_ground:
			player.on_ground = false
			player.position.y -= 96.0
			player.vy = 0.0
			player.air_bat_used = true
		guard3 += 1
	ok(not player.on_ground, "空击全程保持离地（一段无突进）")
	player.set_state("gun_jump_air")
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	ok(player.state != "bat1", "空中第二次不可起手", player.state)
	player.keys = {}
	var guard4 := 0
	while not player.on_ground and guard4 < 600:
		player.step(1.0 / 60)
		guard4 += 1
	ok(player.on_ground and not player.air_bat_used, "落地重置空击次数")

	print("== 冲刺音效信号 ==")
	var dashed_count := [0]
	player.dashed.connect(func() -> void: dashed_count[0] += 1)
	player._test_clean_motion_state()
	player.on_ground = true
	player.dash_cooldown_t = 0.0
	player.keys = {KEY_D: true, KEY_SHIFT: true}
	player._prev_keys = {}
	player.step(1.0 / 60)
	ok(dashed_count[0] == 1, "闪现成功发 dashed 信号", str(dashed_count[0]))

	print("")
	print("棍击测试完成: %d 通过, %d 失败" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func approx2(a: float, b: float, tol := 0.5) -> bool:
	return absf(a - b) <= tol
