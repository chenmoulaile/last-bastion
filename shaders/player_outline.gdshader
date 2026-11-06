shader_type canvas_item;
// wp10-dots-visibility（P1-3）：玩家 1px 半透暖白轮廓描边。
// 审计实测（夜间街道）：角色主色亮度 31/255、紧邻背景 13.9/255，对比度 1.03:1
// ——深色军装在暗街上不可辨。本 shader 沿轮廓外圈 1px 画
// Color(0.92,0.9,0.85,0.35) 半透暖白线，zoom=4 下为锐利轮廓线，不改变本体像素
// （保持像素风）。
// 注意：Godot 4 canvas_item 进入 fragment() 时 COLOR 已预乘 TEXTURE 采样
// （本体直接再乘会得到 tex² 变黑；透明像素 COLOR=0 会使描边消失），
// 因此在 vertex() 里先把顶点色（含 modulate/CanvasModulate 链）存入 varying。

varying vec4 v_tint;

uniform vec4 outline_color : source_color = vec4(0.92, 0.9, 0.85, 0.35);
uniform float outline_width : hint_range(1.0, 4.0) = 1.0;

// 帧限幅采样宏：越出当前 48px 帧横区间/图外的采样按透明计。
// （Godot 的内置 TEXTURE 只能在 fragment/light 中访问，故用宏在调用点展开。）
#define FRAME_ALPHA(UV2) \
	(((UV2).x >= x0 && (UV2).x < x1 && (UV2).y >= 0.0 && (UV2).y < fh) \
			? texture(TEXTURE, (UV2)).a : 0.0)

void vertex() {
	v_tint = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.5) {
		// 本体像素：纹理 × 顶点色（等同默认输出，保持像素原样）。
		COLOR = tex * v_tint;
	} else {
		// 透明像素：8 邻域（1px）内存在本体即描边。
		// 角色条带全部是 48x48 帧的均匀横排（tools/assert_no_stray_dots.py 同款
		// 切帧），当前帧的 UV 横区间可由 UV 自身推算；采样点越出本帧则视为透明
		// ——否则贴帧边的帧会读到相邻帧的像素，沿帧缝描出假轮廓。
		vec2 ps = TEXTURE_PIXEL_SIZE;
		float fw = 48.0 * ps.x;
		float ix = floor(UV.x / fw);
		float x0 = ix * fw;
		float x1 = (ix + 1.0) * fw;
		float fh = 48.0 * ps.y;
		vec2 o = ps * outline_width;
		float na = 0.0;
		na = max(na, FRAME_ALPHA(UV + vec2(o.x, 0.0)));
		na = max(na, FRAME_ALPHA(UV + vec2(-o.x, 0.0)));
		na = max(na, FRAME_ALPHA(UV + vec2(0.0, o.y)));
		na = max(na, FRAME_ALPHA(UV + vec2(0.0, -o.y)));
		na = max(na, FRAME_ALPHA(UV + o));
		na = max(na, FRAME_ALPHA(UV - o));
		na = max(na, FRAME_ALPHA(UV + vec2(o.x, -o.y)));
		na = max(na, FRAME_ALPHA(UV + vec2(-o.x, o.y)));
		float m = step(0.5, na);
		COLOR = vec4(outline_color.rgb, outline_color.a * m) * v_tint;
	}
}
