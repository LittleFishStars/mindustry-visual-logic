class_name MlogText
extends RefCounted

## mlog 字符串字面量读写（对齐 Mindustry 的 LParser）：只认 `\n` `\"` `\\` `\uXXXX`，其余原样保留 —— 读写两侧必须共用这一套。

## 写：逻辑字符串 → 字面量内容（不含引号）。
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


## 读：字面量内容（不含引号）→ 逻辑字符串。
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


static func is_literal(token: String) -> bool:
	return token.length() >= 2 and token.begins_with("\"") and token.ends_with("\"")
