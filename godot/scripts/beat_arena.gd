extends Node2D
class_name BeatArena
## A separate encounter, deliberately absent from enemy/cargo/timeline snapshots.
const CONDUCTOR := preload("res://scripts/beat_conductor.gd")
const WARDEN := preload("res://scripts/beat_warden.gd")
const NOTE := preload("res://scripts/beat_note.gd")
const COLORS := {"normal": Color("5fe6f0"), "heavy": Color("f0b44a"), "bomb": Color("ff2ad8")}
## 2026-09-28 用户试玩反馈：自由移动+挥棒不好用 → 改为喵斯快跑式双轨。
## 倒数开始后主角锁定在判定线前原地奔跑（场景由 m07_beat_stage_fx 向左滚动）：
## W/↑ 上到隔板上层并挥棒，S/↓ 回地面下层并挥棒；按一次就停在该层，直到按另一个键切换。
## 按键时在该轨 ±RHYTHM_WINDOW 内找最近音符判定（不再看球棒几何）。炸弹靠"不在它那条轨"躲。
const RHYTHM_WINDOW := 0.20      ## 出手判定窗（秒）；漏判 = 过线超过此值
const LANE_FOOT := 36.0          ## 音符中心离主角脚底的高度（两层相同）；上层脚底 = 隔板顶面
## 2026-09-28 新机制「冲刺反击」（用户设计）：谱面 rushes 拍点前 4 拍 Boss 头顶出现「!」原地蓄力 2 拍，
## 再用 2 拍冲到主角攻击距离 → 子弹时间（音乐与谱面减速到 0.3 倍，音调随之下沉；用户反馈直接暂停太突兀）
## → 1.5 秒（真实时间）内任意攻击键连打 Boss → 击退回原位，击退期间速度拉回 1.0，继续打谱。
const RUSH_WARN_BEATS := 2.0
const RUSH_DASH_BEATS := 2.0
const COUNTER_TIME := 3.0            ## 贴身反击时长上限（真实秒）；约 9 下/秒可摸到 15% 上限，更快的手必打满
const FINISHER_DAMAGE := 16          ## 时间到未打满时自动补的击退终结伤害（不超过剩余上限）
const COUNTER_CAP_RATIO := 0.15      ## 单次反击伤害上限 = Boss 最大血量 15%（用户定）；打满即终结重击
## 分档「卡肉」：[从第几下起, 每下伤害, 顿帧秒]。顿帧即手速上限——越往后越沉、越慢、越痛，
## 且每档打满手速时的秒伤都高于上一档（2/0.05=40 → 5/0.09≈56 → 8/0.14≈57），不是惩罚而是越打越重。
const COUNTER_TIERS := [[1, 2, 0.03], [7, 5, 0.07], [13, 8, 0.12]]
const COUNTER_RECOVER := 0.02        ## 每击顿帧后的收招
const PERFECT_COUNTER_BONUS := 2000
const KNOCKBACK_TIME := 0.5
const SLOWMO_RATE := 0.3
const SLOWMO_EASE_IN := 0.15   ## 降速过渡时长（秒）
const RUSH_REACH := 150.0      ## Boss 冲到主角前方多远停下（脚底距离）
const DUAL_GAP := 0.12          ## 双键音符：上下两次按键允许的最大间隔（秒）
const HEAVY_FLY_TIME := 0.6     ## 双键音符被击飞到 Boss 的弧线时长
## 统一击打音效：用户选定原版第一个球棒命中声（06_bat_hit_normal，原增益 +3.5dB），所有音符同一采样、不随机
const HIT_SFX := preload("res://assets/sfx/06_bat_hit_normal.wav")
const PLAYER_OFFSET := -34.0     ## 主角站在判定环左侧，挥棒扫过判定环
var host: Node2D
var config: Dictionary
var conductor: BeatConductor
var boss: BeatWarden
var notes: Array[BeatNote] = []
var state := "waiting"
var count_time := 0.0
var frozen := false
var combo := 0
var score := 0
var rating := ""
var rating_time := 0.0
var swing := 0
var rings: Array[Sprite2D] = []
var lights: Array[Sprite2D] = []
var bursts: Array[Dictionary] = []
var hud_layer: CanvasLayer
var hp_label: Label
var hp_bar: ProgressBar
var judge_label: Label
var _death_time := 0.0
var _pulse_beat := 0.0
signal rated(value: String, lane: String)   ## 每次评价（含 Miss），供 BeatHud 弹字
var counts := {"Perfect": 0, "Great": 0, "Hit": 0, "Miss": 0}
var max_combo := 0
var _hit_voices: Array[AudioStreamPlayer] = []
var _hit_voice_i := 0
var rush_state := ""            ## "" / warn / dash / counter / knockback
var rush_timer := 0.0
var counter_hits := 0
var counter_damage := 0
var counter_cap := 1
var counter_tier := 0
var perfect_counter := false
var _counter_lock := 0.0            ## 顿帧 + 收招剩余；期间按键进缓冲
var _counter_buffer := 0
var _hitstop := 0.0
var _counter_pos := Vector2.ZERO
signal damage_popped(amount: int, world: Vector2, tier: int)   ## tier 0/1/2 = 档位，3 = 终结重击
var _rush_beat := 0.0
var _rush_done := {}
var _boss_home := Vector2.ZERO
var _knock_from := Vector2.ZERO
var _prev_click := false
var rush_mark: Node2D
var rhythm_lock := false         ## true = 双轨操作接管主角（倒数起到击破/重置）
var player_lane := "ground"
var _prev_up := false
var _prev_down := false

