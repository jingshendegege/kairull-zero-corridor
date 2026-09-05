extends SceneTree
## M02 playtest 第五轮验收（无头）：
##   1) 关卡 BGM：active_bgm 非空 → game 创建循环音乐播放器（音量压在音效之下）；
##      空 → 不创建。m02 场景销毁后 active_bgm 还原（音乐随之停止）。
##   2) CLEAR 卡文字自适应：卡宽 = max(标题宽, 副标题宽) + 2*PAD_X，保底 MIN_W——
##      "M01 旧城区" / "M02 数据塔" / 压力串 "M99 超长关卡名称测试" 均不溢框。
##   3) 出口 → 竞技场转场：CLEAR 卡停留 1.4s → 0.5s 淡黑 → 切 hk_arena.tscn；
##      转场后 hornet 在场、Boss 血条可见、玩家出生点正确、m02 静态量不泄漏。
## 跑法：godot --headless --path godot --script scripts/test_m02_round5.gd

var _pass := 0
var _fail := 0

const DT := 1.0 / 60.0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _reset_statics() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_exit_requires_boss = false
	GameBackground.active_cfg = []


func _run() -> void:
	# ============ 1) BGM：默认关（active_bgm 空）不创建音乐播放器 ============
	print("== BGM：空配置不创建播放器 ==")
	_reset_statics()
	var plain: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(plain)
	await process_frame
	await process_frame
	ok(plain.music == null, "active_bgm 为空 → 无音乐播放器")
	plain.queue_free()
	await process_frame

	# ============ 2) BGM：m02 boot 配置下创建循环播放器 ============
	print("== BGM：m02 配置创建循环播放器 ==")
	_reset_statics()
	var m02: Node2D = load("res://scenes/m02_tower.tscn").instantiate()
	get_root().add_child(m02)
	await process_frame
	await process_frame
	var game: Node2D = m02.get_node("Game")
	ok(game.music != null, "active_bgm 非空 → 音乐播放器已创建")
	if game.music != null:
		ok(game.music.playing, "音乐正在播放")
		ok(game.music.stream != null, "音乐流已加载（mp3 导入生效）")
		ok(absf(game.music.volume_db - game.MUSIC_VOLUME_DB) < 0.01,
			"音乐音量 = MUSIC_VOLUME_DB（%.1f dB，压在音效之下）" % game.MUSIC_VOLUME_DB,
			"vol=%.1f" % game.music.volume_db)
		ok(game.music.volume_db < -6.0, "音量明显低于 0dB 音效基准",
			"vol=%.1f" % game.music.volume_db)
		ok(game.music.finished.is_connected(game.music.play),
			"finished 信号接 play = 播完即回放（循环）")
	m02.queue_free()
	await process_frame
	ok(CorridorLevel.active_bgm == "", "m02 销毁后 active_bgm 还原（音乐随场景停止）")
	ok(CorridorLevel.active_next_scene == "", "m02 销毁后 active_next_scene 还原")

	# ============ 3) CLEAR 卡文字自适应 ============
	print("== CLEAR 卡文字自适应 ==")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	var overlay := GameHudOverlay.new()
	var sub_text := "回廊区段已肃清 · Backspace 重置"
	var sw := font.get_string_size(sub_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, GameHudOverlay.CLEAR_SUB_SIZE).x
	for title: String in ["M01 旧城区", "M02 数据塔", "M99 超长关卡名称测试"]:
		var tt: String = title + " CLEAR"
		var tw := font.get_string_size(tt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, GameHudOverlay.CLEAR_TITLE_SIZE).x
		var card := overlay.clear_card_size(font, tt, sub_text)
		ok(card.x >= tw + 2.0 * GameHudOverlay.CLEAR_CARD_PAD_X - 0.01,
			"「%s」卡宽 %.0f ≥ 标题宽 %.0f + 2*padding" % [tt, card.x, tw])
		ok(card.x >= sw + 2.0 * GameHudOverlay.CLEAR_CARD_PAD_X - 0.01,
			"「%s」卡宽 ≥ 副标题宽 %.0f + 2*padding" % [tt, sw])
		ok(card.x >= GameHudOverlay.CLEAR_CARD_MIN_W,
			"「%s」卡宽 ≥ 保底 MIN_W %.0f" % [tt, GameHudOverlay.CLEAR_CARD_MIN_W])
		ok(card.y == GameHudOverlay.CLEAR_CARD_H, "「%s」卡高不变" % tt)
	overlay.free()

	# ============ 4) 出口 → 竞技场转场 ============
	print("== 出口 → hk_arena 转场 ==")
	_reset_statics()
	m02 = load("res://scenes/m02_tower.tscn").instantiate()
	get_root().add_child(m02)
	current_scene = m02   ## 模拟主场景运行态：change_scene_to_file 才能接管/释放
	await process_frame
	await process_frame
	for i in range(3):
		await physics_frame

	game = m02.get_node("Game")
	var player: KairullPlayer = game.player
	player.auto_input = false
	player.hp = 999
	# 直达塔心出口门口（本测试不验走位，走位覆盖在 round4）
	player.position = game.level.exit_point
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	for i in range(10):
		await physics_frame
		if game.level_cleared:
			break
	ok(game.level_cleared, "玩家到门口 → level_cleared")
	ok(game._clear_elapsed >= 0.0, "过关计时器启动", "t=%.2f" % game._clear_elapsed)
	ok(game.music != null and game.music.playing, "过关瞬间 BGM 仍在播放")

	# 推进到 CLEAR 卡停留结束、淡黑进行中（≈50%）
	while game._clear_elapsed >= 0.0 and game._clear_elapsed < game.CLEAR_HOLD + game.FADE_TIME * 0.5 \
			and not game._transitioning:
		game._update_clear_transition(DT)
	ok(not game._transitioning, "淡黑中段尚未切场景")
	ok(game._fade_k > 0.35 and game._fade_k < 0.65, "淡黑进度 ≈50%",
		"k=%.2f" % game._fade_k)
	ok(absf(game.hud._fade_rect.modulate.a - game._fade_k) < 0.02,
		"HUD 淡黑层 alpha 跟随进度", "a=%.2f" % game.hud._fade_rect.modulate.a)

	# 推进到淡黑完成 → 触发切场景（call_deferred，等帧末生效）
	while not game._transitioning:
		game._update_clear_transition(DT)
	ok(game._fade_k >= 1.0, "淡黑完成（k=1）才发起切场景")
	for i in range(4):
		await process_frame

	ok(not is_instance_valid(m02), "m02 场景已释放")
	var arena: Node2D = get_root().get_node_or_null("HKArena")
	ok(arena != null, "当前场景已切换为 hk_arena")
	ok(current_scene == arena, "current_scene 指向 hk_arena")
	if arena != null:
		var game2: Node2D = arena.get_node("Game")
		await process_frame
		await process_frame
		ok(game2.red_boss != null and game2.red_boss is HornetBoss,
			"竞技场 hornet 在场")
		ok(game2.red_boss != null and not game2.red_boss.dead, "hornet 存活")
		ok(game2.hud._boss_bar_bg.visible and game2.hud._boss_bar_fill.visible,
			"Boss 血条已显示")
		ok(absf(game2.hud._boss_bar_fill.size.x - 554.0) < 1.0,
			"Boss 血条满格（HP 18/18）", "w=%.1f" % game2.hud._boss_bar_fill.size.x)
		ok(game2.player != null and
				game2.player.position.distance_to(game2.level.spawn) < 2.0,
			"玩家出生在竞技场 @ 点", str(game2.player.position))
		ok(game2.music != null and game2.music.playing,
			"竞技场 BGM 已接续播放（round6：老城区曲目延续进 Boss 战）")
		ok(game2.music != null and absf(game2.music.volume_db - (-12.0)) < 0.01,
			"竞技场 BGM 音量 -12dB（Boss 战略提，默认 -14）",
			"vol=%.1f" % (game2.music.volume_db if game2.music != null else 999.0))
		ok(game2._clear_elapsed < 0.0, "新场景过关计时器干净")
	# m02 静态量不泄漏：arena 配置就位，m02 专有项已还原
	ok(CorridorLevel.active_map == CorridorLevel.MAP_HK_ARENA,
		"active_map = 竞技场图（非 m02 塔图）")
	ok(CorridorLevel.active_minion == "none", "active_minion = none（Boss 单挑）")
	ok(CorridorLevel.active_boss == "hornet", "active_boss = hornet")
	ok(CorridorLevel.active_bgm == "res://assets/bgm/m02_oldtown.mp3",
		"active_bgm = 老城区曲目（round6 起竞技场接续 BGM，不再置空）")
	ok(CorridorLevel.active_title == "HK 竞技场", "active_title = HK 竞技场（修复 CLEAR 卡回退 M01 的待办 bug）")
	ok(CorridorLevel.active_tile_style.is_empty(), "active_tile_style 已还原为 {}")
	ok(CorridorLevel.active_next_scene == "", "active_next_scene 为空 → 竞技场过关不连锁转场")

	# 清理
	if arena != null:
		arena.queue_free()
	current_scene = null
	await process_frame
	_reset_statics()

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
