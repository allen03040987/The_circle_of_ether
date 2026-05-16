shader_type canvas_item;

// 🌟 改用 float (0.0 代表關閉，1.0 代表開啟純白)
uniform float active_flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);
	
	// 🌟 使用 mix 函數：當 active_flash 為 1.0 時，RGB 強制變為 1.0 (純白)，但保留圖片原本的透明度 (alpha)
	COLOR = mix(base_color, vec4(1.0, 1.0, 1.0, base_color.a), active_flash);
}