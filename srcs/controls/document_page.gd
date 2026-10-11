class_name DocumentPage
extends Control

## 应用内文档页（帮助 → Document）：左边章节，右边富文本。
##
## 它是多标签页系统里的一个页面，[b]不是[/b] [LogicEditorTab] —— 所以「存盘 / 导出 / 撤销」
## 这类操作在文档页上是空操作（[Main] 的 `_current_editor()` 会返回 null，菜单项也据此置灰）。
##
## 正文就是下面的 [constant SECTIONS]：改文档只改这里，不用碰场景 ——
## 场景只提供「章节按钮 + 富文本」这副骨架。

## 章节列表：`{"title": 章节名, "body": BBCode 正文}`。加章节只往这里加一项。
const SECTIONS: Array = [
	{
		"title": "概览",
		"body": """[b]Mindustry Visual Logic[/b] 把 mlog 变成积木：拖块搭逻辑，再导出成能直接粘进
Mindustry 处理器的 mlog 文本。

[ul]
[*]左侧是积木库，按类别分组；
[*]右侧是画布，竖着排下来的一串积木叫一条[b]链[/b]；
[*]块可以嵌套：像 If 这种带巢的块，把别的块拖进巢里就成它的子块；
[*]每个新页上都自带一个 [b]Start[/b] —— 它是程序的起点，调色板里看不到它（自动放的）。
[/ul]

[b]导出从 Start 开始[/b]：只有它那一格[b]往下[/b]的块会进 mlog —— 它前面的块、
画布上其他链，都不导出。所以「一条程序」就是「从 Start 往下的一串」。
Start 不能复制、也不能删除（一个文档就一个起点）。

项目存成 JSON —— 存的是「谁是谁的子块、字段是什么值、每条链摆在画布哪儿」，
与 Godot 版本无关，也能手工查看。导出成 mlog 走 [code]File → Export to clipboard[/code]（或按 [code]F5[/code]）。"""
	},
	{
		"title": "基本操作",
		"body": """[b]左键拖动[/b]：拿起一块，它后面的块会一起走；插到链中间时后面的块会让位。
拖到画布空白处 = 变成一条新链；拖到左侧积木列表上松手 = 删除（拿起的整串一起删）。
原地松手 = 没搬动，不改数据。

[b]右键拖动[/b]：复制。拖出来的是这一块[b]和它的整棵子树[/b]（巢里的块会跟着走），原块留在原地；
拖到左侧积木列表或画布外松手 = 取消；原地松手 = 什么都不做。
复制整体算一条撤销记录。

[b]标签页[/b]：单击已选中的那个标签就地改名；双击任意标签关闭它（关掉最后一个会自动补一个空白页）；
右键任意标签也是改名。

[b]画布[/b]：滚轮缩放；在空白处按住左键拖动平移。"""
	},
	{
		"title": "嵌套与分支",
		"body": """带巢的块（例如 If）左边有一条竖条，把块拖到竖条右边就会成为它的子块；
子块再带巢也没问题，深度不限。

[b]注意[/b]：If 是纯容器 —— 导出时它自己不占一行，巢里的块按顺序平铺展开。
需要真正的条件跳转时用 [b]Jump[/b]。"""
	},
	{
		"title": "Jump 与跳线",
		"body": """Jump 的第一个格子不是数字输入框，而是一个[b]目标按钮[/b]（按钮上写着它锁到了哪一块）：

[ul]
[*]在按钮上按住，拖到某一块上松手 = 把跳转锁定到那块；
[*]拖到自己身上、或拖到左侧积木列表上松手 = 解除锁定；
[*]在空白处松手 / 右键 / Esc = 取消，保持原样。
[/ul]

锁定之后画布上会出现一条[b]跳线[/b]：从 Jump 左边绕出去、接到目标块上，颜色按目标块区分，
多条线重叠时会自动分层错开。拖动过程中悬停的候选块会被描一圈边。

导出时目标会被换算成[b]指令行号[/b]，不用自己数行：注释行（[code]#[/code]）与标签行
（[code]label:[/code]）都不占行号，与 Mindustry 汇编器数法一致。
目标块被删掉时，指向它的引用会在同一条撤销记录里被清掉，不会留下死引用。"""
	},
	{
		"title": "存盘 / 导出 / 导入",
		"body": """[ul]
[*][code]File → Save[/code] / [code]Save As…[/code]：存成 .json 项目文件；
[*][code]File → Export to clipboard[/code]：导出 mlog 到系统剪贴板，直接粘进游戏；
[*][code]F5[/code]：快捷导出 —— 与上一条同一件事，不用点菜单（当前页不是编辑器时只会提示一声）；
[*][code]File → Load from clipboard[/code]：把剪贴板里的 mlog 变回积木（替换当前项目）；
[*][code]File → Append from clipboard[/code]：追加到当前项目后面（jump 行号会自动按偏移对齐）；
[*][code]Edit → Undo[/code] / [code]Redo[/code]：撤销 / 重做；[code]Edit → Clear[/code]：清空（可撤销）。
[/ul]

导入会尽量把每一行认回原来的块；认不出来的行会被跳过，并在输出里给出提示。"""
	},
	{
		"title": "设置",
		"body": """[code]Edit → Settings…[/code]

[ul]
[*][b]Max FPS[/b]：帧率上限；
[*][b]UI scale[/b]：整个界面的缩放，改完立刻生效；
[*][b]Export mlog when the window loses focus[/b]：切走窗口时自动把当前页导出到剪贴板。
[/ul]

设置存在用户目录的 [code]settings.json[/code] 里，关闭设置窗口时才写盘。"""
	},
	{
		"title": "积木定义（进阶）",
		"body": """积木长什么样、怎么导出，全都写在 [code]blocks/{语言}/*.xml[/code] 里 ——
[b]加一块积木不需要写代码[/b]：

[code]<Block name="Print">
  <Literal>print</Literal>
  <Field id="content" />
  <Row>
    <Text>Print</Text>
    <LineBox id="content" placeholder="frog" />
  </Row>
</Block>[/code]

[ul]
[*][code]<Literal>[/code] / [code]<Field>[/code]：导出模板（原样输出 / 取某个字段的值）；
[*][code]<Field id="target" link="true"/>[/code]：这一格存的是[b]块引用[/b]（Jump 的目标就是它）；
[*][code]<Field as="string"/>[/code]：字符串格（引号与转义由编辑器管，内容里打引号不会写坏）；
[*][code]<Field allow_empty="true"/>[/code]：允许留空（注释文本）；
[*][code]<Item alias="atan2">angle</Item>[/code]：认旧名字（导入时自动换成现在的写法）；
[*][code]<Row when="…">[/code]：显式分行；[code]when[/code] 支持 [code]&[/code]（与）、[code]|[/code]（或）、[code]~[/code]（非）与括号；
[*]元素有 [code]<Text>[/code] / [code]<LineBox>[/code] / [code]<Option>[/code]+[code]<Item>[/code] / [code]<Button>[/code] / [code]<Selector>[/code] / [code]<JumpTarget>[/code] / [code]<Nest>[/code]。
[/ul]

字段名拼错、取值不合法、元素标签没注册，加载时都会报出来 —— 写错不会静默变成「永远显示」。"""
	},
]

@onready var nChapters: VBoxContainer = %Chapters
@onready var nTitle: Label = %Title
@onready var nBody: RichTextLabel = %Body

## 当前章节下标（-1 = 还没选）。
var _current: int = -1


func _ready() -> void:
	for index in SECTIONS.size():
		var button := Button.new()
		button.text = String(SECTIONS[index].get("title", "?"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _show_section(index))
		nChapters.add_child(button)
	if not SECTIONS.is_empty():
		_show_section(0)


## 切到某一章：正文换成它的 BBCode，章节按钮里只有它保持按下态。
func _show_section(index: int) -> void:
	if index < 0 or index >= SECTIONS.size():
		return
	_current = index
	var section: Dictionary = SECTIONS[index]
	nTitle.text = String(section.get("title", ""))
	nBody.text = String(section.get("body", ""))
	nBody.scroll_to_line(0)
	for i in nChapters.get_child_count():
		var button := nChapters.get_child(i) as Button
		if button != null:
			button.set_pressed_no_signal(i == index)
