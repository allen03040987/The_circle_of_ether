class_name VsArtRegistry
## 武藝名稱字串 → 腳本路徑的對照表。VsCharacterRegistry 的角色武藝池只存純字串
## （不像主遊戲 equipped_martial_arts 直接存完整資源路徑），所以需要這一層
## 查表——VsPlayer._load_arts() 施放時用 art_slots 裡的字串來這裡查腳本。
##
## 六招全部對應腳本齊了。get_art_script() 找不到就回傳 null，
## VsPlayer._load_arts() 對應處理成「這個槽位選了但沒東西」，不會報錯——
## 保留這個容錯路徑供之後新增角色/武藝時使用。
const SCRIPTS: Dictionary = {
	"Art_Clotty_1": "res://VsMods/player/arts/Art_Clotty_1.gd",
	"Art_Clotty_2": "res://VsMods/player/arts/Art_Clotty_2.gd",
	"Art_Clotty_3": "res://VsMods/player/arts/Art_Clotty_3.gd",
	"Art_Clotty_4": "res://VsMods/player/arts/Art_Clotty_4.gd",
	"Art_Clotty_5": "res://VsMods/player/arts/Art_Clotty_5.gd",
	"Art_Clotty_6": "res://VsMods/player/arts/Art_Clotty_6.gd",
}

static func get_art_script(art_name: String) -> Script:
	if SCRIPTS.has(art_name):
		return load(SCRIPTS[art_name])
	return null
