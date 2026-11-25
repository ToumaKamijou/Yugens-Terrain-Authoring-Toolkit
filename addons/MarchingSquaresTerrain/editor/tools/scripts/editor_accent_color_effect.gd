@tool
extends RichTextEffect
class_name RichTextEditorAccent


var bbcode := "EDITOR_ACCENT"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	char_fx.color = EditorInterface.get_base_control().get_theme_color("accent_color", "Editor").lightened(0.6)
	return true
