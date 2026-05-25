shader_type canvas_item;

// Individual quad overlap
const float quad_overlap = 0.01;

// Antialiasing
uniform float antialiasing = 1.0;

// Pixel size
uniform float thickness_pixels = 2.0;

const int MAX_CONTROL_POINTS = 64;

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
varying float v_side;

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

// Roll rope fraction t with looping
float apply_roll(float t, float start, float end) {
    float l = end - start;
    return l > 0.0 ? start + mod(t - start + roll, l) : t;
}

void vertex() {
    float source_t0 = CUSTOM0.x;
    float source_t1 = min(source_t0 + pixel_step, 1.0);
    float emission = CUSTOM0.y;
    float roll_start = CUSTOM0.z;
    float roll_end = CUSTOM0.w;

    v_emission = emission;

    float tp = apply_roll(max(source_t0 - pixel_step, 0.0), roll_start, roll_end);
    float t0 = apply_roll(source_t0, roll_start, roll_end);
    float t1 = apply_roll(source_t1, roll_start, roll_end);

    // Clamp wrapping
    t0 = mix(t0, mix(roll_start, roll_end, step(tp, t0)), step(pixel_step * 2.0, abs(t0 - tp)));
    t1 = mix(t1, mix(roll_start, roll_end, step(t1, t0)), step(pixel_step * 2.0, abs(t1 - t0)));

    // Sample rope positions and tangents
    vec2 p0;
    vec2 p1;
    vec2 tangent0;
    vec2 tangent1;

    sample_rope_full(t0, p0, tangent0);
    sample_rope_full(t1, p1, tangent1);

    vec2 normal0 = vec2(-tangent0.y, tangent0.x);
    vec2 normal1 = vec2(-tangent1.y, tangent1.x);

    vec2 tangent = normalize(p1 - p0);

    float along = VERTEX.x;
    float side = VERTEX.y - 0.5;
    v_side = side * 2.0;

    vec2 center = mix(
        p0 - tangent * quad_overlap,
        p1 + tangent * quad_overlap,
        along
    );

    vec2 normal = normalize(mix(normal0, normal1, along));

    VERTEX = center + normal * side * thickness_pixels;

    // Check if this rope section is cut
    int i0;
    float u0;
    rope_segment(t0, i0, u0);

    int i1;
    float u1;
    rope_segment(t1, i1, u1);

    float not_cut0 = 1.0 - step(0.5, control_point_is_cut[i0]);
    float not_cut1 = 1.0 - step(0.5, control_point_is_cut[i1]);

    // Ignore the last segment and cut sections
    float valid =  not_cut0 * not_cut1 * step(source_t0, 1.0 - 1e-6);

    v_color = vec4(COLOR.rgb, COLOR.a * valid);
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

    // Antialiasing
    COLOR.a *= smoothstep(0.0, fwidth(v_side) * antialiasing, 1.0 - abs(v_side));
}
