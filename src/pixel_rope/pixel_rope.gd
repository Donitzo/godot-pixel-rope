@tool
extends MeshInstance2D
## A verlet-based pixelated rope class
class_name PixelRope

@export_group('Anchors')

## Start anchor node.
@export var start_node: Node2D
## Whether start anchor is pinned after reset.
@export var start_pinned: bool = true
## End anchor node.
@export var end_node: Node2D
## Whether end anchor is pinned after reset.
@export var end_pinned: bool = true

var _start_pinned: bool:
    get: return start_node != null and start_pinned
var _end_pinned: bool:
    get: return end_node != null and end_pinned

func is_point_pinned(i: int) -> bool:
    return i == 0 and _start_pinned or\
        i == control_point_count - 1 and _end_pinned or\
        _pinned_control_points.has(i)

@export_group('Visuals')

## Draw the rope as a smooth ribbon instead of pixels.
@export var smooth_rope: bool = false

## The alpha of grace pixels. Use 0 to disable.
@export_range(0.0, 1.0) var grace_alpha: float = 0.5:
    set(value):
        grace_alpha = value
        if _material != null:
            _material.set_shader_parameter('grace_alpha', grace_alpha)

## Rope thickness in integers.
@export_range(1, 8) var rope_thickness: int = 1:
    set(value):
        rope_thickness = value
        if _material != null:
            _material.set_shader_parameter('thickness_pixels', rope_thickness)

## The number of pixels per world unit (oversampled on purpose).
@export_range(0.001, 8.0) var pixels_per_unit: float = 2.0
## The fraction of existing pixels the mesh must grow or shrink before being rebuilt (0.2 = 20%)
@export var mesh_rebuild_threshold: float = 0.2

@export_subgroup('Segments')

## List of rope segments.
@export var segments: Array[PixelRopeSegment] = []
## Repeat all segments this number of times.
@export_range(1, 128) var segment_repeats: int = 1
var _normalized_segment_lengths: PackedFloat32Array = PackedFloat32Array()

@export_subgroup('Roll')

## Distance, in world units, that rolling segments are shifted/cycled along the rope.
@export var roll: float
## World units at which rolling segments shift per second.
@export var roll_velocity: float = 32

@export_group('Simulation')

const MAX_CONTROL_POINTS: int = 64
## The number of control points in the rope.
@export_range(2, MAX_CONTROL_POINTS) var control_point_count: int = 16

@export_subgroup('Length')

## The initial length of the rope in world units.
@export var initial_length: float = 50.0
## Whether the initial length is added on top of the length between the start_node to the end_node.
@export var initial_length_is_sag: bool = true

@export_subgroup('Physics')

## How strongly the rope resists compression.
@export_range(0.0, 1.0) var compression_stiffness: float = 0.1
## How strongly the rope resists tension.
@export_range(0.0, 1.0) var tension_stiffness: float = 1.0

## The force on the full rope.
@export var rope_force: Vector2 = Vector2(0.0, 980.0)
## The rope velocity damping per physics step.
@export var rope_damping: float = 0.02
## The number of constrain iterations per physics step.
@export var rope_constraint_iterations: int = 3

@export_subgroup('Controllers')

## Rope controllers allows you to control rope behaviour.
@export var controllers: Array[PixelRopeController] = []

@export_subgroup('Warmup')

## The number of warmup simulation steps.
@export var warmup_steps: int = 32
## The warmup timestep.
@export var warmup_timestep: float = 1.0 / 60.0
## Whether to disable the rope after warmup.
@export var one_shot: bool = false

@export_group('Collision')

## Whether rope control points collide with 2D physics bodies.
@export var collide_with_world: bool = false
## 2D physics collision mask used by rope collision queries.
@export_flags_2d_physics var collision_mask: int = 1
## Distance to push rope points away from hit surfaces.
@export_range(0.0, 32.0) var collision_radius: float = 0.1

@export_subgroup('Response')

## Tangential velocity removed on collision.
@export_range(0.0, 1.0) var collision_friction: float = 0.7
## Normal velocity retained after impact.
@export_range(0.0, 1.0) var collision_restitution: float = 0.2

