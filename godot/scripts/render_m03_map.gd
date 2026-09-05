extends SceneTree
## M03 纯场景地图全景渲染：无人物 / 无敌人 / 无玩法物件（拾取/门/CRT/桶全隐藏），
## 只保留 地形 + 装饰 + 灯光 —— 供用户专注验收地图本身。
## 相机停用物理驱动，手动分段横移，zoom 0.5 出高清分段图（上层 4 段 + 下层 4 段）。
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_m03_map.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M03_BACKROOM
	CorridorLevel.active_rooms = CorridorLevel.MAP_M03_BACKROOM_ROOMS
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "none"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "tower"}
	CorridorLevel.active_tileset_path = "res://assets/clips/tileset_m03.png"
	CorridorLevel.active_stair_material = "stone"
	CorridorLevel.active_decor = CorridorLevel.MAP_M03_BACKROOM_DECOR
	CorridorLevel.active_bg_texture_path = "res://assets/clips/bg_m03_full.png"
	CorridorLevel.stair_material_zones = CorridorLevel.MAP_M03_BACKROOM_STAIRS
	CorridorLevel.active_exit_requires_usb = false
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	if scene.wall_backdrop != null:
		scene.wall_backdrop.queue_redraw()   # 风格走 rooms 表 style 字段（生成器分配）

	# ---- 剥离全部玩法元素：人物 / 敌人 / 拾取件 / 桶 / CRT / 功能门 ----
	scene.set_physics_process(false)      # 停掉逐帧逻辑（相机不再被 lerp 驱动）
	scene.player.visible = false
	for m in scene.minions:
		if is_instance_valid(m):
			m.visible = false
	if scene.red_boss != null and is_instance_valid(scene.red_boss):
		scene.red_boss.visible = false
	for pk in scene.pickups:
		if is_instance_valid(pk):
			pk.visible = false
	for pr in scene.props:
		if is_instance_valid(pr):
			pr.visible = false            # CRT 与爆炸桶都是玩法 prop
	for d in scene.doors:
		if is_instance_valid(d):
			d.visible = false             # 清场门是玩法元素
	if scene.hud != null:
		scene.hud.visible = false
	if scene.debug_overlay != null:
		scene.debug_overlay.visible = false

	# 绕开 Camera2D（其变换不可靠），直接用视口 canvas_transform 分段渲染
	var vp := get_root()
	# ---- 诊断：StairRamp / BgSprite / Level 节点状态 ----
	print("DIAG zones=", CorridorLevel.stair_material_zones)
	for ch in scene.get_children():
		if ch.name.begins_with("StairRamp") or ch.name == "BgSprite" or ch.name == "Level":
			var tinfo := "-"
			var pxinfo := "-"
			if "texture" in ch:
				var t: Texture2D = ch.texture
				if t != null:
					var timg: Image = t.get_image()
					if timg != null and timg.get_width() > 90:
						var pc: Color = timg.get_pixel(96, 130)
						pxinfo = "size=%s px(96,130)=%s" % [t.get_size(), pc]
						tinfo = "loaded"
			print("DIAG ", ch.name, " idx=", ch.get_index(), " pos=", ch.position,
					" visible=", ch.visible, " tex=", tinfo, " ", pxinfo)
	var dir := OS.get_environment("USERPROFILE") + "/AppData/Local/Temp/m03_map"
	DirAccess.make_dir_recursive_absolute(dir)
	scene.get_node("Level").visible = false   # 诊断：隐藏地形层
	var rows := [
		{"name": "upper", "cy": 350.0},
		{"name": "lower", "cy": 700.0},
	]
	var s := 0.6                          # 缩放：视口 1080/0.6 = 1800 世界 px 每段
	var x0s := [0.0, 1280.0, 2560.0, 3320.0]   # 段起点（覆盖 5120）
	var y0 := -117.0                      # 顶部留 70 画面 px 灰（PIL 后裁）
	for row in rows:
		for i in x0s.size():
			var x0: float = x0s[i]
			vp.canvas_transform = Transform2D(Vector2(s, 0.0), Vector2(0.0, s),
					Vector2(-x0 * s, -y0 * s))
			for j in range(4):
				await physics_frame
			await RenderingServer.frame_post_draw
			var img := get_root().get_viewport().get_texture().get_image()
			img.save_png(dir + "/%s_%d.png" % [row["name"], i + 1])
			print("SHOT: %s_%d" % [row["name"], i + 1])
	print("SAVED: " + dir)
	quit(0)
