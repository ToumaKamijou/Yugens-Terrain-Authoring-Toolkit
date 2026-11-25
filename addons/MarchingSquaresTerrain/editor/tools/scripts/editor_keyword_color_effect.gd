@tool
extends RichTextEffect
class_name RichTextEditorKeyword


var bbcode := "EDITOR_KEYWORD"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	char_fx.color = EditorInterface.get_editor_settings().get_setting("text_editor/theme/highlighting/keyword_color").lightened(0.3)
	return true
