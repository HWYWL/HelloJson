import { EditorStore } from '../viewmodel/EditorStore';

/**
 * 打开 / 解析大文件时的全屏进度遮罩：阻断误触，并给出「正在打开 / 正在解析」反馈。
 * 进度未知（如解码、解析阶段）时只显示转圈，知道字节进度时额外显示进度条。
 */
@Component
export struct BusyOverlay {
  @Consume('store') store: EditorStore;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
        })

      Column({ space: 12 }) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.store.theme().keyText)
          Text(this.store.busyText)
            .fontSize(13)
            .fontColor(this.store.theme().text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        if (this.store.busyProgress >= 0) {
          Progress({
            value: Math.round(this.store.busyProgress * 100),
            total: 100,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(6)
            .color(this.store.theme().keyText)
        }
      }
      .width(300)
      .padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .borderRadius(12)
      .backgroundColor(this.store.theme().panelBg)
      .border({ width: 0.5, color: this.store.theme().panelBorder })
      .shadow({ radius: 12, color: '#33000000' })
    }
    .width('100%')
    .height('100%')
  }
}
