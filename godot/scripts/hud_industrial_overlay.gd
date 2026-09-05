extends GameHudOverlay
## 工业检疫终端皮肤：常驻信息靠边，房间提示短驻留，游戏中不铺全屏遮罩。
## 继承旧房间卡 API，旧地图与 Boss 测试无需改变生命周期和尺寸接口。

const RUN_SESSION := preload("res://scripts/run_session.gd")

const INK := Color("#0c171e")
const INK_LIGHT := Color("#172932")
const LINE := Color("#3c5962")
const PAPER := Color("#e4eee7")
const MUTED := Color("#98b0b4")
const MINT := Color("#86dac9")
const GOLD := Color("#dfbd7d")
const DANGER := Color("#ef789d")
const SKIN_INTRO_TIME := 2.4
const LIFE_PANEL := Rect2(20, 18, 246, 70)
const TIME_PANEL := Rect2(20, 96, 246, 50)
const PROGRESS_PANEL := Rect2(1010, 18, 330, 89)
const RESULT_PANEL := Rect2(380, 239, 600, 249)


func _draw() -> void:
	if hud == null or hud.host == null or hud.host.player == null:
		return
	var model := build_view_model()
	var font := hud.get_theme_font()
	_draw_vital_panel(font, model)
	_draw_route_panel(font, model)
	if bool(model["timeline"]["enabled"]):
		_draw_time_panel(font, model)
	if bool(model["cleared"]):
		_draw_result(font, model)
	elif bool(model["signal_interrupted"]):
		_draw_signal_notice(font, model)
	elif bool(model["dead"]):
		_draw_result(font, model) # 旧宿主没有倒带 API 时仍保留原重试卡。
	else:
		_draw_room_notice(font, model)
		_draw_entry_notice(font, model)
		_draw_control_strip(font, model)
		# 玩家仍使用方向键决定朝向；这里只留一个小定位点，不暗示枪械瞄准能力。
		var pointer := get_viewport().get_mouse_position().round()
		draw_rect(Rect2(pointer - Vector2(2, 2), Vector2(4, 4)), Color(0.60, 0.79, 0.80, 0.6), false, 1.0)
	if hud.msg_active() and not bool(model["dead"]) and not bool(model["cleared"]) \
			and not bool(model["signal_interrupted"]):
		var message := fit_text(font, hud._msg, 14, 560)
		var width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_panel(Rect2(680 - width * 0.5 - 16, 113, width + 32, 31), GOLD)
		_text(font, Vector2(680 - width * 0.5, 134), message, 14, GOLD)


## 与场景只交换数据，不在 HUD 内写入关卡、存档、敌人或输入状态。
func build_view_model() -> Dictionary:
	var host := hud.host
	var player: KairullPlayer = host.player
	var room_index: int = host.current_room
	var room_name := "外部通道"
	var local_alive := 0
	var local_total := 0
	var rooms_total := 0
	if host.level != null:
		rooms_total = host.level.rooms.size()
		if room_index >= 0 and room_index < rooms_total:
			room_name = str(host.level.rooms[room_index].get("name", "未知区段"))
			local_alive = maxi(0, host.room_alive_count(room_index))
			local_total = maxi(0, host.room_total_count(room_index))
	var defeated := 0
	for enemy: Node2D in host.minions:
		if is_instance_valid(enemy) and enemy.dead:
			defeated += 1
	var run: Dictionary = {}
	if host.has_method("run_progress"):
		run = host.run_progress()
	var elapsed := maxf(0.0, float(run.get("elapsed", Time.get_ticks_msec() / 1000.0 - hud.level_start_t)))
	var total := maxi(0, int(run.get("enemies_total", host.minions.size())))
	var completed := clampi(int(run.get("enemies_defeated", defeated)), 0, total)
	var timeline := hud.timeline_state()
	var hp_max := hud.player_hp_capacity(player)
	# 当前生命上限是HUD的最终显示依据；一血现在属于独立“武士零”，不能误标成三血困难。
	var difficulty_key := "zero" if hp_max == 1 else "hard" if hp_max == 3 else "easy"
	var difficulty_name: String = RUN_SESSION.name_for_difficulty(difficulty_key)
	var model := {
		"hp": clampi(player.hp, 0, hp_max), "hp_max": hp_max,
		"dead": player.dead, "cleared": host.level_cleared,
		"timeline": timeline, "difficulty_text": "%s · %dHP" % [difficulty_name, hp_max],
		"low_health": player.hp <= 1 and player.hp < hp_max,
		"signal_interrupted": bool(timeline["enabled"]) and (player.dead or timeline["phase"] in ["dying", "rewinding", "interference"]),
		"show_death_card": player.dead and not bool(timeline["enabled"]),
		"title": CorridorLevel.active_title if not CorridorLevel.active_title.is_empty() else "零号回廊",
		"room_name": room_name, "room_index": room_index,
		"local_alive": local_alive, "local_total": local_total,
		"rooms_total": maxi(0, int(run.get("rooms_total", rooms_total))),
		"rooms_cleared": maxi(0, int(run.get("rooms_cleared", 0))),
		"enemies_total": total, "enemies_defeated": completed,
		"checkpoint": str(run.get("checkpoint", "关卡入口")),
		"checkpoint_index": int(run.get("checkpoint_index", -1)),
		"elapsed": elapsed, "time_text": format_time(elapsed),
		"is_extended": bool(run.get("is_extended", false)),
	}
	if run.get("rooms_completed") is Array:
		# 清场顺序不一定连续；保留确切房间下标，空数组也代表“尚无完成区段”。
		model["rooms_completed"] = run["rooms_completed"].duplicate()
	return model


