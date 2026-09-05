extends SceneTree
## 真窗口局部美术验收；不写项目配置，不用headless截图冒充正常渲染。

const SMOKE := preload("res://scripts/smoke_tactics.gd")
const OUTPUT := "C:/Users/Administrator/Documents/ChatGPT/游戏制作/work/chrono-freight-before-20260905/smoke-visual"
const WIDE_OUTPUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/chrono-freight-20260905"

class Stage extends Node2D:
	func solid_at(_x: float, y: float) -> bool:
		return y >= 448
	func is_platform(_x: float, _y: float) -> bool:
		return false
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 540), Color("#090e16"))
		draw_rect(Rect2(30, 96, 900, 352), Color("#243941"))
		for x in range(40, 940, 56):
			draw_rect(Rect2(x, 110, 2, 336), Color("#14262d"))
		for y in range(124, 447, 32):
			draw_line(Vector2(30, y), Vector2(930, y), Color("#1b2d35"), 1, false)
		draw_rect(Rect2(30, 445, 900, 3), Color("#a5b9ad"))
		draw_rect(Rect2(30, 448, 900, 27), Color("#172830"))
		for x in range(38, 930, 32):
			draw_rect(Rect2(x, 455, 23, 12), Color("#32454b"), false, 1)
		draw_string(ThemeDB.fallback_font, Vector2(36, 43), "SMOKE / 3X HORIZONTAL COVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#c6eee0"))
		draw_string(ThemeDB.fallback_font, Vector2(36, 73), "672 px wide  |  192 px high  |  4.8 seconds  |  same throw range", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#8eb8b8"))
		draw_string(ThemeDB.fallback_font, Vector2(104, 505), "LEFT WING / COVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#adc5c4"))
		draw_string(ThemeDB.fallback_font, Vector2(405, 505), "CENTER / ICON ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#a2d8cf"))
		draw_string(ThemeDB.fallback_font, Vector2(715, 505), "RIGHT WING / COVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#adc5c4"))


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = Vector2i(960, 540)
	get_root().content_scale_size = Vector2i(960, 540)
	get_root().title = "烟雾战术 - 真窗口局部验收"
	var stage := Stage.new()
	get_root().add_child(stage)
	var db := AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json", "res://assets/clips/hero/hero_atlas.json"])
	var actors: Array[KairullPlayer] = []
	for x in [176, 480, 784]:
		var actor := KairullPlayer.new()
		actor.db = db
		actor.auto_input = false
		actor.spawn = Vector2(x, 447.9)
		actor.z_index = 10
		stage.add_child(actor)
		actor._sync_sprite()
		actors.append(actor)
	var smoke := SMOKE.new()
	stage.add_child(smoke)
	smoke.setup(stage, [], actors[1])
	actors[1].set_carried_smoke(true)
	actors[1].dash_cooldown_t = 1.0
	actors[1]._sync_dash_cooldown_ui()
	actors[1].aim_override = Vector2(790, 438)
	smoke.spawn_pickup(Vector2(895, 447.9))
	smoke.deploy_cloud(Vector2(480, 445))
	smoke.step(0.6)
	for actor in actors:
		actor.set_smoke_cover(smoke.contains_actor(actor))
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	get_root().get_texture().get_image().save_png(OUTPUT + "/01-carry-trajectory-and-smoke.png")
	DirAccess.make_dir_recursive_absolute(WIDE_OUTPUT)
	get_root().get_texture().get_image().save_png(WIDE_OUTPUT + "/烟雾-三倍横向范围.png")
	get_root().get_texture().get_image().save_png(WIDE_OUTPUT + "/烟雾-携带图标-不按R无轨迹.png")
	assert(not smoke._preview_visible, "没有按R时不能显示轨迹")
	actors[1].keys = {KEY_R: true}
	smoke.step(0.0)
	assert(smoke._preview_visible, "按住R才显示轨迹")
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(WIDE_OUTPUT + "/烟雾-按住R瞄准-虚线抛物线.png")
	actors[1].keys.clear()
	smoke.step(0.0)
	assert(not smoke._preview_visible, "松R立刻隐藏轨迹")
	actors[1].z_index = 50
	actors[1].set_time_focus(true)
	actors[1]._sync_sprite()
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(OUTPUT + "/02-smoke-with-time-focus.png")
	print("SMOKE_VISUAL_RESULT: PASS / ", OUTPUT)
	stage.queue_free()
	await process_frame
	quit()
