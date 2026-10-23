import { EditorStore } from '../viewmodel/EditorStore';

/**
 * 打开 / 解析大文件时的全屏进度遮罩：阻断误触，并给出「正在打开 / 正在解析」反馈。
 * 进度未知（如解码、解析阶段）时只显示转圈，知道字节进度时额外显示进度条。
 *
 * 转圈用「属性动画驱动的旋转弧线」而不是 LoadingProgress：
 * 解析会长时间占满 JS 线程，系统 LoadingProgress 的动画停摆，看上去像卡死；
 * animateTo 的属性动画由渲染线程插值，JS 线程被占用时仍能继续转动。
 * 视觉上做成「淡色圆环 + 一小段亮弧」，转起来就是常见的加载指示，而不是整个图标绕圈。
 */
@Component
export struct BusyOverlay {
  @Consume('store') store: EditorStore;
  @State private spinAngle: number = 0;

  aboutToAppear(): void {
    this.startSpin();
  }

  private startSpin(): void {
    animateTo({
      duration: 800,
      curve: Curve.Linear,
      iterations: -1,
      playMode: PlayMode.Normal
    }, () => {
      this.spinAngle = 360;
    });
  }

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
          Stack({ alignContent: Alignment.Center }) {
            // 淡色整环作为轨道
            Circle()
              .width(18)
              .height(18)
              .fillOpacity(0)
              .stroke(this.store.theme().keyText)
              .strokeWidth(2)
              .opacity(0.2)

            // 一小段亮弧：绕自身圆心旋转，形成转圈效果
            Path()
              .commands('M 10 1 A 9 9 0 0 1 19 10')
              .fillOpacity(0)
              .stroke(this.store.theme().keyText)
              .strokeWidth(2)
              .strokeLineCap(LineCapStyle.Round)
              .width(20)
              .height(20)
              .rotate({ angle: this.spinAngle })
          }
          .width(20)
          .height(20)
          .accessibilityText('加载中')

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
