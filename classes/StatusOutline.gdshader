shader_type canvas_item;
// 通用狀態輪廓描邊——霸體(黃)/無敵(紅)共用同一份，只是套用時給不同的 line_color。
// 原理：偵測貼圖本身透明的邊緣像素旁邊有沒有不透明的鄰居，有的話畫上描邊色。
//
// 🛡️ frame_uv_min/frame_uv_max：這隻角色的貼圖是多格 spritesheet (hframes/vframes)，
// 直接用 TEXTURE_PIXEL_SIZE 往鄰居採樣會採到隔壁格的內容，在畫面上/下冒出不該有的描邊雜點。
// 呼叫端 (Player.gd) 每幀依目前 frame 算出這一格的 UV 範圍傳進來，採樣超出這個範圍就當作透明處理。

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform float line_thickness : hint_range(0.0, 5.0) = 1.5;
uniform float outline_alpha : hint_range(0.0, 1.0) = 1.0; // 漸進漸出用的整體強度
uniform vec2 frame_uv_min = vec2(0.0, 0.0);
uniform vec2 frame_uv_max = vec2(1.0, 1.0);

// 🔧 TEXTURE 這種內建取樣器只有在 fragment()/vertex() 裡才看得到，自訂函式要用的話得自己收一個 sampler2D 參數
float sample_alpha_in_frame(sampler2D tex, vec2 uv) {
	if (uv.x < frame_uv_min.x || uv.x > frame_uv_max.x || uv.y < frame_uv_min.y || uv.y > frame_uv_max.y) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);
	vec2 texel = TEXTURE_PIXEL_SIZE * line_thickness;

	float edge_alpha = 0.0;
	edge_alpha += sample_alpha_in_frame(TEXTURE, UV + vec2(texel.x, 0.0));
	edge_alpha += sample_alpha_in_frame(TEXTURE, UV + vec2(-texel.x, 0.0));
	edge_alpha += sample_alpha_in_frame(TEXTURE, UV + vec2(0.0, texel.y));
	edge_alpha += sample_alpha_in_frame(TEXTURE, UV + vec2(0.0, -texel.y));
	edge_alpha = min(edge_alpha, 1.0) * outline_alpha * line_color.a; // line_color.a 拿來當這個狀態自己的「最大不透明度」

	vec4 outline = vec4(line_color.rgb, edge_alpha);
	COLOR = mix(outline, base_color, base_color.a);
}
