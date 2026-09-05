extends SceneTree
## 新终端 HUD 的数据/文字/兼容与跟身 CD 检查；像素观感另走真窗口 render_hud_redesign。

const SKIN := preload("res://scripts/hud_industrial_overlay.gd")
var _pass := 0
var _fail := 0

class HudHost:
	extends Node2D
	var player: KairullPlayer
	var db: AtlasDB
	var level: CorridorLevel
	var red_boss: Node2D
	var minions: Array = []
	var debug := false
	var current_room := 1
	var level_cleared := false
	var progress := {"elapsed": 97.8, "enemies_total": 20, "enemies_defeated": 8,
		"rooms_total": 10, "rooms_cleared": 3, "checkpoint": "货运中继站",
		"checkpoint_index": 2, "is_extended": true}
	func room_alive_count(_index: int) -> int:
		return 2
	func room_total_count(_index: int) -> int:
		return 5
	func run_progress() -> Dictionary:
		return progress


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := HudHost.new()
	host.db = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json"])
	host.level = CorridorLevel.new()
	host.level.build(false)
	host.level.rooms = [{"name": "安全入口", "rect": Rect2i(0, 0, 8, 12)},
		{"name": "检疫货运长廊", "rect": Rect2i(8, 0, 20, 12)}]
	host.player = KairullPlayer.new()
	host.player.auto_input = false
	host.player.db = host.db
	host.player.level = host.level
	get_root().add_child(host)
	host.add_child(host.player)
	var hud := GameHud.new()
	hud.host = host
	host.add_child(hud)
	await process_frame
	var overlay: GameHudOverlay = hud._overlay
	ok(overlay.get_script() == SKIN, "正式 HUD 已换成工业终端皮肤")
	ok(overlay is GameHudOverlay, "保留旧 GameHudOverlay 类型和房间 API")
	ok(not overlay.uses_gun_reticle(), "纯近战不绘制大枪械准星")
	ok(not hud._help_label.visible and hud._help_label.text.contains("双S 下穿平台") \
			and hud._help_label.text.contains("1.5秒"), "隐藏重复帮助行，保留操作文本契约")
	var model: Dictionary = overlay.build_view_model()
	ok(model["room_name"] == "检疫货运长廊" and model["local_alive"] == 2 \
			and model["local_total"] == 5, "区段名与本区威胁来自当前房间")
	ok(model["rooms_total"] == 10 and model["enemies_total"] == 20 \
			and model["enemies_defeated"] == 8, "扩展关卡 10 区段 / 20 敌人数据正确")
	ok(model["checkpoint"] == "货运中继站" and model["checkpoint_index"] == 2,
			"同步点数据使用宿主单一来源")
	ok(model["time_text"] == "01:37" and model["is_extended"], "计时与扩展关卡状态正确")
	ok(not model.has("rooms_completed") and overlay.is_room_completed(model, 2) \
			and not overlay.is_room_completed(model, 3), "旧宿主仅有完成数时保留连续前缀回退")
	# 刻意先清后面的房间：不能把仍有高台敌人的早期区段误标为已清。
	host.progress["rooms_completed"] = [0, 3, 5]
	model = overlay.build_view_model()
	ok(model["rooms_completed"] == [0, 3, 5], "精确已清房间下标透传到视图模型")
	for index in 10:
		ok(overlay.is_room_completed(model, index) == [0, 3, 5].has(index),
				"非连续清场正确映射第 %d 区段" % (index + 1))
	ok(not overlay.is_room_completed(model, -1) and not overlay.is_room_completed(model, 10),
			"进度段条忽略越界下标")
	host.progress["rooms_completed"] = []
	model = overlay.build_view_model()
	ok(not overlay.is_room_completed(model, 0) and not overlay.is_room_completed(model, 2),
			"精确完成列表为空时不退回计数前缀")
	host.progress.erase("rooms_completed")
	var font := hud.get_theme_font()
	for width in [180.0, 250.0, 366.0, 548.0]:
		var fitted: String = overlay.fit_text(font, "协议检疫站·外环货运集散与数据清洗中继长廊·维护传输总站", 22, width)
		ok(font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x <= width \
				and fitted.ends_with("…"), "长中文标题在 %.0fpx 预算内省略" % width)
	ok(overlay.fit_text(font, "凯露尔", 17, 180.0) == "凯露尔", "短标题不截断")
	ok(overlay.format_time(-1.0) == "00:00" and overlay.format_time(600.0) == "10:00",
			"计时非负并支持十分钟以上流程")
	overlay.show_room_card("货运中继站", 3, 5)
	ok(overlay._room_card_name == "货运中继站" and overlay._room_card_until > 0.0,
			"进房短卡保留原调用方式")
	overlay.reset_room_card()
	ok(overlay._room_card_until == 0.0, "重试可清除房间卡")
	host.player.hp = 1
	model = overlay.build_view_model()
	ok(model["hp"] == 1 and not model["dead"], "低生命仍为普通游戏视图")
	host.player.dead = true
	model = overlay.build_view_model()
	ok(model["dead"] and not model["cleared"], "死亡状态显示局部重试面板")
	host.player.dead = false
	host.level_cleared = true
	model = overlay.build_view_model()
	ok(model["cleared"], "清关状态可读取完整行动统计")
	host.progress = {}
	host.current_room = -1
	model = overlay.build_view_model()
	ok(not model["is_extended"] and model["checkpoint"] == "关卡入口" \
			and model["enemies_total"] == 0, "旧关卡无扩展统计时平稳回退")
	ok(not SKIN.LIFE_PANEL.intersects(SKIN.PROGRESS_PANEL) \
			and SKIN.RESULT_PANEL.get_area() < 1360.0 * 765.0 * 0.20,
			"角落状态无重叠，结算面板不到屏幕面积两成")
	host.player.step(1.0 / 60.0)
	var cooldown := host.player.get_node("DashCooldownUI")
	cooldown.set_cooldown(0.75, 1.5, true)
	ok(cooldown.visible and absf(cooldown.ready_ratio() - 0.5) < 0.001,
			"1.5秒CD在0.75秒时六段充能条恰好半满")
	cooldown.set_cooldown(0.0, 1.5, true)
	ok(not cooldown.visible, "冲刺就绪时跟身CD整体隐藏")
	cooldown.set_cooldown(1.0, 1.5, false)
	ok(not cooldown.visible and cooldown.get_parent() == host.player,
			"死亡可隐藏CD；控件仍随玩家而非固定屏幕")
	ok(KairullPlayer.DASH_COOLDOWN == 1.5, "冲刺冷却正式改为1.5秒")
	host.level.free()
	host.free()
	await process_frame
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
