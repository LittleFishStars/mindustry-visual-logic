@tool
extends Container


var Editor = preload("res://Scenes/editor.tscn")

@onready var nMenuBar: Control 	= $MenuBar
@onready var nEditors: Control 	= $Editors
@onready var nBackground: Panel = $Panel

@onready var wNotice: Window 	= $NoticeWindow


func _on_sort_children() -> void:
	fit_child_in_rect(self.nMenuBar, Rect2(Vector2.ZERO, Vector2(self.size.x, 0)))
	fit_child_in_rect(self.nEditors, Rect2(0, self.nMenuBar.size.y, self.size.x, self.size.y - self.nMenuBar.size.y))
	fit_child_in_rect(self.nBackground, Rect2(Vector2.ZERO, self.size))


## 新建页面
func new_page(title: StringName, scn: Resource) -> Node:
	var node = scn.instantiate()
	var count = 1
	self.nEditors.add_child(node)
	self.nEditors.current_tab = node.get_index()
	while self.nEditors.has_node(title + str(count)):
		count += 1
	node.name = title + str(count)
	return node


## 文件菜单
func _on_file_id_pressed(id: int) -> void:
	match id:
		0:
			self.new_page("File", self.Editor)
		1:
			# 保存文件
			pass


## 帮助菜单
func _on_help_id_pressed(id: int) -> void:
	match id:
		0:
			# 文档
			pass
		1:
			self.wNotice.show()
		2:
			# 关于
			pass
