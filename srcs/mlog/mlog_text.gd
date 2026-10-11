class_name MlogText
extends RefCounted

## mlog 文本里字符串字面量的读写规则。
##
## 与 Mindustry 的 [code]LAssembler.unescape()[/code] / [code]LParser.string()[/code] 对齐：
## 认识的转义只有 `\n`、`\"`、`\\`、`\uXXXX`，其余（比如 `\t`）原样保留。
##
## 读写两侧必须共用这一套：只加引号不转义的话，用户在输入框里打一个 `"`，
## 导出的 `print "a"b"` 会让游戏的解析器整行报错；只去引号不解码的话，
## 导入 `print "a\"b"` 会把反斜杠一起存进字段，编辑器里看到的就不是原来的文本。

## 写：把「逻辑字符串」变成字面量内容（不含前后引号）。
static func escape(value: String) -> String:
	var out := ""
	for i in value.length():
		match value[i]:
			"\\":
				out += "\\\\"
			"\"":
				out += "\\\""
			"\n":
				out += "\\n"
			"\r":
				out += "\\n"
			_:
				out += value[i]
	return out


## 读：把字面量内容（不含前后引号）解码回「逻辑字符串」。
static func unescape(raw: String) -> String:
	if not raw.contains("\\"):
		return raw
	var out := ""
	var i := 0
	while i < raw.length():
		var ch := raw[i]
		if ch == "\\" and i + 1 < raw.length():
			var next := raw[i + 1]
			if next == "n":
				out += "\n"
				i += 2
				continue
			if next == "\"" or next == "\\":
				out += next
				i += 2
				continue
			if next == "u" and i + 5 < raw.length():
				var code := raw.substr(i + 2, 4).hex_to_int()
				if code > 0:
					out += String.chr(code)
					i += 6
					continue
		out += ch
		i += 1
	return out


## 整个 token 是不是一个字符串字面量（两侧都有引号）。
static func is_literal(token: String) -> bool:
	return token.length() >= 2 and token.begins_with("\"") and token.ends_with("\"")
