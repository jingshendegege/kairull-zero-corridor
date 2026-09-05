extends SceneTree
## M02 数据塔真实窗口冒烟：启动 m02_tower.tscn 跑 300 帧自动退出（含 BGM 播放），
## 任何 SCRIPT ERROR / ERROR 输出都会打到 stderr 供外层检查。
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/smoke_m02_windowed.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node2D = load("res://scenes/m02_tower.tscn").instantiate()
	get_root().add_child(scene)
	for i in range(300):   ## ≈10s@fixed-fps 30：标题卡淡出 + BGM 播放 + 敌人 AI 全程推进
		await process_frame
	print("SMOKE_RESULT: PASS")
	quit(0)
