shader_type canvas_item;
// 「锈蚀频率」漫画后处理：色阶量化 + 纸张颗粒 + 信号干扰扭曲。
// 平时克制档案感；Gore 事件时 intensity 短暂增强（暴力瞬间漫画化）。
// Godot 4：屏幕纹理必须显式声明为 hint_screen_texture uniform（P0-1）。
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;   // gore 增强 0->1
uniform float interference : hint_range(0.0, 1.0) = 0.0; // 信号干扰（最终 Boss）
uniform float posterize_levels : hint_range(3.0, 12.0) = 6.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// 信号干扰：横向撕裂
	if (interference > 0.01) {
		float band = floor(uv.y * 36.0);
		float shift = (hash(vec2(band, floor(TIME * 14.0))) - 0.5) * 0.012 * interference;
		uv.x += shift * step(0.72, hash(vec2(band, floor(TIME * 7.0))));
	}
	vec3 col = texture(SCREEN_TEXTURE, uv).rgb;
	// 色阶量化（Posterization）
	float levels = mix(10.0, posterize_levels, max(intensity, 0.35));
	col = floor(col * levels + 0.5) / levels;
	// 旧纸张颗粒
	float grain = hash(uv * vec2(640.0, 360.0) + floor(TIME * 3.0)) * 0.055;
	col += grain - 0.027;
	// 冷档案色调（轻微去饱和 + 偏青）
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), 0.18);
	col.b += 0.015;
	// Gore 瞬间：轻微提饱和 + 压暗边缘（vignette 反差）
	if (intensity > 0.01) {
		col.r += intensity * 0.05;
		float d = distance(uv, vec2(0.5));
		col *= 1.0 - smoothstep(0.55, 0.95, d) * intensity * 0.35;
	}
	// 干扰噪点
	if (interference > 0.01) {
		float noise = hash(uv * vec2(320.0, 180.0) + floor(TIME * 24.0));
		col = mix(col, vec3(noise), interference * 0.12);
	}
	COLOR = vec4(col, 1.0);
}