func is_room_completed(model: Dictionary, index: int) -> bool:
	if index < 0 or index >= int(model.get("rooms_total", 0)):
		return false
	if model.get("rooms_completed") is Array:
		return model["rooms_completed"].has(index)
	# 旧地图宿主没有精确下标时，才沿用原有计数前缀显示。
	return index < int(model.get("rooms_cleared", 0))


func format_time(seconds: float) -> String:
	var whole := maxi(0, floori(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]


## draw_string 必须先量宽再定位；极长关卡名逐字符省略，不用负宽度伪居中。
func fit_text(font: Font, value: String, font_size: int, max_width: float) -> String:
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return value
	var result := value
	while not result.is_empty():
		result = result.left(result.length() - 1)
		if font.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			return result + "…"
	return ""


func _panel(rect: Rect2, accent: Color, opacity := 1.0) -> void:
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.25 * opacity))
	draw_rect(rect, Color(INK, 0.95 * opacity))
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(LINE, opacity), 1.0)
	draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), Color(accent, opacity))
	draw_rect(Rect2(rect.end - Vector2(7, 7), Vector2(3, 3)), Color(accent, 0.6 * opacity))


func _text(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(font, at.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_vital_panel(font: Font, model: Dictionary) -> void:
	# 武士零满血1/1是完整生命，不允许常驻“生命告急”假警报；困难按3格正常显示。
	var low := bool(model["low_health"])
	var accent := DANGER if low else MINT
	_panel(LIFE_PANEL, accent)
	_text(font, Vector2(34, 39), "凯露尔", 17, PAPER)
	_text(font, Vector2(159, 38), str(model["difficulty_text"]), 10, MUTED)
	var segments := clampi(int(model["hp_max"]), 1, 10)
	var slot_width := 210.0 / segments
	for index in segments:
		var at := Vector2(35 + index * slot_width, 48)
		var segment_width := slot_width - 7.0
		var active := index < int(model["hp"])
		var body := PackedVector2Array([at, at + Vector2(segment_width, 0), at + Vector2(segment_width - 4.0, 13), at + Vector2(0, 13)])
		draw_colored_polygon(body, accent if active else INK_LIGHT)
		if active:
			draw_rect(Rect2(at + Vector2(2, 2), Vector2(maxf(3.0, segment_width - 9.0), 2)), Color(PAPER, 0.45))
	var vital_text := "生命告急" if low else ("武士零协议 · 一击即倒" if int(model["hp_max"]) == 1 else "生命信号稳定")
	_text(font, Vector2(35, 77), vital_text, 10, accent if low else MUTED)


func time_status_text(timeline: Dictionary) -> String:
	if timeline["phase"] == "interference":
		return "信号干扰 · 正在重建场景"
	if timeline["phase"] == "rewinding":
		return "短倒带 · 回放刚才片段"
	if timeline["phase"] == "dying":
		return "信号中断 · 等待重新接入" if bool(timeline["death_prompt_ready"]) else "信号丢失 · 准备回溯"
	if bool(timeline["active"]):
		return "剩余 %.1f 秒 · 松开恢复" % float(timeline["remaining"])
	if float(timeline["lockout"]) > 0.0:
		# 耗尽锁定与完整复充是两件事；不能把1.2秒锁定误报为充满时间。
		return "耗尽锁定 %.1f 秒 · 松开右键" % float(timeline["lockout"])
	if float(timeline["energy_ratio"]) < 0.999:
		return "能量回复中 · 完整复充约5秒"
	return "按住右键 · 最长 %.1f 秒" % float(timeline["max_duration"])


func _draw_time_panel(font: Font, model: Dictionary) -> void:
	var timeline: Dictionary = model["timeline"]
	var accent := MINT if bool(timeline["active"]) or float(timeline["energy_ratio"]) >= 0.999 else GOLD
	_panel(TIME_PANEL, accent)
	_text(font, Vector2(35, 113), "时停 / 右键", 11, accent)
	_text(font, Vector2(205, 113), "%.1fs" % float(timeline["remaining"]), 10, MUTED)
	draw_rect(Rect2(35, 120, 215, 4), INK_LIGHT)
	draw_rect(Rect2(35, 120, floorf(215.0 * float(timeline["energy_ratio"])), 4), accent)
	_text(font, Vector2(35, 139), fit_text(font, time_status_text(timeline), 10, 215), 10, MUTED)


func _draw_signal_notice(font: Font, model: Dictionary) -> void:
	# 死亡等待期间以居中的两句字幕为主，不重复铺左侧提示卡。
	if bool(model["timeline"]["death_prompt_ready"]) or model["timeline"]["phase"] == "interference":
		return
	var rewinding := str(model["timeline"]["phase"]) == "rewinding"
	_panel(Rect2(20, 158, 246, 43), MINT if rewinding else GOLD, 0.88)
	_text(font, Vector2(35, 177), "倒带  /  REWIND" if rewinding else "信号丢失  /  LOST", 12, PAPER)
	_text(font, Vector2(35, 193), "回放刚才片段" if rewinding else "信号暂时中断", 10, MUTED)


func _draw_route_panel(font: Font, model: Dictionary) -> void:
	_panel(PROGRESS_PANEL, GOLD)
	var room_title := "%02d  %s" % [maxi(1, int(model["room_index"]) + 1), str(model["room_name"])]
	_text(font, Vector2(1024, 39), fit_text(font, room_title, 15, 250), 15, PAPER)
	_text(font, Vector2(1288, 38), str(model["time_text"]), 11, MUTED)
	var local := "区域安全" if int(model["local_total"]) == 0 else ("本区肃清" if int(model["local_alive"]) == 0 \
			else "本区威胁  %02d / %02d" % [int(model["local_alive"]), int(model["local_total"])])
	_text(font, Vector2(1024, 60), local, 12, MINT if int(model["local_alive"]) == 0 else GOLD)
	var defeated := int(model["enemies_defeated"])
	var total := int(model["enemies_total"])
	_text(font, Vector2(1215, 60), "击破 %02d/%02d" % [defeated, total], 11, MUTED)
	var sections := clampi(int(model["rooms_total"]), 1, 16)
	var current := clampi(int(model["room_index"]), 0, sections - 1)
	var cell_width := 302.0 / sections
	for index in sections:
		var color := MINT if is_room_completed(model, index) else LINE
		if index == current:
			color = GOLD
		draw_rect(Rect2(1024 + index * cell_width, 72, maxf(3, cell_width - 3), 4), color)
	var rewind_label := checkpoint_status_text(model)
	_text(font, Vector2(1024, 95), fit_text(font, rewind_label, 10, 298), 10, MUTED)


## 一处中途记录台必须真正激活后才承诺局部恢复；展示宿主给出的当前地点，不自行保存快照。
func checkpoint_status_text(model: Dictionary) -> String:
	if not bool(model["timeline"]["enabled"]):
		return "同步点 · " + str(model["checkpoint"])
	if int(model["checkpoint_index"]) < 0:
		return "检查点未激活 · 失败回入口"
	return "当前检查点 · " + str(model["checkpoint"])


func _draw_entry_notice(font: Font, model: Dictionary) -> void:
	if hud.host.debug:
		return
	var elapsed := Time.get_ticks_msec() / 1000.0 - hud.level_start_t
	if elapsed < 0.0 or elapsed >= SKIN_INTRO_TIME:
		return
	var alpha := clampf((SKIN_INTRO_TIME - elapsed) / 0.45, 0.0, 1.0)
	var offset := 49.0 if bool(model["timeline"]["enabled"]) else 0.0
	_panel(Rect2(20, 109 + offset, 398, 79), GOLD, alpha)
	_text(font, Vector2(36, 133 + offset), "任务接入  /  ZERO CORRIDOR", 10, Color(GOLD, alpha))
	_text(font, Vector2(35, 160 + offset), fit_text(font, str(model["title"]), 22, 366), 22, Color(PAPER, alpha))
	_text(font, Vector2(36, 177 + offset), "穿过检疫线路 · 抵达出口", 10, Color(MUTED, alpha))


func _draw_room_notice(font: Font, model: Dictionary) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0 - hud.level_start_t
	if elapsed < SKIN_INTRO_TIME or hud.host.debug:
		return   ## 与入场卡共用左上信息槽，不能叠卡或遮住地面的敌人。
	var remain := _room_card_until - Time.get_ticks_msec() / 1000.0
	if remain <= 0.0:
		return
	var alpha := clampf(remain / 0.35, 0.0, 1.0)
	var offset := 49.0 if bool(model["timeline"]["enabled"]) else 0.0
	_panel(Rect2(20, 109 + offset, 318, 59), MINT, alpha)
	_text(font, Vector2(35, 133 + offset), fit_text(font, _room_card_name, 17, 280), 17, Color(PAPER, alpha))
	_text(font, Vector2(36, 154 + offset), fit_text(font, _room_card_sub, 11, 280), 11, Color(MUTED, alpha))


func _draw_control_strip(font: Font, model: Dictionary) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0 - hud.level_start_t
	var alpha := clampf(1.0 - (elapsed - 11.0), 0.0, 1.0)
	if alpha <= 0.0:
		return
	var controls := "Esc 暂停/继续    A/D 移动    W 跳跃    左键 挥棒/击飞箱    Ctrl 翻滚    Shift 冲刺1.5s    双S 下穿"
	if bool(model["timeline"]["enabled"]):
		controls += "    右键 时停 · 2s / 复充5s"
	var panel_width := 1190.0 if bool(model["timeline"]["enabled"]) else 931.0
	_panel(Rect2(20, 714, panel_width, 31), LINE, alpha * 0.92)
	_text(font, Vector2(34, 735), fit_text(font, controls, 12, panel_width - 28.0), 12,
			Color(MUTED, alpha))


func _draw_result(font: Font, model: Dictionary) -> void:
	var cleared := bool(model["cleared"])
	var accent := MINT if cleared else DANGER
	_panel(RESULT_PANEL, accent)
	_text(font, Vector2(405, 269), "PROTOCOL / 01" if cleared else "SIGNAL / LOST", 11, accent)
	_text(font, Vector2(404, 313), "回廊已肃清" if cleared else "线路中断", 34, PAPER)
	_text(font, Vector2(406, 340), fit_text(font, str(model["title"]) if cleared else \
			"可从「%s」继续突破" % str(model["checkpoint"]), 15, 548), 15, MUTED)
	draw_line(Vector2(406, 357), Vector2(954, 357), LINE, 1.0)
	var stats := ["行动时间", "敌人击破", "区段肃清"]
	var values := [str(model["time_text"]), "%d / %d" % [int(model["enemies_defeated"]), int(model["enemies_total"])],
		"%d / %d" % [int(model["rooms_cleared"]), int(model["rooms_total"])]]
	for index in 3:
		_text(font, Vector2(407 + index * 185, 379), stats[index], 11, MUTED)
		_text(font, Vector2(406 + index * 185, 408), values[index], 22, PAPER)
	var instruction := "Backspace  复位玩家"
	if bool(model["is_extended"]):
		instruction = "Enter  重新挑战     Backspace  返回同步点" if cleared \
				else "Backspace  同步点重试     Enter  从头开始"
	if bool(model["timeline"]["enabled"]):
		instruction = "Enter  重新挑战     Esc  暂停菜单"
	_text(font, Vector2(407, 458), fit_text(font, instruction, 14, 548), 14, accent)


func uses_gun_reticle() -> bool:
	return false
