extends Node
class_name BeatConductor
## Absolute, monotonic song timeline. Inject a seconds clock for deterministic tests.
var chart: Dictionary = {}
var music: AudioStreamPlayer
var clock := Callable()
## Optional compensated playback-position source, used to test asynchronous seeks.
var playback_clock := Callable()
var time := 0.0
var loop_count := 0
var running := false
var frozen := false
var _last_clock := 0.0
var _scheduled_cycle := -1
var _pending: Array[Dictionary] = []
var _horns: Dictionary = {}
var _judge_x := 0.0
var _seek_waiting := false
var _seek_stale_threshold := 0.0

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

func start() -> void:
	reset()
	running = true
	_last_clock = float(clock.call()) if clock.is_valid() else 0.0
	music.play(0.0)
	_schedule_cycle(0)
	_schedule_cycle(1) # Lead-in notes must spawn BEFORE the audio loop boundary.

func reset() -> void:
	running = false
	frozen = false
	time = 0.0
	loop_count = 0
	_scheduled_cycle = -1
	_seek_waiting = false
	_pending.clear()
	if music != null:
		music.stop()
		music.stream_paused = false
		music.volume_db = -14.0

func set_frozen(value: bool) -> void:
	if frozen == value:
		return
	frozen = value
	if clock.is_valid():
		_last_clock = float(clock.call())
	music.stream_paused = value

func advance() -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if not running or frozen:
		return due
	if clock.is_valid():
		var now := float(clock.call())
		time += maxf(0.0, now - _last_clock)
		_last_clock = maxf(now, _last_clock)
	else:
		var audible := float(playback_clock.call()) if playback_clock.is_valid() else \
				music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		# AudioServer applies seek on its mixing thread. Never add the new loop offset
		# to a stale pre-seek position (that would skip an entire loop in one frame).
		if _seek_waiting and audible < _seek_stale_threshold:
			_seek_waiting = false
		if not _seek_waiting:
			time = maxf(time, maxf(0.0, audible) + loop_count * loop_duration())
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
