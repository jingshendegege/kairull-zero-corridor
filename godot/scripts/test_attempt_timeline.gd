extends SceneTree
## 短倒带纯算法合同：用 mock host 验证 3 秒滑窗、1.2 秒回看、端点与局部姿态。

const TIMELINE := preload("res://scripts/attempt_timeline.gd")

var _pass := 0
var _fail := 0


class MockPlayer extends Node2D:
	var face := 1
	var state := "idle"
	var frame := 0
	var t := 0.0
	var dead := false
	var local_marker := "origin"
	var applied_pose: Dictionary = {}

	func capture_timeline_pose() -> Dictionary:
		return {"position": position, "face": face, "state": state, "frame": frame,
				"t": t, "dead": dead, "local_marker": local_marker}

	func apply_timeline_pose(pose: Dictionary) -> void:
		applied_pose = pose.duplicate(true)
		position = pose.get("position", position)
		face = int(pose.get("face", face))
		state = str(pose.get("state", state))
		frame = int(pose.get("frame", frame))
		t = float(pose.get("t", t))
		dead = bool(pose.get("dead", dead))
		local_marker = str(pose.get("local_marker", local_marker))


class MockEnemy extends Node2D:
	var state := "idle"
	var frame := 0
	var face := 1
	var dead := false
	var _anim_clock := 0.0
	var sync_count := 0

	func _sync_sprite() -> void:
		sync_count += 1


