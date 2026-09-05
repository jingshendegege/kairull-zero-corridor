extends Node2D
## HK 竞技场可玩入口：包装 game.tscn，实例化前切到竞技场配置。
## 手动玩：Godot 编辑器运行本场景，或命令行
##   godot --path godot res://scenes/hk_arena.tscn
## 退出场景时还原默认配置，不影响主线 M01。


func _ready() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_HK_ARENA
	CorridorLevel.active_hide_rows_from = 19   # 地面视觉交给背景街道
	CorridorLevel.active_minion = "none"       # Boss 单挑
	CorridorLevel.active_boss = "hornet"
	CorridorLevel.active_bgm = "res://assets/bgm/m02_oldtown.mp3"   # 延续 M02 老城区 BGM 进 Boss 战
	CorridorLevel.active_bgm_db = -12.0        # Boss 战略提音量（默认 -14）
	CorridorLevel.active_exit_requires_boss = true   # 出口上锁：击破大黄蜂才放行
	CorridorLevel.active_title = "HK 竞技场"   # 修复：未设标题时 CLEAR 卡回退显示 M01
	GameBackground.active_cfg = GameBackground.CFG_HK_STREET
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
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_exit_requires_boss = false
	CorridorLevel.active_title = ""
	GameBackground.active_cfg = []
