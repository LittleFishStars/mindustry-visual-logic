class_name DocumentPage
extends Control

## 应用内文档页（帮助 → Document）：左边章节，右边富文本。
##
## 正文不在代码里：每页一个文件放在 [constant DOCS_DIR]，文件名排序决定章节顺序，
## 首行是章节名、其余是 BBCode 正文 —— 加一页只需往那个文件夹里丢一个文件。
## 它不是 [LogicEditorTab]（存盘 / 导出 / 撤销在它上面是空操作）。

const DOCS_DIR: String = "res://docs"
const EXTENSION: String = "bbcode"
## 一个文档文件都没读到时的提示（导出时漏掉 docs/ 最容易出现）。
const MISSING_HINT: String = "[b]找不到文档文件[/b]：%s/*.%s\n导出时请把 docs/ 加进「Filters to export non-resource files/folders」。"

@onready var nChapters: VBoxContainer = %Chapters
@onready var nTitle: Label = %Title
@onready var nBody: RichTextLabel = %Body

## 章节：`{"title": …, "body": …}`，按文件名排序。
var _sections: Array[Dictionary] = []
var _current: int = -1


func _ready() -> void:
	_sections = _load_sections()
	for index in _sections.size():
		var button := Button.new()
		button.text = String(_sections[index].get("title", "?"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _show_section(index))
		nChapters.add_child(button)
	if _sections.is_empty():
		nTitle.text = "文档"
		nBody.text = MISSING_HINT % [DOCS_DIR, EXTENSION]
		return
	_show_section(0)


## 读 [constant DOCS_DIR] 下的文档文件：文件名排序 → 首行章节名，其余正文。
func _load_sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(DOCS_DIR):
		return out
	var names := DirAccess.get_files_at(DOCS_DIR)
	names.sort()
	for file_name in names:
		if file_name.get_extension().to_lower() != EXTENSION:
			continue
		var text := FileAccess.get_file_as_string(DOCS_DIR.path_join(file_name))
		if text == "":
			push_warning("文档文件为空或读不出来：%s" % file_name)
			continue
		var parts := text.split("\n", true, 1)
		out.append({
			"title": parts[0].strip_edges(),
			"body": parts[1] if parts.size() > 1 else "",
		})
	return out


func _show_section(index: int) -> void:
	if index < 0 or index >= _sections.size():
		return
	_current = index
	nTitle.text = String(_sections[index].get("title", ""))
	nBody.text = String(_sections[index].get("body", ""))
	nBody.scroll_to_line(0)
	for i in nChapters.get_child_count():
		var button := nChapters.get_child(i) as Button
		if button != null:
			button.set_pressed_no_signal(i == index)
