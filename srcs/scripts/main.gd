@tool
extends Container


@onready var nMenuBar: Control 	= $MenuBar
@onready var nEditors: Control 	= $Editors
@onready var nBackground: Panel = $Panel

@onready var wNotice: Window 	= $NoticeWindow

var Editor = preload("res://srcs/scenes/editor.tscn")

var custom_cursor 		= preload("res://assets/sprites/cursors/cursor.png")
var ibeam_cursor 		= preload("res://assets/sprites/cursors/ibeam.png")
var hand_cursor 		= preload("res://assets/sprites/cursors/hand.png")
var hsize_cursor 		= preload("res://assets/sprites/cursors/hsize.png")
var vsize_cursor 		= preload("res://assets/sprites/cursors/vsize.png")
var bdiagsize_cursor 	= preload("res://assets/sprites/cursors/bdiagsize.png")
var fdiagsize_cursor 	= preload("res://assets/sprites/cursors/fdiagsize.png")


func _ready() -> void:
	# 设置鼠标指针
	Input.set_custom_mouse_cursor(custom_cursor, Input.CURSOR_ARROW, Vector2(32, 32))
	Input.set_custom_mouse_cursor(ibeam_cursor, Input.CURSOR_IBEAM, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hand_cursor, Input.CURSOR_POINTING_HAND, Vector2(32, 32))
	Input.set_custom_mouse_cursor(vsize_cursor, Input.CURSOR_VSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(hsize_cursor, Input.CURSOR_HSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(bdiagsize_cursor, Input.CURSOR_BDIAGSIZE, Vector2(32, 32))
	Input.set_custom_mouse_cursor(fdiagsize_cursor, Input.CURSOR_FDIAGSIZE, Vector2(32, 32))
	
	# 创建初始编辑器
	self.new_editor()


func _on_sort_children() -> void:
	fit_child_in_rect(self.nMenuBar, Rect2(Vector2.ZERO, Vector2(self.size.x, 0)))
	fit_child_in_rect(self.nEditors, Rect2(0, self.nMenuBar.size.y, self.size.x, self.size.y - self.nMenuBar.size.y))
	fit_child_in_rect(self.nBackground, Rect2(Vector2.ZERO, self.size))


## 新建页面: 
## 将 [param scn] 添加到标签页，默认名称为 [param title] 。
func new_page(title: StringName, scn: Resource) -> Node:
	var node = scn.instantiate()
	var count = 1
	self.nEditors.add_child(node)
	self.nEditors.current_tab = node.get_index()
	while self.nEditors.has_node(title + str(count)):
		count += 1
	node.name = title + str(count)
	return node

## 新建编辑器页面
func new_editor():
	self.new_page(tr("File", "main"), self.Editor)


## 文件菜单
func _on_file_id_pressed(id: int) -> void:
	match id:
		0:
			self.new_editor()
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
