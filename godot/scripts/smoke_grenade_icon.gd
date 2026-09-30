extends Node2D
## 小罐体是代码原生像素图形；地上补给与头顶携带槽共用，不新增模糊素材。

const CANISTER_TEX := preload("res://assets/maps/hazards/smoke_canister.png")


func _draw() -> void:
	# 携带与地上补给都只画罐体，不再夹带R或其他字符；按键说明交给操作提示。
	# 2026-09-28 像素罐体精灵（tools/art/hazards/build_hazard_sprites.py）；地上补给与头顶携带槽共用。
	draw_texture(CANISTER_TEX, Vector2(-7, -11))
