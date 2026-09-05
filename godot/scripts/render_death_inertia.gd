extends SceneTree
## 正式M01真窗口固定镜头：同时记录主角、近战兵、枪手的真实前冲抛物线。
## 只改变验收站位/模拟时钟，不修改地图、角色素材、碰撞或实际伤害接入链。

const OUTPUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/death-inertia-20260905"
const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
const MARKS := [0, 5, 10, 18, 28, 42, 60, 78]
const NAMES := ["01-命中起点", "02-惯性前冲", "03-小抛物线", "04-着地衔接", "05-惯性减速", "06-滑移收尾", "07-落稳", "08-完整收尾"]
var _game: Node2D
var _boot: Node2D
var _targets: Array[Node2D] = []
var _origins: Array[Vector2] = []
var _ground_y := 0.0
var _errors := 0
var _captures: Array[Texture2D] = []
var _evidence: Array[String] = []
var _captions: Array[String] = []
var _max_lifts := [0.0, 0.0, 0.0]
var _first_dust_frame := -1

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ", label)
	_evidence.append(("PASS " if condition else "FAIL ") + label)
	_errors += int(not condition)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("真实位移与落地灰尘视觉验收禁止headless截图")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	SESSION.begin_run("easy")
	_boot = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	root.add_child(_boot)
	await process_frame
	await process_frame
	_game = _boot.get_node("Game")
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
	if hook == null or gun == null or not hook.has_method("set_corpse_ground"):
		_check(false, "正式关卡两类敌人及世界投影API均存在")
		await _finish()
		return
	_ground_y = hook.position.y
	_targets = [_game.player, hook, gun]
	var starts := [530.0, 870.0, 1210.0]
	for index in _targets.size():
		var actor: Node2D = _targets[index]
		actor.position = Vector2(starts[index], _ground_y)
		actor.visible = true
		actor.face = -1
		actor._sync_sprite()
		_origins.append(actor.position)
	for prop: Node2D in _game.props:
		prop.visible = false
	_game.player.vy = 0.0
	_game.player.vx = 0.0
	_game.player.face = 1
	_game.player.on_ground = true
	_game.player.keys.clear()
	_game.current_room = 1
	_game.cam_tl = Vector2(420.0, _ground_y - 520.0).round()
	_game.cam.position = _game.cam_tl + Vector2(680.0, 382.5)
	_game.cam.force_update_scroll()
	_game.bg._process(0.0)
	# 来自左侧的真实致命伤使三者同向前冲；不直接设置dead、不手工生成尘土。
	seed(905103)
	for enemy: Node2D in [hook, gun]:
		_game._on_player_bat_swung(enemy.body_rect(), 1)
	_game.player.force_death(_game.player.position.x - 100.0)
	_check(hook.dead and gun.dead and _game.player.dead and _game._corpse_impacts.size() == 2,
			"敌人与主角经正式伤害链立即死亡，两个敌人惯性任务登记")
	await _capture(0, 0)
	for frame in range(1, 79):
		for effect: Node in _game.fx_layer.get_children():
			if effect.has_method("_process") and effect.get("active") == true:
				effect._process(DT)
		hook.step(DT)
		gun.step(DT)
		# 宿主击退入口已经统一推进死亡弹道，不能再单独更新一次导致双倍速度。
		_game._update_enemy_knockbacks(DT)
		_game.player.step(DT)
		_game.fx_layer.queue_redraw()
		_game.bg._process(0.0)
		for index in _targets.size():
			_max_lifts[index] = maxf(float(_max_lifts[index]), _ground_y - _targets[index].position.y)
		var stats: Dictionary = _game.fx_layer.corpse_dust_stats()
		if _first_dust_frame < 0 and int(stats["total"]) > 0:
			_first_dust_frame = frame
		if frame == _first_dust_frame + 3 and _first_dust_frame > 0:
			await process_frame
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(OUTPUT.path_join("首次落地灰尘-真窗口.png")) == OK,
					"首落后50ms灰尘真窗口截图")
		if MARKS.has(frame):
			await _capture(MARKS.find(frame), frame)
	for index in _targets.size():
		var actor: Node2D = _targets[index]
		var shift: float = actor.position.x - _origins[index].x
		_check(shift > 180.0, "对象%d实际惯性位移%.2fpx明显超过旧短推退" % [index, shift])
		_check(float(_max_lifts[index]) > 10.0 and float(_max_lifts[index]) < 70.0,
				"对象%d真实根节点小抛物线高度%.2fpx" % [index, _max_lifts[index]])
		_check(absf(actor.position.y - _ground_y) < 1.1, "对象%d在真实地面落稳" % index)
	_check(hook.corpse_lift == 0.0 and gun.corpse_lift == 0.0,
			"敌人全程不叠旧视觉抬升")
	_check(_game._corpse_impacts.is_empty(), "完成后没有遗留敌人惯性任务")
	var final_stats: Dictionary = _game.fx_layer.corpse_dust_stats()
	_check(int(final_stats["total"]) == 3 and int(final_stats["active"]) == 0,
			"主角与两敌人各一次落尘，收尾全部回池")
	await _contact_sheet()
	await _finish()