func setup(game: Node2D, arena_config: Dictionary) -> void:
	host = game
	config = arena_config.duplicate(true)
	boss = WARDEN.new()
	boss.position = Vector2(config.boss_feet[0], config.boss_feet[1])
	add_child(boss)
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.chart))
	boss.setup(config.boss_atlas, int(chart.boss_hp))
	boss.boss_died.connect(_on_boss_died)
	_boss_home = boss.position
	rush_mark = Node2D.new()
	rush_mark.name = "RushMark"
	rush_mark.visible = false
	rush_mark.draw.connect(_draw_rush_mark)
	add_child(rush_mark)
	conductor = CONDUCTOR.new()
	add_child(conductor)
	conductor.setup(config, {"ground": boss.anchor("horn_ground_world").x,
			"air": boss.anchor("horn_air_world").x})
	host.player.bat_swing_started.connect(_on_swing_started)
	host.player.bat_swung.connect(_on_bat_swung)
	_build_visuals()
	reset_fight()

func _build_visuals() -> void:
	for lane in ["ground", "air"]:
		var ring := Sprite2D.new()
		ring.texture = load(NOTE.ART + "judge_ring.png")
		ring.position = Vector2(config.judge_x, config["lane_" + lane + "_y"])
		ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(ring)
		rings.append(ring)
	var rect: Array = config.stage_rect
	for y in [float(rect[1]) + 24.0, float(config.floor_y) + 4.0]:
		for x in range(int(rect[0]) + 32, int(rect[0]) + int(rect[2]), 64):
			var bar := Sprite2D.new()
			bar.texture = load(NOTE.ART + "stage_lightbar.png")
			bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			bar.position = Vector2(x, y)
			add_child(bar)
			lights.append(bar)
	judge_label = Label.new()
	judge_label.position = Vector2(float(config.judge_x) - 145, float(config.lane_air_y) - 160) # 双轨模式主角会升到空中轨，文字让开头顶
	judge_label.size = Vector2(290, 80)
	judge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	judge_label.add_theme_font_override("font", host.hud.get_theme_font())
	judge_label.add_theme_font_size_override("font_size", 22)
	judge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(judge_label)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 6
	add_child(hud_layer)
	hp_label = Label.new()
	hp_label.position = Vector2(420, 16)
	hp_label.size = Vector2(520, 30)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_override("font", host.hud.get_theme_font())
	hp_label.add_theme_font_size_override("font_size", 21)
	hp_label.text = "节拍监察官 BEAT WARDEN"
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(420, 49)
	hp_bar.size = Vector2(520, 14)
	hp_bar.show_percentage = false
	hp_bar.max_value = boss.max_hp
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 2026-09-28 Claude：血条改为品红填充 + 深紫底框（默认主题是灰色，看不出血量）。
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ff3f94")
	fill.border_color = Color("ffd0e6")
	fill.border_width_top = 2
	var back := StyleBoxFlat.new()
	back.bg_color = Color("1b1832")
	back.border_color = Color("0b0916")
	back.set_border_width_all(2)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_bar.add_theme_stylebox_override("background", back)
	hud_layer.add_child(hp_bar)