@export_subgroup('Performance')

## Interval between control points tested for collisions. 1 = test every point. Is fixed.
@export_range(1, 8) var collision_test_point_interval: int = 1
## Collision test time interval in physics ticks for idle rope control points
@export_range(1, 8) var collision_test_idle_stride: int = 4
## How many seconds of non-colliding it takes for a control point to go idle
@export var collision_sleep_seconds: float = 2.0

# Raycast distance from INSIDE a collision shape towards the surface
const _RAYCAST_DISTANCE: float = 8.0

# Shader material
@onready var _material: ShaderMaterial = material as ShaderMaterial

# Array mesh
var _mesh: ArrayMesh

# The resting rope length
var _rope_length: float
var rope_length: float:
    get: return _rope_length
    set(value):
        _rope_length = max(value, 0.001)

        var required_pixel_count: int = max(2, ceili(_rope_length * pixels_per_unit) + 1)
        var change_factor: float = 1 if _pixel_count == 0 else\
            abs(required_pixel_count - _pixel_count) / float(_pixel_count)
        var needs_rebuild: bool = _material != null and (
            _pixel_count == 0 or required_pixel_count != _pixel_count and change_factor >= mesh_rebuild_threshold
        )

        if needs_rebuild:
            _rebuild_mesh()

# The number of pixels in the rope
var _pixel_count: int

# The previous control point positions
var _cp_last: PackedVector2Array = PackedVector2Array()
# The current control point positions
var _cp_next: PackedVector2Array = PackedVector2Array()

# Cut / Pinned control points
var _cut_control_points: PackedFloat32Array = PackedFloat32Array()
var _pinned_control_points: Dictionary[int, Vector2] = {}

# Temporary control points
var _temp_control_points: PackedVector4Array = PackedVector4Array()

# The number of seconds since a control point collided with the world
var _seconds_since_control_point_collision: PackedFloat32Array = PackedFloat32Array()

# Current collision stride
var _collision_tick: int = 0

func _ready() -> void:
    if Engine.is_editor_hint():
        return

    if one_shot:
        set_process(false)
        set_physics_process(false)

    _material = ShaderMaterial.new()
    material = _material
    _material.shader = preload('./shaders/smooth_rope.gdshader')\
        if smooth_rope else preload('./shaders/pixel_rope.gdshader')

    _cut_control_points.resize(MAX_CONTROL_POINTS)
    _temp_control_points.resize(MAX_CONTROL_POINTS)
    _seconds_since_control_point_collision.resize(MAX_CONTROL_POINTS)

    reset()

func reset() -> void:
    if segments.is_empty():
        segments.append(PixelRopeSegment.new())

    # Normalize segment lengths
    _normalized_segment_lengths.resize(segments.size() * segment_repeats)

    var total_segment_length: float = 0.0
    for segment in segments:
        total_segment_length += max(segment.length, 0.0) * segment_repeats

    if total_segment_length <= 1e-6:
        push_error('Segment lengths must add up to more than 0')
        return

    for i in segments.size() * segment_repeats:
        _normalized_segment_lengths[i] = max(segments[i % segments.size()].length, 0.0) / total_segment_length

    var has_start: bool = start_node != null
    var has_end: bool = end_node != null

    if not has_start and not has_end:
        push_error('PixelRope needs a start_node or end_node')
        return

    var a: Vector2 = start_node.global_position if has_start else Vector2.ZERO
    var b: Vector2 = end_node.global_position if has_end else Vector2.ZERO

    if has_start and not has_end:
        b = a + Vector2(0.0, initial_length)
    elif not has_start and has_end:
        a = b - Vector2(0.0, initial_length)

    # Reset cut / pinned control points
    for i in MAX_CONTROL_POINTS:
        _cut_control_points[i] = 0
    
    # Start ropes sleeping
    for i in MAX_CONTROL_POINTS:
        _seconds_since_control_point_collision[i] = collision_sleep_seconds + 1e-6

    _material.set_shader_parameter('control_point_is_cut', _cut_control_points)

    _pinned_control_points.clear()

    # Reset control points
    _cp_last.clear()
    _cp_next.clear()

    for i in control_point_count:
        var t: float = i / float(control_point_count - 1)
        var p: Vector2 = a.lerp(b, t)

        _cp_last.append(p)
        _cp_next.append(p)

    # Set rope length
    if has_start and has_end and initial_length_is_sag:
        rope_length = max(a.distance_to(b) + initial_length, 0.001)
    else:
        rope_length = max(initial_length, 0.001)

    # Update fixed shader uniforms
    _material.set_shader_parameter('control_point_count', control_point_count)
    _material.set_shader_parameter('thickness_pixels', rope_thickness)
    _material.set_shader_parameter('grace_alpha', grace_alpha)

    # Warmup simulation
    for i in warmup_steps:
        _simulate_points(warmup_timestep)
        _constrain_points(warmup_timestep)

    _update_shader_params()

