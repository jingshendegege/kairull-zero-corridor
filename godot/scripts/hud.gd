extends CanvasLayer
class_name GameHud
## 工业检疫终端 HUD：生命、行程和局部结算；开发文字默认关闭，由开发开关显式启用。
## 中文字体走 SystemFont（微软雅黑），Godot 默认字体不含 CJK。

var host: Node2D   ## game
const INDUSTRIAL_OVERLAY := preload("res://scripts/hud_industrial_overlay.gd")
const TIME_SIGNAL := preload("res://scripts/time_signal_overlay.gd")

var _state_label: Label
var _info_label: Label
var _aim_label: Label
var _dbg_label: Label
var _help_label: Label
var _overlay: GameHudOverlay
var _boss_bar_bg: ColorRect
var _boss_bar_fill: ColorRect
var _fade_rect: ColorRect     ## 过关转场淡黑（全屏黑，alpha 由 game.set_fade 驱动）
var _msg := ""
var _msg_until := 0.0
## 关卡开始时刻（秒）：开场标题卡与底部操作说明的淡入淡出都以此为零点
var level_start_t := 0.0


func _ready() -> void:
	level_start_t = Time.get_ticks_msec() / 1000.0
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]

	_state_label = _make_label(font, 15, Color("#86dac9"), Vector2(22, 105))
	_info_label = _make_label(font, 12, Color("#98b0b4"), Vector2(22, 127))
	_aim_label = _make_label(font, 12, Color("#dfbd7d"), Vector2(22, 145))
	_dbg_label = _make_label(font, 12, Color("#98b0b4"), Vector2(22, 163))

	# 底部操作说明：压暗，开场 12s 后淡出（默认视图极简）
	_help_label = _make_label(font, 11, Color("#4d6284"), Vector2(0, 742))
	_help_label.text = "Esc 暂停/继续 · A/D 移动 · Shift 冲刺(1.5秒CD) · Ctrl 翻滚 · W 跳 · 双S 下穿平台 · 左键 挥棒/击飞货箱 · Backspace 重试"
	_help_label.size = Vector2(1360, 20)
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.visible = false ## 文本契约保留；统一由新皮肤绘制控制条，避免两套 UI 重叠。

	# Boss 血条：顶部居中加粗横条（霓虹粉底 + 暗底框，560×16）
	_boss_bar_bg = ColorRect.new()
	_boss_bar_bg.color = Color(0.08, 0.05, 0.14, 0.85)
	_boss_bar_bg.position = Vector2(400, 22)
	_boss_bar_bg.size = Vector2(560, 16)
	add_child(_boss_bar_bg)
	_boss_bar_fill = ColorRect.new()
	_boss_bar_fill.color = Color("#ff4fa3")
	_boss_bar_fill.position = Vector2(403, 25)
	_boss_bar_fill.size = Vector2(554, 10)
	add_child(_boss_bar_fill)

	_overlay = INDUSTRIAL_OVERLAY.new()
	_overlay.hud = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# 过关转场淡黑：最后添加 = 盖在 CLEAR 卡与所有 HUD 元素之上
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.position = Vector2.ZERO
	_fade_rect.size = Vector2(1360, 765)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)


## 过关转场淡黑进度（0..1），game._update_clear_transition 每帧驱动
func set_fade(k: float) -> void:
	_fade_rect.modulate.a = clampf(k, 0.0, 1.0)


func get_theme_font() -> Font:
	return _state_label.get_theme_font("font")


func msg_active() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _msg_until


## 时间状态只读转译：旧宿主没有此 API 时，禁止凭按键名误恢复旧枪械瞄准。
func timeline_state() -> Dictionary:
	if is_instance_valid(host) and host.has_method("timeline_view_model"):
		var raw: Variant = host.call("timeline_view_model")
		if raw is Dictionary:
			return TIME_SIGNAL.normalize_view_model(raw)
	return TIME_SIGNAL.normalize_view_model({})


## 生命上限由角色单一来源提供；旧空宿主仍可回退，不在每帧扫描整张属性表。
func player_hp_capacity(player: Node) -> int:
	if player is KairullPlayer:
		return maxi(1, (player as KairullPlayer).max_hp)
	return KairullPlayer.HP_MAX


