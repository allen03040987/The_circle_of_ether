class_name Art_Katana_12
extends MartialArt

# 🌟 數據更新：改為 4 段連擊，並附帶些微向前的擊退力
const CONFIG = {
	"anim": "katana/attack_c1_2",
	"hitbox_name": "C1",
	"type": Damage.Type.HEAVY,
	"max_hits": 4,                     # 🌟 變成 4 段判定
	"interval": 0.1,                   # 🌟 每 0.1 秒打擊一次
	"sticky": true,                    # 🌟 啟用黏著打擊，把敵人捲在空中
	"knockback": Vector2(50.0, -400.0),# 🌟 微調擊退：加上 X 軸 50 的微幅向前推力
	"shake": 15.0,                     # 稍微調低單下震動，避免 4 連擊把螢幕震飛
	"shake_on_hit_only": true,
	"base_dmg": 180,                   # 🌟 總傷維持約 720 (180 x 4 = 720)
	"hit_sfx_type": "hit",
	"energy": 3,                       # 單下能量獲取降低，靠多段彌補
	"switch": 4,
	"iai_reward": 2,
	"spark_type": 1,
	"spark_scale": 0.8,
	"action_type": Weapon.ActionType.SKILL
}

@export var launch_start_time: float = 0.1      
@export var launch_duration: float = 0.1       
@export var vertical_launch_speed: float = -650.0 
@export var forward_launch_speed: float = 380.0 # 🌟 新增：起跳時稍微向前的推力速度

var is_launch_triggered: bool = false
var launch_timer: float = 0.0

func enter() -> void:
	super.enter()
	weapon.step_cooldown = 0.15
	weapon.air_attack_locked = false
	weapon.is_attacking = true
	is_launch_triggered = false
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	weapon.combo_step = 12
	weapon._play_martial_art_attack(CONFIG)

func get_current_velocity(delta: float) -> Vector2:
	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	if player.animation_player.current_animation_position >= launch_start_time and not is_launch_triggered:
		is_launch_triggered = true
		launch_timer = launch_duration
		
	if is_launch_triggered:
		if launch_timer > 0: 
			launch_timer -= delta
			new_y = vertical_launch_speed * speed_mult
			# 🌟 解除橫向鎖死 (0.0)，改為依照面向給予稍微向前的位移！
			new_x = player.direction * forward_launch_speed * speed_mult 
		else: 
			# 🌟 滯空緩降期間保留一點慣性，讓手感更平滑，不要瞬間煞車停住
			new_x = move_toward(new_x, 0.0, base_friction * 0.5)
			if new_y < 0:
				new_y = move_toward(new_y, 0.0, player.default_gravity * 2.0 * delta)
			else:
				new_y += player.default_gravity * delta
	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	return is_launch_triggered
