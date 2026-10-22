import { EditorStore } from '../viewmodel/EditorStore';

/** 左右（上下）分栏拖拽条 */
@Component
export struct Splitter {
  @Consume('store') store: EditorStore;
  private splitStart: number = 0.46;

  build() {
    Stack() {
      Column()
        .width(this.store.stackVertical ? '100%' : 2)
        .height(this.store.stackVertical ? 2 : '100%')
        .backgroundColor(this.store.theme().panelBorder)
    }
    .width(this.store.stackVertical ? '100%' : 16)
    .height(this.store.stackVertical ? 16 : '100%')
    .backgroundColor(this.store.theme().panelBg)
    .gesture(
      PanGesture({ fingers: 1, distance: 1 })
        .onActionStart(() => {
          this.splitStart = this.store.splitRatio;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.store.stackVertical) {
            if (this.store.flexH > 0) {
              this.store.splitRatio = this.store.clampRatio(this.splitStart + event.offsetY / this.store.flexH);
            }
          } else if (this.store.flexW > 0) {
            this.store.splitRatio = this.store.clampRatio(this.splitStart + event.offsetX / this.store.flexW);
          }
        })
    )
  }
}
