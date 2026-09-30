extends Node
## VibeHub 创意工坊桥接（Claude，2026-09-30）。全局自动加载。
## 网页端：从 window.KairullMods（web/kairull-mods.js）读取 Mod 注册的数值/外观，并把游戏事件发回 JS。
## 桌面端 / 无头测试：没有 JS 环境，保持原值、事件只记入 events_log，不影响任何玩法。
## Mod 不能直接访问 Godot 节点；所有数值在这里再次校验与限幅，公开 API 见仓库根目录 WORKSHOP.md。

const RUN_SESSION := preload("res://scripts/run_session.gd")
const CHRONO := preload("res://scripts/chrono_charge.gd")
const BEAT_ARENA := preload("res://scripts/beat_arena.gd")
const API_VERSION := 1
const POLL_INTERVAL := 0.5

var web_enabled := false
var events_log: Array[Dictionary] = []   ## 最近 32 条事件（调试/测试用）
var player_tint := Color.WHITE
var has_player_tint := false
var _api: JavaScriptObject
var _version := -1
var _poll_t := 0.0
var _game: Node = null
var _scene: Node = null
var _cleared := false
var _ready_sent := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_api = JavaScriptBridge.get_interface("KairullMods")
	web_enabled = _api != null
	if web_enabled:
		_refresh(true)


## 把 JS 端汇总好的注册表（已按注册顺序合并）应用到游戏；所有值在此再次限幅。
func apply(data: Dictionary) -> void:
	var hp := {}
	var health: Dictionary = data.get("difficultyHealth", {})
	for mode in RUN_SESSION.DIFFICULTIES:
		if health.has(mode):
			hp[mode] = clampi(int(health[mode]), 1, 9)
	RUN_SESSION.hp_overrides = hp
	var chrono: Dictionary = data.get("timeStop", {})
	CHRONO.duration_scale = clampf(float(chrono.get("durationScale", 1.0)), 0.25, 4.0)
	CHRONO.recharge_scale = clampf(float(chrono.get("rechargeScale", 1.0)), 0.25, 4.0)
	var boss: Dictionary = data.get("boss", {})
	BEAT_ARENA.mod_boss_hp_scale = clampf(float(boss.get("hpScale", 1.0)), 0.25, 4.0)
	var tint: Dictionary = data.get("playerTint", {})
	has_player_tint = tint.has("color") and Color.html_is_valid(String(tint.color))
	if has_player_tint:
		var target := Color.html(String(tint.color))
		var strength := clampf(float(tint.get("strength", 1.0)), 0.0, 1.0)
		player_tint = Color.WHITE.lerp(Color(target.r, target.g, target.b, 1.0), strength)
	else:
		player_tint = Color.WHITE


## 恢复全部默认值（测试与 Mod 全部注销时用）。
func reset() -> void:
	apply({})


func emit(event_name: String, payload: Dictionary = {}) -> void:
	events_log.append({"name": event_name, "payload": payload})
	if events_log.size() > 32:
		events_log.pop_front()
	if web_enabled:
		_api._emit(event_name, JSON.stringify(payload))


func _refresh(force := false) -> void:
	var version := int(_api._version)
	if not force and version == _version:
		return
	_version = version
	var parsed = JSON.parse_string(String(_api._snapshot()))
	if parsed is Dictionary:
		apply(parsed)


func _process(dt: float) -> void:
	if web_enabled:
		_poll_t -= dt
		if _poll_t <= 0.0:
			_poll_t = POLL_INTERVAL
			_refresh()
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		_attach(scene)
	if _game != null and is_instance_valid(_game):
		if _game.level_cleared and not _cleared:
			_cleared = true
			emit("level:clear", _level_info())
		if has_player_tint and _game.player != null and _game.player._sprite != null:
			var sprite: Sprite2D = _game.player._sprite
			sprite.modulate = Color(player_tint.r, player_tint.g, player_tint.b, sprite.modulate.a)


func _attach(scene: Node) -> void:
	_game = scene.get_node_or_null("Game") if scene != null else null
	_cleared = false
	if scene != null and not _ready_sent:
		_ready_sent = true
		emit("game:ready", {"apiVersion": API_VERSION})
		if web_enabled:
			_api._gameReady(API_VERSION)
	if _game == null:
		if scene != null:
			emit("menu:enter", {})
		return
	var player: Node = _game.player
	player.hurt.connect(func() -> void: emit("player:hurt", {"hp": player.hp, "maxHealth": player.max_hp}))
	player.died.connect(func() -> void: emit("player:death", _level_info()))
	var arena = _game.get("beat_arena")
	if arena != null and is_instance_valid(arena):
		arena.rated.connect(func(value: String, lane: String) -> void:
			emit("rhythm:judge", {"rating": value.to_lower(), "lane": lane, "combo": arena.combo}))
		arena.boss.boss_died.connect(func() -> void: emit("boss:defeat", {"boss": "beat_warden", "scene": _level_info().scene}))
	var red = _game.get("red_boss")
	if red != null and is_instance_valid(red) and red.has_signal("boss_died"):
		red.boss_died.connect(func() -> void: emit("boss:defeat", {"boss": "red", "scene": _level_info().scene}))
	emit("level:start", _level_info())


func _level_info() -> Dictionary:
	return {"scene": String(CorridorLevel.active_restart_scene).get_file().get_basename(),
		"title": CorridorLevel.active_title, "difficulty": RUN_SESSION.difficulty,
		"maxHealth": RUN_SESSION.max_health()}
