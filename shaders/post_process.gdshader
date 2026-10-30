shader_type canvas_item;
// LAST BASTION - full-screen post-process overlay.
// Applies: chromatic aberration, radial blur, damage vignette, blood distortion.
// Attach to a full-rect ColorRect on a CanvasLayer above the game world (below HUD).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float chromatic_aberration : hint_range(0.0, 0.03) = 0.0;
uniform float radial_blur_strength : hint_range(0.0, 1.0) = 0.0;
uniform float damage_vignette : hint_range(0.0, 1.0) = 0.0;
uniform float blood_distortion : hint_range(0.0, 1.0) = 0.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.05;
uniform float time : hint_range(0.0, 1000.0) = 0.0;
uniform vec2 screen_size : hint_range(0, 1000) = vec2(640, 360);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);

	// --- chromatic aberration (radial, toward screen center) ---
	vec2 aberration = centered * chromatic_aberration * 0.15;
	float r = texture(screen_texture, uv + aberration).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - aberration).b;
	vec3 col = vec3(r, g, b);

	// --- radial blur (only in kill cam direction) ---
	if (radial_blur_strength > 0.001) {
		float blur_amount = radial_blur_strength * 0.05;
		vec3 accum = col;
		for (int i = 1; i < 8; i++) {
			float scale = 1.0 - float(i) * blur_amount;
			vec2 sample_uv = vec2(0.5) + centered * scale;
			accum += texture(screen_texture, sample_uv).rgb;
		}
		col = mix(col, accum / 9.0, radial_blur_strength * 0.6);
	}

	// --- damage vignette (red blood wester edge) ---
	if (damage_vignette > 0.001) {
		float vignette = smoothstep(0.0, 0.85, 1.0 - dist);
		float pulse = 0.5 + 0.5 * sin(time * 14.0) * damage_vignette;
		col = mix(col, vec3(0.45, 0.02, 0.01), vignette * damage_vignette * 0.45 * pulse);
	}

	// --- blood distortion (screen-space wobble from ear-ringing) ---
	if (blood_distortion > 0.001) {
		float wobble = sin(time * 8.0) * blood_distortion * 0.012;
		float wobble2 = cos(time * 13.0) * blood_distortion * 0.010;
		vec2 distort = vec2(wobble, wobble2) * (1.0 - dist);
		col = texture(screen_texture, uv + distort).rgb;
	}

	// --- scanline (subtle CRT retention) ---
	if (scanline_intensity > 0.001) {
		float scan = sin(uv.y * screen_size.y * 3.14159 * 2.0 + time * 3.0);
		col *= 1.0 - scanline_intensity * 0.10 * maxf(0.0, scan);
	}

	COLOR = vec4(col, 1.0);
}
