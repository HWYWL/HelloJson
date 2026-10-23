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
| 代码生成 | JSON Schema (draft-07)、TypeScript / Go / Kotlin / Rust / Java / C# / Swift / Dart 类型定义（Java 可选 getter/setter 或 Lombok `@Data`） |
| Schema 校验 | 载入自定义 schema 校验当前文档，错误带 JSON 路径与行号；点击定位到图形节点，出错节点及其祖先描红 |
| 格式转换 | JSON ⇄ YAML / CSV / XML / TOML / Properties / URL 查询串 / Markdown 表格（双向，可写回编辑器） |
| 导入导出 | 文件导入（自动识别 .json/.yaml/.csv/.xml/.toml/.properties/.md/.query）、拖拽文件或文本导入、URL 导入、剪贴板粘贴、保存 JSON、导出 SVG（整图矢量）/ PNG / JPEG |
| 其他 | 深色/浅色主题、横竖屏自适应分栏、全屏图形模式、配置与内容本地持久化 |
| 大文档 | 按文档体量自动降级：解析防抖拉长、图形节点数截断（80K 字符以上最多 1500 节点，300K 以上 600 节点）、树视图最多 3000 项、语法高亮 40K 字符以上关闭、落盘节流 |

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
│   ├── CodeGen.ets      Schema / 类型生成
│   ├── Convert.ets      YAML / CSV / XML 互转 + 搜索
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

## 签名与真机安装

本机已具备 release 证书材料（`F:\OpenHarmony\Key\HelloJson\Release`），可用 `hap-sign-tool` 手动签名：

```powershell
java -jar F:\OpenHarmony\Sdk\26.0.0\toolchains\lib\hap-sign-tool.jar sign-app -mode localSign `
  -keyAlias HelloJson -appCertFile "F:\OpenHarmony\Key\HelloJson\Release\HelloJson.cer" `
  -profileFile "F:\OpenHarmony\Key\HelloJson\Release\HelloJsonRelease.p7b" `
  -inFile entry\build\default\outputs\default\entry-default-unsigned.hap `
  -signAlg SHA256withECDSA -keystoreFile "F:\OpenHarmony\Key\HelloJson\Release\HelloJson.p12" `
  -keystorePwd "<pwd>" -keyPwd "<pwd>" -outFile build-output\HelloJson-release.hap -compatibleVersion 24 -signCode 1
```

> ⚠️ release（distribution）证书签名的包无法直接 `hdc install` 到真机（错误 9568322 not trusted app source）。
> 真机调试需要在 DevEco Studio 中执行一次自动签名（Project Structure → Signing Configs → Automatically generate signature），
> 生成包含本机 UDID 的调试证书与 profile 后再安装。

## 当前设备

- 真机：`PCE-W30` / HarmonyOS 6.1.0.135 / API 24 / UDID `ED8FBDC2BB5ED0C17F39EDA79C4C41A67EB191481451AE6C047602F74A2A8AFE`
