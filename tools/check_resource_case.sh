#!/usr/bin/env bash
# ==========================================================================
# 資源路徑大小寫檢查工具 (Resource Path Case Checker)
#
# 用途：Windows 檔案系統不分大小寫，preload("res://Foo.WAV") 就算實際檔名是
# "foo.wav" 在編輯器裡也完全正常運作，只有匯出後 (或搬到 Linux/Mac 這種真的
# 分大小寫的系統) 才會炸掉，變成一個編輯器裡永遠看不到的地雷。
# 這個腳本掃描 .gd/.tscn/.tres 裡所有 res:// 資源路徑，跟硬碟上的實際檔名
# 逐一比對大小寫，抓出兩種問題：
#   1. CASE MISMATCH：路徑確實存在，但大小寫跟參照的字串不一致
#   2. NOT FOUND：路徑對應的檔案根本不存在（不管大小寫），例如資源被改名/刪除
#      但程式碼裡忘了更新引用
#
# 用法：在專案根目錄下執行
#   bash tools/check_resource_case.sh
# ==========================================================================

set -u
cd "$(dirname "$0")/.." || exit 1

mismatch_count=0
missing_count=0
checked_count=0

declare -A seen

check_path() {
	local res_path="$1"
	# 已經檢查過的路徑不要重複檢查
	if [ -n "${seen[$res_path]:-}" ]; then return; fi
	seen[$res_path]=1

	local rel="${res_path#res://}"
	local dir base actual
	dir=$(dirname "$rel")
	base=$(basename "$rel")
	checked_count=$((checked_count + 1))

	if [ ! -d "$dir" ]; then
		echo "❌ NOT FOUND (目錄不存在): $res_path"
		missing_count=$((missing_count + 1))
		return
	fi

	if [ -f "$rel" ]; then
		return # 精確比對就找到了，完全沒問題
	fi

	# 精確比對失敗，改用不分大小寫找一次，看看是不是「大小寫不一致」還是「根本沒有這個檔案」
	actual=$(find "$dir" -maxdepth 1 -iname "$base" 2>/dev/null | head -1 | xargs -r basename)

	if [ -n "$actual" ]; then
		echo "⚠️  CASE MISMATCH: 程式碼寫 \"$base\"，實際檔名是 \"$actual\"  (於 $dir/)"
		echo "    完整路徑: $res_path"
		mismatch_count=$((mismatch_count + 1))
	else
		echo "❌ NOT FOUND (連大小寫都對不上，檔案可能已被改名/刪除): $res_path"
		missing_count=$((missing_count + 1))
	fi
}

echo "🔍 掃描 .gd 檔案裡的 preload()/load() ..."
while IFS= read -r path; do
	check_path "$path"
done < <(
	grep -rohE '(preload|load)\("res://[^"]+"\)' --include="*.gd" . 2>/dev/null \
		| grep -oE 'res://[^"]+'
)

echo "🔍 掃描 .tscn/.tres 檔案裡的 ext_resource path= ..."
while IFS= read -r path; do
	check_path "$path"
done < <(
	grep -rohE 'path="res://[^"]+"' --include="*.tscn" --include="*.tres" . 2>/dev/null \
		| sed -E 's/^path="(.*)"$/\1/'
)

echo ""
echo "=========================================="
echo "掃描完成：共檢查 $checked_count 條不重複的資源路徑"
echo "  大小寫不一致: $mismatch_count"
echo "  完全找不到:   $missing_count"
echo "=========================================="

if [ "$mismatch_count" -gt 0 ] || [ "$missing_count" -gt 0 ]; then
	exit 1
fi
exit 0
