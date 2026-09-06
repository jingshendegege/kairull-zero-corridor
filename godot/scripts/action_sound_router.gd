extends Node
class_name ActionSoundRouter
## 按作用路由独立音色：每类洗牌变体、连杀去重、有限声部与独立峰值限幅。
## 只在_ready加载流和创建播放器；暂停世界不暂停听觉收尾，切场不累积AudioBus。

const BANK := "res://assets/sfx/action_v1/"
const MANIFEST := BANK + "manifest.json"
const BUS_NAME := &"KairullActionSfx"
const MAX_VOICES := 8
const KILL_CHAIN_WINDOW := 2.4
const KILL_MERGE_WINDOW := 0.028
const MIN_GAIN_DB := -36.0
const MAX_GAIN_DB := -2.0

static var _bus_users := 0
static var _owns_bus := false

var clock_override := -1.0 ## 确定性测试使用；运行时保持负值，按真实音频时间计数
var last_event: Dictionary = {}
var _catalog: Dictionary = {}
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_events: Array[String] = []
var _voice_until: Array[float] = []
var _voice_priority: Array[int] = []
var _bags: Dictionary = {}
var _last_variants: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _last_kill_at := -INF
var _kill_streak := 0
var _loaded_streams := 0
var _bus_registered := false
var _web_audio := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_web_audio = OS.has_feature("web")
	_rng.randomize()
	# Web 使用低延迟 Sample 播放；自定义 AudioEffect 总线会让浏览器混音路径
	# 增加延迟并产生卡顿，因此 Web 音效直接送入 Master。
	if not _web_audio:
		_register_bus()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		push_error("独立动作音效清单缺失或格式错误: " + MANIFEST)
		return
	_catalog = parsed.get("events", {})
	for event: String in _catalog:
		var clips: Array[AudioStream] = []
		for entry: Dictionary in _catalog[event]["clips"]:
			var stream := _load_action_stream(BANK + str(entry["file"]))
			if stream == null:
				push_error("动作音效缺失: " + str(entry["file"]))
				continue
			clips.append(stream)
			_loaded_streams += 1
		_streams[event] = clips
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "ActionVoice%02d" % index
		voice.bus = &"Master" if _web_audio else BUS_NAME
		add_child(voice)
		_voices.append(voice)
		_voice_events.append("")
		_voice_until.append(0.0)
		_voice_priority.append(0)


func _load_action_stream(path: String) -> AudioStream:
	# 优先读有效导入资源，未导入的本地WAV仍可即时测试；PCK分支仅做兼容，尚未实际导出验收。
	# 未来导出须包含manifest.json；未导入WAV需显式包含原文件，或先导入并打包重映射资源。
	if FileAccess.file_exists(path + ".import"):
		var config := ConfigFile.new()
		if config.load(path + ".import") == OK:
			var imported := str(config.get_value("remap", "path", ""))
			if not imported.is_empty() and FileAccess.file_exists(imported):
				return load(path) as AudioStream
	if not FileAccess.file_exists(path) and ResourceLoader.exists(path):
		return load(path) as AudioStream
	return AudioStreamWAV.load_from_file(path)


func _register_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS_NAME)
		AudioServer.set_bus_send(index, &"Master")
		# 新版HardLimiter优先；旧后端使用标准Limiter，二者都限制最终叠加峰值。
		var limiter: AudioEffect = ClassDB.instantiate("AudioEffectHardLimiter") \
				if ClassDB.class_exists("AudioEffectHardLimiter") else AudioEffectLimiter.new()
		limiter.set("ceiling_db", -1.5)
		AudioServer.add_bus_effect(index, limiter)
		_owns_bus = true
	_bus_users += 1
	_bus_registered = true


func _exit_tree() -> void:
	stop_all()
	for voice: AudioStreamPlayer in _voices:
		voice.stream = null
	_streams.clear()
	if _bus_registered:
		_bus_users = maxi(0, _bus_users - 1)
		if _bus_users == 0 and _owns_bus:
			var index := AudioServer.get_bus_index(BUS_NAME)
			if index >= 0:
				AudioServer.remove_bus(index)
			_owns_bus = false
		_bus_registered = false


