extends SceneTree
## 时停HUD/录像表现合同：只验证状态和布局，不以无头截图代替真窗口观感。

const SIGNAL := preload("res://scripts/time_signal_overlay.gd")
const SKIN := preload("res://scripts/hud_industrial_overlay.gd")
var _pass := 0
var _fail := 0

class LegacyHost extends Node2D:
	var player: KairullPlayer
	var db: AtlasDB
	var level: CorridorLevel
	var red_boss: Node2D
	var minions: Array = []
	var debug := false
	var current_room := 0
	var level_cleared := false
	func room_alive_count(_index: int) -> int:
		return 0
	func room_total_count(_index: int) -> int:
		return 0

class TimelineHost extends LegacyHost:
	var progress := {"checkpoint": "关卡入口", "checkpoint_index": -1}
	var timeline: Variant = {"enabled": true, "active": false, "energy_ratio": 1.0,
		"remaining": 2.0, "max_duration": 2.0, "lockout": 0.0, "phase": "playing",
		"rewind_progress": 0.0, "difficulty": "easy"}
	func timeline_view_model() -> Variant:
		return timeline
	func run_progress() -> Dictionary:
		return progress


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)


func make_hud(host: LegacyHost) -> GameHud:
	host.db = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json"])
	host.level = CorridorLevel.new()
	host.level.build(false)
	host.level.rooms = [{"name": "信号测试站", "rect": Rect2i(0, 0, 20, 20)}]
	host.player = KairullPlayer.new()
	host.player.auto_input = false
	host.player.db = host.db
	host.player.level = host.level
	get_root().add_child(host)
	host.add_child(host.player)
	var hud := GameHud.new()
	hud.host = host
	host.add_child(hud)
	return hud


