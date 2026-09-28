@tool
extends GLTFDocumentExtension

# Stylized albedo-only assets have no specular highlight: Godot's default 0.5 gives a plastic
# sheen. glTF can say so (KHR_materials_specular), but Godot 4.6 doesn't read that extension,
# so every imported material gets its specular set to 0 here. Registered for editor imports by
# plugin.gd and for runtime imports by scripts/godot_validate.gd.


func _import_post_parse(state: GLTFState) -> Error:
	for material in state.get_materials():
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).metallic_specular = 0.0
	return OK
