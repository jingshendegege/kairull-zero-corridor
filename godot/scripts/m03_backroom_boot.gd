extends Node2D
## M03 黑市包间 "THE BACKROOM" 可玩入口：4 层拾取关。
## 手动玩：Godot 编辑器运行本场景，或
##   godot --path godot res://scenes/m03_backroom.tscn
## 设计：取件即通关（拾取 USB 解锁出口，不强制清房 —— 与 M02 清房制区分）。
## 现状：地图/楼梯/三材质/背景风格已接；K/U 拾取 prop 与解锁逻辑待接入。


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M03_BACKROOM
	CorridorLevel.active_rooms = CorridorLevel.MAP_M03_BACKROOM_ROOMS
	CorridorLevel.active_hide_rows_from = -1   # 室内 tiles 全渲染
	CorridorLevel.active_minion = "grunt"      # 风衣枪手（x 刷点，密室精英待接）
	CorridorLevel.active_boss = "none"         # 拾取关无关底
	CorridorLevel.active_tile_style = {"name": "tower"}   # 室内成品色图集
	CorridorLevel.active_stair_material = "stone"         # 主楼梯石砌（样张推荐）
	CorridorLevel.active_exit_requires_usb = true         # 取件闸门：USB 入手才放行出口
	CorridorLevel.active_decor = CorridorLevel.MAP_M03_BACKROOM_DECOR  # 背景装饰层
	CorridorLevel.stair_material_zones = CorridorLevel.MAP_M03_BACKROOM_STAIRS  # 三材质楼梯分区
	CorridorLevel.active_bg_texture_path = "res://assets/clips/bg_m03_full.png"  # 离线精绘背景贴图
	CorridorLevel.active_enemy_rim = Color(1.0, 0.82, 0.4, 0.75)       # 敌人暖黄轮廓光（teal 环境里跳出来）
	CorridorLevel.active_tileset_path = "res://assets/clips/tileset_m03.png"  # M03 自绘地形（警示条地板/teal 墙/暖橙台）
	CorridorLevel.active_title = "M03 黑市包间"
	CorridorLevel.active_bgm = "res://assets/bgm/m02_oldtown.mp3"   # 暂复用暗调循环曲（正式 BGM 待定）
	CorridorLevel.active_next_scene = ""       # 取件解锁出口后接 M04（待定）
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	# 背景墙风格：rooms 表每间自带 style（0竖板/1横板/2loft），不再用 override
	if game.wall_backdrop:
		game.wall_backdrop.queue_redraw()


func _exit_tree() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_stair_material = "stone"
	CorridorLevel.active_exit_requires_usb = false
	CorridorLevel.active_decor = []
	CorridorLevel.stair_material_zones = []
	CorridorLevel.active_bg_texture_path = ""
	CorridorLevel.active_enemy_rim = Color()
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_next_scene = ""
	GameBackground.active_cfg = []
