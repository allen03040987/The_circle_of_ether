class_name MechlAttack1State
extends VsPlayerAttackState # 🌟 直接繼承公用的第一段普攻！

func enter() -> void:
	# 1. 先呼叫老爸（老爸會去播動畫）
	super.enter()
	
# 🌟 神級修正：透過 player 去找，而且只找到 "Hitbox" 這層就好！
	var my_hitbox = player.get_node_or_null("Graphics/Hitbox") as VsHitbox as VsHitbox
	
	if my_hitbox != null:
		# 3. 呼叫大腦注入 80 點基礎傷害與 Buff
		player.buff_hitbox(my_hitbox, 80.0)
		print("✅ 成功注入基礎傷害 80！目前層數：", player.current_sheathe_stacks)
	else:
		print("❌ 慘了！找不到判定框，路徑寫錯了！")
		
