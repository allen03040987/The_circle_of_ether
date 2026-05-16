shader_type canvas_item;

// 這三個是你可以從屬性面板直接調整的參數
uniform int dist = 2; // 陰影距離
uniform vec4 color: source_color = vec4(0.0, 0.0, 0.0, 0.5); // 陰影顏色與透明度
uniform float angle: hint_range(0.0, 360.0) = 90.0; // 陰影角度

varying vec2 main_uv;
varying vec2 shadow_uv;

void vertex() {
	// 這個 Shader 最神的地方：它會自動把圖片網格「撐大」，這樣陰影才不會被裁切掉！
	vec2 uv = TEXTURE_PIXEL_SIZE * float(dist * 2);
	vec2 uv_half = uv * 0.5;
	vec2 uv_dist = uv + 1.0;
	
	vec2 shadow_direction = (vec4(cos(radians(angle)), sin(radians(angle)), 0.0, 1.0) * MODEL_MATRIX).xy;
	
	VERTEX *= uv_dist;
	
	main_uv = UV * uv_dist - uv_half;
	shadow_uv = main_uv - shadow_direction * uv_half;
}

void fragment() {
	// 擷取陰影形狀
	float shadow_amt = texture(TEXTURE, shadow_uv).a
		* step(-1.0, -shadow_uv.x)
		* step(-1.0, -shadow_uv.y)
		* step(0.0, shadow_uv.x)
		* step(0.0, shadow_uv.y);
	
	// 套用陰影顏色
	COLOR = color * shadow_amt;
	
	// 擷取原始圖片顏色
	vec4 main_color = texture(TEXTURE, main_uv)
		* step(-1.0, -main_uv.x)
		* step(-1.0, -main_uv.y)
		* step(0.0, main_uv.x)
		* step(0.0, main_uv.y);
	
	// 將重疊區域變黑
	COLOR = mix(COLOR, vec4(0.0, 0.0, 0.0, 1.0), main_color.a);

	// 將原始圖片疊加回陰影之上
	COLOR += main_color * main_color.a;
}