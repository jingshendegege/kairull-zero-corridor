extends SceneTree
## 排查：霓虹 tile 样式是否生效（采样生成纹理像素）

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M01_NEON
	CorridorLevel.active_tile_style = {"name": "neon"}
	var level := CorridorLevel.new()
	get_root().add_child(level)
	level.build(true)
	var src: TileSetAtlasSource = level.tilemap.tile_set.get_source(0)
	var img := src.texture.get_image()
	# tile1（# 顶）：中心像素 & 顶沿像素
	print("tile1 top: ", img.get_pixel(1 * 32 + 16, 0), " mid: ", img.get_pixel(1 * 32 + 16, 16))
	print("tile2 mid: ", img.get_pixel(2 * 32 + 16, 16))
	print("tile4 top: ", img.get_pixel(4 * 32 + 16, 0), " mid: ", img.get_pixel(4 * 32 + 16, 16))
	# 单元格确认：kiosk c82 r17 应该画了 tile
	print("cell c82 r17: ", level.tilemap.get_cell_atlas_coords(Vector2i(82, 17)))
	quit(0)
