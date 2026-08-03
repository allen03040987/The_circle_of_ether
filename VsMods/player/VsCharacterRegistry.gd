class_name VsCharacterRegistry
## 角色 id → 場景路徑/武藝池的對照表。跟 VsArtRegistry 同一套 pattern
## （純靜態 Dictionary + lookup function，不掛 autoload）。
##
## 目前只有 "Clotty" 一個角色，scene_path 指向既有的 VsPlayer.tscn——
## 之後 Part B（Inherited Scene 拆分）完成、驗證過 VsPlayerClotty.tscn 沒問題後，
## 只需要改這裡的 scene_path 一行，不影響其他程式碼。
const CHARACTERS: Dictionary = {
	"Clotty": {
		"display_name": "Clotty",
		"scene_path": "res://VsMods/player/VsPlayerClotty.tscn",
		"arts": [
			"Art_Clotty_1", "Art_Clotty_2", "Art_Clotty_3",
			"Art_Clotty_4", "Art_Clotty_5", "Art_Clotty_6",
		],
	},
	"Naihe": {
		# 場景 VsPlayerNaihe.tscn（原本是 VsPlayerClotty.tscn 的原樣複製，用來
		# 驗證選角畫面能不能處理「兩個角色」）。武藝從 2026-08-01 起改成移植自
		# 主遊戲關底 BOSS「奈何橋」（enemies/boss/BossNaihe/）自己的招式庫，不是
		# 另一把武器——目前只完成 1~4（attack_6 地刺／attack_8／attack_7／
		# dash_back 後撤），5、6 待使用者說明後再補。
		"display_name": "奈何",
		"scene_path": "res://VsMods/player/VsPlayerNaihe.tscn",
		"arts": [
			"Art_Naihe_1", "Art_Naihe_2", "Art_Naihe_3", "Art_Naihe_4",
		],
	},
	"Asatsubaki": {
		# 佔位角色（2026-08-03）——場景 VsPlayerAsatsubaki.tscn 是 VsPlayerClotty.tscn
		# 的原樣複製（含獨立的 AsatsubakiAnimLib.tres，不跟 Clotty 共用同一份
		# AnimationLibrary 檔案——共用會導致其中一邊改動畫時把另一邊的動畫庫
		# 一起改壞，Naihe 當初踩過這個坑，見 CLAUDE.md「VsMods 選角色系統」）。
		# 武藝暫時沿用 Clotty 的六招，等使用者說明真正的招式來源後再替換，
		# 屆時只需要換這裡的 arts/display_name，跟 Naihe 走過的路一樣。
		# skill_script：她第一個真正屬於自己的機制（血影召喚／附身），見
		# VsSkill_Asatsubaki.gd／CLAUDE.md「VsMods Asatsubaki 血影機制」。
		"display_name": "Asatsubaki",
		"scene_path": "res://VsMods/player/VsPlayerAsatsubaki.tscn",
		"arts": [
			"Art_Clotty_1", "Art_Clotty_2", "Art_Clotty_3",
			"Art_Clotty_4", "Art_Clotty_5", "Art_Clotty_6",
		],
		"skill_script": "res://VsMods/player/states/VsSkill_Asatsubaki.gd",
	},
	"Mech": {
		# 佔位角色（2026-08-03）——場景 VsPlayerMech.tscn 是 VsPlayerClotty.tscn
		# 的原樣複製（含獨立的 MechAnimLib.tres，不跟 Clotty 共用同一份
		# AnimationLibrary 檔案，理由同 Naihe/Asatsubaki，見 CLAUDE.md
		# 「VsMods 選角色系統」）。武藝/美術/招式來源都還沒定案，使用者明確
		# 表示先不用管，沿用 Clotty 的六招當佔位，等後續說明後再替換
		# display_name/arts/scene_path 裡的貼圖，跟 Naihe/Asatsubaki 走過的路一樣。
		"display_name": "Mech",
		"scene_path": "res://VsMods/player/VsPlayerMech.tscn",
		"arts": [
			"Art_Clotty_1", "Art_Clotty_2", "Art_Clotty_3",
			"Art_Clotty_4", "Art_Clotty_5", "Art_Clotty_6",
		],
	},
	"Ripple": {
		# 佔位角色（2026-08-03）——場景 VsPlayerRipple.tscn 是 VsPlayerClotty.tscn
		# 的原樣複製（含獨立的 RippleAnimLib.tres），同上一個條目的理由。
		"display_name": "Ripple",
		"scene_path": "res://VsMods/player/VsPlayerRipple.tscn",
		"arts": [
			"Art_Clotty_1", "Art_Clotty_2", "Art_Clotty_3",
			"Art_Clotty_4", "Art_Clotty_5", "Art_Clotty_6",
		],
	},
}

const DEFAULT_CHARACTER := "Clotty"

static func get_scene(character_id: String) -> PackedScene:
	var path: String = CHARACTERS.get(character_id, {}).get("scene_path", "")
	return load(path) if path != "" else null

static func get_arts(character_id: String) -> Array:
	return CHARACTERS.get(character_id, {}).get("arts", [])

static func get_display_name(character_id: String) -> String:
	return CHARACTERS.get(character_id, {}).get("display_name", character_id)

## 空字串＝沿用 VsPlayerBase.tscn 內建的靜態 VsSkill 節點（絕大多數角色）；
## 有值則是這個角色專屬的技能腳本路徑，VsPlayer._load_skill() 會動態換掉靜態
## 節點，見該函式與 CLAUDE.md「VsMods Asatsubaki 血影機制」。
static func get_skill_script(character_id: String) -> String:
	return CHARACTERS.get(character_id, {}).get("skill_script", "")

static func all_ids() -> Array:
	return CHARACTERS.keys()
