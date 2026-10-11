class_name ExportPart
extends RefCounted

## mlog 导出串的一段：字面量与取值分开装，字面量可含空格，每段可自行决定前面是否插空格。
enum Kind {
	## 原样输出（可以含空格、引号）。
	LITERAL,
	FIELD,
	## 取第一个"可见且有值"的字段的值（对应旧语法的 %a|b）。
	FIRST_VISIBLE,
}

var kind: Kind = Kind.LITERAL
var literal: String = ""
var field: StringName = &""
var fields: Array[StringName] = []
## kind == FIELD 时：该字段是块引用（值形如 `#<节点 id>`），导出换成目标块行号、导入再绑回。
var link: bool = false

## kind == FIELD 时：空值不补 `0`（XML `allow_empty="true"`，注释文本这类字段要它）。
var allow_empty: bool = false

## kind == FIELD 时：该字段是字符串（XML `as="string"`）：引号与转义由导出器加。
var as_string: bool = false

## 本段之前是否插空格（`glue` / `space_before`）：`print "x"` 这种引号紧贴值就靠它。
var space_before: bool = true

static func make_literal(text: String) -> ExportPart:
	var part := ExportPart.new()
	part.kind = Kind.LITERAL
	part.literal = text
	return part


static func make_field(field_id: StringName) -> ExportPart:
	var part := ExportPart.new()
	part.kind = Kind.FIELD
	part.field = field_id
	return part


static func make_first_visible(field_ids: Array[StringName]) -> ExportPart:
	var part := ExportPart.new()
	if field_ids.size() == 1:
		part.kind = Kind.FIELD
		part.field = field_ids[0]
	else:
		part.kind = Kind.FIRST_VISIBLE
		part.fields = field_ids
	return part


func set_text(value: String) -> void:
	literal = value


func describe() -> String:
	match kind:
		Kind.LITERAL:
			return literal
		Kind.FIELD:
			return "%" + String(field)
		_:
			var names: PackedStringArray = []
			for field_id in fields:
				names.append(String(field_id))
			return "%" + "|".join(names)
