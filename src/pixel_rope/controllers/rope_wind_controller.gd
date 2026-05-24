extends PixelRopeController
## Simulates wind on the rope
class_name RopeWindController

@export var speed_a: float = 2.0
@export var speed_b: float = 10.0
@export var y_frequency: float = 0.1
@export var strength: float = 2.0

func simulate_points(
    rope: PixelRope,
    delta: float,
    control_points: PackedVector2Array,
    point_count: int
) -> void:
    var time: float = Time.get_ticks_msec() * 0.001

    for i in point_count:
        if rope.is_point_pinned(i):
            continue

        var wind: float = sin(time * speed_a + control_points[i].y * y_frequency) *\
            sin(time * speed_b) * strength

        control_points[i] += Vector2(wind, 0.0) * delta
