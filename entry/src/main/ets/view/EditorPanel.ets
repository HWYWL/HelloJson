import { EditorStore } from '../viewmodel/EditorStore';
import { HSpan, TabInfo } from '../viewmodel/Types';

/**
 * 编辑区：编辑 / 高亮两种模式、查找栏、示例选择面板。
 *
 * 文本滚动定位属于视图职责，由本组件注册到 store.onScrollToMatch，
 * 数据层只负责命中位置计算。
 */
@Component
export struct EditorPanel {
  @Consume('store') store: EditorStore;
  /** 右键菜单作用的标签 */
  @State contextTabId: string = '';
  private textScroller: Scroller = new Scroller();
  private textContentH: number = 0;
  private textViewH: number = 0;

  aboutToAppear(): void {
    this.store.onScrollToMatch = () => {
      this.scrollToMatch();
    };
  }

  aboutToDisappear(): void {
    this.store.onScrollToMatch = () => {
    };
  }

  /**
   * 滚动到当前命中：按字符偏移在全文中的比例估算纵向位置。
   * 高亮视图是等宽字体 + 固定宽度换行，视觉高度与字符数近似成正比。
   */
  private scrollToMatch(): void {
    const offset = this.store.matchOffset();
    if (offset < 0) {
      return;
    }
    const total = this.store.jsonText.length;
    if (total <= 0 || this.textContentH <= this.textViewH) {
      return;
    }
    let y = (offset / total) * this.textContentH - this.textViewH / 3;
    const maxY = this.textContentH - this.textViewH;
    if (y < 0) {
      y = 0;
    }
    if (y > maxY) {
      y = maxY;
    }
    this.textScroller.scrollTo({ xOffset: 0, yOffset: y });
  }