func reset_fight(resume_ambience := false) -> void:
	_clear_notes()
	for burst: Dictionary in bursts:
		burst.sprite.queue_free()
	bursts.clear()
	conductor.reset()
	boss.reset()
	state = "waiting"
	frozen = false
	count_time = 0.0
	_death_time = 0.0
	combo = 0
	score = 0
	rating = ""
	rating_time = 0.0
	swing = 0
	for key in counts:
		counts[key] = 0
	_end_rush(true)
	_rush_done.clear()
	max_combo = 0
	_release_rhythm()
	CorridorLevel.active_exit_requires_boss = true
	hud_layer.visible = false
	judge_label.text = "W/↑ 上层 · S/↓ 下层（按一次就停留）\n粉色炸弹：换到另一层躲开"
	_pulse_beat = 0.0
	_update_visuals()
	if resume_ambience and is_instance_valid(host.music) and not host.music.playing:
		host.music.stream_paused = false
		host.music.pitch_scale = 1.0
		host.music.play()

func blocks_exit() -> bool:
	return state != "defeated"

func set_frozen(value: bool) -> void:
	frozen = value
	conductor.set_frozen(value)

## 舞台/HUD 用：玩家时停或冲刺反击时停都算「时间停止」。
func time_stopped() -> bool:
	return frozen


## 当前播放速率（子弹时间 < 1），供舞台/HUD 同步减速。
func time_rate() -> float:
	return conductor.rate

func step(dt: float) -> void:
	if rhythm_lock:
		# 主角的自动输入已关闭；时停键仍需透传给宿主的时停检测。
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			host.player.keys[MOUSE_BUTTON_RIGHT] = true
		else:
			host.player.keys.erase(MOUSE_BUTTON_RIGHT)
	if frozen or host.player.dead or host.time_phase != "playing" or host.level_cleared:
		return
	var visual_dt := dt
	if state == "waiting":
		var rect: Array = config.stage_rect
		if host.player.position.x >= float(rect[0]) + 64.0 \
				and host.level.room_at(host.player.position.x, host.player.position.y - 1.0) \
				== host.level.rooms.size() - 1:
			state = "count_in"
			count_time = 0.0
			hud_layer.visible = true
			judge_label.text = "3"
			_engage_rhythm()
	elif state == "count_in":
		count_time += maxf(dt, 0.0)
		_rhythm_tick(dt)
		_pulse_beat = count_time / conductor.seconds(1.0)
		judge_label.text = ["3", "2", "1", "GO"][mini(3, floori(_pulse_beat))]
		if count_time >= conductor.seconds(float(conductor.chart.beats_per_bar)):
			state = "playing"
			if is_instance_valid(host.music):
				host.music.stop()
			conductor.start()
			judge_label.text = "GO\nCOMBO 0"
	elif state == "playing":
		var before := conductor.time
		for event: Dictionary in conductor.advance():
			spawn_note(event)
		var elapsed := conductor.time - before
		visual_dt = elapsed
		_pulse_beat = conductor.song_beat()
		_update_rush(dt)
		if state != "playing":
			return
		_rhythm_tick(dt)
		if conductor.finale_started():
			boss.expose()
		boss.step(elapsed, _pulse_beat)
		_advance_notes(elapsed)
		if host.player.dead:
			return
		rating_time = maxf(0.0, rating_time - elapsed)
		judge_label.text = "%s\nCOMBO %d · %d" % [rating if rating_time > 0 else "", combo, score]
	elif state == "dying":
		_death_time += dt
		boss.step(dt, _pulse_beat)
		conductor.music.volume_db = lerpf(-14.0, -60.0, minf(1.0, _death_time / 0.5))
		if _death_time >= 0.5:
			conductor.music.stop()
			state = "defeated"
			_release_rhythm()
			CorridorLevel.active_exit_requires_boss = false
			hud_layer.visible = false
			host.hud.show_msg("BOSS 击破！前往出口 >")
	_advance_bursts(visual_dt)
	_update_visuals()

func spawn_note(event: Dictionary) -> BeatNote:
	var note := NOTE.new()
	note.setup(event, config, float(conductor.chart.note_speed_px), conductor.time)
	add_child(note)
	notes.append(note)
	boss.fire(note.lane)
	return note

func _on_swing_started(_stage: int) -> void:
	swing += 1

func _on_bat_swung(hitbox: Rect2, _stage: int) -> void:
	if state == "playing" and not frozen and not host.player.dead:
		bat_contacts(hitbox)