func play_event(event: StringName, pitch := 1.0, gain_db := 0.0) -> Dictionary:
	var key := String(event)
	if not _streams.has(key) or _streams[key].is_empty() or _voices.is_empty():
		return {"played": false, "event": key, "reason": "unknown_event"}
	var now := _now()
	var spec: Dictionary = _catalog[key]
	var final_pitch := pitch
	if key == "enemy_kill":
		_kill_streak = mini(6, _kill_streak + 1) if now - _last_kill_at <= KILL_CHAIN_WINDOW else 1
		var merged := now - _last_kill_at < KILL_MERGE_WINDOW
		_last_kill_at = now
		if merged:
			# 同一挥棒/爆炸同瞬多杀只留一次确认，不把多条爆音叠到削波。
			last_event = {"played": false, "event": key, "reason": "coalesced",
				"kill_streak": _kill_streak}
			return last_event.duplicate()
		final_pitch *= 1.0 + 0.024 * minf(4.0, _kill_streak - 1)
		gain_db -= minf(2.1, float(_active_count(key)) * 0.7)
	var voice_index := _select_voice(key, int(spec["voice_cap"]), int(spec["priority"]), now)
	if voice_index < 0:
		return {"played": false, "event": key, "reason": "priority_budget"}
	var variant := _next_variant(key)
	var stream: AudioStream = _streams[key][variant]
	var voice := _voices[voice_index]
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = clampf(final_pitch, 0.65, 1.45)
	voice.volume_db = clampf(float(spec["gain_db"]) + gain_db, MIN_GAIN_DB, MAX_GAIN_DB)
	voice.play()
	_voice_events[voice_index] = key
	_voice_until[voice_index] = now + stream.get_length() / voice.pitch_scale
	_voice_priority[voice_index] = int(spec["priority"])
	last_event = {"played": true, "event": key, "variant": variant + 1,
		"path": BANK + str(spec["clips"][variant]["file"]), "pitch": voice.pitch_scale,
		"gain_db": voice.volume_db, "voice": voice_index, "kill_streak": _kill_streak}
	return last_event.duplicate()


func _select_voice(event: String, cap: int, priority: int, now: float) -> int:
	var same: Array[int] = []
	var free := -1
	for index in _voices.size():
		if _voice_until[index] <= now:
			if free < 0:
				free = index
		elif _voice_events[index] == event:
			same.append(index)
	if same.size() >= cap:
		var oldest := same[0]
		for index in same:
			if _voice_until[index] < _voice_until[oldest]:
				oldest = index
		return oldest
	if free >= 0:
		return free
	# 预算满时优先替换低优先级/快结束的声部，不能让新破风截断死亡或回溯。
	var weakest := 0
	for index in range(1, _voices.size()):
		if _voice_priority[index] < _voice_priority[weakest] or \
				(_voice_priority[index] == _voice_priority[weakest] and _voice_until[index] < _voice_until[weakest]):
			weakest = index
	return weakest if priority >= _voice_priority[weakest] else -1


func _next_variant(event: String) -> int:
	var bag: Array = _bags.get(event, [])
	var count: int = _streams[event].size()
	if bag.is_empty():
		bag = range(count)
		for index in range(count - 1, 0, -1):
			var swap := _rng.randi_range(0, index)
			var saved: int = bag[index]
			bag[index] = bag[swap]
			bag[swap] = saved
		if count > 1 and bag.back() == _last_variants.get(event, -1):
			var saved: int = bag[0]
			bag[0] = bag[count - 1]
			bag[count - 1] = saved
	var chosen: int = bag.pop_back()
	_bags[event] = bag
	_last_variants[event] = chosen
	return chosen


func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_ticks_usec() / 1000000.0


func _active_count(event := "") -> int:
	var count := 0
	for index in _voices.size():
		if _voice_until[index] > _now() and (event.is_empty() or _voice_events[index] == event):
			count += 1
	return count


func stop_all() -> void:
	for index in _voices.size():
		_voices[index].stop()
		_voice_until[index] = 0.0
		_voice_events[index] = ""


func reset_sequence() -> void:
	stop_all()
	_bags.clear()
	_last_variants.clear()
	_last_kill_at = -INF
	_kill_streak = 0
	last_event.clear()


func set_random_seed(value: int) -> void:
	_rng.seed = value
	reset_sequence()


func debug_stats() -> Dictionary:
	return {"voices": _voices.size(), "active": _active_count(), "streams": _loaded_streams,
		"events": _catalog.size(), "bus": BUS_NAME, "bus_users": _bus_users,
		"kill_streak": _kill_streak}


func event_names() -> Array:
	return _catalog.keys()
