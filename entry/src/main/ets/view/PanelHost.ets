import { DiffLine } from '../core/JsonDiff';
import { SchemaError } from '../core/SchemaValidator';
import { EditorStore } from '../viewmodel/EditorStore';
import { TabInfo } from '../viewmodel/Types';
import { ResultArea } from './ResultArea';

/**
 * 居中浮动面板：URL 导入、关于、节点详情、jq / JSONPath、Schema / 类型、格式转换。
 * 内容由 store.modalType 决定，遮罩层与外层定位由页面负责。
 * 标题栏可拖动，偏移被限制在可视区域内。
 */
@Component
export struct PanelHost {
  @Consume('store') store: EditorStore;
  /** 相对居中位置的拖拽偏移 */
  @State dragX: number = 0;
  @State dragY: number = 0;
  /** 面板实际尺寸，用于限制拖拽范围 */
  @State panelW: number = 0;
  @State panelH: number = 0;
  private dragBaseX: number = 0;
  private dragBaseY: number = 0;

  private maxDragX(): number {
    const w = this.store.flexW > 0 ? this.store.flexW : 360;
    const limit = (w - this.panelW) / 2;
    return limit > 0 ? limit : 0;
  }

  private maxDragY(): number {
    const h = this.store.flexH > 0 ? this.store.flexH : 640;
    const limit = (h - this.panelH) / 2;
    return limit > 0 ? limit : 0;
  }

