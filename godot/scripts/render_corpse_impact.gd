extends SceneTree
## 正式M01真窗口验收：两类敌人沿正式伤害/击退链死亡，手动单步只为固定拍摄时刻。
## 原场景、地图、碰撞和美术不改；帧序列与GPU拼版写入外部交付目录。

const OUTPUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/corpse-impact-20260905"
const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
const MARKS := [2, 9, 17, 24, 26, 48]
const NAMES := ["01-命中", "02-顶点滞空", "03-下落", "04-首次落地灰尘", "05-轻弹", "06-收尾"]
const TITLES := ["命中 / 0.033s", "顶点滞空 / 0.150s", "下落 / 0.283s", "首次着地后 / 0.400s", "单次轻弹 / 0.433s", "贴地收尾 / 0.800s"]

var _game: Node2D
var _boot: Node2D
var _targets: Array[Node2D] = []
var _ground_y := 0.0
var _errors := 0
var _captures: Array[Texture2D] = []
var _evidence: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ", label)
	_evidence.append(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_errors += 1


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("尸体与灰尘视觉验收禁止headless截图")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	SESSION.begin_run("easy")
	_boot = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	root.add_child(_boot)
	await process_frame
	await process_frame
	_game = _boot.get_node("Game")
	# 停掉自动模拟，但仍由真实窗口绘制；防止截图等待时间把0.32秒灰尘提前耗完。
	_boot.process_mode = Node.PROCESS_MODE_DISABLED
	_game.player.auto_input = false
	_game.hud.visible = false
	_game.debug = false
	var hook: Node2D
	var gun: Node2D
	for enemy: Node2D in _game.minions:
		enemy.player = null
		enemy.visible = false
		if enemy is FreightInspector and (hook == null or enemy.position.x < hook.position.x):
			hook = enemy
		if enemy is GruntGunner and (gun == null or enemy.position.x < gun.position.x):
			gun = enemy
	if hook == null or gun == null or not hook.has_method("set_corpse_lift") or not gun.has_method("set_corpse_lift"):
		_check(false, "正式关卡两类敌人及视觉抬升API均存在")
		await _finish()
		return
	_targets = [hook, gun]
	_ground_y = hook.position.y
	hook.position = Vector2(720.0, _ground_y)
	gun.position = Vector2(1100.0, _ground_y)
	for enemy: Node2D in _targets:
		enemy.visible = true
		enemy.face = -1
		enemy._sync_sprite()
	for prop: Node2D in _game.props:
		prop.visible = false
	_game.player.position = Vector2(565.0, _ground_y)
	_game.player.face = 1
	_game.player.vy = 0.0
	_game.player.vx = 0.0
	_game.player.on_ground = true
	_game.player.keys.clear()
	_game.player._sync_sprite()
	_game.current_room = 1
	_game.cam_tl = Vector2(440.0, _ground_y - 520.0).round()
	_game.cam.position = _game.cam_tl + Vector2(680.0, 382.5)
	_game.cam.force_update_scroll()
	_game.bg._process(0.0)
	# 用正式球棒伤害回调分别命中，只隔离拍摄站位，不伪造dead/尘土状态。
	seed(70502)
	for enemy: Node2D in _targets:
		_game._on_player_bat_swung(enemy.body_rect(), 1)
	_check(hook.dead and gun.dead and _game._corpse_impacts.size() == 2,
			"两种敌人经正式球棒链即刻击杀并登记尸体表现")
	for frame in range(1, 49):
		# 特效先更新旧实例，新落地事件产生的灰尘下一拍才走时钟。
		for effect: Node in _game.fx_layer.get_children():
			if effect.has_method("_process") and effect.get("active") == true:
				effect._process(DT)
		for enemy: Node2D in _targets:
			enemy.step(DT)
		_game._update_enemy_knockbacks(DT)
		_game._update_corpse_impacts(DT)
		_game.fx_layer.queue_redraw()
		_game.bg._process(0.0)
		if MARKS.has(frame):
			var index := MARKS.find(frame)
			var stats: Dictionary = _game.fx_layer.corpse_dust_stats()
			var sample := "%s ground=(%.2f,%.2f) lift=(%.2f,%.2f) dust=%s" % [
					NAMES[index], hook.position.y, gun.position.y, hook.corpse_lift, gun.corpse_lift, stats]
			print(sample)
			_evidence.append(sample)
			_check(is_equal_approx(hook.position.y, _ground_y) and is_equal_approx(gun.position.y, _ground_y),
					"%s：实际脚底地面锚未被视觉腾空改变" % NAMES[index])
			if frame == 24:
				_check(stats["active"] == 2 and stats["total"] == 2, "首次落地每名敌人只生成一组灰尘")
				for effect: Node in _game.fx_layer._corpse_dust_active:
					_check(effect.elapsed >= 0.02 and effect.elapsed <= 0.06,
							"截图锁定可见灰尘年龄%.4fs" % effect.elapsed)
			await _capture(index)
	_check(_game._corpse_impacts.is_empty() and hook.corpse_lift == 0.0 and gun.corpse_lift == 0.0,
			"收尾两种尸体回到原脚底，无遗留抬升任务")
	var final_stats: Dictionary = _game.fx_layer.corpse_dust_stats()
	_check(final_stats["total"] == 2 and final_stats["pooled"] == 2 and final_stats["active"] == 0,
			"反弹没有重复尘爆，首次尘土全部回池停止")
	await _contact_sheet()
	await _dust_closeup()
	await _finish()


func _capture(index: int) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	_check(capture.save_png(OUTPUT.path_join(NAMES[index] + ".png")) == OK, NAMES[index] + " 真窗口截图保存")
	_captures.append(ImageTexture.create_from_image(capture))


func _contact_sheet() -> void:
	# 用Godot实际渲染的截图作为TextureRect输入，由GPU生成小型对照板，不重绘或AI伪造游戏画面。
	var board := SubViewport.new()
	board.size = Vector2i(1320, 970)
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(board)
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1320, 970)
	backdrop.color = Color("#111922")
	board.add_child(backdrop)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	var title := Label.new()
	title.text = "尸体重量感 / 正式M01真窗口 · 左：货钩巡检员  右：枪手"
	title.position = Vector2(24, 14)
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 24)
	board.add_child(title)
	for i in _captures.size():
		var column := i % 2
		var row := i / 2
		var label := Label.new()
		label.text = TITLES[i]
		label.position = Vector2(24 + column * 650, 61 + row * 300)
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 23)
		board.add_child(label)
		var area := AtlasTexture.new()
		area.atlas = _captures[i]
		# 只裁出真实截图中的双方与地面；原始完整窗口图同时保留。
		area.region = Rect2(60.0, 265.0, 1100.0, 430.0)
		var view := TextureRect.new()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.texture = area
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.position = Vector2(24 + column * 650, 98 + row * 300)
		view.size = Vector2(624, 244)
		view.clip_contents = true
		board.add_child(view)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(board.get_texture().get_image().save_png(OUTPUT.path_join("尸体滞空-落地灰尘-真窗口对照.png")) == OK,
			"真实画面GPU对照板保存")
	board.free()


