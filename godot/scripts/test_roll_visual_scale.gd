extends SceneTree
## 翻滚体型回归：只校验运行时统一缩放、脚底、描边/虚影及原动作预算，不修改原素材。

var _pass := 0
var _fail := 0


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		push_error("  FAIL  " + label)


func _run() -> void:
	var db := AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json",
		"res://assets/clips/hero/hero_atlas.json"])
	var player := KairullPlayer.new()
	player.auto_input = false
	player.db = db
	player.spawn = Vector2(500.25, 400.25)
	root.add_child(player)
	player._sync_sprite()
	# 只读源素材审计使用绝对路径；本脚本不随游戏导出，不触发res路径的导出提示。
	var source := Image.load_from_file(ProjectSettings.globalize_path("res://assets/clips/hero/hero_roll.png"))
	ok(source.get_size() == Vector2i(3072, 512), "原图仍为六个512正方形格，未重新切片")
	ok(KairullPlayer.ROLL_FRAME_COUNT == 6 and db.actions.hero_roll.frames == 6,
		"原六帧数量不变")
	ok(KairullPlayer.ROLL_DISTANCE == 192.0 and KairullPlayer.ROLL_FPS_MULT == 0.75
		and is_equal_approx(KairullPlayer.ROLL_DURATION, 1.0 / 3.0), "6格、18fps、三分之一秒不变")
	ok(is_equal_approx(KairullPlayer.ROLL_INVULN_TIME, 0.14), "翻滚前0.14秒无敌窗口不变")
	ok(player.w == 22.0 and player.h == 52.0, "受击框分离后22×52移动碰撞仍不变")
	ok(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED, "枪械与旧滑铲仍禁用")
	for direction in [1, -1]:
		player.face = direction
		player.state = "gun_idle"
		player._apply_sprite("hero_idle", 0)
		ok(player._sprite.scale.is_equal_approx(Vector2.ONE * 0.4), "朝向%d：站立保持0.4" % direction)
		ok(player.hurtbox_rect().size == Vector2(34, 82), "朝向%d：站立受击框34×82" % direction)
		ok(is_equal_approx(player.hurtbox_rect().get_center().x, player.position.x + 6.0 * direction),
			"朝向%d：站立受击框朝脸部偏6px" % direction)
		for f in range(6):
			player.state = "roll"
			player.frame = f
			player._apply_sprite("hero_roll", f)
			var label := "朝向%d / 帧%d" % [direction, f + 1]
			ok(player._sprite.scale.is_equal_approx(Vector2.ONE * 0.328), label + "：统一0.328，不逐帧拉伸")
			ok(player._sprite.region_rect == Rect2(f * 512, 0, 512, 512), label + "：保留原帧顺序")
			var bounds := source.get_region(Rect2i(f * 512, 0, 512, 512)).get_used_rect()
			ok(bounds.end.y == 500, label + "：原画底边500，无跨帧越界")
			var bottom_y := player._sprite.global_position.y + bounds.end.y * player._sprite.scale.y
			ok(absf(bottom_y - player.position.y) <= 0.5, label + "：像素取整后脚底误差不超0.5px")
			ok(player._outline.scale.is_equal_approx(player._sprite.scale)
				and player._outline.global_position == player._sprite.global_position
				and player._outline.flip_h == player._sprite.flip_h, label + "：描边缩放/锚点/朝向同步")
			player._spawn_dash_afterimage(Color.CYAN, player._sprite.global_transform, KairullPlayer.ROLL_GHOST_LIFETIME)
			var ghost: Sprite2D = player._dash_ghosts.back().sprite
			ok(ghost.scale.is_equal_approx(player._sprite.scale)
				and ghost.global_transform.is_equal_approx(player._sprite.global_transform)
				and ghost.region_rect == player._sprite.region_rect and ghost.flip_h == player._sprite.flip_h,
				label + "：虚影复制本体尺寸/帧/变换")
			ok(player.hurtbox_rect().size == Vector2(38, 34)
				and is_equal_approx(player.hurtbox_rect().end.y, player.position.y), label + "：低矮38×34受击框贴脚底")
	player.free()
	db = null
	await process_frame
	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: ", "PASS" if _fail == 0 else "FAIL")
	quit(0 if _fail == 0 else 1)
