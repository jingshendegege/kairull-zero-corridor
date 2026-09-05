extends Node2D
## M02 数据塔可玩入口：包装 game.tscn，实例化前切到 M02 塔内配置。
## 手动玩：Godot 编辑器运行本场景，或命令行
##   godot --path godot res://scenes/m02_tower.tscn
## 退出场景时还原默认配置，不影响主线默认关与 M01 街关。


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M02_TOWER
	CorridorLevel.active_rooms = CorridorLevel.MAP_M02_TOWER_ROOMS
	CorridorLevel.active_hide_rows_from = -1   # 室内 tiles 全渲染（无背景地面图）
	CorridorLevel.active_minion = "grunt"      # 风衣枪手杂兵（19 个 x 刷点）
	CorridorLevel.active_boss = "none"         # 纯清版过关，无关底 Boss
	CorridorLevel.active_tile_style = {"name": "tower"}   # 塔专用图集（成品色）
	CorridorLevel.active_title = "M02 数据塔"
	CorridorLevel.active_bgm = "res://assets/bgm/m02_oldtown.mp3"   # 老城区 BGM 循环
	CorridorLevel.active_next_scene = "res://scenes/hk_arena.tscn"  # CLEAR → 淡黑 → 竞技场
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM   # task B 再换真背景
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)


func _exit_tree() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = []
