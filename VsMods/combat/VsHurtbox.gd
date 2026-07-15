class_name VsHurtbox
extends Area2D
## VS 模式受擊判定框（被動，由 VsHitbox 驅動偵測）

signal hurt(hitbox: VsHitbox)

## 由 VsHitbox._on_area_entered() 在偵測到重疊時呼叫
func receive_hit(hitbox: VsHitbox) -> void:
	emit_signal("hurt", hitbox)
