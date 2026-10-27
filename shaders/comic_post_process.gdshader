shader_type canvas_item;
// LAST BASTION - comic post-process (overlay pass, keeps the 640x360 pixel base)
//
// 1. luminance-gradient edge detection -> 1px ink outline
// 2. posterization to a small palette (default 8 steps, subtle)
// 3. paper grain modulated around neutral grey so it never crushes blacks
// 4. gore_boost temporarily thickens ink + pushes reds (GoreEvent)
//
// Attach to a full-rect ColorRect on a CanvasLayer *below* the HUD so text
// stays crisp.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D paper_noise : repeat_enable, filter_linear;
uniform float outline_strength : hint_range(0.0, 3.0) = 0.9;
uniform float outline_threshold : hint_range(0.0, 1.0) = 0.22;
uniform float posterize_levels : hint_range(2.0, 32.0) = 8.0;
uniform float posterize_mix : hint_range(0.0, 1.0) = 0.55;
uniform float paper_strength : hint_range(0.0, 1.0) = 0.10;
uniform float saturation : hint_range(0.0, 2.0) = 1.08;
uniform float gore_boost : hint_range(0.0, 2.0) = 0.0;

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec3 col = texture(screen_texture, uv).rgb;

	// --- edge detection on the luminance channel -----------------------------
	// Sample two pixels out so single-pixel dither/rain does not ink the whole
	// frame; only real silhouettes survive.
	vec2 step2 = texel * 2.0;
	float lum_c = luminance(col);
	float lum_r = luminance(texture(screen_texture, uv + vec2(step2.x, 0.0)).rgb);
	float lum_u = luminance(texture(screen_texture, uv + vec2(0.0, step2.y)).rgb);
	float lum_l = luminance(texture(screen_texture, uv - vec2(step2.x, 0.0)).rgb);
	float lum_d = luminance(texture(screen_texture, uv - vec2(0.0, step2.y)).rgb);
	float edge = abs(lum_c - lum_r) + abs(lum_c - lum_u)
		+ abs(lum_c - lum_l) + abs(lum_c - lum_d);

	// --- posterization (blended, so the pixel art keeps its gradients) -------
	// floor() (not round) so dark scenes quantize *down*; rounding up lifts
	// every near-black area to 1/levels and washes the frame out.
	vec3 posterized = floor(col * posterize_levels) / posterize_levels;
	vec3 graded = mix(col, posterized, posterize_mix);

	// --- ink ---------------------------------------------------------------
	float ink = smoothstep(outline_threshold, outline_threshold + 0.18, edge);
	ink *= clamp(outline_strength + gore_boost * 0.9, 0.0, 3.0);
	graded = mix(graded, vec3(0.02, 0.019, 0.018), clamp(ink, 0.0, 0.85));

	// --- paper grain (neutral around 0.5, never crushes the image) ----------
	float paper = luminance(texture(paper_noise, uv * 6.0).rgb);
	graded *= 1.0 + (paper - 0.5) * paper_strength * 2.0;

	// --- gore punch ---------------------------------------------------------
	float redness = clamp(col.r - max(col.g, col.b), 0.0, 1.0);
	graded.r += redness * gore_boost * 0.35;

	// --- saturation ---------------------------------------------------------
	float gray = luminance(graded);
	graded = mix(vec3(gray), graded, saturation);

	COLOR = vec4(graded, 1.0);
}
