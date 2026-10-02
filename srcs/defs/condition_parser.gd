class_name ConditionParser
extends RefCounted

## `when="…"` 的解析器：小布尔表达式 → [ConditionDef]。
##
## 文法（`!` 优先级最高，其次 `&&`，最后 `||`；`and` / `or` / `not` 同样可用）：
## [codeblock]
## expr       := or
## or         := and { ("||" | "or") and }
## and        := unary { ("&&" | "and") unary }
## unary      := ("!" | "not") unary | primary
## primary    := "(" expr ")" | comparison
## comparison := FIELD ( ("=" | "!=") VALUE ("|" VALUE)* )?
##             | VALUE ("|" VALUE)*          # 仅当块里声明了 layout-field
## [/codeblock]
##
## 解析失败不抛异常：返回恒真条件，把原因写进 `errors`（编辑器可以就地提示），
## 而不是像旧的 `show` 白名单那样拼错就静默失效。

## 结果字典：{"condition": ConditionDef, "errors": PackedStringArray, "warnings": PackedStringArray}
static func parse(text: String, layout_field: StringName = &"", def: BlockDef = null) -> Dictionary:
	var parser := ConditionParser.new()
	return parser._run(text, layout_field, def)


var _tokens: Array[Dictionary] = []
var _index: int = 0
var _source: String = ""
var _layout_field: StringName = &""
var _def: BlockDef = null
var _errors := PackedStringArray()
var _warnings := PackedStringArray()


func _run(text: String, layout_field: StringName, def: BlockDef) -> Dictionary:
	_source = text
	_layout_field = layout_field
	_def = def
	_index = 0
	_errors = PackedStringArray()
	_warnings = PackedStringArray()
	_tokens = _tokenize(text)
	var condition := ConditionDef.always()
	if _errors.is_empty():
		condition = _parse_or()
		if _index < _tokens.size():
			_error("多余的内容：%s" % _describe_token(_tokens[_index]))
	if not _errors.is_empty():
		condition = ConditionDef.always()
	return {"condition": condition, "errors": _errors, "warnings": _warnings}


#region 词法

