extends Resource
## Rope controllers can add custom control point behaviour
class_name PixelRopeController

## Whether the controller is enabled
@export var enabled: bool = true

func simulate_points(
    _rope: PixelRope,
    _delta: float,
    _control_points: PackedVector2Array,
    _point_count: int
) -> void:
    pass
