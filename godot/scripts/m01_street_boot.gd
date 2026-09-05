extends Node2D
## M01 旧城区霓虹街可玩入口：包装 game.tscn，实例化前切到 M01 街关配置。
## 手动玩：Godot 编辑器运行本场景，或命令行
##   godot --path godot res://scenes/m01_street.tscn
## 退出场景时还原默认配置，不影响主线默认关。


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M01_NEON
	CorridorLevel.active_hide_rows_from = 19   # 地面视觉交给 L2 走道带，只留碰撞
	CorridorLevel.active_minion = "grunt"      # 风衣枪手杂兵（12 个 x 刷点）
	CorridorLevel.active_boss = "none"         # 纯清版过关，无关底 Boss
	CorridorLevel.active_tile_style = {"name": "neon"}   # 深紫灰砖体 + 霓虹顶沿
	GameBackground.active_cfg = GameBackground.CFG_M01_NEON
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	# 注意：player.auto_input 必须保持 true —— 它表示"自动采集键鼠输入"，
	# 置 false 会让 _physics_process 直接返回（那是无头测试的手动驱动模式），
	# 表现为精灵不出现、无法操控。


func _exit_tree() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	GameBackground.active_cfg = []
