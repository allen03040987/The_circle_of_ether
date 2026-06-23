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
