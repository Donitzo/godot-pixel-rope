extends Resource
## A single-colored segment in a pixel rope
class_name PixelRopeSegment

## Fraction of the rope occupied by this segment. Is normalized automatically.
@export var length: float = 1.0
## The segment fill color.
@export var color: Color = Color.WHITE
## Emission strength applied to this segment.
@export_range(0.0, 8.0) var emission: float = 0.0
## Color roll interval start segment. Use 0 for both to disable rolling.
@export_range(0, 64) var roll_start_segment: int = 0
## Color roll interval end segment (exclusive). Use 0 for both to disable rolling.
@export_range(0, 64) var roll_end_segment: int = 0
