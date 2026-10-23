import { EditorStore } from '../viewmodel/EditorStore';

/** 底部状态栏：统计、有效性、当前选中路径与视图状态 */
@Component
export struct BottomBar {
  @Consume('store') store: EditorStore;

  build() {
    Row() {
      Text(this.store.viewMode === 'graph' ? ('节点 ' + this.store.nodeCount) : ('树行 ' + this.store.treeItems.length))
        .fontSize(10)
        .fontColor(this.store.theme().text)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('边 ' + this.store.edgeCount)
        .fontSize(10)
        .fontColor(this.store.theme().text)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('行 ' + this.store.caretLine + ' 列 ' + this.store.caretColumn + ' / 共 ' +
        this.store.lineCount + ' 行 ' + this.store.charCount + ' 字符')
        .fontSize(10)
        .fontColor(this.store.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text(this.store.isEmpty() ? '空文档' :
        (this.store.errorMsg.length > 0 ? ('第 ' + this.store.errorLine + ' 行有错') : 'JSON 有效'))
        .fontSize(10)
        .fontColor(this.store.isEmpty() ? this.store.theme().dimText :
          (this.store.errorMsg.length > 0 ? this.store.theme().errorColor : this.store.theme().successColor))
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .margin({ right: 6 })
      if (this.store.selectedPath.length > 0) {
        Text(this.store.selectedPath)
          .fontSize(11)
          .fontColor(this.store.theme().accent)
          .maxLines(1)
          .layoutWeight(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 4, right: 6 })
      } else {
        Blank()
      }
      if (this.store.findVisible) {
        Text('查找 ' + this.store.findIndex + ' / ' + this.store.findTotal)
          .fontSize(10)
          .fontColor(this.store.theme().searchHit)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.store.theme().nodeBgAlt)
          .margin({ right: 6 })
      }
      Text(this.store.highlighted ? '高亮模式' : '编辑模式')
        .fontSize(10)
        .fontColor(this.store.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text(this.store.viewMode === 'graph' ? '图形视图' : '树视图')
        .fontSize(10)
        .fontColor(this.store.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('布局 ' + (this.store.layoutDir === 'RIGHT' ? '→' :
        (this.store.layoutDir === 'DOWN' ? '↓' : (this.store.layoutDir === 'LEFT' ? '←' : '↑'))))
        .fontSize(10)
        .fontColor(this.store.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('缩放 ' + this.store.zoomText)
        .fontSize(10)
        .fontColor(this.store.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.store.theme().nodeBgAlt)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .backgroundColor(this.store.theme().toolbarBg)
    .border({ width: { top: 0.5 }, color: this.store.theme().panelBorder })
  }
}
