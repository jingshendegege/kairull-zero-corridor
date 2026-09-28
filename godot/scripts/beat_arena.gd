extends Node2D
class_name BeatArena
## A separate encounter, deliberately absent from enemy/cargo/timeline snapshots.
const CONDUCTOR := preload("res://scripts/beat_conductor.gd")
const WARDEN := preload("res://scripts/beat_warden.gd")
const NOTE := preload("res://scripts/beat_note.gd")
const COLORS := {"normal": Color("5fe6f0"), "heavy": Color("f0b44a"), "bomb": Color("ff3f94")}
## 2026-09-28 用户试玩反馈：自由移动+挥棒不好用 → 改为喵斯快跑式双轨。
## 倒数开始后主角锁定在判定线前原地奔跑（场景由 m07_beat_stage_fx 向左滚动）：
## W/↑ 上到隔板上层并挥棒，S/↓ 回地面下层并挥棒；按一次就停在该层，直到按另一个键切换。
## 按键时在该轨 ±RHYTHM_WINDOW 内找最近音符判定（不再看球棒几何）。炸弹靠"不在它那条轨"躲。
const RHYTHM_WINDOW := 0.20      ## 出手判定窗（秒）；漏判 = 过线超过此值
const LANE_FOOT := 36.0          ## 音符中心离主角脚底的高度（两层相同）；上层脚底 = 隔板顶面
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
		show_rating(rate(conductor.time - note.hit_time))
		host.play_action("metal_impact" if note.kind == "heavy" else "body_hit")

func _advance_notes(dt: float) -> void:
	# The existing active strike starts at BAT_HIT_AT and recovery/cancel opens at BAT_CANCEL_OPEN.
	var active_bat: bool = host.player.batting() and host.player._bat_progress() >= host.player.BAT_HIT_AT \
			and host.player._bat_progress() < host.player.BAT_CANCEL_OPEN
	for note: BeatNote in notes.duplicate():
		if note.spent:
			continue
		if note.reflected:
			var target := note.reflection_target
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
			show_rating("Miss")
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

func show_rating(value: String) -> void:
	rating = value
	rating_time = 0.6
	if value == "Miss":
		combo = 0
	else:
		combo += 1
		score += {"Perfect": 100, "Great": 70, "Hit": 40}[value]

func _on_boss_died() -> void:
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

func _burst(at: Vector2, kind: String) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(NOTE.ART + "note_burst.png")
	sprite.hframes = 4
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = at
	sprite.modulate = COLORS[kind]
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
	var color := Color("8ff8ff") if posmod(floori(_pulse_beat), 2) == 0 else Color("ff5aa8")
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


func _release_rhythm() -> void:
	if not rhythm_lock:
		return
	rhythm_lock = false
	player_lane = "ground"
	var p: Node2D = host.player
	p.keys.clear()
	p.auto_input = true
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
	if up and not _prev_up:
		rhythm_press("air")
	if down and not _prev_down:
		rhythm_press("ground")
	_prev_up = up
	_prev_down = down
	var p: Node2D = host.player
	p.invuln_t = maxf(0.0, p.invuln_t - dt)
	_place_player()
	if not p.batting():
		p.set_state("run")   # 两层都原地奔跑
	p._advance_frame(dt)
	p._sync_sprite()


## 一次出手：瞬移到该层（并停留）挥棒；在该轨判定窗内取时间误差最小的音符反弹（炸弹不可打）。
func rhythm_press(lane: String) -> BeatNote:
	player_lane = lane
	var p: Node2D = host.player
	p.state = ""
	p.set_state("bat2")
	_place_player()
	swing += 1
	if state != "playing" or frozen:
		return null
	var best: BeatNote = null
	var best_error := INF
	for note: BeatNote in notes:
		if note.spent or note.reflected or note.contacted or note.kind == "bomb" or note.lane != lane:
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
	show_rating(rate(best_error))
	host.play_action("metal_impact" if best.kind == "heavy" else "body_hit")
	return best
