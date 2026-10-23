import { EditorStore } from '../viewmodel/EditorStore';

/**
 * 顶栏：品牌、文件/工具/查询/生成/导出菜单、格式化与折叠、视图切换、主题与编辑区开关。
 *
 * 注意：@Builder 的值参数不会随状态刷新，所以凡是外观依赖状态的按钮
 * （菜单、分段控制器、深浅色/全屏切换）都必须写成无参 Builder 或直接内联。
 */
@Component
export struct TopBar {
  @Consume('store') store: EditorStore;

  /** 鸿蒙风格顶栏按钮：胶囊、透明底、按下有反馈（仅用于文字不变的按钮） */
  @Builder
  navButton(label: string, key: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .stateStyles({
        normal: { .backgroundColor('#00000000') },
        pressed: { .backgroundColor(this.store.theme().isDark ? '#26FFFFFF' : '#14000000') }
      })
      .onClick(() => this.store.dispatch(key))
  }

  /** 顶栏分组分隔线 */
  @Builder
  barDivider() {
    Divider()
      .vertical(true)
      .height(18)
      .color(this.store.theme().panelBorder)
      .margin({ left: 8, right: 8 })
  }

  /** 顶栏：深浅色切换（文字随状态变化，必须无参） */
  @Builder
  themeButton() {
    Text(this.store.darkMode ? '浅色' : '深色')
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .stateStyles({
        normal: { .backgroundColor('#00000000') },
        pressed: { .backgroundColor(this.store.theme().isDark ? '#26FFFFFF' : '#14000000') }
      })
      .onClick(() => this.store.dispatch('theme'))
  }

  /** 顶栏：全屏图形 / 显示编辑 */
  @Builder
  editorToggleButton() {
    Text(this.store.showEditor ? '全屏图形' : '显示编辑')
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .stateStyles({
        normal: { .backgroundColor('#00000000') },
        pressed: { .backgroundColor(this.store.theme().isDark ? '#26FFFFFF' : '#14000000') }
      })
      .onClick(() => this.store.dispatch('toggleEditor'))
  }

  /** 顶栏：图形 / 树视图 分段控制器 */
  @Builder
  viewSegment() {
    Row() {
      Text('图形')
        .fontSize(12)
        .fontWeight(this.store.viewMode === 'graph' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.store.viewMode === 'graph' ? this.store.theme().text : this.store.theme().dimText)
        .padding({ left: 13, right: 13, top: 5, bottom: 5 })
        .borderRadius(13)
        .backgroundColor(this.store.viewMode === 'graph' ? this.store.theme().canvasBg : '#00000000')
        .shadow(this.store.viewMode === 'graph' ?
          { radius: 4, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.store.setViewMode('graph'))
      Text('树视图')
        .fontSize(12)
        .fontWeight(this.store.viewMode === 'tree' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.store.viewMode === 'tree' ? this.store.theme().text : this.store.theme().dimText)
        .padding({ left: 13, right: 13, top: 5, bottom: 5 })
        .borderRadius(13)
        .backgroundColor(this.store.viewMode === 'tree' ? this.store.theme().canvasBg : '#00000000')
        .shadow(this.store.viewMode === 'tree' ?
          { radius: 4, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.store.setViewMode('tree'))
    }
    .padding(2)
    .borderRadius(15)
    .backgroundColor(this.store.theme().nodeBgAlt)
  }

  @Builder
  fileMenuButton() {
    Text('文件 ▾')
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.fileMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.store.theme().panelBg
      })
  }

