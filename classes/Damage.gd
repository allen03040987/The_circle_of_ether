class_name Damage
extends RefCounted
## 傷害數據封裝包 (Damage Data Payload)

enum Type { 
	NO_STUN,
	LIGHT,  
	HEAVY,  
	THROW  
}

enum SourceType {
	MELEE,      
	PROJECTILE, 
	ASSIST      
}

var amount: int
var source: Node2D = null
var type: Type = Type.LIGHT
var source_type: SourceType = SourceType.MELEE
var knockback_force: Vector2 = Vector2.ZERO
var blocks_stagger: bool = false ## 這下攻擊有沒有被受擊方的霸體/強霸體擋掉硬直/擊退（傷害本身可能還是有，只是不強制轉場）——由 Player.gd::_on_hurtbox_hurt() 算好塞進來
