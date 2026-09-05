extends Node2D
## 第三关“垂直货运井”：清下半塔后才解锁中枢存点，不在开局直接记录。

const DATA := preload("res://generated/m05_vertical_freight_data.gd")
const FLOOR_WAYFINDING := preload("res://scripts/m05_floor_wayfinding.gd")


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M05_VERTICAL_FREIGHT
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
	CorridorLevel.active_title = "03 垂直货运井"
	CorridorLevel.active_tile_style = {"name": "quarantine"}
	CorridorLevel.active_tileset_path = "res://assets/maps/quarantine/tileset_quarantine.png"
	# 第三关明确使用第一关同曲；从第二关进入时换回，死亡重开仍保持本曲进度。
	CorridorLevel.active_bgm = "res://assets/bgm/m02_oldtown.mp3"
	CorridorLevel.active_bgm_db = -16.0
	CorridorLevel.active_exit_requires_boss = true
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_campaign_mode = true
	CorridorLevel.active_restart_scene = "res://scenes/m05_vertical_freight.tscn"
	GameBackground.active_cfg = GameBackground.CFG_QUARANTINE
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	# 导向标放在建筑之上、地形/角色/血迹之下；只此boot接入，不改变前两关美术。
	var signs := FLOOR_WAYFINDING.new()
	signs.name = "FloorWayfinding"
	game.add_child(signs)
	game.move_child(signs, game.level.get_index())


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
