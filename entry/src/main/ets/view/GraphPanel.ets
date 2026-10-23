import { hilog } from '@kit.PerformanceAnalysisKit';
import { treeLayout } from '../core/TreeLayout';
import { computeBounds } from '../core/EdgeGeometry';
import { HitResult, RenderState, hitTest, renderGraph } from './GraphRenderer';
import { EditorStore } from '../viewmodel/EditorStore';
import { TreePanel } from './TreePanel';

/**
 * 图形区：Canvas 自绘 + 平移/缩放手势 + 图形工具条，树视图也叠加在同一区域。
 *
 * 画布的平移量、缩放比例、尺寸属于纯视图状态，留在这里；
 * 数据结构、折叠集合与主题由 store 统一维护，通过钩子回调触发重绘。
 */
@Component
export struct GraphPanel {
  @Consume('store') store: EditorStore;
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private renderState: RenderState = new RenderState();
  private offsetX: number = 0;
  private offsetY: number = 0;
  private zoomLevel: number = 1;
  private canvasW: number = 0;
  private canvasH: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private lastPinchScale: number = 1;
  /** 正在捏合：屏蔽单指平移，避免两套手势同时改偏移导致缩放锚点漂移 */
  private pinching: boolean = false;
  private panning: boolean = false;
  /** schema 出错路径缓存，避免每帧重建 Set */
  private errorPathCache: string[] = [];
  private errorPathCacheSet: Set<string> = new Set<string>();
  private inited: boolean = false;
  /** 等待适配视图（画布尺寸变化或布局变化后） */
  private fitPending: boolean = true;
  /** 用户是否手动平移/缩放过，手动后不再自动适配 */
  private userAdjusted: boolean = false;

  aboutToAppear(): void {
    this.store.onRepaint = () => {
      this.drawNow();
    };
    this.store.onRequestFit = (immediate: boolean) => {
      this.userAdjusted = false;
      if (immediate) {
        this.fitNow();
      } else {
        this.fitPending = true;
      }
    };
  }

  aboutToDisappear(): void {
    this.store.onRepaint = () => {
    };
    this.store.onRequestFit = (immediate: boolean) => {
    };
  }

  private clampScale(value: number): number {
    if (value < 0.12) {
      return 0.12;
    }
    if (value > 4) {
      return 4;
    }
    return value;
  }

  /** schema 出错路径集合：数组未变化时复用上一次的 Set，避免每帧重建 */
  private errorPathSet(): Set<string> {
    const src = this.store.schemaErrorPaths;
    if (src.length === this.errorPathCache.length) {
      let same = true;
      for (let i = 0; i < src.length; i++) {
        if (src[i] !== this.errorPathCache[i]) {
          same = false;
          break;
        }
      }
      if (same) {
        return this.errorPathCacheSet;
      }
    }
    this.errorPathCache = src.slice();
    const set: Set<string> = new Set<string>();
    for (let i = 0; i < src.length; i++) {
      set.add(src[i]);
    }
    this.errorPathCacheSet = set;
    return set;
  }

  private drawNow(): void {
    if (this.canvasW <= 1 || this.canvasH <= 1) {
      return;
    }
    this.renderState.offsetX = this.offsetX;
    this.renderState.offsetY = this.offsetY;
    this.renderState.scale = this.zoomLevel;
    this.renderState.direction = this.store.layoutDir;
    this.renderState.theme = this.store.theme();
    this.renderState.selectedId = this.store.selectedNodeId;
    this.renderState.errorPaths = this.errorPathSet();
    renderGraph(this.ctx, this.store.graph, this.renderState, this.canvasW, this.canvasH);
  }