func bat_contacts(hitbox: Rect2) -> void:
	for note: BeatNote in notes.duplicate():
		if note.spent or note.reflected or not note.body_rect().intersects(hitbox):
			continue
		_contact_note(note)
		if host.player.dead:
			return # Death signal clears the encounter synchronously.

func _contact_note(note: BeatNote) -> void:
	if not note.bat_contact(swing, conductor.time):
		return
	_burst(note.position, note.kind)
	if note.kind == "bomb":
		host.player.take_damage(1, note.position.x)
	else:
		if note.reflected:
			note.reflection_target = boss.target_point()
		show_rating(rate(conductor.time - note.hit_time), note.lane)
		_play_hit(note.kind == "heavy")

func _advance_notes(dt: float) -> void:
	# The existing active strike starts at BAT_HIT_AT and recovery/cancel opens at BAT_CANCEL_OPEN.
	var active_bat: bool = host.player.batting() and host.player._bat_progress() >= host.player.BAT_HIT_AT \
			and host.player._bat_progress() < host.player.BAT_CANCEL_OPEN
	for note: BeatNote in notes.duplicate():
		if note.spent:
			continue
		if note.reflected:
			var target := note.reflection_target
			if note.fly_t >= 0.0:   # 双键音符：高抛弧线 + 旋转 + 放大，被击飞砸向 Boss
				note.fly_t = minf(HEAVY_FLY_TIME, note.fly_t + dt)
				var k := note.fly_t / HEAVY_FLY_TIME
				note.position = note.fly_from.lerp(target, k) + Vector2(0, -260.0 * sin(PI * k))
				note.rotation += 18.0 * dt
				note.scale = Vector2.ONE * (1.0 + 0.5 * sin(PI * k))
				if k >= 1.0:
					note.position = target
					if host.has_method("add_camera_shake"):
						host.add_camera_shake(Vector2.RIGHT, 0.35)
			else:
				note.position = note.position.move_toward(target, 900.0 * dt)
			if note.position.distance_to(target) < 0.001:
				note.spent = true
				_burst(target, note.kind)
				var damage := int(conductor.chart.note_damage[note.kind])
				if conductor.finale_started():
					damage *= int(conductor.chart.finale_core_multiplier)
				boss.take_reflected_hit(damage)
				if boss.dead:
					return
			continue
		var old := note.position
		var was_cracked := note.cracked
		note.advance_incoming(conductor.time)
		# Sweep the note footprint so low frame rates cannot tunnel through a player/bat.
		var travel := note.position - old
		var destination := note.position
		var steps := maxi(1, ceili(travel.length() / 8.0))
		for index in range(1, steps + 1):
			note.position = old + travel * (float(index) / steps)
			if rhythm_lock:
				break
			if active_bat and note.body_rect().intersects(host.player._bat_hitbox()):
				_contact_note(note)
				if host.player.dead:
					return
			if note.spent or note.reflected:
				break
			if note.body_rect().intersects(host.player.hurtbox_rect()):
				note.spent = true
				_burst(note.position, note.kind)
				host.player.take_damage(1, note.position.x)
				if host.player.dead:
					return
				break
			if note.cracked and not was_cracked:
				# A first heavy contact anchors its new half-speed path right here.
				destination = note.position
				break
		if not note.spent and not note.reflected:
			note.position = destination
		if rhythm_lock and note.kind == "bomb" and not note.contacted and not note.spent \
				and conductor.time >= note.hit_time:
			note.contacted = true
			if player_lane == note.lane:
				note.spent = true
				_burst(note.position, note.kind)
				host.player.take_damage(1, note.position.x)
				if host.player.dead:
					return
		if not note.contacted and not note.missed and note.kind != "bomb" \
				and conductor.time - note.hit_time > (RHYTHM_WINDOW if rhythm_lock else 0.150):
			note.missed = true
			show_rating("Miss", note.lane)
		if note.position.x < float(config.stage_rect[0]):
			note.spent = true
	for index in range(notes.size() - 1, -1, -1):
		if notes[index].spent:
			notes[index].queue_free()
			notes.remove_at(index)

static func rate(error: float) -> String:
	if absf(error) <= 0.080001:
		return "Perfect"
	if absf(error) <= 0.140001:
		return "Great"
	return "Hit"

