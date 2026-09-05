extends SceneTree
## 球棒击退 + 跟随伤口喷血真窗口验收。
##
## 使用真实 game.tscn 与真实 FreightInspector，只把关卡静态配置换成一间开阔测试房。
## 玩家通过正式挥棍动画发出 bat_swung，依次截取命中、击退中段和击退结束：
##   godot --path godot --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://scripts/render_bat_knockback_blood.gd
## 输出：user://bat_knockback_blood/bat_knockback_blood_*.png（不污染仓库资产导入）。

const DT := 1.0 / 60.0
const MAP_W := 44
const MAP_H := 24
const OUTPUT_DIR := "user://bat_knockback_blood"
const FREIGHT_SCRIPT := preload("res://scripts/freight_inspector.gd")

var _game: Node2D
var _player: KairullPlayer
var _enemy: Node2D
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_configure_test_room()
	var packed := load("res://scenes/game.tscn") as PackedScene
	if packed == null:
		_fail("无法载入真实 game.tscn")
		_finish()
		return

	_game = packed.instantiate() as Node2D
	get_root().add_child(_game)
	current_scene = _game
	await process_frame
	await process_frame

	_player = _game.player as KairullPlayer
	if _player == null or _game.minions.size() != 1:
		_fail("测试房应只生成一名敌人，实际=%d" % _game.minions.size())
		_finish()
		return
	_enemy = _game.minions[0] as Node2D
	if _enemy == null or _enemy.get_script() != FREIGHT_SCRIPT:
		_fail("测试目标不是 FreightInspector")
		_finish()
		return

	# 固定双方站位并关掉敌人索敌，只保留真实死亡、击退、特效和关卡碰撞。
	var floor_y := float((MAP_H - 1) * CorridorLevel.TS) - 0.1
	_player.auto_input = false
	_player.position = Vector2(15 * CorridorLevel.TS + 16.0, floor_y)
	_player.face = 1
	_player.vx = 0.0
	_player.vy = 0.0
	_player.on_ground = true
	_player.keys.clear()
	_player._prev_keys.clear()
	_enemy.position = Vector2(18 * CorridorLevel.TS + 16.0, floor_y)
	_enemy.player = null
	_game.debug = false
	_game.hud.visible = false
	_game.cam_tl = _game._cam_target()
	_game.cam.position = (_game.cam_tl + Vector2(_game.VW, _game.VH) * 0.5).round()
	seed(37041) # 固定霓虹血色和液滴散布，三张图可重复对照。

	for _i in 3:
		await process_frame
	var start_x: float = _enemy.position.x
	print("球棒击退验收：player=", _player.position, " enemy=", _enemy.position)

	# 走正式玩家动作：首帧前送，动画越过命中窗后同步触发 game 的正式伤害链。
	_player.keys = {MOUSE_BUTTON_LEFT: true}
	_player._prev_keys.clear()
	_player.step(DT)
	_player.keys.clear()
	var hit_found: bool = bool(_enemy.dead)
	for _i in range(30):
		if hit_found:
			break
		_player.step(DT)
		await physics_frame
		await process_frame
		hit_found = bool(_enemy.dead)
	if not hit_found:
		_fail("正式挥棍动画未命中 FreightInspector")
		_finish()
		return

	# 命中后约 2 帧：白色爆点、彩色主液柱与伤口首批血滴应同时可见。
	await _advance_frames(2)
	await _shot("bat_knockback_blood_01_hit")

	# 命中后约 0.12 秒：尸体正在滑动，伤口喷口应追上尸体，旧血滴留在身后。
	await _advance_frames(5)
	await _shot("bat_knockback_blood_02_mid")

	# 主液幕结束后：击退与伤口续喷均已完成，只留下原命中点的世界空间墙渍，
	# 可以与中段图里的尸体终点直接对照，确认持久渍没有跟着尸体平移。
	await _advance_frames(70)
	await _shot("bat_knockback_blood_03_end")

	var moved := _enemy.position.x - start_x
	var decals := 0
	if _game.paint_layer != null and _game.paint_layer.blood_wall_manager != null:
		decals = int(_game.paint_layer.blood_wall_manager.debug_stats()["active"])
	print("击退位移=%.2f px，持久墙渍=%d，活动击退=%d" % [moved, decals,
			_game.debug_enemy_knockback_count()])
	if moved < 80.0:
		_fail("致命一段击退距离过短：%.2f" % moved)
	if decals < 1:
		_fail("击退结束画面没有持久墙渍")

	_finish()


func _advance_frames(count: int) -> void:
	for _i in range(count):
		# auto_input=false 时手动推进玩家动画；敌人、击退和两层喷血仍由真实场景逐帧运行。
		_player.keys.clear()
		_player.step(DT)
		await physics_frame
		await process_frame


func _shot(file_stem: String) -> void:
	await process_frame
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		_fail("无法创建截图目录：%s (%s)" % [absolute_dir, make_error])
		return
	var image := get_root().get_texture().get_image()
	var path := OUTPUT_DIR.path_join(file_stem + ".png")
	var error := image.save_png(path)
	print("截图 ", file_stem, " -> ", ProjectSettings.globalize_path(path), " err=", error)
	if error != OK:
		_fail("截图保存失败：%s (%s)" % [path, error])


func _configure_test_room() -> void:
	var rows := PackedStringArray()
	rows.append("#".repeat(MAP_W))
	for _row in range(1, MAP_H - 2):
		rows.append("#" + ".".repeat(MAP_W - 2) + "#")
	# 玩家与巡检员相隔三格；首击 1.2 格前送后进入 76px 正式命中盒。
	rows.append("#" + ".".repeat(14) + "@" + ".." + "m"
			+ ".".repeat(24) + "#")
	rows.append("#".repeat(MAP_W))
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_rooms = [{"name": "击退与喷血验收", "rect": Rect2i(1, 1, 42, 22)}]
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt" # m 标记会由 game 正式覆盖为 FreightInspector。
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "tower"}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM


func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	for child in node.get_children():
		_stop_audio(child)


func _restore_static_config() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = []


func _fail(message: String) -> void:
	_failed = true
	push_error(message)


func _finish() -> void:
	if _game != null and is_instance_valid(_game):
		_stop_audio(_game)
		if _game.fx_layer != null:
			_game.fx_layer.clear_explosions()
		# 先释放真实场景，再还原静态关卡配置；否则存活的 Background 可能在退出前
		# 又重绘一帧并读到已经清空的 active_cfg。
		current_scene = null
		_game.free()
		_game = null
	_restore_static_config()
	print("RENDER_RESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
