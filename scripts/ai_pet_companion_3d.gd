extends Node3D
## AI-Pet-Begleiter in 3D (Kapitel 6.2 der Master-Bible).
## folgt dem Spieler mit Lerp und schwebt sanft.
##
## Abweichung vom Bible-Original: dort wurde die Schwebebewegung nach dem
## Lerp auf die Weltposition addiert (position.y += sin(...) * delta).
## Das sammelt Drift an und kämpft gegen den Lerp. Stattdessen geht der
## Hover als Offset ins Ziel – stabiler und gleiche Optik.

@export var target_player: Node3D
@export var follow_speed: float = 3.0
@export var hover_amplitude: float = 0.2
@export var hover_frequency: float = 2.0

var time_passed: float = 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(target_player):
		return

	time_passed += delta

	var target_pos: Vector3 = target_player.global_position + (target_player.global_transform.basis * Vector3(1.2, 1.5, -1.0))
	target_pos.y += sin(time_passed * hover_frequency) * hover_amplitude
	global_position = global_position.lerp(target_pos, follow_speed * delta)

	look_at(target_player.global_position + Vector3(0, 1.2, 0), Vector3.UP)