func show_rating(value: String, lane := "") -> void:
	rating = value
	rating_time = 0.6
	if value == "Miss":
		combo = 0
	else:
		combo += 1
		score += {"Perfect": 100, "Great": 70, "Hit": 40}[value]
	counts[value] = int(counts.get(value, 0)) + 1
	max_combo = maxi(max_combo, combo)
	rated.emit(value, lane)

func _on_boss_died() -> void:
	_end_rush(false)
	_clear_notes()
	state = "dying"
	_death_time = 0.0
	conductor.running = false
	host.fx_layer.spawn_explosion(boss.target_point(), 2.0)
	host.play_action("enemy_kill")
	host.add_camera_shake(Vector2.LEFT, 1.0)

func _clear_notes() -> void:
	for note: BeatNote in notes:
		note.queue_free()
	notes.clear()

func _burst(at: Vector2, kind: String, size := 1.0) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(NOTE.ART + "note_burst.png")
	sprite.hframes = 4
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = at
	sprite.modulate = COLORS[kind]
	sprite.scale = Vector2.ONE * size
	add_child(sprite)
	bursts.append({"sprite": sprite, "time": 0.0})

func _advance_bursts(dt: float) -> void:
	for index in range(bursts.size() - 1, -1, -1):
		bursts[index].time += maxf(0.0, dt)
		if bursts[index].time >= 0.24:
			bursts[index].sprite.queue_free()
			bursts.remove_at(index)
		else:
			bursts[index].sprite.frame = mini(3, floori(bursts[index].time / 0.06))

func _update_visuals() -> void:
	var pulse := 1.0 - fposmod(_pulse_beat, 1.0)
	var color := Color("ffb040") if posmod(floori(_pulse_beat), 2) == 0 else Color("ff3a1a")   # 摇滚版：橙/红交替
	for ring: Sprite2D in rings:
		ring.scale = Vector2.ONE * (0.85 + 0.2 * pulse)
		ring.modulate = Color(color, 0.5 + 0.5 * pulse)
	for bar: Sprite2D in lights:
		bar.modulate = Color(color, 0.25 + 0.75 * pulse)
	hp_bar.value = boss.hp


# ------------------------------------------------------------------ 喵斯快跑式双轨操作
func _engage_rhythm() -> void:
	var p: Node2D = host.player
	rhythm_lock = true
	player_lane = "ground"
	_prev_up = true   # 进场时仍按着的键不算一次出手
	_prev_down = true
	p.auto_input = false
	p.keys.clear()
	p.vx = 0.0
	p.vy = 0.0
	p.face = 1
	p.set_state("gun_idle")
	_place_player()
	host.hud.visible = false       # 通用 HUD 与节奏战 HUD（beat_hud.gd）互斥
	hud_layer.visible = false
	judge_label.visible = false


func _release_rhythm() -> void:
	if not rhythm_lock:
		return
	rhythm_lock = false
	player_lane = "ground"
	var p: Node2D = host.player
	p.keys.clear()
	p.auto_input = true
	host.hud.visible = true
	judge_label.visible = state == "waiting"   # 击破后不再显示旧的判定文字（结算由 BeatHud 负责）
	if not p.dead:
		_place_player()
		p.set_state("gun_idle")


func _place_player() -> void:
	var p: Node2D = host.player
	var lift := air_lift() if player_lane == "air" else 0.0
	p.position = Vector2(float(config.judge_x) + PLAYER_OFFSET, float(config.floor_y) - lift - 0.1)
	p.vx = 0.0
	p.vy = 0.0


## 上层站位高度：隔板顶面 = 上层音符中心下方 LANE_FOOT。
func air_lift() -> float:
	return float(config.floor_y) - (float(config.lane_air_y) + LANE_FOOT)


## 每个物理帧：读上/下键边沿、推进主角动画与受伤无敌计时（主角 step 已停）。
func _rhythm_tick(dt: float) -> void:
	if not rhythm_lock:
		return
	var up := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var down := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var click := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if rush_state == "counter":
		if (up and not _prev_up) or (down and not _prev_down) or (click and not _prev_click):
			counter_hit()
	else:
		if up and not _prev_up:
			rhythm_press("air")
		if down and not _prev_down:
			rhythm_press("ground")
	_prev_click = click
	_prev_up = up
	_prev_down = down
	var p: Node2D = host.player
	p.invuln_t = maxf(0.0, p.invuln_t - dt)
	_place_player()
	if not p.batting():
		p.set_state("gun_idle" if rush_state == "counter" else "run")   # 两层都原地奔跑；反击时站定
	if _hitstop <= 0.0:
		p._advance_frame(dt)
	p._sync_sprite()


