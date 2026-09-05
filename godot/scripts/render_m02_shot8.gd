extends SceneTree
## M02 playtest 第五轮渲染验收（真实窗口跑，m02 boot 自带 BGM）：
##   a 玩家到塔心出口 —— CLEAR 卡弹出，标题文字舒适收在琥珀双框内（不再溢出）
##   b 过关 1.4s 后淡黑进行中（≈50% 灰场，卡仍隐约可见）
##   c 转场完成 —— hk_arena 竞技场：大黄蜂在场 + 顶部 Boss 血条（交接渲染证明）
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_shot8.gd
## 输出：user://shot8_*.png（外层拷到 m02_renders/）

var _shot_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var m02: Node2D = load("res://scenes/m02_tower.tscn").instantiate()
	get_root().add_child(m02)
	current_scene = m02   ## 模拟主场景运行态，change_scene_to_file 才能接管/释放
	await process_frame
	await process_frame

	var game: Node2D = m02.get_node("Game")
	var player: KairullPlayer = game.player
	player.auto_input = false
	player.hp = 999   ## 摆拍期间挨枪不死
	game.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 20.0   ## 标题卡/帮助条淡出
	print("  BGM playing = ", game.music != null and game.music.playing, "（应为 true）")

	# ============ 镜头 a：到出口，CLEAR 卡（文字自适应框内）============
	player.position = game.level.exit_point
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	for i in range(10):
		await physics_frame
		if game.level_cleared:
			break
	print("  镜头a level_cleared = ", game.level_cleared, "（应为 true）")
	game._update_room_state()
	game.cam_tl = game._cam_target()
	for i in range(15):   ## 卡呼吸 + 相机就位（仍处 1.4s 停留期，无淡黑）
		await process_frame
	print("  镜头a fade_k = %.2f（应为 0）" % game._fade_k)
	await _shot("shot8_a_clear_card_fit")

	# ============ 镜头 b：淡黑进行中（≈50%）============
	var guard := 0
	while is_instance_valid(game) and game._fade_k < 0.45 and guard < 300:
		await process_frame
		guard += 1
	if is_instance_valid(game):
		print("  镜头b fade_k = %.2f（应 0.45~0.75）" % game._fade_k)
		await _shot("shot8_b_fade_to_black")

	# ============ 镜头 c：转场完成，竞技场 hornet + Boss 血条 ============
	guard = 0
	while current_scene == m02 and guard < 300:
		await process_frame
		guard += 1
	var arena: Node2D = get_root().get_node_or_null("HKArena")
	print("  镜头c 场景切换 = ", arena != null, "（应为 true）")
	if arena == null:
		print("RENDER_RESULT: FAIL（未切到 hk_arena）")
		quit(1)
		return
	var game2: Node2D = arena.get_node("Game")
	var player2: KairullPlayer = game2.player
	player2.auto_input = false
	player2.hp = 999
	game2.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 20.0   ## 竞技场标题卡跳过
	# 把玩家挪到大黄蜂附近取景：出生点距 hornet（出口 c47）太远，镜头装不下
	player2.position = Vector2(40 * 32 + 16, 19 * 32 - 0.1)
	player2.vx = 0.0
	player2.vy = 0.0
	player2.face = 1
	for i in range(30):   ## hornet AI 起步 + Boss 血条刷新 + 相机缓动
		await process_frame
	game2.cam_tl = game2._cam_target()
	for i in range(5):
		await process_frame
	var boss: Node2D = game2.red_boss
	print("  镜头c hornet = ", boss is HornetBoss, " hp = ", boss.hp if boss != null else -1,
		" boss_bar = ", game2.hud._boss_bar_bg.visible)
	await _shot("shot8_c_arena_hornet")

	print("RENDER_RESULT: PASS")
	quit(0)


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
