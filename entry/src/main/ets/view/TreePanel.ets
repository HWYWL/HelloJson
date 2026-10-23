import { rowColor } from '../core/GraphModel';
import { EditorStore } from '../viewmodel/EditorStore';
import { TreeItem } from '../viewmodel/Types';

/** 树视图：按层级缩进展开 JSON 结构 */
@Component
export struct TreePanel {
  @Consume('store') store: EditorStore;

  build() {
    List() {
      LazyForEach(this.store.treeData, (item: TreeItem, index: number) => {
        ListItem() {
          Row() {
            if (item.isContainer && item.hasChildren) {
              Text(item.collapsed ? '▸' : '▾')
                .fontSize(11)
                .fontColor(this.store.theme().dimText)
                .width(14)
                .margin({ left: item.depth * 14 })
                .onClick(() => this.store.toggleTreeItem(item.path))
            } else {
              Text('')
                .width(14)
                .margin({ left: item.depth * 14 })
            }
            Text(item.label)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.store.theme().keyText)
              .margin({ left: 2 })
            Text(item.isContainer ? ' ' + item.value : ': ' + item.value)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(item.isContainer ? this.store.theme().dimText : rowColor(this.store.theme(), item.kind))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 4 })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(index % 2 === 0 ? this.store.theme().canvasBg : this.store.theme().panelBg)
          .onClick(() => {
            if (item.isContainer && item.hasChildren) {
              this.store.toggleTreeItem(item.path);
            }
          })
        }
      }, (item: TreeItem) => item.path + '_' + item.depth)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.theme().canvasBg)
    .cachedCount(10)
  }
}