func _rebuild_mesh() -> void:
    # Create pixel vertices
    _pixel_count = max(2, ceili(_rope_length * pixels_per_unit) + 1)

    var vertex_count: int = _pixel_count * 6

    var vertices: PackedVector2Array = PackedVector2Array()
    var colors: PackedColorArray = PackedColorArray()
    var custom0: PackedFloat32Array = PackedFloat32Array()

    vertices.resize(vertex_count)
    colors.resize(vertex_count)
    custom0.resize(vertex_count * 4)

    var segment_index: int = 0
    var segment_end: float = max(_normalized_segment_lengths[0], 0.0)

    for i in _pixel_count:
        var t: float = i / float(_pixel_count - 1)

        while segment_index < segments.size() * segment_repeats - 1 and t >= segment_end:
            segment_index += 1
            segment_end += max(_normalized_segment_lengths[segment_index], 0.0)

        var segment: PixelRopeSegment = segments[segment_index % segments.size()]

        var color: Color = segment.color
        var emission: float = segment.emission
        var roll_t: Vector2 = Vector2.ZERO
        for s in min(int(segment.roll_start_segment), segments.size() * segment_repeats):
            roll_t.x += _normalized_segment_lengths[s]
        for s in min(int(segment.roll_end_segment), segments.size() * segment_repeats):
            roll_t.y += _normalized_segment_lengths[s]
        roll_t = Vector2(min(roll_t.x, 1), min(roll_t.y, 1))

        var base: int = i * 6

        # Position
        vertices[base + 0] = Vector2(0.0, 0.0)
        vertices[base + 1] = Vector2(1.0, 0.0)
        vertices[base + 2] = Vector2(0.0, 1.0)
        vertices[base + 3] = Vector2(1.0, 1.0)
        vertices[base + 4] = Vector2(0.0, 1.0)
        vertices[base + 5] = Vector2(1.0, 0.0)

        for j in 6:
            # Color
            colors[base + j] = color

            var k: int = (base + j) * 4

            # Metadata
            custom0[k + 0] = t
            custom0[k + 1] = emission
            custom0[k + 2] = roll_t.x
            custom0[k + 3] = roll_t.y

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_CUSTOM0] = custom0

    _mesh = ArrayMesh.new()
    _mesh.add_surface_from_arrays(
        Mesh.PRIMITIVE_TRIANGLES,
        arrays,
        [],
        {},
        (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
    )
    mesh = _mesh

    _material.set_shader_parameter('pixel_step', 1.0 / (_pixel_count - 1))

    # Force pixels to always be drawn fully opaque when the rope is not supersampled
    _material.set_shader_parameter('force_full', _rope_length / float(_pixel_count - 1) >= 1.0)

func _update_shader_params() -> void:
    var bounds: Rect2 = Rect2(to_local(_cp_next[0]), Vector2.ZERO)

    # Update control points
    for i in control_point_count:
        var p: Vector2 = to_local(_cp_next[i])

        bounds = bounds.expand(p)

        var tangent: Vector2 = Vector2.ZERO

        var has_left: bool = i > 0
        var has_right: bool = i < control_point_count - 1

        var left_connected: bool = has_left and _cut_control_points[i - 1] < 0.5
        var right_connected: bool = has_right and _cut_control_points[i] < 0.5

        if left_connected and right_connected:
            tangent = (to_local(_cp_next[i + 1]) - to_local(_cp_next[i - 1])) * 0.5
        elif left_connected:
            tangent = to_local(_cp_next[i]) - to_local(_cp_next[i - 1])
        elif right_connected:
            tangent = to_local(_cp_next[i + 1]) - to_local(_cp_next[i])

        _temp_control_points[i] = Vector4(p.x, p.y, tangent.x, tangent.y)

    # Update shader uniforms
    _material.set_shader_parameter('control_points', _temp_control_points)
    _material.set_shader_parameter('roll', roll / _rope_length)

    # Update bounding rect
    var padding: int = rope_thickness
    _mesh.custom_aabb = AABB(Vector3(
        bounds.position.x - padding, bounds.position.y - padding, -1.0),
        Vector3(bounds.size.x + padding * 2, bounds.size.y + padding * 2, 2.0)
    )

func nearest_control_point(world_position: Vector2, min_distance: float) -> int:
    var best_index: int = -1
    var best_distance: float = min_distance * min_distance

    for i in control_point_count:
        var distance: float = _cp_next[i].distance_squared_to(world_position)
        if distance < best_distance:
            best_distance = distance
            best_index = i

    return best_index

# Cut the constraint after a control point
func cut_rope(control_point_index: int) -> void:
    var i: int = clampi(control_point_index, 0, control_point_count - 2)
    _cut_control_points[i] = 1.0
    _material.set_shader_parameter('control_point_is_cut', _cut_control_points)

# Cut the rope near a world position
func cut_rope_at_position(world_position: Vector2, min_distance: float = 8.0) -> bool:
    var i: int = nearest_control_point(world_position, min_distance)
    if i >= 0:
        cut_rope(i)
        return true
    return false

# Pin the rope at a control point
func pin_rope(control_point_index: int, world_position: Vector2, clear: bool = false) -> void:
    var i: int = clampi(control_point_index, 0, control_point_count - 1)
    if clear:
        _pinned_control_points.erase(i)
    else:
        _pinned_control_points[i] = world_position

# Pin the rope near a world position
func pin_rope_at_position(world_position: Vector2, min_distance: float = 8.0, clear: bool = false) -> bool:
    var i: int = nearest_control_point(world_position, min_distance)
    if i >= 0:
        pin_rope(i, world_position, clear)
        return true
    return false

func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint():
        return

    _simulate_points(delta)
    _constrain_points(delta)

func _process(delta: float) -> void:
    if Engine.is_editor_hint():
        queue_redraw()
        return

    roll += roll_velocity * delta

    _update_shader_params()

func _simulate_points(delta: float) -> void:
    for i in control_point_count:
        if is_point_pinned(i):
            continue

        var pc: Vector2 = _cp_next[i]
        var velocity: Vector2 = (pc - _cp_last[i]) * (1.0 - rope_damping)

        _cp_last[i] = pc
        _cp_next[i] = pc + velocity + rope_force * delta * delta

    for controller in controllers:
        if controller.enabled:
            controller.simulate_points(self, delta, _cp_next, control_point_count)

func _constrain_points(delta: float) -> void:
    var pin_start: bool = _start_pinned
    var pin_end: bool = _end_pinned

    var a: Vector2 = start_node.global_position if pin_start else Vector2.ZERO
    var b: Vector2 = end_node.global_position if pin_end else Vector2.ZERO

    var l: int = control_point_count - 1
    var segment_length: float = _rope_length / float(l)

    # Constrain control points
    for i in rope_constraint_iterations:
        for p in _pinned_control_points:
            _cp_next[p] = _pinned_control_points[p]
        if pin_start:
            _cp_next[0] = a
        if pin_end:
            _cp_next[l] = b

        for j in control_point_count - 1:
            # Switch direction every other iteration
            j = j if i % 2 == 0 else control_point_count - 2 - j

            if _cut_control_points[j] > 0.5:
                continue

            var d: Vector2 = _cp_next[j + 1] - _cp_next[j]
            var distance: float = d.length()
            if distance <= 1e-6:
                continue

            var error: float = distance - segment_length

            var stiffness: float
            if error > 0.0:
                stiffness = tension_stiffness
            else:
                stiffness = compression_stiffness

            if stiffness <= 1e-6:
                continue

            var correction: Vector2 = d / distance * error * stiffness

            var p0_pinned: bool = is_point_pinned(j)
            var p1_pinned: bool = is_point_pinned(j + 1)

            if p0_pinned == p1_pinned:
                if not p0_pinned:
                    _cp_next[j] += correction * 0.5
                    _cp_next[j + 1] -= correction * 0.5
            elif p0_pinned:
                _cp_next[j + 1] -= correction
            else:
                _cp_next[j] += correction

    # Axis aligned world collisions
    if collide_with_world:
        const probe_directions: Array[Vector2] = [
            Vector2.RIGHT,
            Vector2.LEFT,
            Vector2.DOWN,
            Vector2.UP,
        ]

        var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state

        var ray_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
            Vector2.ZERO,
            Vector2.ZERO,
            collision_mask
        )
        ray_query.hit_from_inside = false
        
        _collision_tick += 1
        
        for j in control_point_count:
            # Point is skipped or pinned
            if (j % collision_test_point_interval) != 0 or is_point_pinned(j):
                continue
            
            var sleeping: bool = _seconds_since_control_point_collision[j] > collision_sleep_seconds
            _seconds_since_control_point_collision[j] += delta

            # Point is sleeping and staggered
            if sleeping and\
                ((_collision_tick + j / collision_test_point_interval) % collision_test_idle_stride) > 0:
                continue

            var point: Vector2 = _cp_next[j]

            var best_target_position: Vector2 = point
            var best_normal: Vector2 = Vector2.ZERO
            var best_overlap: float = INF

            for direction in probe_directions:
                ray_query.from = point + direction * _RAYCAST_DISTANCE
                ray_query.to = point - direction * collision_radius

                var hit: Dictionary = space_state.intersect_ray(ray_query)
                if hit.is_empty() or hit.normal == Vector2.ZERO:
                    continue

                var normal: Vector2 = hit.normal
                var target_position: Vector2 = hit.position + normal * collision_radius
                var overlap: float = (target_position - point).length_squared()

                if overlap < best_overlap:
                    best_overlap = overlap
                    best_target_position = target_position
                    best_normal = normal

            if best_overlap == INF:
                continue
            
            _seconds_since_control_point_collision[j] = 0

            var movement: Vector2 = best_target_position - _cp_next[j]
            var velocity: Vector2 = _cp_next[j] - _cp_last[j]

            _cp_next[j] = best_target_position
            _cp_last[j] += movement

            var normal_velocity: float = velocity.dot(best_normal)
            if normal_velocity < 0.0:
                var tangent_velocity: Vector2 = velocity - best_normal * normal_velocity
                var new_velocity: Vector2 = tangent_velocity * (1.0 - collision_friction)
                new_velocity += -best_normal * normal_velocity * collision_restitution

                _cp_last[j] = _cp_next[j] - new_velocity

        if pin_start:
            _cp_next[0] = a
        if pin_end:
            _cp_next[l] = b

    for p in control_point_count:
        if is_point_pinned(p):
            _cp_last[p] = _cp_next[p]

# Debug rendering
func _draw() -> void:
    if not Engine.is_editor_hint():
        return

    draw_set_transform_matrix(get_global_transform().affine_inverse())

    if start_node != null:
        var a: Vector2 = start_node.global_position
        draw_circle(a, 1.0, Color.RED, false)

    if end_node != null:
        var b: Vector2 = end_node.global_position
        draw_circle(b, 1.0, Color.ORANGE, false)

        if start_node != null:
            var a: Vector2 = start_node.global_position
            draw_line(a, b, Color.YELLOW)
