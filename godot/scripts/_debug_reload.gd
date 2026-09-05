extends SceneTree
## 复现：换弹结束后按住方向键，移动是否自动恢复
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var db := AtlasDB.new("res://assets/clips", "res://assets/clips/bat/bat_atlas.json")
	var level := CorridorLevel.new()
	level.build(false)
	var p := KairullPlayer.new()
	p.auto_input = false
	p.db = db
	p.level = level
	get_root().add_child(p)
	p.spawn = level.spawn
	p.reset_to_spawn()
	for i in range(30):
		p.step(1.0 / 60)

	p.gun_ammo = 3
	p.start_reload()
	print("换弹开始 state=", p.state, " reloading=", p.reloading)

	# 情景A：换弹完成瞬间已按住 D（用户场景：一直按着）
	# 但 D 一按就会打断——所以真实场景是：换弹完成前用户松开着，
	# 完成后按着 D 不动？直接模拟：换弹快跑完时按下 D 并保持
	for i in range(160):   # 2.8s ≈ 168 步
		if i == 150:
			p.keys = {KEY_D: true}   # 临完成前按住
		p.step(1.0 / 60)
	print("完成后 state=", p.state, " reloading=", p.reloading,
		" vx=", p.vx, " ammo=", p.gun_ammo)
	for i in range(30):
		p.step(1.0 / 60)
	print("30步后 state=", p.state, " vx=", p.vx, " clip=", p.current_clip(),
		" frame=", p.frame)

	# 情景B：换弹完成后才按 D
	p.position = Vector2(800, 19 * 32 - 0.1)
	p.vy = 0.0
	p.gun_ammo = 2
	p.keys = {}
	for i in range(30):
		p.step(1.0 / 60)
	p.start_reload()
	for i in range(180):
		p.step(1.0 / 60)
	p.keys = {KEY_D: true}
	p.step(1.0 / 60)
	print("B: 完成后按D state=", p.state, " vx=", p.vx)
	quit(0)
