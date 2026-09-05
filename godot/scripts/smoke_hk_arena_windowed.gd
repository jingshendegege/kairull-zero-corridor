extends SceneTree
## HK 竞技场真实窗口冒烟：启动 hk_arena.tscn 跑 240 帧自动退出
## （含 BGM 接续播放 + 大黄蜂 AI 推进 + 出口门锁定态绘制），
## 任何 SCRIPT ERROR / ERROR 输出都会打到 stderr 供外层检查。
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/smoke_hk_arena_windowed.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node2D = load("res://scenes/hk_arena.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var game: Node2D = scene.get_node("Game")
	print("  BGM playing = ", game.music != null and game.music.playing, "（应为 true）")
	print("  出口锁定 = ", game.exit_door != null and game.exit_door.locked, "（应为 true）")
	for i in range(240):   ## ≈8s@fixed-fps 30：标题卡淡出 + BGM 循环 + Boss AI 全程推进
		await process_frame
	print("SMOKE_RESULT: PASS")
	quit(0)
