class_name ExportPart
extends RefCounted

## mlog 导出串的一段。
##
## 旧实现把整条导出串写成空格分隔的字符串，于是[b]带空格的字面量根本没法表达[/b]
## （`print "hello world"` 会被切碎成三段）。新格式把字面量与取值分开装，
## 字面量里可以有任意空格，而且每段可以自己决定前面要不要空格。
enum Kind {
	## 原样输出（可以含空格、引号）。
	LITERAL,
	## 取某个字段的值。
	FIELD,
	## 取第一个"可见且有值"的字段的值（对应旧语法的 %a|b）。
	FIRST_VISIBLE,
}

var kind: Kind = Kind.LITERAL
## kind == LITERAL 时使用。
var literal: String = ""
## kind == FIELD 时使用。
var field: StringName = &""
## kind == FIRST_VISIBLE 时的候选字段（按序取第一个可见且有值的）。
var fields: Array[StringName] = []
## kind == FIELD 时：该字段是[b]块引用[/b]（值形如 `#<节点 id>`，见 [method LogicGraph.make_link_ref]）。
##
## 引用不直接进 mlog：导出时由 [MlogExporter] 解析成目标块所在的行号，
## 导入时再由 [MlogImporter] 把行号绑回块引用 —— 两端问的是同一个标记。
## 在 XML 里写成 `<Field id="target" link="true"/>`。
var link: bool = false

## kind == FIELD 时：空值不再补 `0`，就写空串（注释这类字段要它）。
##
## 在 XML 里写成 `<Field id="text" allow_empty="true"/>`。别的字段空值补 0 是
## 对的 —— mlog 缺参数就是 0，但 `#` 后面不该凭空长出一个 0。
var allow_empty: bool = false

## kind == FIELD 时：该字段是[b]字符串[/b]（要带引号写、要转义）。
##
## 在 XML 里写成 `<Field id="content" as="string"/>`：字面量引号交给导出器加，
## 这样它能把内容里的 `"` 与 `\` 转义掉（手写 `<Literal>"</Literal>` 做不到这件事）。
## 导入时反向：去引号 + 解码转义（见 [MlogText]）。
var as_string: bool = false

## 输出时是否在本段之前插一个空格。
##
## 旧模板靠 `" ".join(parts)` 拼接，于是无法表达 `print "x"` 这种“引号紧贴值”的写法。
## 把「加不加空格」交给每段自己决定后，引号、前缀、后缀都能精确表达。
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
