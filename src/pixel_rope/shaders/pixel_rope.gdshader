shader_type canvas_item;

// Pixel size
uniform float thickness_pixels = 2.0;

// Adjust these overlaps to optimize pixel spacing

// Minimum overlap for full pixel coverage
const float FULL_COVERAGE = 0.55;
// Minimum overlap for gracing a pixel
const float GRACE_COVERAGE = 0.2;

// Whether to force full coverage
uniform float force_full = 0.0;

const int MAX_CONTROL_POINTS = 64;

// The alpha of gracing pixels.
uniform float grace_alpha = 0.5;

// The number of active control points
uniform int control_point_count = 16;
uniform vec4 control_points[MAX_CONTROL_POINTS];
uniform float control_point_is_cut[MAX_CONTROL_POINTS];
// xy = position
// zw = tangent

// Normalized rope-fraction distance between adjacent pixels
uniform float pixel_step = 1.0;

// Roll offset in rope-fraction length
uniform float roll = 0.0;

// Varyings
varying vec2 v_world;
varying vec4 v_color;
varying float v_emission;

// Hermite curve
vec2 hermite(vec2 p0, vec2 m0, vec2 p1, vec2 m1, float u) {
    float u2 = u * u;
    float u3 = u2 * u;

    return
        (2.0 * u3 - 3.0 * u2 + 1.0) * p0 +
        (u3 - 2.0 * u2 + u) * m0 +
        (-2.0 * u3 + 3.0 * u2) * p1 +
        (u3 - u2) * m1;
}

// Hermite curve direction
vec2 hermite_derivative(vec2 p0, vec2 m0, vec2 p1, vec2 m1, float u) {
    float u2 = u * u;

    return
        (6.0 * u2 - 6.0 * u) * p0 +
        (3.0 * u2 - 4.0 * u + 1.0) * m0 +
        (-6.0 * u2 + 6.0 * u) * p1 +
        (3.0 * u2 - 2.0 * u) * m1;
}

// Rope segment index i and fraction u and rope fraction t
void rope_segment(float t, out int i, out float u) {
    float x = t * float(control_point_count - 1);
    i = clamp(int(floor(x)), 0, control_point_count - 2);
    u = x - float(i);
}

// Sample rope position at rope fraction t
vec2 sample_rope_position(float t) {
    int i;
    float u;
    rope_segment(t, i, u);

    vec2 p0 = control_points[i].xy;
    vec2 p1 = control_points[i + 1].xy;

    vec2 m0 = control_points[i].zw;
    vec2 m1 = control_points[i + 1].zw;

    return hermite(p0, m0, p1, m1, u);
}

// Sample rope position and tangent at rope fraction t
void sample_rope_full(float t, out vec2 p, out vec2 tangent) {
    int i;
    float u;
    rope_segment(t, i, u);

    vec2 p0 = control_points[i].xy;
    vec2 p1 = control_points[i + 1].xy;

    vec2 m0 = control_points[i].zw;
    vec2 m1 = control_points[i + 1].zw;

    p = hermite(p0, m0, p1, m1, u);

    vec2 d = hermite_derivative(p0, m0, p1, m1, u);
    tangent = dot(d, d) < 1e-6 ? vec2(1.0, 0.0) : normalize(d);
}

float distance_to_pixel_exit(vec2 p, vec2 dir) {
    vec2 cell_min = floor(p + vec2(0.5)) - vec2(0.5);
    vec2 cell_max = cell_min + vec2(1.0);

    vec2 side = mix(cell_min, cell_max, step(vec2(0.0), dir));

    vec2 safe_dir = mix(vec2(1e-6), dir, step(vec2(1e-6), abs(dir)));
    vec2 t = (side - p) / safe_dir;

    vec2 valid = step(vec2(1e-6), abs(dir));
    t = mix(vec2(1e20), t, valid);

    return max(min(t.x, t.y), 0.0);
}

float pixel_path_length(vec2 p, vec2 tangent) {
    float forward = distance_to_pixel_exit(p, tangent);
    float backward = distance_to_pixel_exit(p, -tangent);

    return forward + backward;
}

// Roll rope fraction t with looping
float apply_roll(float t, float start, float end) {
    float l = end - start;
    return l > 0.0 ? start + mod(t - start + roll, l) : t;
}

void vertex() {
    float source_t = CUSTOM0.x;
    float emission = CUSTOM0.y;
    float roll_start = CUSTOM0.z;
    float roll_end = CUSTOM0.w;

    v_emission = emission;

    // Get current and previous pixel rope fraction t (rolled)
    float tc = apply_roll(source_t, roll_start, roll_end);
    float tp = apply_roll(max(source_t - pixel_step, 0.0), roll_start, roll_end);

    // Check if rope is cut
    int ti;
    float tu;
    rope_segment(tc, ti, tu);
    bool is_cut = control_point_is_cut[ti] > 0.5;

    // Get pixel positions
    vec2 pc;
    vec2 tangent;
    sample_rope_full(tc, pc, tangent);
    vec2 pp = sample_rope_position(tp);

    ivec2 ic = ivec2(floor(pc + vec2(0.5 + 1e-6)));
    ivec2 ip = ivec2(floor(pp + vec2(0.5 + 1e-6)));

    // Compare pixels
    bool same_as_previous =
        source_t > pixel_step * 0.5 &&
        ic.x == ip.x &&
        ic.y == ip.y;

    float path_length = pixel_path_length(pc, tangent);
    float full = step(FULL_COVERAGE, path_length + force_full);
    float grace = step(GRACE_COVERAGE, path_length);
    float alpha = mix(grace * grace_alpha, 1.0, full) * float(!same_as_previous) * float(!is_cut);

    v_color = vec4(COLOR.rgb, COLOR.a * alpha);

    VERTEX = vec2(ic) + VERTEX * vec2(thickness_pixels);
    v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    if (v_color.a < 1e-6) {
        discard;
    }

    // For custom effects, you can use:
    // - v_color: rope color
    // - v_emission: emission value
    // - v_world: world-space fragment position

    COLOR = v_color;

    COLOR.rgb += v_emission * (0.5 + 0.5 * sin(TIME * 6.0)) * vec3(1.0);
}