  private clampValue(value: number, limit: number): number {
    if (value > limit) {
      return limit;
    }
    if (value < -limit) {
      return -limit;
    }
    return value;
  }

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
        Flex({ wrap: FlexWrap.Wrap }) {
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
            .margin({ right: 6 })
            .onClick(() => {
              this.store.genLanguage = 'rust';
              this.store.outputText = this.store.buildTypes('rust');
            })
          Text('Java')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'java' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'java' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .margin({ right: 6 })
            .onClick(() => {
              this.store.genLanguage = 'java';
              this.store.outputText = this.store.buildTypes('java');
            })
          Text('C#')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'csharp' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'csharp' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .margin({ right: 6 })
            .onClick(() => {
              this.store.genLanguage = 'csharp';
              this.store.outputText = this.store.buildTypes('csharp');
            })
          Text('Swift')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'swift' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'swift' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .margin({ right: 6 })
            .onClick(() => {
              this.store.genLanguage = 'swift';
              this.store.outputText = this.store.buildTypes('swift');
            })
          Text('Dart')
            .fontSize(12)
            .fontColor(this.store.genLanguage === 'dart' ? this.store.theme().canvasBg : this.store.theme().text)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.store.genLanguage === 'dart' ?
              this.store.theme().accent : this.store.theme().nodeBgAlt)
            .onClick(() => {
              this.store.genLanguage = 'dart';
              this.store.outputText = this.store.buildTypes('dart');
            })
        }
        .width('100%')
        .margin({ bottom: 8 })
        if (this.store.genLanguage === 'java') {
          Row() {
            Text('get / set')
              .fontSize(12)
              .fontColor(this.store.javaLombok ? this.store.theme().text : this.store.theme().canvasBg)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.store.javaLombok ?
                this.store.theme().nodeBgAlt : this.store.theme().accent)
              .margin({ right: 6 })
              .onClick(() => {
                this.store.javaLombok = false;
                this.store.outputText = this.store.buildTypes('java');
              })
            Text('Lombok')
              .fontSize(12)
              .fontColor(this.store.javaLombok ? this.store.theme().canvasBg : this.store.theme().text)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.store.javaLombok ?
                this.store.theme().accent : this.store.theme().nodeBgAlt)
              .onClick(() => {
                this.store.javaLombok = true;
                this.store.outputText = this.store.buildTypes('java');
              })
          }
          .width('100%')
          .margin({ bottom: 8 })
        }
        if (this.store.genLanguage === 'typescript') {
          Row() {
            Text('字段可选')
              .fontSize(12)
              .fontColor(this.store.typeOptional ? this.store.theme().canvasBg : this.store.theme().text)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.store.typeOptional ?
                this.store.theme().accent : this.store.theme().nodeBgAlt)
              .margin({ right: 6 })
              .onClick(() => {
                this.store.typeOptional = !this.store.typeOptional;
                this.store.outputText = this.store.buildTypes('typescript');
              })
            Text('export')
              .fontSize(12)
              .fontColor(this.store.typeExport ? this.store.theme().canvasBg : this.store.theme().text)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.store.typeExport ?
                this.store.theme().accent : this.store.theme().nodeBgAlt)
              .margin({ right: 6 })
              .onClick(() => {
                this.store.typeExport = !this.store.typeExport;
                this.store.outputText = this.store.buildTypes('typescript');
              })
            Text('从 Schema 生成')
              .fontSize(12)
              .fontColor(this.store.theme().accent)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.store.theme().nodeBgAlt)
              .onClick(() => {
                this.store.generateTypesFromSchema();
              })
          }
          .width('100%')
          .margin({ bottom: 8 })
        } else {
          Row() {
            Text('从 Schema 生成')
              .fontSize(12)
              .fontColor(this.store.theme().accent)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.store.theme().nodeBgAlt)
              .onClick(() => {
                this.store.generateTypesFromSchema();
              })
          }
          .width('100%')
          .margin({ bottom: 8 })
        }
      }
      ResultArea()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  convertBody() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        Text('YAML')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'yaml' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'yaml' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ right: 6, bottom: 6 })
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
          .margin({ right: 6, bottom: 6 })
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
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.store.targetFormat = 'xml';
            this.store.outputText = this.store.buildConvert('xml');
          })
        Text('TOML')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'toml' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'toml' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.store.targetFormat = 'toml';
            this.store.outputText = this.store.buildConvert('toml');
          })
        Text('Properties')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'properties' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'properties' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.store.targetFormat = 'properties';
            this.store.outputText = this.store.buildConvert('properties');
          })
        Text('查询串')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'query' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'query' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.store.targetFormat = 'query';
            this.store.outputText = this.store.buildConvert('query');
          })
        Text('Markdown')
          .fontSize(12)
          .fontColor(this.store.targetFormat === 'markdown' ? this.store.theme().canvasBg : this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.targetFormat === 'markdown' ?
            this.store.theme().accent : this.store.theme().nodeBgAlt)
          .margin({ bottom: 6 })
          .onClick(() => {
            this.store.targetFormat = 'markdown';
            this.store.outputText = this.store.buildConvert('markdown');
          })
      }
      .width('100%')
      .margin({ bottom: 2 })
      Row() {
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

  /** schema 校验面板：载入 schema → 校验 → 错误逐条定位 */
  @Builder
  schemaCheckBody() {
    Column() {
      Row() {
        Text(this.store.schemaName.length > 0 ? this.store.schemaName : '未载入 schema')
          .fontSize(12)
          .fontColor(this.store.schemaName.length > 0 ? this.store.theme().text : this.store.theme().dimText)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ right: 8 })
        Text('选文件')
          .fontSize(12)
          .fontColor(this.store.theme().canvasBg)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.theme().accent)
          .margin({ right: 6 })
          .onClick(() => {
            this.store.pickSchemaFile();
          })
        Text('粘贴')
          .fontSize(12)
          .fontColor(this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.theme().nodeBgAlt)
          .margin({ right: 6 })
          .onClick(() => {
            this.store.pasteSchemaFromClipboard();
          })
        Text('示例')
          .fontSize(12)
          .fontColor(this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.theme().nodeBgAlt)
          .margin({ right: 6 })
          .onClick(() => {
            this.store.useDemoSchema();
          })
        Text('重校验')
          .fontSize(12)
          .fontColor(this.store.theme().text)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.theme().nodeBgAlt)
          .margin({ right: 6 })
          .onClick(() => {
            this.store.runSchemaCheck();
          })
        Text('生成数据')
          .fontSize(12)
          .fontColor(this.store.theme().accent)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.store.theme().nodeBgAlt)
          .onClick(() => {
            this.store.generateSchemaMock();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.store.schemaMessage.length > 0) {
        Text(this.store.schemaMessage)
          .fontSize(11)
          .fontColor(this.store.theme().errorColor)
          .width('100%')
          .margin({ bottom: 6 })
      }

      if (this.store.schemaChecked) {
        Text(this.store.schemaOk ?
          '校验通过：文档符合该 schema' :
          ('不符合该 schema：共 ' + this.store.schemaErrors.length.toString() + ' 处问题'))
          .fontSize(12)
          .fontColor(this.store.schemaOk ? this.store.theme().successColor : this.store.theme().errorColor)
          .width('100%')
          .margin({ bottom: 6 })
      }

      if (this.store.schemaErrors.length > 0) {
        List() {
          ForEach(this.store.schemaErrors, (err: SchemaError, index: number) => {
            ListItem() {
              Row() {
                Text('L' + err.line.toString())
                  .fontSize(10)
                  .fontColor(this.store.theme().errorColor)
                  .width(44)
                  .textAlign(TextAlign.End)
                  .margin({ right: 8 })
                Column() {
                  Text(err.path)
                    .fontSize(11)
                    .fontFamily('monospace')
                    .fontColor(this.store.theme().text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(err.message)
                    .fontSize(10)
                    .fontColor(this.store.theme().dimText)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ top: 5, bottom: 5 })
              .onClick(() => {
                this.store.gotoSchemaError(index);
              })
            }
          }, (err: SchemaError, index: number) => index.toString() + '_' + err.path + '_' + err.message)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(this.store.theme().canvasBg)
        .borderRadius(8)
        .padding(4)
        .divider({ strokeWidth: 0.5, color: this.store.theme().panelBorder })
        .scrollBar(BarState.Auto)
      } else if (this.store.schemaText.length === 0) {
        Text('点「示例」可一键体验，或选择一份 JSON Schema（draft-07）文件校验当前文档。\n' +
          '支持 type / required / properties / additionalProperties / items / enum / const /\n' +
          'minimum / maximum / minLength / maxLength / pattern / allOf / anyOf / oneOf / not /\n' +
          '本地 $ref（#/definitions、#/$defs）。')
          .fontSize(11)
          .fontColor(this.store.theme().dimText)
          .width('100%')
          .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** A / B 两侧的标签选择条（外观依赖状态，写成无参 Builder） */
  @Builder
  diffPickers() {
    Column() {
      Row() {
        Text('A')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.theme().dimText)
          .width(20)
        Scroll() {
          Row() {
            ForEach(this.store.tabs, (t: TabInfo) => {
              Text(t.title)
                .fontSize(11)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 140 })
                .fontColor(this.store.diffA === t.id ? this.store.theme().canvasBg : this.store.theme().text)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(5)
                .margin({ right: 4 })
                .backgroundColor(this.store.diffA === t.id ?
                  this.store.theme().accent : this.store.theme().nodeBgAlt)
                .onClick(() => this.store.setDiffSide('a', t.id))
            }, (t: TabInfo) => 'a_' + t.id)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Start)
      }
      .width('100%')
      .height(30)
      .margin({ bottom: 6 })

      Row() {
        Text('B')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.store.theme().dimText)
          .width(20)
        Scroll() {
          Row() {
            ForEach(this.store.tabs, (t: TabInfo) => {
              Text(t.title)
                .fontSize(11)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 140 })
                .fontColor(this.store.diffB === t.id ? this.store.theme().canvasBg : this.store.theme().text)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(5)
                .margin({ right: 4 })
                .backgroundColor(this.store.diffB === t.id ?
                  this.store.theme().accent : this.store.theme().nodeBgAlt)
                .onClick(() => this.store.setDiffSide('b', t.id))
            }, (t: TabInfo) => 'b_' + t.id)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Start)
      }
      .width('100%')
      .height(30)
      .margin({ bottom: 6 })
    }
    .width('100%')
  }

  @Builder
  diffSummary() {
    Row() {
      Text(this.store.diffAdded === 0 && this.store.diffRemoved === 0 ?
        '两份文档内容一致' : ('+' + this.store.diffAdded + ' 行 / −' + this.store.diffRemoved + ' 行'))
        .fontSize(11)
        .fontColor(this.store.diffAdded === 0 && this.store.diffRemoved === 0 ?
          this.store.theme().successColor : this.store.theme().dimText)
      if (this.store.diffTruncated) {
        Text('（差异过大，仅显示前 4000 行）')
          .fontSize(10)
          .fontColor(this.store.theme().errorColor)
          .margin({ left: 6 })
      }
      Blank()
    }
    .width('100%')
    .margin({ bottom: 6 })
  }

  @Builder
  diffList() {
    List() {
      ForEach(this.store.diffRows, (row: DiffLine, index: number) => {
        ListItem() {
          Row() {
            Text(row.aLine === 0 ? '' : row.aLine.toString())
              .fontSize(10)
              .fontColor(this.store.theme().dimText)
              .width(36)
              .textAlign(TextAlign.End)
              .margin({ right: 6 })
            Text(row.bLine === 0 ? '' : row.bLine.toString())
              .fontSize(10)
              .fontColor(this.store.theme().dimText)
              .width(36)
              .textAlign(TextAlign.End)
              .margin({ right: 6 })
            Text(row.kind === 'add' ? '+' : (row.kind === 'del' ? '−' : ' '))
              .fontSize(11)
              .fontColor(row.kind === 'add' ? this.store.theme().successColor :
                (row.kind === 'del' ? this.store.theme().errorColor : this.store.theme().dimText))
              .width(12)
            Text(row.text.length === 0 ? ' ' : row.text)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor(row.kind === 'del' ? this.store.theme().errorColor :
                (row.kind === 'add' ? this.store.theme().successColor : this.store.theme().text))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ top: 1, bottom: 1 })
          .backgroundColor(row.kind === 'add' ? '#1A4EC9B0' :
            (row.kind === 'del' ? '#1AF14C4C' : '#00000000'))
        }
      }, (row: DiffLine, index: number) => this.store.diffSeq.toString() + '_' + index.toString())
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(this.store.theme().canvasBg)
    .borderRadius(8)
    .padding(4)
    .scrollBar(BarState.Auto)
    .cachedCount(20)
  }

  @Builder
  diffBody() {
    Column() {
      this.diffPickers()
      this.diffSummary()
      this.diffList()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  sheetContent() {
    Column() {
      Row() {
        Text('⠿')
          .fontSize(15)
          .fontColor(this.store.theme().dimText)
          .margin({ right: 6 })
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
      .gesture(
        PanGesture({ fingers: 1, distance: 5 })
          .onActionStart(() => {
            this.dragBaseX = this.dragX;
            this.dragBaseY = this.dragY;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.dragX = this.clampValue(this.dragBaseX + event.offsetX, this.maxDragX());
            this.dragY = this.clampValue(this.dragBaseY + event.offsetY, this.maxDragY());
          })
      )

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

      if (this.store.modalType === 'diff') {
        this.diffBody()
      }

      if (this.store.modalType === 'schemaCheck') {
        this.schemaCheckBody()
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
    .translate({ x: this.dragX, y: this.dragY })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.panelW = Number(newValue.width);
      this.panelH = Number(newValue.height);
    })
  }
}
