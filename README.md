# HelloJson

原生鸿蒙（HarmonyOS NEXT）JSON 可视化与编辑工具，纯 ArkTS / ArkUI 实现，无 WebView、无三方运行时依赖。

功能对齐开源项目 [jsoncrack.com](https://github.com/AykutSarac/jsoncrack.com) 的核心能力，渲染层与布局引擎完全重写。

## 功能

| 类别 | 能力 |
|---|---|
| 可视化 | JSON → 交互式节点图，Canvas 绘制，支持缩放（双指捏合 / PC 滚轮，均以手指或指针位置为锚点）、平移（单指拖拽）、点击选中、节点折叠/展开、一键折叠全部/展开全部 |
| 布局 | 自研分层树布局，支持 4 个方向（右/下/左/上）切换 |
| 视图 | 图形视图 ⇄ 树形视图（树节点可折叠） |
| 编辑器 | 多格式输入（JSON / JSONC 注释、尾随逗号）、实时解析、错误行号提示、按标签独立的撤销 / 重做（连续输入自动合并成一步）、缩进 2/4 空格、字号缩放、自动换行开关 |
| 快捷键 | `Ctrl+S` 保存、`Ctrl+Z` 撤销、`Ctrl+Y` / `Ctrl+Shift+Z` 重做、`Ctrl+O` 打开、`Ctrl+N` 新建标签、`Ctrl+W` 关闭标签、`Ctrl+F` 查找、`Ctrl+Shift+F` 格式化、`Esc` 关闭弹层 |
| 格式化 | 2 空格格式化、压缩单行、递归键排序、转义 / 反转义、JSON 校验 |
| 查询 | jq 子集（字段/索引/切片/迭代/递归/管道/逗号/构造/内置函数/比较与算术）、JSONPath 子集（通配、递归下降、切片、过滤表达式）、全文搜索并高亮命中节点 |
| 查找替换 | 文本查找支持正则（`.*` 开关，gi 标志）、上一个/下一个、替换当前与全部替换，命中计数与高亮；编辑区显示行号栏与光标行列 |
| 代码生成 | JSON Schema (draft-07)、TypeScript / Go / Kotlin / Rust / Java / C# / Swift / Dart 类型定义（Java 可选 getter/setter 或 Lombok `@Data`；TypeScript 可选字段 / export；可按已载入 schema 推断类型） |
| Schema 校验 | 载入自定义 schema 校验当前文档，错误带 JSON 路径与行号；点击定位到图形节点，出错节点及其祖先描红；可按 schema 生成示例数据（枚举/范围/必填/数组长度/$ref） |
| 格式转换 | JSON ⇄ YAML / CSV / XML / TOML / Properties / URL 查询串 / Markdown 表格（双向，可写回编辑器） |
| 导入导出 | 文件导入（自动识别 .json/.yaml/.csv/.xml/.toml/.properties/.md/.query）、拖拽文件或文本导入、URL 导入、剪贴板粘贴、保存 JSON、导出 SVG（整图矢量）/ PNG / JPEG |
| 其他 | 深色/浅色主题、横竖屏自适应分栏、全屏图形模式、弹窗标题栏可拖动且限制在可视区域内、配置与内容本地持久化 |
| 大文档 | 按文档体量自动降级：解析防抖拉长、图形节点数截断（80K 字符以上最多 1500 节点，300K 以上 600 节点）、树视图 LazyForEach 懒加载（最多 3000 项）、语法高亮 40K 字符以上关闭、落盘节流 |

## 更新记录

### 未发布（0.3.0 开发中）

**查找与编辑**

- 查找栏支持正则（`.*` 开关，`gi` 标志）、上一个 / 下一个、替换当前与全部替换，正则语法错误即时提示
- 高亮视图新增行号栏（关闭自动换行时显示，2000 行以内），编辑器实时显示光标行列
- 缩进 2/4 空格、字号 10–20、自动换行开关，随设置持久化
- 按标签独立的撤销 / 重做，连续输入自动合并为一步
- 快捷键：`Ctrl+S` / `Ctrl+Z` / `Ctrl+Y` / `Ctrl+O` / `Ctrl+N` / `Ctrl+W` / `Ctrl+F` / `Ctrl+Shift+F` / `Esc`

**代码生成**

- 新增 C#、Swift、Dart 目标：C# 属性 + `[JsonPropertyName]`、Swift `Codable` + `CodingKeys`、Dart 平铺类 + `fromJson` / `toJson`
- Java 支持 getter/setter 与 Lombok `@Data` 两种模式，字段名冲突自动补 `@JsonProperty`
- TypeScript 可选字段（`key?: T`）与 `export interface` 开关
- 可按已载入的 schema 推断类型

**Schema**

- 新增 Schema 校验（draft-07 子集）：错误带 JSON 路径与行号，点击定位并描红节点
- 新增 Schema → 示例数据：`enum` / `const` / `default` / `example`、数值范围、长度、数组长度、`format`、`$ref`、`oneOf` / `anyOf` / `allOf`

**格式与导入**

- 格式转换新增 TOML / Properties / URL 查询串 / Markdown 表格，均为 JSON 双向
- 文件导入识别 `.toml` / `.properties` / `.md` / `.query`，支持拖拽文件或文本导入
- JSON 差异对比（双标签行级 diff、增删统计、超大差异截断）

**其他**

- 弹窗标题栏可拖动，偏移自动限制在可视区域内
- 树视图改用 `LazyForEach`，数千行不再一次性创建节点
- 修复安装脚本在构建失败时仍签名安装旧包
- 修复 TypeScript 内联对象中非法 key 未转义

<details>
<summary>v0.2.0（2026-10-22）· 多标签与组件化</summary>

- 编辑区顶部标签条：新建 / 切换 / 关闭，未保存的标签带小圆点
- 标签右键菜单：关闭、关闭其他、全部关闭
- 每个标签独立的正文、报错、图形、树视图、折叠状态、选中路径、查找状态；主题与视图模式全局共享
- 标签与激活项持久化，旧版单文档自动迁移为第一个标签
- 打开文件 / URL 导入 / 剪贴板粘贴自动新建标签
- 主页面拆分为顶栏、编辑区、图形区、树视图、结果区、浮层面板，状态收敛到共享数据层

</details>

<details>
<summary>v0.1.0（2026-10-22）· 首发版本</summary>

- JSON → 交互式节点图：缩放（双指 / 滚轮，按指针位置锚定）、平移、选中、折叠 / 展开、一键折叠
- 自研分层树布局，支持右 / 下 / 左 / 上四个方向
- 图形视图 ⇄ 树视图切换
- 编辑器：JSONC 注释与尾随逗号、实时解析、错误行号提示
- 格式化、压缩单行、递归键排序、转义 / 反转义、JSON 校验
- jq 子集与 JSONPath 子集查询
- JSON Schema（draft-07）生成
- JSON ⇄ YAML / CSV / XML 双向转换
- 文件 / URL / 剪贴板导入，导出 SVG / PNG / JPEG
- 深色 / 浅色主题、横竖屏自适应分栏、全屏图形模式
- 发布签名脚本、应用图标与应用商店截图

</details>

## 架构

```
entry/src/main/ets/
├── core/                纯逻辑层（无 UI 依赖，可单测）
│   ├── JValue.ets       JSON 值模型
│   ├── JsonParser.ets   带偏移量的递归下降解析器（支持注释与尾随逗号）
│   ├── JsonWriter.ets   序列化 / 格式化 / 排序 / 转义
│   ├── GraphBuilder.ets JSON → 节点图（对象合并为单节点，数组展开为子节点）
│   ├── TreeLayout.ets   分层树布局（替代 ELK）
│   ├── JqEngine.ets     jq 子集解释器
│   ├── JsonPathEngine.ets
│   ├── CodeGen.ets      Schema / 类型生成（8 种语言）
│   ├── MockGen.ets      Schema → 示例数据
│   ├── SchemaValidator.ets  Schema 校验（draft-07 子集）
│   ├── Convert.ets      YAML / CSV / XML / TOML / Properties / 查询串 / Markdown 互转 + 搜索
│   ├── SvgExport.ets    SVG 导出
│   └── Storage.ets      preferences 持久化
├── view/GraphRenderer.ets  Canvas 渲染与命中测试
└── pages/Index.ets         主界面（工具栏 / 编辑器 / 图形 / 弹窗）
```

## 构建

```powershell
$env:DEVECO_SDK_HOME='F:\OpenHarmony\command-line-tools\sdk'
F:\OpenHarmony\command-line-tools\bin\hvigorw.bat assembleHap --no-daemon -p product=default -p buildMode=release
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`

