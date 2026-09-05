extends SceneTree
## M01 道具/艺术 UI/霓虹 tile 渲染验收：真实窗口跑（无头截图为空）。
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m01_props.gd
## 输出：user://shot2_*.png
##   1 开场 VHS 标题卡（~0.6s）        2 广场连锁桶对 + 枪手
##   3 爆炸桶引爆瞬间清怪              4 塔门青光 + M01 CLEAR 卡
##   5 出生区全景（霓虹 tile + CRT + 心形 + 残敌计数）

var _shot_count := 0
var _scene: Node2D


func _init() -> void:
	call_deferred("_run")


func _wait_real(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _run() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M01_NEON
	CorridorLevel.active_hide_rows_from = 19
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "neon"}
	GameBackground.active_cfg = GameBackground.CFG_M01_NEON
	_scene = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(_scene)
	await process_frame
	await process_frame

	var player: KairullPlayer = _scene.player
	var ground_y := 19.0 * 32 - 0.1

	# --- 镜头 1：开场 VHS 标题卡（~0.9s，扫描线正扫过标题） ---
	await _wait_real(900)
	await _shot("shot2_1_intro_card")

	# 等标题卡播完，避免污染后续镜头
	await _wait_real(2300)

	# --- 镜头 2：广场连锁桶对（c99/c101）+ 街面双枪（c97/c100） ---
	player.position = Vector2(92 * 32, ground_y)
	player.vy = 0.0
	_scene.cam_tl = _scene._cam_target()
	await _settle(20)
	await _shot("shot2_2_barrel_cluster")

	# --- 镜头 3：引爆 c99 桶 → 连锁 c101，炸死 c97/c100 枪手 ---
	var barrel: PropBarrel = null
	for pr in _scene.props:
		if pr is PropBarrel and absf(pr.position.x - (99 * 32 + 16)) < 1.0:
			barrel = pr
	if barrel != null:
		barrel.take_hit(barrel.position.x, 1)
		# 引信 0.35s（fixed-fps 30 → 物理步 1/30），等爆炸后 ~3 帧抓爆心
		while not barrel.dead:
			await process_frame
		await _settle(3)
	await _shot("shot2_3_barrel_explosion")

	# --- 镜头 4：塔门青光 + CLEAR 卡 ---
	player.position = Vector2(184 * 32, ground_y)
	player.vy = 0.0
	_scene.cam_tl = _scene._cam_target()
	await _settle(8)
	player.position = _scene.level.exit_point
	player.vy = 0.0
	await _settle(10)
	print("  level_cleared: ", _scene.level_cleared)
	await _wait_real(400)   ## 让门脉动与 CLEAR 卡呼吸感出来
	await _shot("shot2_4_exit_clear")

	# --- 镜头 5：出生区全景（CRT c13 + 桶 c24 + 售货亭霓虹顶沿 + 心形 + 计数） ---
	_scene.level_cleared = false   ## 复位过关态（等价 Backspace 流程），避免 CLEAR 卡污染全景
	# 先杀两名枪手让残敌计数掉下来（走正常击杀路径出液爆痕迹）
	var killed := 0
	for mn in _scene.minions:
		if killed >= 2:
			break
		if is_instance_valid(mn) and not mn.dead:
			var dir := Vector2(0.6, -0.4)
			var burst: SlimeRibbonBurst = _scene.fx_layer.spawn_bat_hit(
					mn.body_rect().get_center(), dir, 1.35)
			mn.take_hit(mn.position.x, 1)
			_scene.paint_layer.blood_pool(mn.body_rect().get_center(), 1.0, 0,
					burst.current_color.darkened(0.15))
			killed += 1
	player.position = Vector2(18 * 32, ground_y)
	player.vy = 0.0
	_scene.cam_tl = _scene._cam_target()
	await _settle(20)
	await _shot("shot2_5_spawn_overview")

	print("RENDER_RESULT: PASS")
	quit(0)


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