  private fitNow(): void {
    this.fitPending = false;
    if (this.canvasW <= 10 || this.canvasH <= 10) {
      this.fitPending = true;
      return;
    }
    const nodes = this.store.graph.nodes;
    if (nodes.length === 0) {
      this.offsetX = 0;
      this.offsetY = 0;
      this.zoomLevel = 1;
      this.drawNow();
      this.store.updateZoom(this.zoomLevel);
      return;
    }
    const bounds = computeBounds(nodes);
    const pad = 48;
    const sx = (this.canvasW - pad * 2) / Math.max(1, bounds.width);
    const sy = (this.canvasH - pad * 2) / Math.max(1, bounds.height);
    let s = Math.min(sx, sy);
    if (s > 1.3) {
      s = 1.3;
    }
    if (s < 0.12) {
      s = 0.12;
    }
    this.zoomLevel = s;
    this.offsetX = (this.canvasW - bounds.width * s) / 2 - bounds.minX * s;
    this.offsetY = (this.canvasH - bounds.height * s) / 2 - bounds.minY * s;
    hilog.info(0x0000, 'HelloJson', 'fitView ' + this.canvasW + 'x' + this.canvasH +
      ' bounds=' + Math.round(bounds.width) + 'x' + Math.round(bounds.height) +
      ' scale=' + this.zoomLevel);
    this.drawNow();
    this.store.updateZoom(this.zoomLevel);
  }

  /** 以组件内坐标 (cx, cy) 为锚点缩放：该点对应的世界坐标保持不动 */
  private zoomAt(cx: number, cy: number, factor: number): void {
    this.userAdjusted = true;
    const wx = (cx - this.offsetX) / this.zoomLevel;
    const wy = (cy - this.offsetY) / this.zoomLevel;
    this.zoomLevel = this.clampScale(this.zoomLevel * factor);
    this.offsetX = cx - wx * this.zoomLevel;
    this.offsetY = cy - wy * this.zoomLevel;
    this.drawNow();
    this.store.updateZoom(this.zoomLevel);
  }

  private zoomBy(factor: number): void {
    this.zoomAt(this.canvasW / 2, this.canvasH / 2, factor);
  }

  /**
   * 取捏合中心点（组件内坐标，vp）。
   * 优先用两根手指在组件内的坐标平均值，比 pinchCenterX/Y 更稳，
   * 可避免不同系统版本下中心点单位或参考原点不一致造成的锚点偏移。
   */
  private pinchCenter(event: GestureEvent): number[] {
    const fingers = event.fingerList;
    if (fingers !== undefined && fingers.length >= 2) {
      return [(fingers[0].localX + fingers[1].localX) / 2,
        (fingers[0].localY + fingers[1].localY) / 2];
    }
    return [event.pinchCenterX, event.pinchCenterY];
  }

  private onCanvasClick(event: ClickEvent): void {
    const worldX = (event.x - this.offsetX) / this.zoomLevel;
    const worldY = (event.y - this.offsetY) / this.zoomLevel;
    const hit: HitResult = hitTest(this.store.graph, worldX, worldY);
    if (!hit.hit) {
      this.store.selectedNodeId = '';
      this.store.selectedPath = '';
      this.drawNow();
      return;
    }
    if (hit.onCollapse) {
      this.store.toggleCollapse(hit.path);
      return;
    }
    this.store.selectedNodeId = hit.nodeId;
    const node = this.store.graph.node(hit.nodeId);
    this.store.selectedPath = node === undefined ? '' : node.path;
    this.drawNow();
    this.store.openNodeDetail(hit.nodeId);
  }

  private toggleLayoutDir(): void {
    if (this.store.layoutDir === 'RIGHT') {
      this.store.layoutDir = 'DOWN';
    } else if (this.store.layoutDir === 'DOWN') {
      this.store.layoutDir = 'LEFT';
    } else if (this.store.layoutDir === 'LEFT') {
      this.store.layoutDir = 'UP';
    } else {
      this.store.layoutDir = 'RIGHT';
    }
    treeLayout.layout(this.store.graph, this.store.layoutDir);
    this.userAdjusted = false;
    this.fitNow();
    this.store.persist();
  }