func _finish() -> void:
	if is_instance_valid(_boot):
		_stop_audio(_boot)
		_boot.free()
	SESSION.reset_for_tests()
	_evidence.append("CORPSE_WINDOW_RESULT: " + ("PASS" if _errors == 0 else "FAIL"))
	var report := FileAccess.open(OUTPUT.path_join("真窗口验收记录.txt"), FileAccess.WRITE)
	if report != null:
		report.store_string("\n".join(_evidence))
	await process_frame
	print("CORPSE_WINDOW_RESULT: ", "PASS" if _errors == 0 else "FAIL")
	quit(0 if _errors == 0 else 1)


func _dust_closeup() -> void:
	# 同一真实首落帧的nearest三倍局部，仅供检查尘簇硬边和地板接触位置。
	var board := SubViewport.new()
	board.size = Vector2i(760, 240)
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(board)
	for i in 2:
		var atlas := AtlasTexture.new()
		atlas.atlas = _captures[3]
		atlas.region = Rect2(340.0 + 380.0 * i, 460.0, 120.0, 80.0)
		var view := TextureRect.new()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.texture = atlas
		view.position = Vector2(400.0 * i, 0.0)
		view.size = Vector2(360.0, 240.0)
		board.add_child(view)
	await process_frame
	await RenderingServer.frame_post_draw
	board.get_texture().get_image().save_png(OUTPUT.path_join("落地灰尘-原帧局部三倍.png"))
	board.free()


func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		node.stop()
	for child: Node in node.get_children():
		_stop_audio(child)
