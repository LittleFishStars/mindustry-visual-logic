extends Control


@export var list_separation: int = 10

@onready var nBlockKindList: VBoxContainer = $Editor/BlockKindList
@onready var nBlockArea: ScrollContainer = $Editor/EditorSplit/BlockArea

@onready var nArea: SubViewportContainer = $Editor/EditorSplit/EditArea
@onready var nSpace: SubViewport = $Editor/EditorSplit/EditArea/EditSpace
@onready var nCamera: Camera2D = $Editor/EditorSplit/EditArea/EditSpace/Camera

var _block_data: Dictionary
var _current_kind: String

var _now_drag_node: Block
var _drag_offset: Vector2
var _is_dragging: bool


func _ready() -> void:
	_block_data = BlockParse.new().parse()
	for kind in _block_data:
		# 类别列表
		var btn := Button.new()
		btn.text = kind
		btn.pressed.connect(func(): _show_kind(kind))
		nBlockKindList.add_child(btn)
		
		# 块列表
		var kind_list := VBoxContainer.new()
		kind_list.name = kind
		kind_list.size_flags_horizontal = true
		kind_list.size_flags_vertical = true
		kind_list.add_theme_constant_override("separation", self.list_separation)
		kind_list.hide()
		
		# 填充块列表
		for block_name in _block_data[kind]["blocks"]:
			var block := Block.new(kind, block_name, _block_data[kind]["color"])
			block.drag_started.connect(self._on_drag_started.bind(block))
			kind_list.add_child(block)
		nBlockArea.add_child(kind_list)
	_show_kind(_block_data.keys()[0])


func _show_kind(kind: String) -> void:
	if kind == _current_kind:
		return
	if _current_kind:
		nBlockArea.get_node(_current_kind).hide()
	_current_kind = kind
	nBlockArea.get_node(kind).show()


func _on_drag_started(offset: Vector2, node: Block):
	node._is_dragging = false
	self._is_dragging = true
	self._drag_offset = offset
	self._now_drag_node = Block.new(node._kind, node._block_name, node.bg_color)
	self.add_child(self._now_drag_node)
	self._now_drag_node.global_position = node.global_position


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if self._is_dragging:
				self._is_dragging = false
				self._on_drag_ended(event.global_position)
	elif event is InputEventMouseMotion and self._is_dragging:
		self._on_drag_moved(event.global_position)


func _on_drag_moved(pos: Vector2):
	self._now_drag_node.global_position = pos + self._drag_offset

func _on_drag_ended(pos: Vector2):
	self.remove_child(self._now_drag_node)
	if self.nArea.get_global_rect().has_point(pos):
		self.nSpace.add_child(self._now_drag_node)
		self._now_drag_node.position = (
			self.nSpace.get_canvas_transform().affine_inverse() * 
			(pos + self._drag_offset) - 
			self.nArea.global_position
		)
		self.nCamera._on_child_added(self._now_drag_node)
