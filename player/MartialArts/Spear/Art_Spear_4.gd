class_name Art_Spear_4
extends MartialArt

## 🌟 這招自己的設定資料，不佔用武器本體 (Spear.gd) 的任何字典——
## 跟太刀的武藝 (Art_Katana_2/3) 一樣，武藝的資料就近放在武藝自己的檔案裡
const CONFIG = {
	"anim": "spear/c2", "hitbox_name": "C2",
	"type": Damage.Type.HEAVY, "max_hits": 5, "interval": 0.15, "sticky": true,
	"knockback": Vector2(220.0, -200.0), "pull": true, "shake": 15.0, "shake_on_hit_only": true,
	"base_dmg": 50, "energy": 3, "hit_sfx_type": "hit",
	"action_type": Weapon.ActionType.MARTIAL_ART,
}

func _ready() -> void:
	# 🌟 排查發現這裡本來完全沒設，會吃到 MartialArt.gd 基底的預設值 10.0（等於武藝能量全滿才能放一次）；
	# 這個賦值一定要放在 _ready()，不能放在 enter() 裡——Weapon.execute_martial_art() 是在呼叫 enter() 之前
	# 就先讀 energy_cost 扣費了，放在 enter() 裡設定的話這次施放永遠讀到舊值，要等下一次才生效
	energy_cost = 3.0 # 先比照太刀最貴的招式抓一個數字，實際數值麻煩自己測試調整

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.is_attacking = true
	weapon.combo_step = 21

	# 極限轉向特權
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon._play_martial_art_attack(CONFIG)
	print("🌪️ 發動大範圍聚怪武藝！")

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# 21 的物理邏輯非常單純，就是套用基準摩擦力
	new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)