func _capture(index: int, frame: int) -> void:
	var parts: Array[String] = []
	for actor_index in _targets.size():
		var actor: Node2D = _targets[actor_index]
		var dx: float = actor.position.x - _origins[actor_index].x
		var lift: float = _ground_y - actor.position.y
		parts.append("%.0f/%.0f" % [dx, lift])
		if actor_index > 0:
			_check(actor.corpse_lift == 0.0, "%s对象%d本体无二次抬升" % [NAMES[index], actor_index])
			_check(actor._shadow.visible and absf(actor._shadow.global_position.y - (_ground_y - 1.0)) <= 1.1,
					"%s对象%d阴影留在地面" % [NAMES[index], actor_index])
	var line := "%.3fs  主角/近战/枪手：dx/离地px = %s" % [frame * DT, "  ".join(parts)]
	_captions.append(line)
	print(line)
	_evidence.append(line)
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	_check(capture.save_png(OUTPUT.path_join(NAMES[index] + ".png")) == OK, NAMES[index] + "真窗口截图保存")
	_captures.append(ImageTexture.create_from_image(capture))

func _contact_sheet() -> void:
	# 对照板只重排真实GPU截图；每帧相机不动，以同一组地砖观察实际前进。
	var board := SubViewport.new()
	board.size = Vector2i(1440, 1050)
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(board)
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1440, 1050)
	backdrop.color = Color("#101820")
	board.add_child(backdrop)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	_label(board, font, "真实惯性击飞 / 固定镜头逐时刻 · 左主角 / 中近战兵 / 右枪手", Vector2(20, 12), 25)
	_label(board, font, "来自正式 M01 真窗口；dx 是根节点实际前进像素，离地是实际脚底高度，不是精灵偏移。", Vector2(20, 49), 18)
	for index in _captures.size():
		var column := index % 2
		var row := index / 2
		var origin := Vector2(20 + column * 714, 90 + row * 237)
		_label(board, font, NAMES[index] + "  " + "%.3fs" % (MARKS[index] * DT), origin, 21)
		var atlas := AtlasTexture.new()
		atlas.atlas = _captures[index]
		atlas.region = Rect2(0, 340, 1360, 330)
		var view := TextureRect.new()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.texture = atlas
		view.position = origin + Vector2(0, 34)
		view.size = Vector2(690, 167)
		view.clip_contents = true
		board.add_child(view)
		_label(board, font, _captions[index], origin + Vector2(0, 207), 15)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(board.get_texture().get_image().save_png(OUTPUT.path_join("惯性击飞-主角与敌人-真窗口连续对照.png")) == OK,
			"真实前冲小抛物线GPU对照板保存")
	board.free()

func _label(parent: Node, font: Font, value: String, point: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = point
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)

func _finish() -> void:
	if is_instance_valid(_boot):
		_stop_audio(_boot)
		_boot.free()
	SESSION.reset_for_tests()
	_evidence.append("DEATH_INERTIA_WINDOW_RESULT: " + ("PASS" if _errors == 0 else "FAIL"))
	var report := FileAccess.open(OUTPUT.path_join("真窗口验收记录.txt"), FileAccess.WRITE)
	if report != null:
		report.store_string("\n".join(_evidence))
	await process_frame
	print("DEATH_INERTIA_WINDOW_RESULT: ", "PASS" if _errors == 0 else "FAIL")
	quit(0 if _errors == 0 else 1)

func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		node.stop()
	for child: Node in node.get_children():
		_stop_audio(child)
