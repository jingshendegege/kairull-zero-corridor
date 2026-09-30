extends Node
class_name BeatConductor
## Absolute, monotonic song timeline. Inject a seconds clock for deterministic tests.
var chart: Dictionary = {}
var music: AudioStreamPlayer
var clock := Callable()
## Optional compensated playback-position source, used to test asynchronous seeks.
var playback_clock := Callable()
## 真实时间源（秒）。默认系统计时；测试可注入以得到确定结果。
var real_clock := Callable()
var time := 0.0
var loop_count := 0
var running := false
var frozen := false
var rate := 1.0   ## 播放速率：1 = 正常；冲刺反击的子弹时间降到 0.3（music.pitch_scale 同步，谱面时间按实际播放推进）
var _last_clock := 0.0
var _scheduled_cycle := -1
var _pending: Array[Dictionary] = []
var _horns: Dictionary = {}
var _judge_x := 0.0
var _seek_waiting := false
var _seek_stale_threshold := 0.0
var _music_on := false      ## 预倒数（time < 0）期间音乐未开始；越过 0 时才播放
var _last_real := 0.0
## 2026-09-30 修复「卡一会才动」：音频刚启动/寻址时播放位置会停住一小段，旧逻辑 time = max(time, 播放位置)
## 会让音符原地定格。现在时间按真实时间平滑前进，只以 ±5% 的速度慢慢贴近音频；偏差超过 SNAP 才直接对齐。
const SYNC_SNAP := 0.15          ## 音频领先超过此值：直接追上
const SYNC_HOLD := 0.5           ## 音频落后超过此值（真卡住，如切后台）：原地等音频；启动延迟通常小于此值
const SYNC_PULL := 0.05

func setup(config: Dictionary, horns: Dictionary) -> void:
	chart = JSON.parse_string(FileAccess.get_file_as_string(config.chart))
	_horns = horns
	_judge_x = float(config.judge_x)
	music = AudioStreamPlayer.new()
	music.stream = load(config.music)
	music.volume_db = -14.0
	if AudioServer.get_bus_index("Music") >= 0:
		music.bus = "Music"
	add_child(music)

func seconds(beat: float) -> float:
	return beat * 60.0 / float(chart.bpm)

func loop_duration() -> float:
	return seconds(float(chart.loop_to_beat) - float(chart.loop_from_beat))

func song_beat() -> float:
	return (time - loop_count * loop_duration() - float(chart.offset_sec)) / seconds(1.0)

func finale_started() -> bool:
	for section: Dictionary in chart.sections:
		if section.name == "finale":
			return time >= seconds(float(section.from_beat)) + float(chart.offset_sec)
	return false

## preroll > 0：从 -preroll 秒开始走时（音符提前从 Boss 处正常飞出），走到 0 才开始播放音乐。
func start(preroll := 0.0) -> void:
	reset()
	running = true
	_last_clock = float(clock.call()) if clock.is_valid() else 0.0
	_last_real = _real_now()
	time = -maxf(0.0, preroll)
	if time >= 0.0:
		_begin_music()
	_schedule_cycle(0)
	_schedule_cycle(1) # Lead-in notes must spawn BEFORE the audio loop boundary.

func reset() -> void:
	running = false
	frozen = false
	time = 0.0
	loop_count = 0
	_scheduled_cycle = -1
	_seek_waiting = false
	_music_on = false
	_pending.clear()
	rate = 1.0
	if music != null:
		music.stop()
		music.stream_paused = false
		music.pitch_scale = 1.0
		music.volume_db = -14.0

func set_rate(value: float) -> void:
	rate = clampf(value, 0.05, 1.0)
	if music != null:
		music.pitch_scale = rate


func set_frozen(value: bool) -> void:
	if frozen == value:
		return
	frozen = value
	if clock.is_valid():
		_last_clock = float(clock.call())
	_last_real = _real_now()
	music.stream_paused = value

func advance() -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if not running or frozen:
		return due
	var real_now := _real_now()
	var real_dt := clampf(real_now - _last_real, 0.0, 0.25)
	_last_real = real_now
	if clock.is_valid():
		var now := float(clock.call())
		time += maxf(0.0, now - _last_clock) * rate
		_last_clock = maxf(now, _last_clock)
	elif not _music_on:
		time += real_dt * rate   # 预倒数：音乐尚未开始，按真实时间走
	else:
		var audible := float(playback_clock.call()) if playback_clock.is_valid() else \
				music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		# AudioServer applies seek on its mixing thread. Never add the new loop offset
		# to a stale pre-seek position (that would skip an entire loop in one frame).
		if _seek_waiting and audible < _seek_stale_threshold:
			_seek_waiting = false
		var predicted := time + real_dt * rate
		if _seek_waiting:
			time = predicted
		else:
			var target := maxf(0.0, audible) + loop_count * loop_duration()
			if target - predicted > SYNC_SNAP:
				time = target               # 音频领先较多（本帧卡顿后）：直接追上
			elif predicted - target > SYNC_HOLD:
				time = maxf(time, target)   # 音频真的停住了：原地等，绝不倒退
			else:
				# 小偏差：按真实时间走，并以最多 ±5% 的速度向音频靠拢——音符不会停住也不会跳
				var pull := clampf(target - predicted, -real_dt * rate * SYNC_PULL, real_dt * rate * SYNC_PULL)
				time = maxf(time, predicted + pull)
	if time >= 0.0 and not _music_on:
		_begin_music()
	var next_loop := seconds(float(chart.loop_to_beat)) + loop_count * loop_duration()
	if time >= next_loop:
		while time >= next_loop:
			loop_count += 1
			next_loop += loop_duration()
		music.seek(time - loop_count * loop_duration())
		_seek_waiting = not clock.is_valid()
		_seek_stale_threshold = seconds((float(chart.loop_from_beat) + float(chart.loop_to_beat)) * 0.5)
	while _scheduled_cycle < loop_count + 1:
		_schedule_cycle(_scheduled_cycle + 1)
	while not _pending.is_empty() and float(_pending[0].spawn_time) <= time + 0.000001:
		due.append(_pending.pop_front())
	return due

## 预倒数结束：从当前时间点开始播放（通常是 0，若这一帧略过了 0 则补上这一点点）。
func _begin_music() -> void:
	_music_on = true
	time = maxf(time, 0.0)
	if music != null:
		music.play(time - loop_count * loop_duration())


## 倒数结束时强制进入正式播放（真实时间下时钟会自己越过 0；测试注入的时钟可能没走，这里兜底）。
func begin_audio() -> void:
	if running and not _music_on:
		_begin_music()


func _real_now() -> float:
	return float(real_clock.call()) if real_clock.is_valid() else Time.get_ticks_usec() / 1000000.0


func _schedule_cycle(cycle: int) -> void:
	for source: Dictionary in chart.notes:
		if cycle > 0 and (float(source.beat) < float(chart.loop_from_beat) \
				or float(source.beat) >= float(chart.loop_to_beat)):
			continue
		var note := source.duplicate()
		note["time"] = seconds(float(source.beat)) + float(chart.offset_sec) + cycle * loop_duration()
		note["cycle"] = cycle
		note["spawn_time"] = float(note.time) - (float(_horns[source.lane]) - _judge_x) / float(chart.note_speed_px)
		_pending.append(note)
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.spawn_time < b.spawn_time)
	_scheduled_cycle = cycle
