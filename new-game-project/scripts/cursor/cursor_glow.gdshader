shader_type canvas_item;

// The cursor's hover glow, as in the art file (.claude/docs/superpowers/specs/
// 2026-10-17-themed-cursor-art.html): the art drawn 20% brighter over two soft glows
// in the colour, one tight and one wide. Off, the cursor is the plain texture.
//
// A glow is the texture's alpha blurred, tinted, and drawn behind the art. The blur is
// a Gaussian (standard deviation half the radius, as in CSS) estimated from TAPS
// samples of the alpha, laid out on a spiral so that every sample counts the same.
// Radii are in texture pixels: the cursor's textures are RENDER_SCALE times their drawn
// size, so 4 and 8 base pixels are 16 and 32 here. The texture's transparent margin
// (CursorArt.GLOW_MARGIN) leaves room for them.

uniform bool glowing = false;
uniform vec4 glow1 : source_color = vec4(0.71, 0.55, 1.0, 1.0);
uniform vec4 glow2 : source_color = vec4(0.49, 0.31, 0.88, 1.0);
uniform float brightness = 1.2;
uniform float r1_px = 16.0;
uniform float r2_px = 32.0;

const int TAPS = 64;
// How far the blur reaches, in standard deviations: all but the faintest tail.
const float REACH = 3.0;
// The angle between neighbouring samples of a spiral that never lines up with itself.
const float GOLDEN_ANGLE = 2.39996323;
// The CSS filter chains its two drop-shadows, so the wide glow is cast by the art
// together with the tight glow, not by the art alone. Raising the wide glow's
// coverage to this power matches that chain (measured against it) without a second
// blur of the first.
const float CHAIN = 1.5;
// Over this many texture pixels the glow fades out towards the texture's border. The
// wide glow's faint tail is still there when the margin runs out, and the border
// would show as a hard edge.
const float FADE_PX = 24.0;

// `top` over `bottom`, both straight (not premultiplied) colour.
vec4 over(vec4 top, vec4 bottom) {
	float a = top.a + bottom.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	if (glowing) {
		// Both blurs in one pass over the same offsets, in standard deviations.
		float sigma1 = r1_px * 0.5;
		float sigma2 = r2_px * 0.5;
		float inside = 1.0 - exp(-0.5 * REACH * REACH);   // the share of a 2D Gaussian within REACH
		float sum1 = 0.0;
		float sum2 = 0.0;
		for (int i = 0; i < TAPS; i++) {
			// Evenly spaced shares of the Gaussian's mass, each at the distance that holds it.
			float share = (float(i) + 0.5) / float(TAPS) * inside;
			float dist = sqrt(-2.0 * log(1.0 - share));
			float angle = float(i) * GOLDEN_ANGLE;
			vec2 dir = vec2(cos(angle), sin(angle)) * dist * TEXTURE_PIXEL_SIZE;
			sum1 += texture(TEXTURE, UV + dir * sigma1).a;
			sum2 += texture(TEXTURE, UV + dir * sigma2).a;
		}
		vec2 to_border = min(UV, 1.0 - UV) / TEXTURE_PIXEL_SIZE;
		float fade = smoothstep(0.0, FADE_PX, min(to_border.x, to_border.y));
		float cover1 = fade * sum1 / float(TAPS);
		float cover2 = fade * (1.0 - pow(1.0 - sum2 / float(TAPS), CHAIN));
		vec4 g1 = vec4(glow1.rgb, glow1.a * cover1);
		vec4 g2 = vec4(glow2.rgb, glow2.a * cover2);
		vec4 lit = vec4(min(art.rgb * brightness, vec3(1.0)), art.a);
		COLOR = over(lit, over(g1, g2));
	} else {
		COLOR = art;
	}
}
