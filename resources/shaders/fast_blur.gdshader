shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float radius : hint_range(0.0, 20.0) = 20.0;   // blur size in pixels
uniform float darken : hint_range(0.0, 1.0) = 0.05;   // dims the background a bit

const int TAPS = 5;   // kernel is (2*TAPS+1)^2 = 121 samples per pixel

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float sigma = max(radius / 2.5, 0.001);
	float step_px = radius / float(TAPS);   // pixel spacing between samples

	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int x = -TAPS; x <= TAPS; x++) {
		for (int y = -TAPS; y <= TAPS; y++) {
			vec2 o = vec2(float(x), float(y)) * step_px;
			float w = exp(-dot(o, o) / (2.0 * sigma * sigma));
			sum += texture(screen_texture, SCREEN_UV + o * px).rgb * w;
			total += w;
		}
	}
	COLOR = vec4(sum / total * (1.0 - darken), 1.0);
}