## 一次出手：瞬移到该层（并停留）挥棒；在该轨判定窗内取时间误差最小的音符反弹（炸弹不可打）。
func rhythm_press(lane: String) -> BeatNote:
	var rising := lane == "air" and player_lane == "ground"
	player_lane = lane
	var p: Node2D = host.player
	p.state = ""
	p.set_state("bat3" if rising else "bat2")   # 用户要求：从下层切到上层用连击第三段
	_place_player()
	swing += 1
	if state != "playing" or frozen:
		return null
	var dual := _press_dual(lane)
	if dual != null:
		return dual
	var best: BeatNote = null
	var best_error := INF
	for note: BeatNote in notes:
		if note.spent or note.reflected or note.contacted or note.kind in ["bomb", "heavy"] or note.lane != lane:
			continue
		var error := conductor.time - note.hit_time
		if absf(error) <= RHYTHM_WINDOW and absf(error) < absf(best_error):
			best = note
			best_error = error
	if best == null:
		return null
	best.contacted = true
	best.reflected = true
	best.last_swing = swing
	best.reflection_target = boss.target_point()
	_burst(best.position, best.kind)
	show_rating(rate(best_error), lane)
	_play_hit(false)
	return best


## 双键音符：记录这一层的按键；上下两层都在判定窗内、且两次按键间隔 ≤ DUAL_GAP → 击飞。
func _press_dual(lane: String) -> BeatNote:
	for note: BeatNote in notes:
		if note.kind != "heavy" or note.spent or note.reflected or note.contacted:
			continue
		var error := conductor.time - note.hit_time
		if absf(error) > RHYTHM_WINDOW:
			continue
		note.dual_press[lane] = conductor.time
		var other: float = note.dual_press["ground" if lane == "air" else "air"]
		if conductor.time - other > DUAL_GAP:
			return null
		note.contacted = true
		note.reflected = true
		note.last_swing = swing
		note.reflection_target = boss.target_point()
		note.fly_from = note.position
		note.fly_t = 0.0
		var beam := note.get_node_or_null("DualBeam")
		if beam != null:
			beam.visible = false   # 击飞后不再显示上下连接光柱
		host.player.state = ""
		host.player.set_state("bat3")   # 双键击飞用最重的一击
		_burst(note.position, note.kind)
		show_rating(rate((conductor.time + other) * 0.5 - note.hit_time), "dual")
		_play_hit(true)
		return note
	return null


## 统一击打音效：所有音符同一个原版采样、同一音调；音量压低到 -4dB（双键 -2.5dB）以免盖过音乐。
func _play_hit(heavy: bool) -> void:
	_play_stream(HIT_SFX, 1.0, -2.5 if heavy else -4.0)   # 用户反馈太响：整体压低，双键只略响


