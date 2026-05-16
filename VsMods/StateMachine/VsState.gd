class_name VsState  # 基礎框架
extends Node2D
# 進入狀態時觸發
func enter() -> void: 
	pass
# 離開狀態時觸發
func exit() -> void:
	pass
# 處理每幀邏輯	
func process_frame(_delta: float) -> VsState:
	return null
# 處理按鍵輸入
func process_input(_event: InputEvent) -> VsState:
	return null
# 處理物理運算
func process_physics(_delta: float) -> VsState:
	return null
