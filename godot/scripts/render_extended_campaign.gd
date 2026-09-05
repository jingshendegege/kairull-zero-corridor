extends SceneTree
## 扩展“协议检疫站”真窗口逐房/转场验收；headless 截图不能替代本脚本。
## 跑法：Godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_extended_campaign.gd
## 输出：user://shot_extended_*.png

const DATA := preload("res://generated/m01_protocol_quarantine_data.gd")
const TS := 32

var _render_failed := false
var _occupied_cells := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("扩展地图美术验收必须使用真窗口")
		quit(1)
		return
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var player: KairullPlayer = game.player
	var art: QuarantineArchitecture = game.quarantine_architecture
	if art == null or art.extended_profile_count != 7 or art.extended_landmark_count != 7 \
			or art.archive_branch_lane_count != 2 or art.service_bench_visual_count != 2 \
			or art.coolant_tank_visual_count != 3 or art.freight_hoist_visual_count != 2 \
			or art.containment_ring_visual_count != 1 or art.stair_visual_count != 3:
		_render_failed = true
		push_error("后半程地标或楼梯结构预算未满足，拒绝输出旧占位画面")

	player.auto_input = false
	player.hp = 999
	game.hud.visible = false
	# Game 会直接 step 敌人和货箱；冻结宿主物理，建筑与检查点的 _process 动画仍保留。
	for minion: Node2D in game.minions:
		minion.process_mode = Node.PROCESS_MODE_DISABLED
	for prop: Node2D in game.props:
		prop.process_mode = Node.PROCESS_MODE_DISABLED
	# 转场截图会手动把镜头放在房间接缝；同时关闭 Game._process，避免下一帧又被
	# 常规房间相机目标覆盖。建筑和检查点节点仍各自执行 _process 动画。
	game.set_process(false)
	game.set_physics_process(false)
	_cleanup_audio(game)
	for raw: Dictionary in DATA.ENTITIES:
		var cell: Array = raw.get("cell", [])
		if cell.size() == 2:
			_occupied_cells[Vector2i(int(cell[0]), int(cell[1]))] = true
	for room: Dictionary in game.level.rooms:
		var checkpoint: Array = room.get("checkpoint_cell", [])
		if checkpoint.size() == 2:
			# 比例尺不能盖住实际灯塔，否则截图会误判成“只有背景终端”。
			_occupied_cells[Vector2i(int(checkpoint[0]), int(checkpoint[1]))] = true

	for i in range(20):
		await process_frame
	var rear_rooms: Array[Dictionary] = []
	for room: Dictionary in game.level.rooms:
		var rect: Rect2i = room["rect"]
		if rect.position.x >= 63:
			rear_rooms.append(room)

	# 每个新增房间一张构图图：保留真实敌人、货箱和灯塔作比例/层级参照，但全部冻结。
	for index in range(rear_rooms.size()):
		var room := rear_rooms[index]
		var position := _room_walk_position(room)
		var stem := "shot_extended_%02d_room_%s" % [index + 1,
				String(room.get("room_id", "unknown"))]
		await _place_and_shot(game, player, position, stem)

	# 再为每个相邻房入口拍一张以边界为中心的图，检查色温切换和黑暗包边连续性。
	for index in range(rear_rooms.size()):
		var room := rear_rooms[index]
		var transition := _left_transition_cell(room)
		if transition.x < 0:
			_render_failed = true
			push_error("房间缺少左侧 RoomTransition：%s" % room.get("room_id", "?"))
			continue
		var previous: Dictionary = game.level.rooms[index + 2]
		var stem := "shot_extended_%02d_transition_%s" % [index + 1,
				String(room.get("room_id", "unknown"))]
		await _place_and_transition_shot(game, player, transition, previous, room, stem)

	_cleanup_audio(game)
	boot.free()
	for i in range(3):
		await process_frame
	await create_timer(0.15).timeout
	print("RENDER_RESULT: ", "FAIL" if _render_failed else "PASS")
	quit(1 if _render_failed else 0)


func _room_walk_position(room: Dictionary) -> Vector2:
	var room_rect: Rect2i = room["rect"]
	var main_walk_id := int(DATA.SEMANTIC_IDS["Traversal"]["MainWalk"])
	var center_x := room_rect.position.x + room_rect.size.x * 0.5
	var best := Vector2i(-1, -1)
	var best_score := INF
	for raw in DATA.SEMANTIC_LAYERS["Traversal"]:
		if int(raw[2]) != main_walk_id:
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if not room_rect.has_point(cell):
			continue
		var blocked_near := false
		for dx in range(-2, 3):
			if _occupied_cells.has(cell + Vector2i(dx, 0)):
				blocked_near = true
				break
		var score := absf(cell.x - center_x) + (1000.0 if blocked_near else 0.0)
		if score < best_score:
			best_score = score
			best = cell
	if best.x < 0:
		_render_failed = true
		push_error("房间缺少 MainWalk 视觉比例尺位置：%s" % room.get("room_id", "?"))
		best = Vector2i(room_rect.get_center().x, room_rect.end.y - 2)
	return Vector2(best.x * TS + TS * 0.5, (best.y + 1) * TS - 0.1)


func _left_transition_cell(room: Dictionary) -> Vector2i:
	var room_rect: Rect2i = room["rect"]
	var transition_id := int(DATA.SEMANTIC_IDS["Traversal"]["RoomTransition"])
	var best := Vector2i(-1, -1)
	for raw in DATA.SEMANTIC_LAYERS["Traversal"]:
		if int(raw[2]) != transition_id:
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if room_rect.has_point(cell) and (best.x < 0 or cell.x < best.x):
			best = cell
	return best


func _place_and_shot(game: Node2D, player: KairullPlayer, pos: Vector2,
		file_stem: String) -> void:
	player._clear_dash_visual()
	player.set_state("gun_idle")
	player.position = pos
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680.0, 382.5)
	for i in range(12):
		await process_frame
	await _save_viewport(file_stem)


func _place_and_transition_shot(game: Node2D, player: KairullPlayer, cell: Vector2i,
		left_room: Dictionary, right_room: Dictionary, file_stem: String) -> void:
	var pos := Vector2(cell.x * TS + TS * 0.5, (cell.y + 1) * TS - 0.1)
	player.position = pos
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	player._sync_sprite()
	game._update_room_state()
	var left_rect: Rect2i = left_room["rect"]
	var right_rect: Rect2i = right_room["rect"]
	var left_center_y := (left_rect.position.y + left_rect.size.y * 0.5) * TS
	var right_center_y := (right_rect.position.y + right_rect.size.y * 0.5) * TS
	# 转场镜头以房间接缝为中心，让两侧材质与照明同时进入画面。
	var camera_center := Vector2(right_rect.position.x * TS,
			roundf((left_center_y + right_center_y) * 0.5))
	# BackgroundLayer 依赖 cam_tl 定位全屏近黑底；只改 Camera2D 会露出默认灰色 clear color。
	game.cam_tl = (camera_center - Vector2(680.0, 382.5)).round()
	game.cam.position = game.cam_tl + Vector2(680.0, 382.5)
	for i in range(12):
		await process_frame
	await _save_viewport(file_stem)


func _save_viewport(file_stem: String) -> void:
	var image := get_root().get_texture().get_image()
	var path := "user://%s.png" % file_stem
	var error := image.save_png(path)
	if error != OK or image.is_empty():
		_render_failed = true
	print("  截图 ", file_stem, " -> ", ProjectSettings.globalize_path(path),
			" err=", error)


func _cleanup_audio(game: Node2D) -> void:
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