func _run() -> void:
	var base := SIGNAL.normalize_view_model({})
	ok(not base["enabled"] and not base["active"] and base["phase"] == "playing",
			"空API默认关闭，不接管旧宿主")
	ok(base["max_duration"] == 2.0 and base["remaining"] == 2.0, "时停默认时长2秒")
	var bounded := SIGNAL.normalize_view_model({"enabled": true, "active": true,
		"energy_ratio": 5.0, "remaining": 9.0, "lockout": -2.0, "rewind_progress": -1.0})
	ok(bounded["energy_ratio"] == 1.0 and bounded["remaining"] == 2.0, "能量显示不越界")
	ok(bounded["lockout"] == 0.0 and bounded["rewind_progress"] == 0.0, "倒带与锁定进度非负")
	var invalid := SIGNAL.normalize_view_model({"enabled": true, "energy_ratio": NAN,
		"remaining": INF, "max_duration": "bad", "phase": "unknown"})
	ok(invalid["energy_ratio"] == 0.0 and invalid["remaining"] == 0.0
			and invalid["max_duration"] == 2.0, "异常数值不污染绘制坐标")
	ok(invalid["phase"] == "playing", "未知阶段平稳回退")
	var dying := SIGNAL.normalize_view_model({"enabled": true, "active": true, "phase": "dying"})
	ok(not dying["active"] and dying["phase"] == "dying", "死亡阶段不会同时显示时停激活")
	ok(not dying["death_prompt_ready"], "倒地动画播完前不出现重开字幕")
	var disabled := SIGNAL.normalize_view_model({"enabled": false, "active": true, "phase": "rewinding"})
	ok(not disabled["active"] and disabled["phase"] == "playing", "关闭API不会残留倒带信号")
	ok(SIGNAL.DEATH_PROMPT == ["不对……", "这样不行。", "（按任意按钮重开）"],
			"死亡字幕使用指定两句与任意按钮说明")
	var interference := SIGNAL.normalize_view_model({"enabled": true, "active": true,
		"phase": "interference", "glitch_progress": 1.3, "death_prompt_ready": true})
	ok(interference["phase"] == "interference" and not interference["active"],
			"花屏是独立转场阶段，不能误显示时停")
	ok(interference["glitch_progress"] == 1.0 and not interference["death_prompt_ready"],
			"花屏进度钳制且禁止死亡等待字幕")
	var glitch_invalid := SIGNAL.normalize_view_model({"enabled": true,
		"phase": "interference", "glitch_progress": NAN})
	ok(glitch_invalid["glitch_progress"] == 0.0, "异常花屏进度安全归零")
	var glitch_disabled := SIGNAL.normalize_view_model({"enabled": false, "phase": "interference"})
	ok(glitch_disabled["phase"] == "playing", "旧宿主或关闭API不残留花屏")
	var screen_size := Vector2(1360, 765)
	var blocks := SIGNAL.interference_blocks(screen_size, 0.5)
	ok(blocks.size() == SIGNAL.GLITCH_BANDS * 4 + SIGNAL.GLITCH_BLOCKS and blocks.size() <= 60,
			"花屏矩形数量不超过60个")
	var total_area := 0.0
	var clipped := true
	var pixel_aligned := true
	var no_white := true
	for block: Dictionary in blocks:
		var rect: Rect2 = block["rect"]
		var color: Color = block["color"]
		total_area += rect.get_area()
		clipped = clipped and Rect2(Vector2.ZERO, screen_size).encloses(rect)
		pixel_aligned = pixel_aligned and rect.position == rect.position.round() and rect.size == rect.size.round()
		no_white = no_white and minf(color.r, minf(color.g, color.b)) < 0.8 and color.a <= 0.76
	ok(total_area < screen_size.x * screen_size.y * 0.18, "花屏总绘制面积低于18%，不靠全屏白闪")
	ok(clipped and pixel_aligned, "RGB撕裂条与错码块逐像素对齐且不越屏")
	ok(no_white, "花屏不使用全白或不透明高亮块")
	ok(blocks == SIGNAL.interference_blocks(screen_size, 0.5), "同一进度图案稳定，不每帧随机频闪")
	ok(SIGNAL.interference_blocks(Vector2.ZERO, 0.5).is_empty(), "空视口不生成无效花屏几何")

	var signal_layer := SIGNAL.new()
	get_root().add_child(signal_layer)
	await process_frame
	ok(signal_layer.layer == 3 and signal_layer.process_mode == Node.PROCESS_MODE_ALWAYS,
			"信号独立CanvasLayer，世界暂停仍可更新")
	ok(signal_layer._surface.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"信号层不拦截右键输入")
	ok(not signal_layer._surface.visible, "普通游戏没有常驻全屏信号")
	signal_layer.set_time_state(true, 0.5, 0.0, "playing", 0.0)
	var signal_model := signal_layer.view_model()
	ok(signal_model["effect_visible"] and signal_model["scanline_mode"] == "held",
			"时停使用固定细扫描线")
	ok(signal_model["remaining"] == 1.0, "独立setter从比例推导剩余秒数")
	ok(not signal_model["full_screen_filter"] and signal_layer._surface.material == null,
			"不使用全屏滤镜或屏幕模糊材质")
	ok(SIGNAL.MAX_SCAN_ALPHA <= 0.12, "扫描线透明度严格限制")
	signal_layer.apply_view_model({"enabled": true, "phase": "dying", "death_prompt_ready": false})
	ok(not signal_layer.view_model()["death_prompt_visible"], "倒地阶段无居中重开字幕")
	signal_layer.apply_view_model({"enabled": true, "phase": "dying", "death_prompt_ready": true})
	ok(signal_layer.view_model()["death_prompt_visible"], "完成倒地后显示居中青色字幕")
	signal_layer.apply_view_model({"enabled": true, "phase": "rewinding", "death_prompt_ready": true})
	ok(not signal_layer.view_model()["death_prompt_visible"], "回溯阶段立即隐藏死亡等待字幕")
	signal_layer.set_time_state(false, 0.0, 0.5, "rewinding", 0.4)
	signal_model = signal_layer.view_model()
	ok(signal_model["scanline_mode"] == "reverse" and signal_model["rewind_progress"] == 0.4,
			"倒带扫描方向与时间轴状态同步")
	signal_layer.set_time_state(false, 0.3, 0.0, "playing", 0.0)
	ok(not signal_layer._surface.visible, "松开时停后信号即时消失")
	signal_layer.set_time_state(false, 0.0, 0.0, "interference", 1.0, 0.4)
	signal_model = signal_layer.view_model()
	ok(signal_model["effect_visible"] and signal_model["interference_visible"]
			and signal_model["scanline_mode"] == "torn", "花屏使用独立撕裂绘制分支")
	ok(signal_model["glitch_progress"] == 0.4 and not signal_model["death_prompt_visible"],
			"独立setter可传花屏进度，转场不出现死亡字")
	await process_frame
	signal_layer.apply_view_model({})
	ok(not signal_layer._surface.visible, "重开后普通游戏清除花屏残留")

	var host := TimelineHost.new()
	var hud := make_hud(host)
	await process_frame
	var skin: GameHudOverlay = hud._overlay
	var model: Dictionary = skin.build_view_model()
	ok(model["hp_max"] == 5 and model["difficulty_text"] == "简单 · 5HP", "简单难度正确显示5HP")
	ok(model["timeline"]["enabled"] and not model["signal_interrupted"], "读取宿主时间API不改变游戏状态")
	ok(skin.time_status_text(model["timeline"]).contains("右键")
			and skin.time_status_text(model["timeline"]).contains("2.0"), "满能量提示右键和2秒时长")
	host.player.configure_max_health(3)
	host.timeline["difficulty"] = "hard"
	model = skin.build_view_model()
	ok(model["hp"] == 3 and model["hp_max"] == 3 and model["difficulty_text"] == "困难 · 3HP",
			"困难正确显示3HP，不再套一血旧标签")
	ok(not model["low_health"], "困难满血3/3不出现生命告急假警报")
	host.player.hp = 1
	model = skin.build_view_model()
	ok(model["low_health"], "困难剩1/3时确实显示生命告急")
	host.player.configure_max_health(1)
	host.timeline["difficulty"] = "zero"
	model = skin.build_view_model()
	ok(model["hp"] == 1 and model["hp_max"] == 1 and model["difficulty_text"] == "武士零 · 1HP",
			"一血独立档显示武士零，不再误称困难")
	ok(not model["low_health"], "武士零满血1/1不出现生命告急假警报")
	ok(skin.checkpoint_status_text(model).contains("未激活") \
			and skin.checkpoint_status_text(model).contains("入口"), "未激活记录台时HUD明确失败回入口")
	host.progress["checkpoint_index"] = 5
	host.progress["checkpoint"] = "中段记录台"
	model = skin.build_view_model()
	ok(skin.checkpoint_status_text(model).contains("中段记录台") \
			and not skin.checkpoint_status_text(model).contains("整关"), "HUD显示宿主实际当前检查点而非继续承诺整关入口")
	host.progress["checkpoint_index"] = -1
	host.progress["checkpoint"] = "关卡入口"
	host.player.configure_max_health(5)
	host.player.hp = 1
	host.timeline["difficulty"] = "easy"
	model = skin.build_view_model()
	ok(model["low_health"], "简单模式1/5正确显示生命告急")
	host.timeline["active"] = true
	host.timeline["energy_ratio"] = 0.6
	host.timeline["remaining"] = 1.2
	model = skin.build_view_model()
	ok(skin.time_status_text(model["timeline"]).contains("1.2")
			and skin.time_status_text(model["timeline"]).contains("松开"), "时停显示剩余秒数和释放提示")
	host.timeline["active"] = false
	host.timeline["lockout"] = 1.2
	model = skin.build_view_model()
	ok(skin.time_status_text(model["timeline"]).contains("锁定 1.2")
			and not skin.time_status_text(model["timeline"]).contains("复充 1.2"), "耗尽锁定不冒充完整复充时间")
	host.timeline["lockout"] = 0.0
	model = skin.build_view_model()
	ok(skin.time_status_text(model["timeline"]).contains("约5秒"), "回复能量提示完整复充约5秒")
	host.player.dead = true
	host.timeline["phase"] = "dying"
	model = skin.build_view_model()
	ok(model["signal_interrupted"] and not model["show_death_card"], "死亡信号不显示Backspace静态卡")
	ok(skin.time_status_text(model["timeline"]).contains("信号丢失"), "死亡准备阶段显示信号丢失")
	host.timeline["death_prompt_ready"] = true
	model = skin.build_view_model()
	ok(skin.time_status_text(model["timeline"]).contains("等待"), "任意键确认前显示等待而非自动倒带")
	# 录像姿态可能把player.dead倒回false，HUD仍须依phase继续显示倒带。
	host.player.dead = false
	host.timeline["phase"] = "rewinding"
	host.timeline["rewind_progress"] = 0.55
	model = skin.build_view_model()
	ok(model["signal_interrupted"] and not model["show_death_card"], "历史存活姿态不会提前恢复普通HUD")
	ok(skin.time_status_text(model["timeline"]).contains("倒带"), "倒带显示录像重置现场")
	signal_layer.host = host
	signal_layer._process(0.016)
	ok(signal_layer.view_model()["rewind_progress"] == 0.55, "独立信号可自动读取宿主API")
	host.debug = true
	hud._process(0.016)
	ok(hud._state_label.position.y > SKIN.TIME_PANEL.end.y, "调试文字避开时停能量条")
	ok(hud._info_label.text.contains("倒带") and not hud._info_label.text.contains("Backspace"),
			"调试死亡提示同步移除旧Backspace文案")
	host.timeline["phase"] = "interference"
	host.timeline["glitch_progress"] = 0.65
	model = skin.build_view_model()
	ok(model["signal_interrupted"] and not model["show_death_card"], "花屏阶段不提前恢复游戏卡或死亡卡")
	ok(skin.time_status_text(model["timeline"]).contains("信号干扰")
			and skin.time_status_text(model["timeline"]).contains("重建场景"), "花屏HUD使用兼容入口/检查点恢复的中性提示")
	hud._process(0.016)
	ok(hud._info_label.text.contains("信号干扰"), "调试状态同步花屏阶段")
	signal_layer._process(0.016)
	ok(signal_layer.view_model()["glitch_progress"] == 0.65, "宿主glitch_progress透传到独立信号")
	ok(not SKIN.LIFE_PANEL.intersects(SKIN.TIME_PANEL)
			and not SKIN.TIME_PANEL.intersects(SKIN.PROGRESS_PANEL), "生命/能量/区段面板互不重叠")
	host.timeline = "unsupported"
	ok(not hud.timeline_state()["enabled"], "非字典API安全回退")
	await process_frame

	var legacy := LegacyHost.new()
	var legacy_hud := make_hud(legacy)
	await process_frame
	legacy.player.dead = true
	model = legacy_hud._overlay.build_view_model()
	ok(not model["timeline"]["enabled"] and model["show_death_card"], "无时间API的旧宿主保留原重试卡")
	ok(not model["signal_interrupted"], "旧Boss/地图不会被新倒带HUD接管")
	signal_layer.free()
	host.level.free()
	host.free()
	legacy.level.free()
	legacy.free()
	await process_frame
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
