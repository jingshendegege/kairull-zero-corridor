extends SceneTree
## M02 playtest 第六轮验收（无头）：
##   1) 竞技场 BGM：hk_arena 接续老城区曲目（音量 -12dB Boss 战略提），
##      场景销毁后 active_bgm/active_bgm_db 还原。
##   2) 出口清场闸门：大黄蜂存活时出口锁定（暗红边光 + 到门不过关）；
##      take_hit 击杀 → 门解锁（青色）→ 到门过关；Backspace 重置 → Boss 复活、门回锁。
##      竞技场 minion=none（0 小怪）天然满足小怪条件。
##   3) M02 回归：闸门开关默认 false，出口到门即过关（清怪仍由房门强制）。
##   4) 房间卡居中：卡宽 = max(房间名宽, 副标题宽) + 2*PAD_X，保底 MIN_W。
## 跑法：godot --headless --path godot --script scripts/test_m02_round6.gd

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


func _press_backspace(game: Node2D) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_BACKSPACE
	ev.pressed = true
	game._unhandled_input(ev)


func _run() -> void:
	# ============ 1) 竞技场 BGM：接续老城区曲目进 Boss 战 ============
	print("== 竞技场 BGM 接续 ==")
	_reset_statics()
	var arena: Node2D = load("res://scenes/hk_arena.tscn").instantiate()
	get_root().add_child(arena)
	await process_frame
	await process_frame
	var game: Node2D = arena.get_node("Game")
	ok(game.music != null, "竞技场创建了音乐播放器（不再静默）")
	if game.music != null:
		ok(game.music.playing, "音乐正在播放")
		ok(game.music.stream != null, "音乐流已加载（mp3 导入生效）")
		ok(absf(game.music.volume_db - (-12.0)) < 0.01,
			"Boss 战音量 -12dB（active_bgm_db 覆盖默认 -14）",
			"vol=%.1f" % game.music.volume_db)
		ok(game.music.finished.is_connected(game.music.play),
			"finished 信号接 play = 循环")
	ok(CorridorLevel.active_exit_requires_boss, "竞技场已开启出口清场闸门")

	# ============ 2) 出口清场闸门：锁 → 击杀 → 解锁过关 → 重置回锁 ============
	print("== 出口清场闸门 ==")
	var player: KairullPlayer = game.player
	player.auto_input = false
	player.hp = 999   ## 摆拍期间挨 Boss 技能不死
	ok(game.exit_door != null, "出口门节点在场")
	ok(game.minions.is_empty(), "竞技场 minion=none → 0 小怪（小怪条件天然满足）")
	var boss: Node2D = game.red_boss
	ok(boss != null and boss is HornetBoss, "大黄蜂在场")
	ok(game._exit_gated(), "Boss 存活 → 出口闸门关闭")

	# Boss 存活时走到出口：不过关
	player.position = game.level.exit_point
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	for i in range(12):
		await physics_frame
	ok(game.exit_door.locked, "Boss 存活 → 出口门 LOCKED（暗红边光）")
	ok(not game.level_cleared, "Boss 存活 → 站到出口也不过关")

	# 击杀大黄蜂（真实受伤通道 take_hit × HP_MAX）
	var hits := 0
	while not boss.dead and hits < HornetBoss.HP_MAX + 4:
		boss.take_hit(player.position.x, 1)
		hits += 1
	ok(boss.dead, "take_hit ×%d 击杀大黄蜂（HP_MAX=%d）" % [hits, HornetBoss.HP_MAX],
		"hp=%d" % boss.hp)
	# 玩家可能被 Boss 冲撞推开，归位后等闸门解锁帧
	player.position = game.level.exit_point
	player.vx = 0.0
	player.vy = 0.0
	for i in range(12):
		await physics_frame
	ok(not game.exit_door.locked, "Boss 死亡 → 出口门解锁（青色呼吸 + 金属闩响）")
	ok(game.level_cleared, "Boss 死亡 → 站到出口即过关")

	# Backspace 重置：Boss 复活、门回锁、过关标志清除
	_press_backspace(game)
	await physics_frame
	await physics_frame
	ok(not game.level_cleared, "Backspace → 过关标志复位")
	ok(not boss.dead and boss.hp == HornetBoss.HP_MAX,
		"Backspace → 大黄蜂满血复活", "hp=%d dead=%s" % [boss.hp, boss.dead])
	ok(game.exit_door.locked, "Backspace → 出口门回锁")
	ok(game.music != null and game.music.playing, "重置后 BGM 仍在播放")

	arena.queue_free()
	await process_frame
	ok(CorridorLevel.active_bgm == "", "竞技场销毁后 active_bgm 还原")
	ok(absf(CorridorLevel.active_bgm_db - (-14.0)) < 0.01, "active_bgm_db 还原 -14")
	ok(not CorridorLevel.active_exit_requires_boss, "出口闸门开关还原 false")

	# ============ 3) M02 回归：闸门默认关，出口到门即过关 ============
	print("== M02 回归：出口行为不变 ==")
	_reset_statics()
	var m02: Node2D = load("res://scenes/m02_tower.tscn").instantiate()
	get_root().add_child(m02)
	await process_frame
	await process_frame
	for i in range(3):
		await physics_frame
	var game2: Node2D = m02.get_node("Game")
	ok(not CorridorLevel.active_exit_requires_boss, "M02 未开启出口闸门（boss=none）")
	ok(game2.red_boss == null, "M02 无关底 Boss")
	ok(game2.minions.size() == 19, "M02 小怪 19 只在场", "n=%d" % game2.minions.size())
	var player2: KairullPlayer = game2.player
	player2.auto_input = false
	player2.hp = 999
	player2.position = game2.level.exit_point
	player2.vx = 0.0
	player2.vy = 0.0
	player2.keys.clear()
	for i in range(10):
		await physics_frame
		if game2.level_cleared:
			break
	ok(game2.exit_door != null and not game2.exit_door.locked,
		"M02 出口门不锁定（闸门关闭 → 恒解锁）")
	ok(game2.level_cleared, "M02 出口到门即过关（回归：行为不变）")
	m02.queue_free()
	await process_frame

	# ============ 4) 房间卡文字自适应 ============
	print("== 房间卡文字自适应 ==")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	var overlay := GameHudOverlay.new()
	for room: Dictionary in CorridorLevel.MAP_M02_TOWER_ROOMS:
		var room_name: String = room["name"]
		for sub: String in ["敌人 19/19", "安全区域"]:
			var nw := font.get_string_size(room_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, GameHudOverlay.ROOM_CARD_NAME_SIZE).x
			var sw := font.get_string_size(sub,
					HORIZONTAL_ALIGNMENT_LEFT, -1, GameHudOverlay.ROOM_CARD_SUB_SIZE).x
			var card := overlay.room_card_size(font, room_name, sub)
			ok(card.x >= nw + 2.0 * GameHudOverlay.ROOM_CARD_PAD_X - 0.01,
				"「%s / %s」卡宽 %.0f ≥ 名宽 %.0f + 2*padding" % [room_name, sub, card.x, nw])
			ok(card.x >= sw + 2.0 * GameHudOverlay.ROOM_CARD_PAD_X - 0.01,
				"「%s / %s」卡宽 ≥ 副标题宽 %.0f + 2*padding" % [room_name, sub, sw])
			ok(card.x >= GameHudOverlay.ROOM_CARD_MIN_W,
				"「%s」卡宽 ≥ 保底 MIN_W %.0f" % [room_name, GameHudOverlay.ROOM_CARD_MIN_W])
			ok(card.y == GameHudOverlay.ROOM_CARD_H, "「%s」卡高不变" % room_name)
	overlay.free()

	_reset_statics()
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
