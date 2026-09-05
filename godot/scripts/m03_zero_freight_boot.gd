extends Node2D
## M03「零号货运站」灰盒入口：双层 U 形回环，纯球棒近战。
## 手动试玩：Godot 编辑器运行本场景，或
##   godot --path godot res://scenes/m03_zero_freight.tscn
## 出生点旁出口先锁定；清掉全图 12 名敌人并从西回落井返回后离场。


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M03_ZERO_FREIGHT
	CorridorLevel.active_rooms = CorridorLevel.MAP_M03_ZERO_FREIGHT_ROOMS
	CorridorLevel.active_hide_rows_from = -1
	# x 仍生成枪手；地图中的 m 刷点会覆盖为近战货运巡检员。
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "tower"}  # 灰盒暂复用 M02 图集
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = "M03 零号货运站"
	CorridorLevel.active_bgm = "res://assets/bgm/m02_oldtown.mp3"
	CorridorLevel.active_bgm_db = -14.0
	# 复用现有全清闸门：无 Boss 时只检查所有小怪是否清空。
	CorridorLevel.active_exit_requires_boss = true
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)


func _exit_tree() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = []
