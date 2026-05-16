class_name BossDeathState
extends BossState

signal died # 宣告死亡訊號，專門用來通知大門開鎖

func enter() -> void:
	print("💀 奈何橋已被擊敗！")
	
	# 播放死亡動畫 (請確保 AnimationPlayer 裡有 "die" 這個動畫)
	boss.play_safe_anim("die")
	
	# 拔除剎車與動能，讓他原地倒下
	boss.velocity.x = 0.0
	
	# 🛡️ 強制關閉所有判定框，防止屍體繼續殺人，也防止玩家繼續鞭屍觸發受擊
	boss.disable_hitbox()
	if boss.hurtbox:
		var shape = boss.hurtbox.get_node_or_null("CollisionShape2D")
		if shape:
			shape.set_deferred("disabled", true)
			
	# 🌟 1. 大聲廣播「我死啦！」，這樣上一回合寫的 Area2D 觸發器就會聽到並開門！
	if boss.has_signal("died"):
		boss.died.emit()
		
	# 🌟 2. 監聽死亡動畫，等動畫播完再處理屍體
	if not boss.animation_player.animation_finished.is_connected(_on_animation_finished):
		boss.animation_player.animation_finished.connect(_on_animation_finished)

func physics_update(delta: float) -> void:
	# 屍體依然要受重力影響，防止如果他在空中被打死，會浮在半空中
	boss.velocity.y += boss.default_gravity * delta
	boss.custom_move_and_slide()
	
# 🌟 3. 動畫播完後的最終處理
func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "die":
		print("💨 BOSS 化為塵埃...")
		
		
		boss.queue_free()
	
