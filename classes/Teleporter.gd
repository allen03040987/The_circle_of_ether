class_name Teleporter # 門
extends Interactable
@export_file("*.tscn") var path: String # 設置新地圖
@export var entry_point: String         # 設置入口位置

# 傳送門邏輯
func interact() -> void:
	super() # 執行基類的邏輯
	Game.change_scene(path , {entry_point = entry_point}) # 調用整個傳送邏輯