  @Builder
  toolMenuButton() {
    Text('工具 ▾')
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.toolMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.store.theme().panelBg
      })
  }

  @Builder
  queryMenuButton() {
    Text('查询 ▾')
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.queryMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.store.theme().panelBg
      })
  }

  @Builder
  generateMenuButton() {
    Text('生成 ▾')
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.generateMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.store.theme().panelBg
      })
  }

  @Builder
  exportMenuButton() {
    Text('导出 ▾')
      .fontSize(13)
      .fontColor(this.store.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.exportMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.store.theme().panelBg
      })
  }

  /** 下拉菜单中的一项（自绘行，便于控制行高与分组） */
  @Builder
  menuItem(label: string, act: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.store.theme().text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .layoutWeight(1)
    }
    .width('100%')
    .height(34)
    .padding({ left: 14, right: 14 })
    .borderRadius(6)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.store.dispatchSheet(act))
  }

  /** 菜单分组分割线 */
  @Builder
  menuDivider() {
    Divider()
      .strokeWidth(1)
      .color(this.store.darkMode ? '#4a4a4e' : '#cdd3db')
      .margin({ left: 10, right: 10, top: 5, bottom: 5 })
  }

  @Builder
  fileMenu() {
    Column() {
      this.menuItem('打开文件…', 'openFile')
      this.menuItem('从 URL 导入…', 'url')
      this.menuItem('从剪贴板粘贴', 'paste')
      this.menuDivider()
      this.menuItem('保存为 JSON 文件', 'saveJson')
      this.menuDivider()
      this.menuItem('载入示例数据…', 'samplePick')
      this.menuItem('清空编辑器', 'clear')
    }
    .width(216)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.store.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.store.darkMode ? '#454549' : '#d8dee5' })
  }

  /** “工具”下拉菜单 */
  @Builder
  toolMenu() {
    Column() {
      this.menuItem('撤销（Ctrl+Z）', 'undo')
      this.menuItem('重做（Ctrl+Y）', 'redo')
      this.menuDivider()
      this.menuItem('格式化（按缩进设置）', 'fmt2')
      this.menuItem('压缩为单行', 'fmt0')
      this.menuDivider()
      this.menuItem('递归排序键名', 'sort')
      this.menuDivider()
      this.menuItem('转义为 JSON 字符串', 'escape')
      this.menuItem('反转义', 'unescape')
      this.menuDivider()
      this.menuItem('缩进 2 空格', 'indent2')
      this.menuItem('缩进 4 空格', 'indent4')
      this.menuItem('字号 +', 'fontInc')
      this.menuItem('字号 -', 'fontDec')
      this.menuItem('切换自动换行', 'wrap')
      this.menuDivider()
      this.menuItem('校验 JSON', 'validate')
    }
    .width(232)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.store.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.store.darkMode ? '#454549' : '#d8dee5' })
  }

  @Builder
  queryMenu() {
    Column() {
      this.menuItem('jq 查询', 'jq')
      this.menuItem('JSONPath 查询', 'path')
      this.menuDivider()
      this.menuItem('JSON 差异对比…', 'diff')
      this.menuDivider()
      this.menuItem('查找替换（Ctrl+F）', 'search')
    }
    .width(216)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.store.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.store.darkMode ? '#454549' : '#d8dee5' })
  }

  @Builder
  generateMenu() {
    Column() {
      this.menuItem('JSON Schema', 'schema')
      this.menuItem('JSON Schema 校验…', 'schemaCheck')
      this.menuDivider()
      this.menuItem('类型定义（TS / Go / Kotlin / Rust / Java / C# / Swift / Dart）', 'types')
      this.menuDivider()
      this.menuItem('格式转换（YAML / CSV / XML / TOML 等）', 'convert')
    }
    .width(292)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.store.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.store.darkMode ? '#454549' : '#d8dee5' })
  }

  @Builder
  exportMenu() {
    Column() {
      this.menuItem('导出 SVG（矢量，整图）', 'svg')
      this.menuItem('导出 PNG（整图高清）', 'png')
      this.menuItem('导出 JPEG（整图高清）', 'jpeg')
      this.menuDivider()
      this.menuItem('复制 JSON 文本', 'copyJson')
    }
    .width(236)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.store.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.store.darkMode ? '#454549' : '#d8dee5' })
  }

  build() {
    Row() {
      Image($r('app.media.logo'))
        .width(26)
        .height(26)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .margin({ right: 8 })
      Text('HelloJson')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.store.theme().text)
      this.barDivider()
      Scroll() {
        Row() {
          this.fileMenuButton()
          this.navButton('格式化', 'format')
          this.navButton('压缩', 'compact')
          this.barDivider()
          this.toolMenuButton()
          this.queryMenuButton()
          this.generateMenuButton()
          this.exportMenuButton()
          this.barDivider()
          this.navButton('折叠', 'collapseAll')
          this.navButton('展开', 'expandAll')
          this.barDivider()
          this.viewSegment()
          this.barDivider()
          this.themeButton()
          this.editorToggleButton()
          this.navButton('关于', 'about')
        }
        .height('100%')
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .align(Alignment.Start)
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 8 })
    .backgroundColor(this.store.theme().toolbarBg)
    .border({ width: { bottom: 0.5 }, color: this.store.theme().panelBorder })
  }
}
