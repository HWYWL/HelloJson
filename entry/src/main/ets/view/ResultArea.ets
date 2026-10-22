import { EditorStore } from '../viewmodel/EditorStore';

/** 结果区：查询 / 校验 / 生成的文本输出，可一键复制 */
@Component
export struct ResultArea {
  @Consume('store') store: EditorStore;

  build() {
    Column() {
      Row() {
        Text('结果').fontSize(12).fontColor(this.store.theme().dimText)
        Blank()
        Text('复制')
          .fontSize(12)
          .fontColor(this.store.theme().accent)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.store.copyText(this.store.outputText);
          })
      }
      .width('100%')
      .margin({ bottom: 6 })
      Scroll() {
        Text(this.store.outputText.length === 0 ? '（空）' : this.store.outputText)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.store.theme().text)
          .width('100%')
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.LocalDevice)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .padding(8)
      .borderRadius(8)
      .backgroundColor(this.store.theme().canvasBg)
    }
    .layoutWeight(1)
    .width('100%')
  }
}
