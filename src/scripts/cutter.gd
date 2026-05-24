extends Node

@onready var ropes: Node = $Ropes

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            for rope in ropes.get_children():
                if rope.start_node != null and rope.start_node.get_parent().name in ['Coil1', 'Coil2', 'Gear'] or\
                    rope.end_node != null and rope.end_node.get_parent().name in ['Coil1', 'Coil2', 'Gear']:
                    continue

                if rope.cut_rope_at_position(event.position):
                    return
