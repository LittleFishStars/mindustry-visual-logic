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


## 字面量，且紧贴上一段（不插空格）。
static func make_suffix(text: String) -> ExportPart:
	var part := make_literal(text)
	part.space_before = false
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


## 把模板字符串解析成段落。
##
## 模板就是"mlog 那一行长什么样"：字面量原样写（可以含空格与引号），
## 取值用占位符 `{字段}`；`{a|b|c}` 表示取第一个「此刻生效」的字段的值。
## 需要字面的大括号时写 `{{` / `}}`。
## [codeblock]
## draw {mode} {r|clr|sk|x1|x|rot} {g|y1|y} …
## print {content}
## print "{content}"
## [/codeblock]
static func parse_template(text: String) -> Array[ExportPart]:
	var out: Array[ExportPart] = []
	var buffer := ""
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == "{":
			if i + 1 < text.length() and text[i + 1] == "{":
				buffer += "{"
				i += 2
				continue
			if buffer != "":
				out.append(_template_literal(buffer))
				buffer = ""
			var end := text.find("}", i)
			if end < 0:
				buffer += text.substr(i)
				break
			var ids: Array[StringName] = []
			for piece in text.substr(i + 1, end - i - 1).split("|", false):
				var trimmed := piece.strip_edges()
				if trimmed != "":
					ids.append(StringName(trimmed))
			var part := make_first_visible(ids)
			part.space_before = false
			out.append(part)
			i = end + 1
		elif ch == "}" and i + 1 < text.length() and text[i + 1] == "}":
			buffer += "}"
			i += 2
		else:
			buffer += ch
			i += 1
	if buffer != "":
		out.append(_template_literal(buffer))
	return out


static func _template_literal(text: String) -> ExportPart:
	var part := make_literal(text)
	part.space_before = false
	return part


## 段落 → 模板字符串（迁移用；按 [member space_before] 复原原样的空格）。
static func to_template(parts: Array[ExportPart]) -> String:
	var out := ""
	for part in parts:
		var text := ""
		match part.kind:
			Kind.LITERAL:
				text = part.literal.replace("{", "{{").replace("}", "}}")
			Kind.FIELD:
				text = "{%s}" % String(part.field)
			_:
				var names := PackedStringArray()
				for field_id in part.fields:
					names.append(String(field_id))
				text = "{" + "|".join(names) + "}"
		if part.space_before and out != "":
			out += " "
		out += text
	return out

## 解析器用它写入标签文本。
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
