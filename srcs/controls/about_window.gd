class_name AboutWindow
extends Window

## 关于窗（帮助 → About）：版本、作者与致谢、反馈与仓库链接。
##
## 版本号与引擎版本都是[b]运行期[/b]读的（[ProjectSettings] / [Engine]），
## 所以升版本时不用回来改这个窗口。正文里的链接可点：交给系统浏览器打开。

const REPOSITORY: String = "https://github.com/LittleFishStars/mindustry-visual-logic"
const DISPLAY_NAME: String = "Mindustry Visual Logic"

@onready var nVersion: Label = %Version
@onready var nBody: RichTextLabel = %Body


func _ready() -> void:
	var version := String(ProjectSettings.get_setting("application/config/version", "?"))
	var engine := String(Engine.get_version_info().get("string", "Godot"))
	nVersion.text = "版本 %s · %s" % [version, engine]
	nBody.text = _body_text()


func open() -> void:
	popup_centered()


func _body_text() -> String:
	return """[b]Mindustry 图形化逻辑编辑器[/b]
%s（MVL）

创作者：Te_泣鸣翡兀（bilibili：初来乍到TE_NasiLeyta）
重要贡献：使针乡呀
B 站空间：[url]https://space.bilibili.com/1738617842[/url]
反馈群（QQ）：1038846685

此软件赠给 使针乡呀，并且公开供所有人使用。
目前应用处于测试阶段，若发现 bug，请在 QQ 群提出。非常感谢！

项目仓库：[url]%s[/url]
操作说明：帮助 → Document""" % [DISPLAY_NAME, REPOSITORY]


func _on_meta_clicked(meta: Variant) -> void:
	var url := String(meta)
	if url.begins_with("http://") or url.begins_with("https://"):
		OS.shell_open(url)


func _on_close_pressed() -> void:
	hide()
