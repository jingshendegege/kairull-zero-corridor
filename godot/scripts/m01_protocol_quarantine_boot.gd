extends Node2D
## 正式第一关“协议检疫站”入口。
## 布局/实体/楼梯/美术语义均由 LDtk 编译数据提供，退出时逐项恢复旧关卡默认值。

const DATA := preload("res://generated/m01_protocol_quarantine_data.gd")


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M01_PROTOCOL
	CorridorLevel.active_rooms = _runtime_rooms()
	CorridorLevel.active_checkpoints = DATA.CHECKPOINTS.duplicate(true) # Python/LDtk唯一定义中段点。
	CorridorLevel.active_stairs = _runtime_stairs()
	CorridorLevel.active_art_style = "quarantine"
	CorridorLevel.active_semantic_layers = DATA.SEMANTIC_LAYERS.duplicate(true)
	CorridorLevel.active_semantic_ids = DATA.SEMANTIC_IDS.duplicate(true)
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt"   # x=枪手；m 由地图标记强制为近战巡检员。
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_title = "M01 协议检疫站"
	CorridorLevel.active_tile_style = {"name": "quarantine"}
	CorridorLevel.active_tileset_path = "res://assets/maps/quarantine/tileset_quarantine.png"
	CorridorLevel.active_bgm = "res://assets/bgm/m02_oldtown.mp3"   # 先复用低音量主线曲，后续可独立换曲。
	CorridorLevel.active_bgm_db = -16.0
	# 长版主线使用补给返回点；清空全图才开放终点，不再自动跳入旧美术 M02。
	CorridorLevel.active_exit_requires_boss = true
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_campaign_mode = true
	CorridorLevel.active_restart_scene = "res://scenes/m01_protocol_quarantine.tscn"
	GameBackground.active_cfg = GameBackground.CFG_QUARANTINE

	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)


func _runtime_rooms() -> Array:
	var result: Array = []
	for source: Dictionary in DATA.ROOMS:
		var room := source.duplicate(true)
		var raw: Array = room["rect"]
		room["rect"] = Rect2i(int(raw[0]), int(raw[1]), int(raw[2]), int(raw[3]))
		# HUD 与旧房间接口仍使用 name；稳定 room_id/decor_profile 同时保留。
		room["name"] = String(room["display_name"])
		result.append(room)
	return result


func _runtime_stairs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in DATA.STAIRS:
		var bottom: Array = source["bottom_cell"]
		var top: Array = source["top_cell"]
		var left_c := mini(int(bottom[0]), int(top[0]))
		result.append({
			"left_c": left_c,
			"bottom_row": int(bottom[1]),
			"steps": int(source["steps"]),
			"rise_dir": 1 if String(source["direction"]) == "right_up" else -1,
		})
	return result


func _exit_tree() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_checkpoints = []
	CorridorLevel.active_stairs = []
	CorridorLevel.active_art_style = ""
	CorridorLevel.active_semantic_layers = {}
	CorridorLevel.active_semantic_ids = {}
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