class MockHost extends Node2D:
	var minions: Array[Node2D] = []
	var props: Array[Node2D] = []
	var player: MockPlayer
	var cam: Camera2D
	var cam_tl := Vector2.ZERO
	var enemy_bullets: Array[Dictionary] = []
	var paint_layer: SlimePaintLayer
	var fx_layer: Node2D

	func _init() -> void:
		player = MockPlayer.new()
		player.name = "MockPlayer"
		add_child(player)
		cam = Camera2D.new()
		cam.name = "MockCamera"
		add_child(cam)
		paint_layer = SlimePaintLayer.new()
		paint_layer.name = "MockPaint"
		add_child(paint_layer)
		fx_layer = Node2D.new()
		fx_layer.name = "MockFx"
		add_child(fx_layer)

	func add_mock_enemy() -> MockEnemy:
		var enemy := MockEnemy.new()
		add_child(enemy)
		minions.append(enemy)
		return enemy


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _run() -> void:
	var host := MockHost.new()
	get_root().add_child(host)
	await process_frame
	var enemy := host.add_mock_enemy()
	var timeline := TIMELINE.new()

	print("== 最近 1.2 秒、左右运动、相机与局部姿态 ==")
	_set_pose(host, enemy, Vector2(-240, 400), Vector2(-480, 100), Vector2(-1000, 20),
			-1, "run", 1, "origin")
	host.enemy_bullets = [{"position": Vector2(-20, 30), "velocity": Vector2.RIGHT}]
	timeline.record(host, 0.0, true)
	_set_pose(host, enemy, Vector2(-120, 400), Vector2(-240, 100), Vector2(-760, 20),
			-1, "roll", 3, "recent_start")
	host.enemy_bullets = [{"position": Vector2(0, 30), "velocity": Vector2.RIGHT}]
	timeline.record(host, 0.8, true)
	_set_pose(host, enemy, Vector2(0, 400), Vector2(0, 100), Vector2(-520, 20),
			1, "run", 7, "middle")
	timeline.record(host, 0.6, true)
	_set_pose(host, enemy, Vector2(120, 400), Vector2(240, 100), Vector2(-280, 20),
			1, "death", 14, "latest")
	host.enemy_bullets = [{"position": Vector2(20, 30), "velocity": Vector2.LEFT}]
	timeline.record(host, 0.6, true)
	ok(timeline.frames.size() == 4, "强制记录保留四个短倒带样本")

	timeline.apply_rewind(host, 0.0)
	ok(host.player.position == Vector2(120, 400) and host.player.position.x > 0,
			"回溯 0% 保持最右侧最新位置", str(host.player.position))
	ok(host.cam.position == Vector2(240, 100) and host.cam_tl == Vector2(-280, 20),
			"回溯 0% 保持最新相机与左上角", "%s / %s" % [host.cam.position, host.cam_tl])
	ok(host.player.local_marker == "latest" and host.player.state == "death"
			and host.player.frame == 14 and host.player.face == 1,
			"回溯 0% 保持最新局部 pose",
			"marker=%s state=%s frame=%d face=%d" % [host.player.local_marker,
					host.player.state, host.player.frame, host.player.face])
	ok(enemy.position == Vector2(120, 420) and enemy.state == "latest"
			and enemy.frame == 14 and enemy.face == 1,
			"回溯 0% 保持敌人最新局部 pose",
			"pos=%s state=%s frame=%d" % [enemy.position, enemy.state, enemy.frame])

	# target=1.25 秒，位于 recent_start(0.8) 与 middle(1.4) 的 75%；
	# 连续量应插值，离散 pose 应取更近的 middle。
	var interpolated_progress := sqrt(0.625)
	timeline.apply_rewind(host, interpolated_progress)
	ok(host.player.position == Vector2(-30, 400) and host.player.local_marker == "middle"
			and host.player.state == "run" and host.player.frame == 7,
			"连续位置插值、离散局部 pose 取最近帧",
			"pos=%s marker=%s state=%s frame=%d" % [host.player.position,
					host.player.local_marker, host.player.state, host.player.frame])
	ok(host.cam.position == Vector2(-60, 100) and host.cam_tl == Vector2(-580, 20),
			"相机与相机左上角按同一时间插值",
			"%s / %s" % [host.cam.position, host.cam_tl])

	timeline.apply_rewind(host, 1.0)
	ok(host.player.position == Vector2(-120, 400) and host.player.local_marker == "recent_start",
			"回溯 100% 只到最近 1.2 秒边界，不回整关原点", str(host.player.position))
	ok(host.player.state == "roll" and host.player.frame == 3 and host.player.face == -1,
			"1.2 秒边界恢复对应离散 pose")
	ok(host.cam.position == Vector2(-240, 100) and host.cam_tl == Vector2(-760, 20)
			and host.cam.offset == Vector2.ZERO, "1.2 秒边界恢复相机并清震屏偏移")
	ok(enemy.sync_count >= 3, "每次敌人回放后同步精灵")

	print("== 同时间强制末帧 ==")
	_set_pose(host, enemy, Vector2(132, 400), Vector2(252, 100), Vector2(-268, 20),
			-1, "death", 15, "forced_latest")
	timeline.record(host, 0.0, true)
	timeline.apply_rewind(host, 0.0)
	ok(host.player.position == Vector2(132, 400) and host.player.local_marker == "forced_latest"
			and host.player.frame == 15,
			"同时间补录死亡帧后，0% 严格使用最后一帧")

	print("== 不足 1.2 秒钳到首帧 ==")
	var short_attempt := TIMELINE.new()
	_set_pose(host, enemy, Vector2(-60, 400), Vector2(-120, 100), Vector2(-640, 20),
			-1, "run", 1, "short_origin")
	short_attempt.record(host, 0.0, true)
	_set_pose(host, enemy, Vector2(0, 400), Vector2(0, 100), Vector2(-520, 20),
			1, "roll", 4, "short_middle")
	short_attempt.record(host, 0.4, true)
	_set_pose(host, enemy, Vector2(60, 400), Vector2(120, 100), Vector2(-400, 20),
			1, "death", 8, "short_latest")
	short_attempt.record(host, 0.4, true)
	short_attempt.apply_rewind(host, 1.0)
	ok(host.player.position == Vector2(-60, 400) and host.player.local_marker == "short_origin",
			"短局历史不足 1.2 秒时安全钳到现存首帧")

	print("== 默认 12Hz 采样 ==")
	var sampled := TIMELINE.new()
	for index in range(60):
		host.player.local_marker = "tick_%02d" % index
		sampled.record(host, 1.0 / 60.0)
	ok(sampled.frames.size() >= 11 and sampled.frames.size() <= 13,
			"60Hz 输入一秒只生成约 12 个样本", str(sampled.frames.size()))

	print("== 36 帧固定频率滑动窗口 ==")
	var window := TIMELINE.new()
	for index in range(80):
		host.player.position = Vector2(index, -index)
		host.player.local_marker = "sample_%04d" % index
		host.player.state = "run" if index % 2 == 0 else "roll"
		window.record(host, 0.0 if index == 0 else TIMELINE.INITIAL_INTERVAL, true)
	ok(window.frames.size() == TIMELINE.MAX_SNAPSHOTS and window.frames.size() == 36,
			"滑动窗口严格限制为 36 帧", str(window.frames.size()))
	ok(Vector2(window.frames[0]["player"]["position"]) == Vector2(44, -44)
			and str(window.frames[0]["player"]["local_marker"]) == "sample_0044",
			"超限逐帧淘汰最旧样本，不保留整关原点")
	var newest: Dictionary = window.frames[-1]
	ok(Vector2(newest["player"]["position"]) == Vector2(79, -79)
			and str(newest["player"]["local_marker"]) == "sample_0079",
			"滑动窗口始终保留当前末帧")
	var ordered := true
	for index in range(1, window.frames.size()):
		ordered = ordered and float(window.frames[index]["time"]) \
				>= float(window.frames[index - 1]["time"])
	var span := float(window.frames[-1]["time"]) - float(window.frames[0]["time"])
	ok(ordered and is_equal_approx(window.interval, TIMELINE.INITIAL_INTERVAL),
			"窗口时间单调且采样间隔不抽稀、不放慢")
	ok(span > 2.8 and span < 3.01, "36 帧在 12Hz 下覆盖约 3 秒", "span=%.6f" % span)

	print("== clear 复位 ==")
	window.clear()
	ok(window.frames.is_empty() and window.elapsed == 0.0
			and window.interval == TIMELINE.INITIAL_INTERVAL and window.accumulator == 0.0,
			"clear 同时清快照、时间与采样器")

	host.free()
	for i in range(3):
		await process_frame
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _set_pose(host: MockHost, enemy: MockEnemy, player_position: Vector2,
		camera_position: Vector2, camera_tl: Vector2, face: int, state: String,
		frame: int, marker: String) -> void:
	host.player.position = player_position
	host.player.face = face
	host.player.state = state
	host.player.frame = frame
	host.player.t = frame / 10.0
	host.player.dead = state == "death"
	host.player.local_marker = marker
	host.cam.position = camera_position
	host.cam_tl = camera_tl
	host.cam.offset = Vector2(7, -5)
	enemy.position = player_position + Vector2(0, 20)
	enemy.face = face
	enemy.state = marker
	enemy.frame = frame
	enemy.dead = state == "death"
	enemy._anim_clock = frame / 12.0