  /** 编辑区头部：编辑 / 高亮 分段控制器 */
  @Builder
  modeSegment() {
    Row() {
      Text('编辑')
        .fontSize(12)
        .fontWeight(!this.store.highlighted ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(!this.store.highlighted ? this.store.theme().text : this.store.theme().dimText)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(!this.store.highlighted ? this.store.theme().canvasBg : '#00000000')
        .shadow(!this.store.highlighted ?
          { radius: 3, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.store.setEditMode(false))
      Text('高亮')
        .fontSize(12)
        .fontWeight(this.store.highlighted ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.store.highlighted ? this.store.theme().text : this.store.theme().dimText)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(this.store.highlighted ? this.store.theme().canvasBg : '#00000000')
        .shadow(this.store.highlighted ?
          { radius: 3, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.store.setEditMode(true))
    }
    .padding(2)
    .borderRadius(14)
    .backgroundColor(this.store.theme().nodeBgAlt)
  }

  @Builder
  findButton(label: string, act: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.store.theme().text)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .borderRadius(5)
      .backgroundColor(this.store.theme().nodeBgAlt)
      .margin({ left: 6 })
      .onClick(() => {
        if (act === 'find') {
          this.store.doFind(true);
        } else if (act === 'prev') {
          this.store.findStep(-1);
        } else if (act === 'next') {
          this.store.findStep(1);
        } else {
          this.store.closeFind();
        }
      })
  }

  /** 浏览器风格查找栏：输入 → 回车/下一个 */
  @Builder
  findBar() {
    Row() {
      TextInput({ text: this.store.findQuery, placeholder: '文本查找' })
        .layoutWeight(1)
        .height(32)
        .fontSize(12)
        .fontFamily('monospace')
        .padding({ left: 8, right: 8, top: 0, bottom: 0 })
        .borderRadius(5)
        .backgroundColor(this.store.theme().canvasBg)
        .fontColor(this.store.theme().text)
        .placeholderColor(this.store.theme().dimText)
        .placeholderFont({ size: 12 })
        .caretColor(this.store.theme().accent)
        .onChange((v: string) => {
          this.store.findQuery = v;
          this.store.doFind(true);
        })
        .onSubmit(() => {
          this.store.findStep(1);
        })
      this.findButton('查找', 'find')
      this.findButton('上一个', 'prev')
      this.findButton('下一个', 'next')
      this.findButton('关闭', 'close')
      Text(this.store.findTotal === 0 ?
        (this.store.findQuery.length > 0 ? '无结果' : '0 / 0') :
        (this.store.findIndex + ' / ' + this.store.findTotal))
        .fontSize(11)
        .fontColor(this.store.findTotal === 0 ? this.store.theme().errorColor : this.store.theme().dimText)
        .margin({ left: 6, right: 4 })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.store.theme().toolbarBg)
    .border({ width: { bottom: 0.5 }, color: this.store.theme().panelBorder })
  }

  @Builder
  sampleCard(title: string, desc: string, kind: string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.store.theme().accent)
        .width(54)
      Text(desc)
        .fontSize(11)
        .fontColor(this.store.theme().text)
        .layoutWeight(1)
        .maxLines(2)
      Text('载入')
        .fontSize(11)
        .fontColor(this.store.theme().canvasBg)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().accent)
    }
    .width('100%')
    .padding(12)
    .margin({ bottom: 8 })
    .borderRadius(8)
    .backgroundColor(this.store.theme().nodeBgAlt)
    .onClick(() => {
      this.store.loadSample(kind);
      this.store.samplePicker = false;
    })
  }

  @Builder
  samplePickerPanel() {
    Column() {
      Row() {
        Text('选择示例数据格式')
          .fontSize(12)
          .fontColor(this.store.theme().text)
        Blank()
        Text('✕')
          .fontSize(13)
          .fontColor(this.store.theme().dimText)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .onClick(() => {
            this.store.samplePicker = false;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Scroll() {
        Column() {
          this.sampleCard('JSON', '标准 JSON 文档，直接可视化', 'json')
          this.sampleCard('YAML', 'YAML 配置，自动转换为 JSON', 'yaml')
          this.sampleCard('CSV', '表格数据，自动转换为对象数组', 'csv')
          this.sampleCard('XML', '节点结构，自动转换为 JSON', 'xml')
          Text('载入前会先清空当前编辑内容与图形')
            .fontSize(10)
            .fontColor(this.store.theme().dimText)
            .margin({ top: 2 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(this.store.theme().canvasBg)
  }

  /** 高亮视图：Span 着色 + 查找命中背景 */
  @Builder
  highlightView() {
    Scroll(this.textScroller) {
      Text() {
        ForEach(this.store.spans, (sp: HSpan, idx: number) => {
          if (sp.bg.length > 0) {
            Span(sp.text).fontColor(sp.color).textBackgroundStyle({ color: sp.bg, radius: 2 })
          } else {
            Span(sp.text).fontColor(sp.color)
          }
        }, (sp: HSpan, idx: number) => this.store.spanSeq.toString() + '_' + idx.toString())
      }
      .fontSize(12)
      .fontFamily('monospace')
      .width('100%')
      .textAlign(TextAlign.Start)
      .wordBreak(WordBreak.BREAK_ALL)
      .copyOption(CopyOptions.LocalDevice)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.textContentH = Number(newValue.height);
      })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.TopStart)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.store.theme().canvasBg)
    .scrollBar(BarState.Auto)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.textViewH = Number(newValue.height);
    })
    .onClick(() => {
      if (!this.store.findVisible) {
        this.store.highlighted = false;
      }
    })
  }

  /** 标签条：新建 / 切换 / 关闭，位于编辑区顶部（全屏图形时随编辑区一起隐藏） */
  @Builder
  tabBar() {
    Row() {
      Scroll() {
        Row() {
          ForEach(this.store.tabs, (t: TabInfo) => {
            Row() {
              if (t.dirty) {
                Text('●')
                  .fontSize(7)
                  .fontColor(this.store.theme().accent)
                  .margin({ right: 4 })
              }
              Text(t.title)
                .fontSize(11)
                .fontColor(t.id === this.store.activeTabId ? this.store.theme().text : this.store.theme().dimText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 132 })
              Text('✕')
                .fontSize(9)
                .fontColor(this.store.theme().dimText)
                .padding({ left: 6, right: 2, top: 1, bottom: 1 })
                .onClick(() => this.store.closeTab(t.id))
            }
            .height(24)
            .padding({ left: 8, right: 4 })
            .borderRadius(6)
            .margin({ right: 4 })
            .backgroundColor(t.id === this.store.activeTabId ?
              this.store.theme().canvasBg : '#00000000')
            .onClick(() => this.store.activateTab(t.id))
            .onMouse((e: MouseEvent) => {
              if (e.button === MouseButton.Right) {
                this.contextTabId = t.id;
              }
            })
            .bindContextMenu(this.tabMenu, ResponseType.RightClick)
          }, (t: TabInfo) => t.id + (t.dirty ? '_1' : '_0') + '_' + t.title)
        }
        .height('100%')
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .align(Alignment.Start)

      Text('＋')
        .fontSize(13)
        .fontColor(this.store.theme().text)
        .width(26)
        .height(22)
        .textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .onClick(() => this.store.newTab())
    }
    .width('100%')
    .height(32)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.store.theme().toolbarBg)
    .border({ width: { bottom: 0.5 }, color: this.store.theme().panelBorder })
  }

  /** 标签右键菜单项 */
  @Builder
  tabMenuRow(label: string, act: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.store.theme().text)
        .layoutWeight(1)
        .maxLines(1)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .height(34)
    .padding({ left: 14, right: 14 })
    .borderRadius(6)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      if (act === 'close') {
        this.store.closeTab(this.contextTabId);
      } else if (act === 'others') {
        this.store.closeOtherTabs(this.contextTabId);
      } else {
        this.store.closeAllTabs();
      }
    })
  }

  /** 标签右键菜单：关闭 / 关闭其他 / 全部关闭 */
  @Builder
  tabMenu() {
    Column() {
      this.tabMenuRow('关闭', 'close')
      this.tabMenuRow('关闭其他', 'others')
      this.tabMenuRow('全部关闭', 'all')
    }
    .width(160)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.store.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.store.darkMode ? '#454549' : '#d8dee5' })
  }

  build() {
    Column() {
      this.tabBar()

      Row() {
        Text('JSON')
          .fontSize(12)
          .fontColor(this.store.theme().dimText)
        Blank()
        if (this.store.errorMsg.length > 0) {
          Text('第 ' + this.store.errorLine + ' 行: ' + this.store.errorMsg)
            .fontSize(11)
            .fontColor(this.store.theme().errorColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        } else {
          Text(this.store.nodeCount + ' 节点 / ' + this.store.edgeCount + ' 边')
            .fontSize(11)
            .fontColor(this.store.theme().dimText)
            .margin({ right: 4 })
        }
        this.modeSegment()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })

      if (this.store.findVisible) {
        this.findBar()
      }

      if (this.store.samplePicker) {
        this.samplePickerPanel()
      } else if (this.store.highlighted) {
        this.highlightView()
      } else {
        TextArea({ text: this.store.jsonText, placeholder: '在此输入 JSON / YAML / CSV / XML' })
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.store.theme().text)
          .backgroundColor(this.store.theme().canvasBg)
          .layoutWeight(1)
          .width('100%')
          .onChange((value: string) => {
            this.store.onTextChanged(value);
          })
          .onKeyEvent((e: KeyEvent) => {
            this.store.onGlobalKey(e);
          })
      }
    }
    .height(this.store.stackVertical ? ((this.store.splitRatio * 100).toFixed(1) + '%') : '100%')
    .width(this.store.stackVertical ? '100%' : ((this.store.splitRatio * 100).toFixed(1) + '%'))
    .backgroundColor(this.store.theme().panelBg)
    .border({
      width: {
        right: this.store.stackVertical ? 0 : 0.5,
        bottom: this.store.stackVertical ? 0.5 : 0
      }, color: this.store.theme().panelBorder
    })
  }
}