# ------------------------------------------------------------------ 冲刺反击
func _update_rush(dt: float) -> void:
	var rushes: Array = conductor.chart.get("rushes", [])
	if rush_state == "":
		for rb in rushes:
			var b := float(rb)
			var key := "%d:%s" % [conductor.loop_count, b]
			if _rush_done.has(key) or _pulse_beat < b - RUSH_WARN_BEATS - RUSH_DASH_BEATS or _pulse_beat >= b:
				continue
			_rush_done[key] = true
			_rush_beat = b
			rush_state = "warn"
			rush_mark.visible = true
			break
	match rush_state:
		"warn":
			boss.position = _boss_home + Vector2(sin(Time.get_ticks_msec() * 0.06) * 3.0, 0)   # 原地蓄力抖动
			if _pulse_beat >= _rush_beat - RUSH_DASH_BEATS:
				rush_state = "dash"
				_update_rush(0.0)   # 切换当帧就开始冲刺位移
		"dash":
			var k := clampf((_pulse_beat - (_rush_beat - RUSH_DASH_BEATS)) / RUSH_DASH_BEATS, 0.0, 1.0)
			var reach_x: float = host.player.position.x + RUSH_REACH
			boss.position = Vector2(lerpf(_boss_home.x, reach_x, k * k), _boss_home.y)   # 加速冲刺
			boss.rotation = -0.12 * k
			if _pulse_beat >= _rush_beat:
				_start_counter()
		"counter":
			rush_timer -= dt
			conductor.set_rate(move_toward(conductor.rate, SLOWMO_RATE, dt * (1.0 - SLOWMO_RATE) / SLOWMO_EASE_IN))
			if _hitstop > 0.0:   # 顿帧：Boss 定格并按档位抖动
				_hitstop -= dt
				var amp: float = [2.0, 4.0, 7.0][counter_tier]
				boss.position = _counter_pos + Vector2(randf_range(-amp, amp), randf_range(-amp * 0.5, amp * 0.5))
				boss.flash = maxf(0.0, boss.flash - dt)
				boss._sync_sprite()
			else:
				boss.position = _counter_pos
				boss.step(dt, _pulse_beat)
			if _counter_lock > 0.0:
				_counter_lock -= dt
				if _counter_lock <= 0.0 and _counter_buffer > 0:
					_counter_buffer -= 1
					_counter_strike()
			if rush_state == "counter" and rush_timer <= 0.0:
				_auto_finisher()   # 用户要求：无论是否打满，都以击退终结收尾
		"knockback":
			rush_timer -= dt
			var k := 1.0 - clampf(rush_timer / KNOCKBACK_TIME, 0.0, 1.0)
			boss.position = _knock_from.lerp(_boss_home, 1.0 - pow(1.0 - k, 3.0)) + Vector2(0, -90.0 * sin(PI * k))
			boss.rotation = 0.5 * sin(PI * k)
			conductor.set_rate(lerpf(SLOWMO_RATE, 1.0, k * k))   # 磁带回速：先慢后快拉回原速
			if rush_timer <= 0.0:
				_end_rush(false)
	rush_mark.position = boss.position + Vector2(0, -300)
	if rush_mark.visible:
		rush_mark.queue_redraw()


func _start_counter() -> void:
	rush_state = "counter"
	rush_timer = COUNTER_TIME
	counter_hits = 0
	counter_damage = 0
	counter_cap = maxi(1, int(round(boss.max_hp * COUNTER_CAP_RATIO)))
	counter_tier = 0
	perfect_counter = false
	_counter_lock = 0.0
	_counter_buffer = 0
	_hitstop = 0.0
	_counter_pos = boss.position
	rush_mark.visible = false
	boss.rotation = 0.0
	if host.has_method("add_camera_shake"):
		host.add_camera_shake(Vector2.LEFT, 0.4)


## 反击期间的一次按键：顿帧中则进缓冲（最多 1 下，顿帧结束立刻打出），否则立即出手。
func counter_hit() -> void:
	if rush_state != "counter" or boss.dead:
		return
	if _counter_lock > 0.0:
		_counter_buffer = 1
		return
	_counter_strike()


## 时间到还没打满：自动补一记击退终结（终结音效/金色大字/强震屏），伤害不超过剩余上限；不算 PERFECT。
func _auto_finisher() -> void:
	var mult := int(conductor.chart.finale_core_multiplier) if conductor.finale_started() else 1
	var damage := clampi(FINISHER_DAMAGE * mult, 0, counter_cap - counter_damage)
	counter_damage += damage
	var p: Node2D = host.player
	p.state = ""
	p.set_state("bat3")
	var pos := boss.target_point()
	_burst(pos, "heavy", 2.6)
	_play_counter_sfx(counter_hits + 1, 2, true)
	damage_popped.emit(counter_damage, pos, 3)   # 终结大字 = 本轮反击总伤害
	if damage > 0:
		boss.take_reflected_hit(damage)
		boss.flash = 0.06
		boss._sync_sprite()
	if host.has_method("add_camera_shake"):
		host.add_camera_shake(Vector2.RIGHT, 0.9)
	if boss.dead:
		_end_rush(true)
	else:
		_start_knockback()


static func counter_tier_for(hit: int) -> int:
	var tier := 0
	for i in COUNTER_TIERS.size():
		if hit >= int(COUNTER_TIERS[i][0]):
			tier = i
	return tier


