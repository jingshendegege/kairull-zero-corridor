extends Node2D
## 第一关：线性屋顶跑酷（2026-09-30 由原第四关提前；通关后接节拍广播塔 Boss），最终泵站由清场房门封锁。

const DATA := preload("res://generated/m06_exhaust_ridge_data.gd")


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M06_EXHAUST_RIDGE
	CorridorLevel.active_rooms = runtime_rooms()
	CorridorLevel.active_checkpoints = DATA.CHECKPOINTS.duplicate(true)
	CorridorLevel.active_stairs = runtime_stairs()
	CorridorLevel.active_art_style = "quarantine"
	CorridorLevel.active_semantic_layers = DATA.SEMANTIC_LAYERS.duplicate(true)
	CorridorLevel.active_semantic_ids = DATA.SEMANTIC_IDS.duplicate(true)
	CorridorLevel.active_tactical_objects = DATA.TACTICAL_OBJECTS.duplicate(true)
	CorridorLevel.active_encounter_boundaries = DATA.ENCOUNTER_BOUNDARIES.duplicate()
	CorridorLevel.active_encounter_policy = DATA.ENCOUNTER_POLICY
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_title = "01 排风脊线"
	CorridorLevel.active_tile_style = {"name": "quarantine"}
	CorridorLevel.active_tileset_path = "res://assets/maps/quarantine/tileset_quarantine.png"
	# 复用时差货运场曲目，与上一关的旧城区曲目区分。
	CorridorLevel.active_bgm = "res://assets/bgm/m04_chrono_freight_0906.mp3"
	CorridorLevel.active_bgm_db = -16.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_kill_refresh_dash = true
	CorridorLevel.active_campaign_mode = true
	CorridorLevel.active_restart_scene = "res://scenes/m06_exhaust_ridge.tscn"
	GameBackground.active_cfg = GameBackground.CFG_M06   # 室外夜空三层视差（Claude 美术）
	# 露天房间不画检疫站墙壳，露出夜空；两座竖井（exhaust_shaft/drop_chute）保留室内墙。
	QuarantineArchitecture.open_sky_profiles = ["roof_hatch", "fan_array", "skylight_gallery",
			"cooling_towers", "relay_service", "sniper_mast", "sky_bridge", "pump_arena", "extraction_crane"]
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	var art := preload("res://scripts/m06_exhaust_ridge_art.gd").new()
	art.name = "ExhaustRidgeArt"
	game.add_child(art)
	game.move_child(art, game.level.get_index())
	art.setup(game)


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
	CorridorLevel.active_kill_refresh_dash = false
	CorridorLevel.active_campaign_mode = false
	CorridorLevel.active_restart_scene = ""
	GameBackground.active_cfg = []
	QuarantineArchitecture.open_sky_profiles = []
