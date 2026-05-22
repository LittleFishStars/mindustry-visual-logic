class_name CSBlock
extends BaseBlock


@export_multiline var template: String
@export var options: Dictionary[String, Variant] = {'a': func (): print(1)}


func _init() -> void:
	super(self.template, self.options)


func _ready() -> void:
	for i in self.get_children(): i.queue_free()
	self.parsing(self.template, self.options)