## 出手一击：按档位结算伤害/顿帧/震屏/音效/伤害跳字；打满 15% 上限 → 终结重击 + PERFECT COUNTER。
func _counter_strike() -> void:
	counter_hits += 1
	counter_tier = counter_tier_for(counter_hits)
	var cfg: Array = COUNTER_TIERS[counter_tier]
	var mult := int(conductor.chart.finale_core_multiplier) if conductor.finale_started() else 1
	var damage := int(cfg[1]) * mult
	var finisher := counter_damage + damage >= counter_cap
	if finisher:
		damage = counter_cap - counter_damage
	counter_damage += damage
	_hitstop = float(cfg[2]) * (2.0 if finisher else 1.0)
	_counter_lock = _hitstop + COUNTER_RECOVER
	var p: Node2D = host.player
	p.state = ""
	p.set_state("bat3" if finisher else ["bat2", "bat1", "bat3"][counter_tier])
	var pos := boss.target_point() + Vector2(randf_range(-26, 26), randf_range(-30, 20))
	_burst(pos, "heavy", [0.8, 1.2, 1.7, 2.6][3 if finisher else counter_tier])
	_play_counter_sfx(counter_hits, counter_tier, finisher)
	# 终结大字显示本轮反击总伤害（连段总伤），普通一击显示单次伤害
	damage_popped.emit(counter_damage if finisher else damage, pos, 3 if finisher else counter_tier)
	boss.take_reflected_hit(damage)
	boss.flash = 0.04   # 连打只闪一层薄白（满闪 0.12 会让 Boss 变成白剪影、吞掉伤害数字）
	boss._sync_sprite()
	if host.has_method("add_camera_shake"):
		host.add_camera_shake(Vector2.RIGHT, 0.9 if finisher else [0.1, 0.22, 0.4][counter_tier])
	if boss.dead:
		_end_rush(true)
	elif finisher:
		perfect_counter = true
		score += PERFECT_COUNTER_BONUS
		_start_knockback()


## 越打越重的反击音效：以用户选定的原版命中声为底，每一下音调都比上一下更沉；
## 二档叠一层压低的第二命中声，三档叠原版「击杀」重击，终结一击 = 击杀 + 撞墙回弹，全部压到最低。
func _play_counter_sfx(hit: int, tier: int, finisher: bool) -> void:
	var sfx: Dictionary = host._sfx
	var pitch := clampf(1.15 - 0.03 * (hit - 1), 0.72, 1.15)
	if finisher:
		_play_stream(sfx.get("kill"), 0.7, 1.0)
		_play_stream(sfx.get("wall"), 0.75, -1.0)
		_play_stream(HIT_SFX, 0.68, -1.0)
		return
	_play_stream(HIT_SFX, pitch, [-5.0, -3.0, -2.0][tier])
	if tier >= 1:
		_play_stream(sfx.get("hit7"), pitch * 0.8, -6.0 if tier == 1 else -4.0)
	if tier >= 2:
		_play_stream(sfx.get("kill"), pitch * 0.9, -4.0)


func _play_stream(stream: AudioStream, pitch: float, volume_db: float) -> void:
	if stream == null:
		return
	if _hit_voices.size() < 8:
		for i in 8 - _hit_voices.size():
			var v := AudioStreamPlayer.new()
			add_child(v)
			_hit_voices.append(v)
	var voice := _hit_voices[_hit_voice_i]
	_hit_voice_i = (_hit_voice_i + 1) % _hit_voices.size()
	voice.stream = stream
	voice.pitch_scale = pitch
	voice.volume_db = volume_db
	voice.play()


func _start_knockback() -> void:
	rush_state = "knockback"
	rush_timer = KNOCKBACK_TIME
	_knock_from = boss.position
	_hitstop = 0.0
	_counter_lock = 0.0
	_counter_buffer = 0
	if host.has_method("add_camera_shake"):
		host.add_camera_shake(Vector2.RIGHT, 0.5)


func _end_rush(force: bool) -> void:
	rush_state = ""
	rush_timer = 0.0
	if rush_mark != null:
		rush_mark.visible = false
	if boss != null and (force or not boss.dead):
		boss.position = _boss_home
		boss.rotation = 0.0
	if conductor != null:
		conductor.set_rate(1.0)


## Boss 头顶的「!」：黑底白边红字，快速脉动。
func _draw_rush_mark() -> void:
	var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.03)
	rush_mark.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * pulse)
	rush_mark.draw_rect(Rect2(-18, -40, 36, 80), Color("0a0606"))
	rush_mark.draw_rect(Rect2(-16, -38, 32, 76), Color.WHITE)
	rush_mark.draw_rect(Rect2(-13, -35, 26, 70), Color("ff2a1a"))
	rush_mark.draw_rect(Rect2(-5, -29, 10, 40), Color.WHITE)
	rush_mark.draw_rect(Rect2(-5, 18, 10, 10), Color.WHITE)
	rush_mark.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

