class_name BossParalyzedState
extends BossState

# 記錄癱瘓處於哪個階段：0=跪下, 1=喘息循環, 2=起身
var paralyze_step: int = 0

func enter() -> void:
	print("💫 BOSS 韌性崩潰！開始跪下...")
	
	# 破韌終極視覺與觸覺回饋
	if CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(25.0, 0.2)
	
	# 拔除任何殘留的攻擊判定
	boss.disable_hitbox()
	boss.velocity.x = 0.0
	
	# 🎬 階段 0：播放剛癱瘓跪下的動畫
	paralyze_step = 0
	
	# ⚠️ 請將這裡的字串換成你實際的「跪下」動畫名稱
	boss.play_safe_anim("paralyze_start") 

func physics_update(delta: float) -> void:
	boss.velocity.y += boss.default_gravity * delta
	boss.custom_move_and_slide()
	
	# ==========================================
	# 🎬 癱瘓三階段動畫派生
	# ==========================================
	if paralyze_step == 0:
		# 當「跪下」動畫播完，自動進入階段 1
		if not boss.animation_player.is_playing():
			paralyze_step = 1
			# ⚠️ 替換為你的「跪下呼吸」動畫名稱
			boss.play_safe_anim("paralyze_loop")
			
	elif paralyze_step == 1:
		# 在喘息階段：等待 Stats 系統把韌性充滿 (is_broken 變回 false)
		if boss.stats and not boss.stats.is_broken:
			print("🔥 BOSS 韌性恢復！準備起身...")
			paralyze_step = 2
			# ⚠️ 替換為你的「爬起」動畫名稱
			boss.play_safe_anim("paralyze_end")
			
	elif paralyze_step == 2:
		# 當「起身」動畫播完，正式恢復戰鬥！
		if not boss.animation_player.is_playing():
			state_machine.transition_to("Decision")