  @Builder
  graphToolbar() {
    Column() {
      Text('+')
        .fontSize(16)
        .fontColor(this.store.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.store.theme().nodeBg)
        .onClick(() => this.zoomBy(1.25))
      Text('−')
        .fontSize(16)
        .fontColor(this.store.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.store.theme().nodeBg)
        .margin({ top: 6 })
        .onClick(() => this.zoomBy(0.8))
      Text(this.store.showEditor ? '⤢' : '⤡')
        .fontSize(15)
        .fontColor(this.store.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.store.theme().nodeBg)
        .margin({ top: 6 })
        .onClick(() => {
          this.store.showEditor = !this.store.showEditor;
          this.userAdjusted = false;
          this.fitPending = true;
        })
      Text(this.store.layoutDir === 'RIGHT' ? '→' : (this.store.layoutDir === 'DOWN' ? '↓' :
        (this.store.layoutDir === 'LEFT' ? '←' : '↑')))
        .fontSize(15)
        .fontColor(this.store.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.store.theme().nodeBg)
        .margin({ top: 6 })
        .onClick(() => {
          this.toggleLayoutDir();
        })
    }
    .padding(8)
    .borderRadius(10)
    .backgroundColor(this.store.theme().panelBg)
    .border({ width: 0.5, color: this.store.theme().panelBorder })
    .shadow({ radius: 8, color: '#22000000' })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Canvas(this.ctx)
        .id('graphCanvas')
        .width('100%')
        .height('100%')
        .backgroundColor(this.store.theme().canvasBg)
        .onReady(() => {
          this.drawNow();
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.canvasW = Number(newValue.width);
          this.canvasH = Number(newValue.height);
          this.inited = true;
          if (this.canvasW > 10 && this.canvasH > 10) {
            if (this.fitPending || !this.userAdjusted) {
              this.fitNow();
            } else {
              this.drawNow();
            }
          }
        })
        .onClick((event: ClickEvent) => {
          this.onCanvasClick(event);
        })
        .onAxisEvent((event: AxisEvent) => {
          // PC 滚轮 / 触控板：以指针位置为锚点缩放
          const v = event.getVerticalAxisValue();
          if (Math.abs(v) < 0.001) {
            return;
          }
          const factor = v > 0 ? 0.9 : 1.1;
          this.zoomAt(event.x, event.y, factor);
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PanGesture({ fingers: 1, distance: 2 })
              .onActionStart(() => {
                if (this.pinching) {
                  return;
                }
                this.userAdjusted = true;
                this.panning = true;
                this.panStartX = this.offsetX;
                this.panStartY = this.offsetY;
              })
              .onActionUpdate((event: GestureEvent) => {
                // 捏合过程中忽略平移，否则两套手势会同时改写偏移
                if (!this.panning || this.pinching) {
                  return;
                }
                // 多指按下时同样不做平移，避免捏合开始前图形先被拖走
                const fingers = event.fingerList;
                if (fingers !== undefined && fingers.length > 1) {
                  return;
                }
                this.offsetX = this.panStartX + event.offsetX;
                this.offsetY = this.panStartY + event.offsetY;
                this.drawNow();
              })
              .onActionEnd(() => {
                this.panning = false;
              })
              .onActionCancel(() => {
                this.panning = false;
              }),
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.userAdjusted = true;
                this.pinching = true;
                this.panning = false;
                this.lastPinchScale = 1;
              })
              .onActionUpdate((event: GestureEvent) => {
                const factor = event.scale / this.lastPinchScale;
                this.lastPinchScale = event.scale;
                const center = this.pinchCenter(event);
                const cx = center[0];
                const cy = center[1];
                const wx = (cx - this.offsetX) / this.zoomLevel;
                const wy = (cy - this.offsetY) / this.zoomLevel;
                this.zoomLevel = this.clampScale(this.zoomLevel * factor);
                this.offsetX = cx - wx * this.zoomLevel;
                this.offsetY = cy - wy * this.zoomLevel;
                this.drawNow();
              })
              .onActionEnd(() => {
                this.pinching = false;
                // 让后续单指拖动以当前偏移为基准，避免松手后跳变
                this.panStartX = this.offsetX;
                this.panStartY = this.offsetY;
                this.store.updateZoom(this.zoomLevel);
              })
              .onActionCancel(() => {
                this.pinching = false;
                this.panStartX = this.offsetX;
                this.panStartY = this.offsetY;
              })
          )
        )

      if (this.store.viewMode === 'tree') {
        TreePanel()
      }

      if (this.store.graph.nodes.length === 0) {
        Text(this.store.errorMsg.length > 0 ?
          ('JSON 解析失败: ' + this.store.errorMsg) : '输入 JSON 以生成图形')
          .fontSize(13)
          .fontColor(this.store.theme().dimText)
          .align(Alignment.Center)
          .padding(24)
          .textAlign(TextAlign.Center)
      }

      this.graphToolbar()
    }
    .layoutWeight(1)
    .width('100%')
  }
}
