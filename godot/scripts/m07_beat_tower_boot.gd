extends Node2D
## 第一关结尾 Boss（2026-09-30 由原第五关提前）：后台、候场检查点与双轨节拍舞台。

const DATA := preload("res://generated/m07_beat_tower_data.gd")


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M07_BEAT_TOWER
	CorridorLevel.active_rooms = runtime_rooms()
	CorridorLevel.active_checkpoints = DATA.CHECKPOINTS.duplicate(true)
	CorridorLevel.active_stairs = runtime_stairs()
	CorridorLevel.active_art_style = "quarantine"
	CorridorLevel.active_semantic_layers = DATA.SEMANTIC_LAYERS.duplicate(true)
	CorridorLevel.active_semantic_ids = DATA.SEMANTIC_IDS.duplicate(true)
	CorridorLevel.active_tactical_objects = DATA.TACTICAL_OBJECTS.duplicate(true)
	CorridorLevel.active_encounter_boundaries = []
	CorridorLevel.active_encounter_policy = "linear_flow"
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_title = "01 BOSS 节拍广播塔"
	CorridorLevel.active_tile_style = {"name": "quarantine"}
	CorridorLevel.active_tileset_path = "res://assets/maps/quarantine/tileset_quarantine.png"
	# 后台与候场室使用低音量旧城区曲目。
	CorridorLevel.active_bgm = "res://assets/bgm/m02_oldtown.mp3"
	CorridorLevel.active_bgm_db = -18.0
	CorridorLevel.active_exit_requires_boss = true
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_kill_refresh_dash = true
	CorridorLevel.active_campaign_mode = true
	CorridorLevel.active_restart_scene = "res://scenes/m07_beat_tower.tscn"
	GameBackground.active_cfg = GameBackground.CFG_M07
	QuarantineArchitecture.open_sky_profiles = ["beat_stage"]
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	var arena := preload("res://scripts/beat_arena.gd").new()
	arena.name = "BeatArena"
	game.add_child(arena)
	game.beat_arena = arena
	arena.setup(game, DATA.BOSS_ARENA)
	# 2026-09-28 Claudeï¼éæèå°å®æ¯å±ï¼LED å¢/é³ç®±/ç¯æ/æ¿åï¼ï¼æ¾å¨å°å½¢ä¹åãè§è²ä¹åã
	var stage_fx := preload("res://scripts/m07_beat_stage_fx.gd").new()
	stage_fx.name = "BeatStageFx"
	game.add_child(stage_fx)
	game.move_child(stage_fx, game.level.get_index())
	stage_fx.setup(game, arena)
	# 节奏战专用 HUD（双轨锁定期间替代通用 HUD，击破后显示结算）
	var beat_hud := preload("res://scripts/beat_hud.gd").new()
	beat_hud.name = "BeatHud"
	game.add_child(beat_hud)
	beat_hud.setup(game, arena)
	# A retry may inherit a stopped backstage player after the boss song.
	if game.music != null and not game.music.playing:
		game.music.stream_paused = false
		game.music.play()



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
