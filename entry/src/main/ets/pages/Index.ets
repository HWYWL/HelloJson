import { common } from '@kit.AbilityKit';
import { EditorStore } from '../viewmodel/EditorStore';
import { TopBar } from '../view/TopBar';
import { EditorPanel } from '../view/EditorPanel';
import { GraphPanel } from '../view/GraphPanel';
import { Splitter } from '../view/Splitter';
import { BottomBar } from '../view/BottomBar';
import { PanelHost } from '../view/PanelHost';

/**
 * 页面只负责布局编排与生命周期：
 * 共享状态由 @Provide 注入，各区域通过 @Consume 订阅同一份 EditorStore。
 */
@Entry
@Component
struct Index {
  @Provide('store') store: EditorStore = new EditorStore();

  aboutToAppear(): void {
    this.store.init(getContext(this) as common.UIAbilityContext);
  }

  aboutToDisappear(): void {
    this.store.persist();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        TopBar()
        Flex({ direction: this.store.stackVertical ? FlexDirection.Column : FlexDirection.Row }) {
          if (this.store.showEditor) {
            EditorPanel()
            Splitter()
          }
          GraphPanel()
        }
        .layoutWeight(1)
        .width('100%')
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.store.onContentResize(Number(newValue.width), Number(newValue.height));
        })
        BottomBar()
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.store.onRootResize(Number(newValue.width));
      })
      .onKeyEvent((e: KeyEvent) => {
        this.store.onGlobalKey(e);
      })

      if (this.store.sheetVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => {
            this.store.sheetVisible = false;
          })
        PanelHost()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.theme().canvasBg)
  }
}
