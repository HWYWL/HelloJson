import { EditorStore } from '../viewmodel/EditorStore';
import { ResultArea } from './ResultArea';

/**
 * 居中浮动面板：URL 导入、关于、节点详情、jq / JSONPath、Schema / 类型、格式转换。
 * 内容由 store.modalType 决定，遮罩层与外层定位由页面负责。
 */
@Component
export struct PanelHost {
  @Consume('store') store: EditorStore;

  @Builder
  aboutRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.store.theme().dimText)
        .width(84)
      Text(value)
        .fontSize(12)
        .fontColor(this.store.theme().text)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  aboutLink(label: string, url: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.store.theme().dimText)
        .width(84)
      Text(url)
        .fontSize(12)
        .fontColor(this.store.theme().accent)
        .decoration({ type: TextDecorationType.Underline, color: this.store.theme().accent })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick(() => {
          this.store.openLink(url);
        })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  aboutTag(label: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.store.theme().text)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(10)
      .backgroundColor(this.store.theme().nodeBgAlt)
      .margin({ right: 6, bottom: 6 })
  }

  @Builder
  aboutContent() {
    Scroll() {
      Column() {
        Row() {
          Image($r('app.media.logo'))
            .width(46)
            .height(46)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)
          Column() {
            Text('HelloJson')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.theme().text)
            Text('原生鸿蒙 JSON 可视化工具')
              .fontSize(11)
              .fontColor(this.store.theme().dimText)
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
          Blank()
          Text('v' + this.store.appVersion)
            .fontSize(11)
            .fontColor(this.store.theme().dimText)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.store.theme().nodeBgAlt)
        }
        .width('100%')
        .margin({ bottom: 14 })

        this.aboutRow('版本', this.store.appVersion + '（versionCode ' + this.store.appVersionCode.toString() + '）')
        this.aboutRow('包名', 'com.yi.json')
        this.aboutRow('技术栈', 'ArkTS · ArkUI · Canvas 自绘')
        this.aboutRow('运行环境', 'HarmonyOS 6.1.1+（API 24+）')
        this.aboutRow('作者', '一叶秋枫')
        this.aboutLink('项目地址', 'https://github.com/HWYWL/HelloJson')

        Text('主要功能')
          .fontSize(12)
          .fontColor(this.store.theme().dimText)
          .width('100%')
          .margin({ top: 12, bottom: 8 })
        Flex({ wrap: FlexWrap.Wrap }) {
          this.aboutTag('图形可视化')
          this.aboutTag('树形视图')
          this.aboutTag('语法高亮')
          this.aboutTag('jq 查询')
          this.aboutTag('JSONPath')
          this.aboutTag('Schema / 类型生成')
          this.aboutTag('YAML · CSV · XML 转换')
          this.aboutTag('SVG / PNG / JPEG 导出')
        }
        .width('100%')

        Text('© 2026 HelloJson · 本工具完全离线运行，数据不会上传')
          .fontSize(10)
          .fontColor(this.store.theme().dimText)
          .width('100%')
          .margin({ top: 12 })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
  }

  @Builder
  urlForm() {
    Column() {
      TextInput({ text: this.store.urlInput, placeholder: 'https://example.com/data.json' })
        .fontSize(13)
        .backgroundColor(this.store.theme().canvasBg)
        .fontColor(this.store.theme().text)
        .margin({ bottom: 12 })
        .onChange((v: string) => {
          this.store.urlInput = v;
        })
        .onSubmit(() => {
          this.store.importFromUrl();
        })
      Button('导入')
        .width('100%')
        .onClick(() => {
          this.store.importFromUrl();
        })
    }
    .width('100%')
  }

  @Builder
  queryBody() {
    Column() {
      Row() {
        TextInput({
          text: this.store.expressionInput,
          placeholder: this.store.modalType === 'jq' ? '.foo | .[]' : '$.foo[*]'
        })
          .layoutWeight(1)
          .fontSize(13)
          .fontFamily('monospace')
          .backgroundColor(this.store.theme().canvasBg)
          .fontColor(this.store.theme().text)
          .onChange((v: string) => {
            this.store.expressionInput = v;
          })
          .onSubmit(() => {
            this.store.runActiveQuery();
          })
        Text('运行')
          .fontSize(13)
          .fontColor(this.store.theme().canvasBg)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(6)
          .backgroundColor(this.store.theme().accent)
          .margin({ left: 8 })
          .onClick(() => {
            this.store.runActiveQuery();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })
      ResultArea()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  genBody() {
    Column() {
      if (this.store.modalType === 'type') {
        Row() {
          Text('TypeScript')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'typescript' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'typescript' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .margin({ right: 6 })
            .onClick(() => {
              this.store.genLanguage = 'typescript';
              this.store.outputText = this.store.buildTypes('typescript');
            })
          Text('Go')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'go' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'go' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .margin({ right: 6 })
            .onClick(() => {
              this.store.genLanguage = 'go';
              this.store.outputText = this.store.buildTypes('go');
            })
          Text('Kotlin')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'kotlin' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'kotlin' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .margin({ right: 6 })
            .onClick(() => {
              this.store.genLanguage = 'kotlin';
              this.store.outputText = this.store.buildTypes('kotlin');
            })
          Text('Rust')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'rust' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'rust' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .onClick(() => {
              this.store.genLanguage = 'rust';
              this.store.outputText = this.store.buildTypes('rust');
            })
        }
        .width('100%')
        .margin({ bottom: 8 })
      }
      ResultArea()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  convertBody() {
    Column() {
      Row() {
        Text('YAML')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'yaml' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'yaml' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ right: 6 })
          .onClick(() => {
            this.store.targetFormat = 'yaml';
            this.store.outputText = this.store.buildConvert('yaml');
          })
        Text('CSV')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'csv' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'csv' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ right: 6 })
          .onClick(() => {
            this.store.targetFormat = 'csv';
            this.store.outputText = this.store.buildConvert('csv');
          })
        Text('XML')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'xml' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'xml' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ right: 6 })
          .onClick(() => {
            this.store.targetFormat = 'xml';
            this.store.outputText = this.store.buildConvert('xml');
          })
        Blank()
        Text('应用到编辑器')
          .fontSize(12)
          .fontColor(this.store.theme().canvasBg)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.theme().accent)
          .onClick(() => {
            this.store.applyConvert();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })
      ResultArea()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  sheetContent() {
    Column() {
      Row() {
        Text(this.store.sheetTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.theme().text)
        Blank()
        if (this.store.busy) {
          LoadingProgress().width(18).height(18).margin({ right: 8 })
        }
        Text('✕')
          .fontSize(16)
          .fontColor(this.store.theme().dimText)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .onClick(() => {
            this.store.sheetVisible = false;
          })
      }
      .width('100%')
      .padding({ bottom: 10 })

      if (this.store.modalType === 'url') {
        this.urlForm()
      }

      if (this.store.modalType === 'about') {
        this.aboutContent()
      }

      if (this.store.modalType === 'result' || this.store.modalType === 'node') {
        ResultArea()
      }

      if (this.store.modalType === 'jq' || this.store.modalType === 'path') {
        this.queryBody()
      }

      if (this.store.modalType === 'schema' || this.store.modalType === 'type') {
        this.genBody()
      }

      if (this.store.modalType === 'convert') {
        this.convertBody()
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.store.theme().panelBg)
  }

  build() {
    Column() {
      this.sheetContent()
    }
    .width('88%')
    .height(this.store.panelHeight())
    .constraintSize({ maxWidth: 880, maxHeight: 760 })
    .borderRadius(18)
    .clip(true)
    .shadow({ radius: 28, color: '#66000000', offsetY: 8 })
  }
}
