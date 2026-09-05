extends Node2D
## 第二关“时差货运场”：LDtk统一提供布局、战术对象和唯一中段检查点。

const DATA := preload("res://generated/m04_chrono_freight_data.gd")


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M04_CHRONO_FREIGHT
	CorridorLevel.active_rooms = runtime_rooms()
	CorridorLevel.active_checkpoints = DATA.CHECKPOINTS.duplicate(true)
	CorridorLevel.active_stairs = runtime_stairs()
	CorridorLevel.active_art_style = "quarantine"
	CorridorLevel.active_semantic_layers = DATA.SEMANTIC_LAYERS.duplicate(true)
	CorridorLevel.active_semantic_ids = DATA.SEMANTIC_IDS.duplicate(true)
	CorridorLevel.active_tactical_objects = DATA.TACTICAL_OBJECTS.duplicate(true)
	CorridorLevel.active_encounter_boundaries = DATA.ENCOUNTER_BOUNDARIES.duplicate()
	CorridorLevel.active_encounter_policy = ""
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_title = "02 时差货运场"
	CorridorLevel.active_tile_style = {"name": "quarantine"}
	CorridorLevel.active_tileset_path = "res://assets/maps/quarantine/tileset_quarantine.png"
	# 延续已认可主线音乐；持久音乐总线在死亡重开时保持进度。
	CorridorLevel.active_bgm = "res://assets/bgm/m04_chrono_freight_0906.mp3" # 用户提供9月6日.mp3，仅第二关使用。
	CorridorLevel.active_bgm_db = -5.5 # 原曲-22.59LUFS比第一关-12.08低10.51dB，补偿听感响度。
	CorridorLevel.active_exit_requires_boss = true
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_campaign_mode = true
	CorridorLevel.active_restart_scene = "res://scenes/m04_chrono_freight.tscn"
	GameBackground.active_cfg = GameBackground.CFG_QUARANTINE
	add_child(load("res://scenes/game.tscn").instantiate())


static func runtime_rooms() -> Array:
	var result: Array = []
	for source: Dictionary in DATA.ROOMS:
		var room := source.duplicate(true)
		var rect: Array = room["rect"]
		room["rect"] = Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
		room["name"] = String(room["display_name"])
		result.append(room)
	return result


static func runtime_stairs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in DATA.STAIRS:
		var bottom: Array = source["bottom_cell"]
		var top: Array = source["top_cell"]
		result.append({"left_c": mini(int(bottom[0]), int(top[0])),
			"bottom_row": int(bottom[1]), "steps": int(source["steps"]),
			"rise_dir": 1 if String(source["direction"]) == "right_up" else -1})
	return result


func _exit_tree() -> void:
	# 不清理文件、不重置会话；只恢复本入口拥有的关卡静态配置。
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_checkpoints = []
	CorridorLevel.active_stairs = []
	CorridorLevel.active_art_style = ""
	CorridorLevel.active_semantic_layers = {}
	CorridorLevel.active_semantic_ids = {}
	CorridorLevel.active_tactical_objects = []
	CorridorLevel.active_encounter_boundaries = []
	CorridorLevel.active_encounter_policy = ""
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_title = ""
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_campaign_mode = false
	CorridorLevel.active_restart_scene = ""
	GameBackground.active_cfg = []
