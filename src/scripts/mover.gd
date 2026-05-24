extends Node2D
class_name Mover

@export var spin: bool = false
@export var speed: float = 100.0
@export var distance: float = 100.0
@export var pause_time: float = 0.5

var _start_x: float = 0.0
var _direction: float = -1
var _paused: float = false

func _ready() -> void:
    _start_x = position.x

func _process(delta: float) -> void:
    if spin:
        rotation += speed * delta
        return

    if _paused:
        return

    position.x += _direction * speed * delta

    if abs(position.x - _start_x) >= distance:
        position.x = _start_x + _direction * distance
        pause_then_turn()

func pause_then_turn() -> void:
    _paused = true
    await get_tree().create_timer(pause_time).timeout
    _direction *= -1
    _paused = false
