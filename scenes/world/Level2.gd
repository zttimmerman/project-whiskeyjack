extends Node3D


func _ready() -> void:
	$NavigationRegion3D.bake_navigation_mesh()
	$EndTrigger.body_entered.connect(_on_end_trigger_body_entered)


func _on_end_trigger_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		var label := $CanvasLayer/EndLabel
		label.modulate = Color(1, 1, 1, 0)
		label.visible = true
		var tween := create_tween()
		tween.tween_property(label, "modulate", Color(1, 1, 1, 1), 1.5)