func _make_label(font: Font, size: int, color: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_size", 2)
	l.position = pos
	add_child(l)
	return l


func show_msg(t: String) -> void:
	_msg = t
	_msg_until = Time.get_ticks_msec() / 1000.0 + 1.0


func _process(_dt: float) -> void:
	if host == null or host.player == null:
		return
	var p: KairullPlayer = host.player
	var timeline := timeline_state()
	var has_timeline := bool(timeline["enabled"])
	# 时停槽与调试行不能重叠；普通游戏仍只显示皮肤中的简洁状态。
	var debug_offset := 57.0 if has_timeline else 0.0
	_state_label.position.y = 105.0 + debug_offset
	_info_label.position.y = 127.0 + debug_offset
	_aim_label.position.y = 145.0 + debug_offset
	_dbg_label.position.y = 163.0 + debug_offset
	# 开发状态块仅在开发开关显式启用后显示；默认视图保持正常游戏信息。
	var dev_on: bool = host.debug
	_state_label.visible = dev_on
	_info_label.visible = dev_on
	_aim_label.visible = dev_on
	_dbg_label.visible = dev_on
	# 底部操作说明：开场 12s 后 1s 内淡出
	var help_elapsed: float = Time.get_ticks_msec() / 1000.0 - level_start_t
	_help_label.modulate.a = clampf(1.0 - (help_elapsed - 12.0), 0.0, 1.0)
	_state_label.text = p.state.to_upper()
	if has_timeline and str(timeline["phase"]) == "interference":
		_info_label.text = "信号干扰 · 正在重建场景" # 是否从检查点续行由run_progress状态决定。
	elif has_timeline and str(timeline["phase"]) == "rewinding":
		_info_label.text = "短倒带 · 回放刚才片段"
	elif has_timeline and bool(timeline["death_prompt_ready"]):
		_info_label.text = "信号中断 · 按任意按钮重开"
	elif has_timeline and (p.dead or str(timeline["phase"]) == "dying"):
		_info_label.text = "信号丢失 · 正在准备回溯"
	elif p.dead:
		_info_label.text = "倒地 · Backspace 重来"
	elif p.rolling():
		_info_label.text = "翻滚闪避"
	elif p.sliding():
		_info_label.text = "滑铲中（可接跳）"
	elif p.state == "run":
		_info_label.text = "奔跑"
	elif p.state == "gun_reload":
		_info_label.text = "换弹中…"
	elif p.state == "aim":
		_info_label.text = "精细瞄准（松开右键移动）"
	elif p.state == "gun_jump_air":
		_info_label.text = "空中"
	elif not p.on_ground:
		_info_label.text = "空中"
	else:
		_info_label.text = "待机"
	if p.aiming:
		_aim_label.text = "仰角 %s%.1f°  朝向 %s" % [
			"+" if p.aim_deg >= 0 else "", p.aim_deg, "右" if p.face > 0 else "左"]
	elif KairullPlayer.GUN_ENABLED:
		_aim_label.text = "水平开火  朝向 %s" % ("右" if p.face > 0 else "左")
	else:
		_aim_label.text = "近战棍击  朝向 %s" % ("右" if p.face > 0 else "左")
	# Boss 血条：无 Boss 或已击破时隐藏
	var boss: Node2D = host.red_boss
	if boss != null and is_instance_valid(boss) and not boss.dead:
		_boss_bar_bg.visible = true
		_boss_bar_fill.visible = true
		var ratio: float = clampf(float(boss.hp) / float(boss.HP_MAX), 0.0, 1.0)
		_boss_bar_fill.size.x = 554.0 * ratio
	else:
		_boss_bar_bg.visible = false
		_boss_bar_fill.visible = false
	var act: Dictionary = host.db.actions[p.current_clip()]
	var ammo_text := ""
	if KairullPlayer.GUN_ENABLED:
		ammo_text = "  弹药 %d/%d%s" % [p.gun_ammo, KairullPlayer.GUN_MAG,
				" · 换弹 %.1fs" % p.reload_t if p.reloading else ""]
	# HP 心形已由 overlay 以霓虹 pip 绘制；调试行只保留帧/弹药/调试开关
	_dbg_label.text = "HP %d/%d%s | 帧 %d/%d %s" % [
		p.hp, player_hp_capacity(p),
		ammo_text,
		p.frame, int(act["frames"]) - 1,
		"开发状态开启" if host.debug else "开发状态关闭"]