func _tokenize(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	var length := text.length()
	while i < length:
		var ch := text[i]
		if ch == " " or ch == "\t" or ch == "\n":
			i += 1
			continue
		var pos := i
		if ch == "(" or ch == ")":
			out.append({"kind": ch, "text": ch, "pos": pos})
			i += 1
			continue
		if ch == "&":
			if i + 1 < length and text[i + 1] == "&":
				out.append({"kind": "&&", "text": "&&", "pos": pos})
				i += 2
			else:
				_error_at("单个 & 不合法，与请写 &&（或 and）", pos)
				i += 1
			continue
		if ch == "|":
			if i + 1 < length and text[i + 1] == "|":
				out.append({"kind": "||", "text": "||", "pos": pos})
				i += 2
			else:
				out.append({"kind": "|", "text": "|", "pos": pos})
				i += 1
			continue
		if ch == "!":
			if i + 1 < length and text[i + 1] == "=":
				out.append({"kind": "!=", "text": "!=", "pos": pos})
				i += 2
			else:
				out.append({"kind": "!", "text": "!", "pos": pos})
				i += 1
			continue
		if ch == "=":
			out.append({"kind": "=", "text": "=", "pos": pos})
			i += 1
			continue
		if ch == "\"":
			i += 1
			var buffer := ""
			while i < length and text[i] != "\"":
				buffer += text[i]
				i += 1
			if i >= length:
				_error_at("引号没有闭合", pos)
			i += 1
			out.append({"kind": "word", "text": buffer, "pos": pos, "quoted": true})
			continue
		var start := i
		while i < length and not _is_delimiter(text[i]):
			i += 1
		out.append({"kind": "word", "text": text.substr(start, i - start), "pos": pos})
	return out


static func _is_delimiter(ch: String) -> bool:
	return ch == " " or ch == "\t" or ch == "\n" or ch == "(" or ch == ")" \
		or ch == "&" or ch == "|" or ch == "!" or ch == "=" or ch == "\""

#endregion


#region 语法

func _parse_or() -> ConditionDef:
	var items: Array[ConditionDef] = [_parse_and()]
	while _match_symbol("||") or _match_keyword("or"):
		items.append(_parse_and())
	return ConditionDef.any_of(items)


func _parse_and() -> ConditionDef:
	var items: Array[ConditionDef] = [_parse_unary()]
	while _match_symbol("&&") or _match_keyword("and"):
		items.append(_parse_unary())
	return ConditionDef.all_of(items)


func _parse_unary() -> ConditionDef:
	if _match_symbol("!") or _match_keyword("not"):
		return ConditionDef.negate(_parse_unary())
	return _parse_primary()


func _parse_primary() -> ConditionDef:
	if _match_symbol("("):
		var inner := _parse_or()
		if not _match_symbol(")"):
			_error("括号没有闭合")
		return inner
	return _parse_comparison()


func _parse_comparison() -> ConditionDef:
	var token := _peek()
	if token.is_empty():
		_error("表达式不完整")
		return ConditionDef.always()
	if String(token.get("kind", "")) != "word":
		_error("这里应当是字段名或取值，却遇到 %s" % _describe_token(token))
		_index += 1
		return ConditionDef.always()
	var first := String(_advance()["text"])
	if _peek_kind() == "=" or _peek_kind() == "!=":
		var negated := _peek_kind() == "!="
		_index += 1
		var values := _parse_values()
		return _validate_compare(first, values, negated)
	# 没有比较符：要么是"字段为真"，要么是 layout-field 的裸取值
	if _layout_field != &"" and not _is_field(first):
		var bare: Array[String] = [first]
		_parse_value_tail(bare)
		return _validate_compare(String(_layout_field), bare, false)
	if _layout_field != &"" and _is_field(first) and _is_layout_value(first):
		_warnings.append("`%s` 既是字段名也是 %s 的取值，这里按字段处理；需要比较取值请写 `%s=%s`"
			% [first, String(_layout_field), String(_layout_field), first])
	if _def != null and not _is_field(first):
		_error("未知字段：%s" % first)
		return ConditionDef.always()
	return ConditionDef.compare(StringName(first), [], false)


func _parse_values() -> Array[String]:
	var values: Array[String] = []
	var token := _peek()
	if token.is_empty() or String(token.get("kind", "")) != "word":
		_error("比较符后面缺少取值")
		return values
	values.append(String(_advance()["text"]))
	_parse_value_tail(values)
	return values


## 解析 `| 取值` 的后续部分（第一个取值已由调用方读掉）。
func _parse_value_tail(values: Array[String]) -> void:
	while _match_symbol("|"):
		var next := _peek()
		if next.is_empty() or String(next.get("kind", "")) != "word":
			_error("`|` 后面缺少取值")
			return
		values.append(String(_advance()["text"]))

#endregion


#region 校验

func _validate_compare(field: String, values: Array[String], negated: bool) -> ConditionDef:
	if _def == null:
		return ConditionDef.compare(StringName(field), values, negated)
	var element := _def.element(StringName(field))
	if element == null:
		_error("未知字段：%s（本块字段：%s）" % [field, _join_ids(_def.field_ids())])
		return ConditionDef.always()
	match element.type:
		&"Option":
			if not element.items.is_empty():
				var legal := PackedStringArray()
				for item in element.items:
					legal.append(item.value_or_text())
				for value in values:
					if not legal.has(value):
						_error("字段 %s 没有取值 `%s`（合法值：%s）" % [field, value, ", ".join(legal)])
		&"Button":
			for value in values:
				if value != "true" and value != "false":
					_error("开关 %s 只能与 true / false 比较（实际 `%s`）" % [field, value])
	return ConditionDef.compare(StringName(field), values, negated)


func _is_field(name: String) -> bool:
	if _def == null:
		return true
	return _def.element(StringName(name)) != null


func _is_layout_value(name: String) -> bool:
	if _def == null or _layout_field == &"":
		return false
	var element := _def.element(_layout_field)
	if element == null:
		return false
	for item in element.items:
		if item.value_or_text() == name:
			return true
	return false


static func _join_ids(ids: Array[StringName]) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(String(id))
	return ", ".join(parts)

#endregion


#region 记号操作

func _peek() -> Dictionary:
	return _tokens[_index] if _index < _tokens.size() else {}


func _peek_kind() -> String:
	return String(_peek().get("kind", ""))


func _advance() -> Dictionary:
	if _index >= _tokens.size():
		return {}
	var token := _tokens[_index]
	_index += 1
	return token


func _match_symbol(kind: String) -> bool:
	if _peek_kind() == kind:
		_index += 1
		return true
	return false


## 只把未加引号的裸词当关键字，`"not"` 这种带引号的取值不会被误吃。
func _match_keyword(word: String) -> bool:
	var token := _peek()
	if String(token.get("kind", "")) != "word" or bool(token.get("quoted", false)):
		return false
	if String(token.get("text", "")).to_lower() != word:
		return false
	_index += 1
	return true


func _describe_token(token: Dictionary) -> String:
	if token.is_empty():
		return "表达式结尾"
	var text := String(token.get("text", ""))
	if String(token.get("kind", "")) == "word":
		return "`%s`（第 %d 字符）" % [text, int(token.get("pos", 0)) + 1]
	return "`%s`（第 %d 字符）" % [text, int(token.get("pos", 0)) + 1]


func _error(message: String) -> void:
	_errors.append(message)


func _error_at(message: String, position: int) -> void:
	_errors.append("%s（第 %d 字符）" % [message, position + 1])

#endregion
