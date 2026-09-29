@tool
extends EditorPlugin

# Registers the glTF import extension for every .glb/.gltf the editor imports.
# Existing assets pick it up on reimport.

var _extension: GLTFDocumentExtension


func _enter_tree() -> void:
	_extension = preload("res://addons/stylized_materials/no_specular_gltf.gd").new()
	GLTFDocument.register_gltf_document_extension(_extension)


func _exit_tree() -> void:
	GLTFDocument.unregister_gltf_document_extension(_extension)
