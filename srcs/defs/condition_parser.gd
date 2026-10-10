class_name ConditionParser
extends RefCounted

## `when="…"` 的解析器：小布尔表达式 → [ConditionDef]。
##
## 只有三个逻辑运算符：`&`（与）、`|`（或）、`~`（非）；优先级 `~` > `&` > `|`。
## 比较显式写「字段=取值」/「字段!=取值」；同一字段的多个取值可以缩写成
## `mode=clear|color`（`|` 右边是裸取值时沿用左边那个字段）——没有"默认字段"这回事，
## 所以不存在"裸字段还是裸取值"的歧义。
## `&&`、`||`、`!`、`and`、`or`、`not` 会被明确拒绝并提示改法。
##
## [codeblock]
## expr       := or
## or         := and { "|" and }
## and        := unary { "&" unary }
## unary      := "~" unary | primary
## primary    := "(" expr ")" | comparison
## comparison := FIELD ("=" | "!=") VALUE { "|" VALUE }   # `|` 后缀沿用同一字段
## [/codeblock]
##
## 解析失败不抛异常：返回恒真条件，把原因写进 `errors`（编辑器可以就地提示），
## 而不是像旧的 `show` 白名单那样拼错就静默失效。

## 结果字典：{"condition": ConditionDef, "errors": PackedStringArray}
## 只做语法解析；「字段是否存在、取值是否合法」由 [BlockLibrary] 在整块解析完后统一校验。
static func parse(text: String) -> Dictionary:
	var parser := ConditionParser.new()
	return parser._run(text)


var _tokens: Array[Dictionary] = []
var _index: int = 0
var _errors := PackedStringArray()


func _run(text: String) -> Dictionary:
	_index = 0
	_errors = PackedStringArray()
	_tokens = _tokenize(text)
	var condition := ConditionDef.always()
	if _errors.is_empty():
		condition = _parse_or()
		if _index < _tokens.size():
			_error("多余的内容：%s" % _describe_token(_tokens[_index]))
	if not _errors.is_empty():
		condition = ConditionDef.always()
	return {"condition": condition, "errors": _errors}


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
		match ch:
			"(", ")":
				out.append({"kind": ch, "text": ch, "pos": pos})
				i += 1
			"&":
				if i + 1 < length and text[i + 1] == "&":
					_error_at("与请用单个 &（`&&` 不再支持）", pos)
					i += 2
				else:
					out.append({"kind": "&", "text": "&", "pos": pos})
					i += 1
			"|":
				if i + 1 < length and text[i + 1] == "|":
					_error_at("或请用单个 |（`||` 不再支持）", pos)
					i += 2
				else:
					out.append({"kind": "|", "text": "|", "pos": pos})
					i += 1
			"~":
				out.append({"kind": "~", "text": "~", "pos": pos})
				i += 1
			"!":
				if i + 1 < length and text[i + 1] == "=":
					out.append({"kind": "!=", "text": "!=", "pos": pos})
					i += 2
				else:
					_error_at("非请用 ~（`!` 不再支持）", pos)
					i += 1
			"=":
				out.append({"kind": "=", "text": "=", "pos": pos})
				i += 1
			"\"":
				i += 1
				var buffer := ""
				while i < length and text[i] != "\"":
					buffer += text[i]
					i += 1
				if i >= length:
					_error_at("引号没有闭合", pos)
				i += 1
				out.append({"kind": "word", "text": buffer, "pos": pos, "quoted": true})
			_:
				var start := i
				while i < length and not _is_delimiter(text[i]):
					i += 1
				out.append({"kind": "word", "text": text.substr(start, i - start), "pos": pos})
	return out


static func _is_delimiter(ch: String) -> bool:
	return ch == " " or ch == "\t" or ch == "\n" or ch == "(" or ch == ")" \
		or ch == "&" or ch == "|" or ch == "~" or ch == "!" or ch == "=" or ch == "\""

#endregion


#region 语法

func _parse_or() -> ConditionDef:
	var items: Array[ConditionDef] = [_parse_and()]
	while _match_symbol("|"):
		items.append(_parse_and())
	_reject_keyword(["or"], "或请用 |")
	return ConditionDef.any_of(items)


func _parse_and() -> ConditionDef:
	var items: Array[ConditionDef] = [_parse_unary()]
	while _match_symbol("&"):
		items.append(_parse_unary())
	_reject_keyword(["and"], "与请用 &")
	return ConditionDef.all_of(items)


func _parse_unary() -> ConditionDef:
	_reject_keyword(["not"], "非请用 ~")
	if _match_symbol("~"):
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
	if _peek_kind() != "=" and _peek_kind() != "!=":
		_error("条件要写成「字段=取值」（例如 mode=clear 或 txt=true），`%s` 后面缺比较符" % first)
		return ConditionDef.always()
	var negated := _peek_kind() == "!="
	_index += 1
	var value_token := _peek()
	if value_token.is_empty() or String(value_token.get("kind", "")) != "word":
		_error("比较符后面缺少取值")
		return ConditionDef.always()
	var values: Array[String] = [String(_advance()["text"])]
	# `mode=clear|color`：`|` 后面还是裸取值（后面不接比较符）时，沿用同一个字段
	while _peek_kind() == "|" and _is_value_at(_index + 1):
		_index += 1
		values.append(String(_advance()["text"]))
	return ConditionDef.compare(StringName(first), values, negated)

#endregion


#region 校验

## 位置 [param index] 是一个"后面不接比较符"的裸取值（取值列表的成员）。
func _is_value_at(index: int) -> bool:
	if index >= _tokens.size():
		return false
	if String(_tokens[index].get("kind", "")) != "word":
		return false
	var next_kind := String(_tokens[index + 1].get("kind", "")) if index + 1 < _tokens.size() else ""
	return next_kind != "=" and next_kind != "!="


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


## 位置不对的旧写法（and / or / not）给出改法提示，而不是含混的"多余的内容"。
func _reject_keyword(words: Array, hint: String) -> void:
	var token := _peek()
	if String(token.get("kind", "")) != "word" or bool(token.get("quoted", false)):
		return
	var text := String(token.get("text", "")).to_lower()
	if words.has(text):
		_error_at("%s（`%s` 不再支持）" % [hint, text], int(token.get("pos", 0)))


func _describe_token(token: Dictionary) -> String:
	if token.is_empty():
		return "表达式结尾"
	return "`%s`（第 %d 字符）" % [String(token.get("text", "")), int(token.get("pos", 0)) + 1]


func _error(message: String) -> void:
	_errors.append(message)


func _error_at(message: String, position: int) -> void:
	_errors.append("%s（第 %d 字符）" % [message, position + 1])

#endregion
