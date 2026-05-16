extends CanvasLayer

var player_1: VsPlayer
var player_2: VsPlayer

# 綁定共通介面 (只有血量、體力、魔力是全角色共通的)
@onready var p1_hp = $P1_HpBar
@onready var p1_stamina = $P1_StaminaBar
@onready var p1_mp = $P1_MpBar

@onready var p2_hp = $P2_HpBar
@onready var p2_stamina = $P2_StaminaBar
@onready var p2_mp = $P2_MpBar

# 🌟 這兩個洞，準備用來插入角色的專屬 UI 卡帶！
@onready var p1_custom_ui_anchor = $P1_CustomUI
@onready var p2_custom_ui_anchor = $P2_CustomUI

func _process(_delta: float) -> void:
	if player_1 != null:
		p1_hp.max_value = player_1.max_hp
		p1_stamina.max_value = player_1.max_stamina
		p1_mp.max_value = player_1.max_mp
		
		p1_hp.value = player_1.current_hp
		p1_stamina.value = player_1.current_stamina
		p1_mp.value = player_1.current_mp
		
	if player_2 != null:
		p2_hp.max_value = player_2.max_hp
		p2_stamina.max_value = player_2.max_stamina
		p2_mp.max_value = player_2.max_mp
		
		p2_hp.value = player_2.current_hp
		p2_stamina.value = player_2.current_stamina
		p2_mp.value = player_2.current_mp
