import { common, bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { JKind, JValue } from '../core/JValue';
import { jsonParser, ParseResult } from '../core/JsonParser';
import { stringifyJson, sortKeysDeep, escapeWholeText, unescapeWholeText } from '../core/JsonWriter';
import { GraphData, GraphTheme, darkTheme, lightTheme, rowColor } from '../core/GraphModel';
import { GraphBuilder } from '../core/GraphBuilder';
import { treeLayout } from '../core/TreeLayout';
import { RenderState, renderGraph, hitTest, HitResult } from '../view/GraphRenderer';
import { computeBounds } from '../core/EdgeGeometry';
import { jqEngine, JqResult } from '../core/JqEngine';
import { jsonPathEngine, JPathResult } from '../core/JsonPathEngine';
import { schemaGenerator, typeGenerator } from '../core/CodeGen';
import { jsonToYaml, yamlToJson, jsonToCsv, csvToJson, jsonToXml, xmlToJson } from '../core/Convert';
import { buildSvg } from '../core/SvgExport';
import { AppConfig, configStore } from '../core/Storage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyCode } from '@kit.InputKit';

const SAMPLE: string = `{
  "name": "HelloJson",
  "version": "1.0.0",
  "description": "原生鸿蒙 JSON 可视化工具",
  "features": [
    "图形可视化",
    "树形视图",
    "jq 查询",
    "JSONPath 查询"
  ],
  "author": {
    "name": "一叶秋枫",
    "homepage": "https://github.com/HWYWL/HelloJson"
  },
  "stats": {
    "stars": 128,
    "active": true,
    "tags": ["harmonyos", "arkts", "json"]
  }
}`;

const SAMPLE_YAML: string = `app:
  name: HelloJson
  version: 1.0.0
  description: 原生鸿蒙 JSON 可视化工具
  features:
    - 图形可视化
    - 树形视图
    - jq 查询
  author:
    name: 一叶秋枫
    homepage: https://github.com/HWYWL/HelloJson
  stats:
    stars: 128
    active: true
`;

const SAMPLE_CSV: string = `name,version,stars,active,lang
HelloJson,1.0.0,128,true,ArkTS
QuickTerm,2.1.0,356,true,Rust
JsonViewer,0.9.3,87,false,TypeScript
`;

const SAMPLE_XML: string = `<?xml version="1.0" encoding="UTF-8"?>
<app>
  <name>HelloJson</name>
  <version>1.0.0</version>
  <description>原生鸿蒙 JSON 可视化工具</description>
  <features>
    <feature>图形可视化</feature>
    <feature>树形视图</feature>
    <feature>JSONPath 查询</feature>
  </features>
  <author>
    <name>一叶秋枫</name>
    <homepage>https://github.com/HWYWL/HelloJson</homepage>
  </author>
</app>`;

/** 语法高亮的文本片段 */
class HSpan {
  text: string = '';
  color: string = '';
  /** 查找命中背景色，空串表示无背景 */
  bg: string = '';

  constructor(text: string, color: string, bg: string = '') {
    this.text = text;
    this.color = color;
    this.bg = bg;
  }
}

class TreeItem {
  depth: number = 0;
  label: string = '';
  value: string = '';
  kind: JKind = JKind.Null;
  path: string = '';
  hasChildren: boolean = false;
  collapsed: boolean = false;
  isContainer: boolean = false;
}

@Entry
@Component
struct Index {
  @State jsonText: string = SAMPLE;
  @State errorMsg: string = '';
  @State errorLine: number = 0;
  @State nodeCount: number = 0;
  @State edgeCount: number = 0;
  @State darkMode: boolean = false;
  @State layoutDir: string = 'DOWN';
  @State viewMode: string = 'graph';
  @State zoomText: string = '100%';
  @State selectedPath: string = '';
  @State showEditor: boolean = true;
  @State sheetVisible: boolean = false;
  @State sheetTitle: string = '';
  @State modalType: string = '';
  @State expressionInput: string = '';
  @State urlInput: string = '';
  @State outputText: string = '';
  @State genLanguage: string = 'typescript';
  @State targetFormat: string = 'yaml';
  @State findVisible: boolean = false;
  @State findQuery: string = '';
  @State findIndex: number = 0;
  @State findTotal: number = 0;
  @State stackVertical: boolean = true;
  @State treeItems: TreeItem[] = [];
  @State busy: boolean = false;
  @State highlighted: boolean = false;
  @State spans: HSpan[] = [];
  @State lineCount: number = 1;
  @State charCount: number = 0;
  @State samplePicker: boolean = false;
  @State splitRatio: number = 0.46;
  @State appVersion: string = '1.0.0';

  private graph: GraphData = new GraphData();
  private root: JValue | null = null;
  private collapsed: Set<string> = new Set<string>();
  private treeCollapsed: Set<string> = new Set<string>();
  /** 文本查找命中位置（字符偏移，升序） */
  private findMatches: number[] = [];
  private textScroller: Scroller = new Scroller();
  private textContentH: number = 0;
  private textViewH: number = 0;
  /** 片段版本号，变化时强制重建 Span（查找高亮切换用） */
  private spanSeq: number = 0;
  private offsetX: number = 0;
  private offsetY: number = 0;
  private zoomLevel: number = 1;
  private canvasW: number = 0;
  private canvasH: number = 0;
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private renderState: RenderState = new RenderState();
  private parseTimer: number = -1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private lastPinchScale: number = 1;
  private darkThemeRef: GraphTheme = darkTheme();
  private lightThemeRef: GraphTheme = lightTheme();
  private inited: boolean = false;
  private fitPending: boolean = true;
  private userAdjusted: boolean = false;
  private flexW: number = 0;
  private flexH: number = 0;
  private splitStart: number = 0.46;
  private pendingAutoFit: boolean = false;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    configStore.init(context);
    const cfg = configStore.load();
    this.darkMode = cfg.darkMode;
    this.layoutDir = cfg.direction;
    this.viewMode = cfg.viewMode;
    if (cfg.jsonText.length > 0) {
      this.jsonText = cfg.jsonText;
    }
    this.renderState.theme = this.theme();
    this.parseAndRender(true);
    this.autoFitEditorWidth();
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
    } catch (e) {
      hilog.warn(0x0000, 'HelloJson', 'read bundle version failed');
    }
  }

  aboutToDisappear(): void {
    this.persist();
  }

  private persist(): void {
    const cfg = new AppConfig();
    cfg.darkMode = this.darkMode;
    cfg.direction = this.layoutDir;
    cfg.viewMode = this.viewMode;
    cfg.jsonText = this.jsonText;
    configStore.save(cfg);
  }

  private theme(): GraphTheme {
    return this.darkMode ? this.darkThemeRef : this.lightThemeRef;
  }

  private clampRatio(value: number): number {
    if (value < 0.18) {
      return 0.18;
    }
    if (value > 0.82) {
      return 0.82;
    }
    return value;
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

  /** 按最长一行自动收缩左栏宽度（不超过总宽一半） */
  private autoFitEditorWidth(): void {
    if (this.stackVertical) {
      this.pendingAutoFit = true;
      return;
    }
    if (this.flexW <= 10) {
      this.pendingAutoFit = true;
      return;
    }
    this.pendingAutoFit = false;
    const lines = this.jsonText.split('\n');
    let maxUnits = 0;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      let units = 0;
      for (let j = 0; j < line.length; j++) {
        units += line.charCodeAt(j) > 0x2e80 ? 2 : 1;
      }
      if (units > maxUnits) {
        maxUnits = units;
      }
    }
    if (maxUnits <= 0) {
      return;
    }
    const desired = maxUnits * 7.4 + 40;
    let ratio = desired / this.flexW;
    if (ratio < 0.18) {
      ratio = 0.18;
    }
    if (ratio > 0.5) {
      ratio = 0.5;
    }
    if (Math.abs(ratio - this.splitRatio) > 0.01) {
      this.splitRatio = ratio;
      this.userAdjusted = false;
      this.fitPending = true;
    }
  }

  private parseAndRender(autoFit: boolean): void {
    this.updateTextStats();
    const result: ParseResult = jsonParser.parse(this.jsonText);
    if (!result.ok || result.root === null) {
      this.errorMsg = result.error === null ? '解析失败' : result.error.message;
      this.errorLine = result.error === null ? 0 : result.error.line;
      this.refreshHighlight();
      return;
    }
    this.errorMsg = '';
    this.errorLine = 0;
    this.root = result.root;
    this.refreshHighlight();
    this.rebuildGraph();
    if (this.viewMode === 'tree') {
      this.refreshTree();
    }
    if (autoFit) {
      this.fitPending = true;
      if (this.canvasW > 10 && this.canvasH > 10) {
        this.fitView(false);
        this.fitPending = false;
      }
    }
    this.draw();
  }

  private updateTextStats(): void {
    this.charCount = this.jsonText.length;
    let lines = 1;
    for (let i = 0; i < this.jsonText.length; i++) {
      if (this.jsonText.charAt(i) === '\n') {
        lines++;
      }
    }
    this.lineCount = lines;
  }

  /** 生成按数据类型着色的片段 */
  private refreshHighlight(): void {
    if (!this.highlighted) {
      return;
    }
    const t = this.theme();
    this.spanSeq++;
    if (this.jsonText.length > 40000) {
      this.spans = this.decorateSpans([new HSpan(this.jsonText, t.text)], t);
      return;
    }
    const out: HSpan[] = [];
    const text = this.jsonText;
    const n = text.length;
    let i = 0;
    while (i < n) {
      const c = text.charAt(i);
      if (c === '"') {
        let j = i + 1;
        while (j < n) {
          const ch = text.charAt(j);
          if (ch === '\\') {
            j += 2;
            continue;
          }
          j++;
          if (ch === '"') {
            break;
          }
        }
        if (j > n) {
          j = n;
        }
        let k = j;
        while (k < n && (text.charAt(k) === ' ' || text.charAt(k) === '\t')) {
          k++;
        }
        const isKey = k < n && text.charAt(k) === ':';
        out.push(new HSpan(text.substring(i, j), isKey ? t.keyText : t.stringColor));
        i = j;
        continue;
      }
      if (c === '-' || (c >= '0' && c <= '9')) {
        let j = c === '-' ? i + 1 : i;
        const digitsStart = j;
        while (j < n) {
          const ch = text.charAt(j);
          if ((ch >= '0' && ch <= '9') || ch === '.' || ch === 'e' || ch === 'E' || ch === '+' || ch === '-') {
            j++;
          } else {
            break;
          }
        }
        if (j > digitsStart) {
          out.push(new HSpan(text.substring(i, j), t.numberColor));
          i = j;
          continue;
        }
      }
      if (text.startsWith('true', i) || text.startsWith('false', i) || text.startsWith('null', i)) {
        const lit = text.startsWith('true', i) ? 'true' :
          (text.startsWith('false', i) ? 'false' : 'null');
        out.push(new HSpan(lit, lit === 'null' ? t.nullColor : t.boolColor));
        i += lit.length;
        continue;
      }
      let j = i + 1;
      while (j < n) {
        const ch = text.charAt(j);
        if (ch === '"' || ch === '-' || (ch >= '0' && ch <= '9') ||
          ch === 't' || ch === 'f' || ch === 'n') {
          break;
        }
        j++;
      }
      out.push(new HSpan(text.substring(i, j), t.dimText));
      i = j;
    }
    this.spans = this.decorateSpans(out, t);
  }

  /** ---------- 文本查找（浏览器风格） ---------- */

  /** 打开查找栏，并切到高亮视图（TextArea 无法做局部高亮） */
  private openFind(): void {
    if (!this.showEditor) {
      this.showEditor = true;
    }
    if (!this.highlighted) {
      this.highlighted = true;
      this.refreshHighlight();
    }
    this.samplePicker = false;
    this.findVisible = true;
    this.doFind(true);
  }

  /** 读取修饰键状态（不同键盘布局/版本下键名大小写不一致，两种都试） */
  private modState(e: KeyEvent, key: string): boolean {
    if (e.getModifierKeyState === undefined) {
      return false;
    }
    try {
      return e.getModifierKeyState([key]);
    } catch (err) {
      return false;
    }
  }

  /** 全局快捷键：Ctrl+F 打开查找，Esc 关闭查找 */
  private onGlobalKey(e: KeyEvent): void {
    if (e.type !== KeyType.Down) {
      return;
    }
    const ctrl = this.modState(e, 'Ctrl') || this.modState(e, 'ctrl');
    if (ctrl && e.keyCode === KeyCode.KEYCODE_F) {
      this.openFind();
      e.stopPropagation();
      return;
    }
    if (this.findVisible && e.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeFind();
      e.stopPropagation();
    }
  }

  private closeFind(): void {
    this.findVisible = false;
    this.findMatches = [];
    this.findTotal = 0;
    this.findIndex = 0;
    this.refreshHighlight();
  }

  /** 重新计算命中位置；jump 为 true 时跳到首个命中 */
  private doFind(jump: boolean): void {
    this.findMatches = [];
    const q = this.findQuery.toLowerCase();
    if (q.length > 0) {
      const lower = this.jsonText.toLowerCase();
      let from = 0;
      while (from <= lower.length - q.length) {
        const idx = lower.indexOf(q, from);
        if (idx < 0) {
          break;
        }
        this.findMatches.push(idx);
        if (this.findMatches.length >= 5000) {
          break;
        }
        from = idx + q.length;
      }
    }
    this.findTotal = this.findMatches.length;
    if (jump) {
      this.findIndex = this.findTotal > 0 ? 1 : 0;
      this.scrollToMatch();
    } else if (this.findIndex > this.findTotal) {
      this.findIndex = this.findTotal;
    }
    this.refreshHighlight();
  }

  /** step: 1 下一个，-1 上一个 */
  private findStep(step: number): void {
    if (this.findTotal === 0) {
      this.doFind(true);
      return;
    }
    let idx = this.findIndex + step;
    if (idx > this.findTotal) {
      idx = 1;
    } else if (idx < 1) {
      idx = this.findTotal;
    }
    this.findIndex = idx;
    this.refreshHighlight();
    this.scrollToMatch();
  }

  /**
   * 滚动到当前命中：按字符偏移在全文中的比例估算纵向位置。
   * 高亮视图是等宽字体 + 固定宽度换行，视觉高度与字符数近似成正比。
   */
  private scrollToMatch(): void {
    if (this.findIndex < 1 || this.findIndex > this.findMatches.length) {
      return;
    }
    const total = this.jsonText.length;
    if (total <= 0 || this.textContentH <= this.textViewH) {
      return;
    }
    const offset = this.findMatches[this.findIndex - 1];
    let y = (offset / total) * this.textContentH - this.textViewH / 3;
    const maxY = this.textContentH - this.textViewH;
    if (y < 0) {
      y = 0;
    }
    if (y > maxY) {
      y = maxY;
    }
    this.textScroller.scrollTo({ xOffset: 0, yOffset: y });
  }

  /** 按命中位置切分片段，给命中文字加背景（当前命中用强调色） */
  private decorateSpans(src: HSpan[], t: GraphTheme): HSpan[] {
    const q = this.findQuery.length;
    if (!this.findVisible || q === 0 || this.findMatches.length === 0) {
      return src;
    }
    const out: HSpan[] = [];
    const cur = this.findIndex - 1;
    let off = 0;
    let mi = 0;
    for (let i = 0; i < src.length; i++) {
      const sp = src[i];
      const s = off;
      const e = off + sp.text.length;
      off = e;
      let pos = s;
      while (pos < e) {
        while (mi < this.findMatches.length && this.findMatches[mi] + q <= pos) {
          mi++;
        }
        if (mi >= this.findMatches.length) {
          out.push(new HSpan(sp.text.substring(pos - s), sp.color));
          break;
        }
        const ms = this.findMatches[mi];
        if (ms >= e) {
          out.push(new HSpan(sp.text.substring(pos - s), sp.color));
          break;
        }
        if (ms > pos) {
          out.push(new HSpan(sp.text.substring(pos - s, ms - s), sp.color));
        }
        const me = Math.min(ms + q, e);
        const isCur = mi === cur;
        out.push(new HSpan(sp.text.substring(ms - s, me - s),
          isCur ? t.matchTextActive : sp.color,
          isCur ? t.matchBgActive : t.matchBg));
        pos = me;
        if (me === ms + q) {
          mi++;
        }
      }
    }
    return out;
  }

  /** 载入示例前先清空现有数据 */
  private clearAll(): void {
    this.jsonText = '';
    this.root = null;
    this.graph = new GraphData();
    this.nodeCount = 0;
    this.edgeCount = 0;
    this.treeItems = [];
    this.selectedPath = '';
    this.findMatches = [];
    this.findTotal = 0;
    this.findIndex = 0;
    this.collapsed.clear();
    this.treeCollapsed.clear();
    this.renderState.selectedId = '';
    this.spans = [];
    this.errorMsg = '';
    this.errorLine = 0;
    this.samplePicker = false;
    this.draw();
  }

  private loadSample(kind: string): void {
    this.clearAll();
    let root: JValue | null = null;
    if (kind === 'yaml') {
      root = yamlToJson(SAMPLE_YAML);
    } else if (kind === 'csv') {
      root = csvToJson(SAMPLE_CSV);
    } else if (kind === 'xml') {
      root = xmlToJson(SAMPLE_XML);
    }
    this.jsonText = root === null ? SAMPLE : stringifyJson(root, 2, false);
    this.parseAndRender(true);
    this.highlighted = true;
    this.refreshHighlight();
    this.autoFitEditorWidth();
    this.toast(kind === 'json' ? '已载入 JSON 示例' :
      ('已载入 ' + kind.toUpperCase() + ' 示例（已转为 JSON）'));
  }

  private rebuildGraph(): void {
    if (this.root === null) {
      return;
    }
    const builder = new GraphBuilder();
    this.graph = builder.build(this.root, this.collapsed);
    treeLayout.layout(this.graph, this.layoutDir);
    this.nodeCount = this.graph.nodes.length;
    this.edgeCount = this.graph.edges.length;
    this.draw();
  }

  private onTextChanged(value: string): void {
    this.jsonText = value;
    if (this.parseTimer >= 0) {
      clearTimeout(this.parseTimer);
    }
    this.parseTimer = setTimeout(() => {
      this.parseAndRender(false);
      this.persist();
    }, 320);
  }

  private draw(): void {
    if (this.canvasW <= 1 || this.canvasH <= 1) {
      return;
    }
    this.renderState.offsetX = this.offsetX;
    this.renderState.offsetY = this.offsetY;
    this.renderState.scale = this.zoomLevel;
    this.renderState.direction = this.layoutDir;
    this.renderState.theme = this.theme();
    renderGraph(this.ctx, this.graph, this.renderState, this.canvasW, this.canvasH);
  }

  private syncZoomText(): void {
    const text = Math.round(this.zoomLevel * 100) + '%';
    if (text !== this.zoomText) {
      this.zoomText = text;
    }
  }

  private fitView(redraw: boolean = true): void {
    if (this.canvasW <= 10 || this.canvasH <= 10) {
      return;
    }
    if (this.graph.nodes.length === 0) {
      this.offsetX = 0;
      this.offsetY = 0;
      this.zoomLevel = 1;
      if (redraw) {
        this.draw();
      }
      return;
    }
    const bounds = computeBounds(this.graph.nodes);
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
    if (redraw) {
      this.draw();
    }
    this.syncZoomText();
  }

  private zoomBy(factor: number): void {
    this.userAdjusted = true;
    const cx = this.canvasW / 2;
    const cy = this.canvasH / 2;
    const wx = (cx - this.offsetX) / this.zoomLevel;
    const wy = (cy - this.offsetY) / this.zoomLevel;
    this.zoomLevel = this.clampScale(this.zoomLevel * factor);
    this.offsetX = cx - wx * this.zoomLevel;
    this.offsetY = cy - wy * this.zoomLevel;
    this.draw();
    this.syncZoomText();
  }

  private onCanvasClick(event: ClickEvent): void {
    const worldX = (event.x - this.offsetX) / this.zoomLevel;
    const worldY = (event.y - this.offsetY) / this.zoomLevel;
    const hit: HitResult = hitTest(this.graph, worldX, worldY);
    if (!hit.hit) {
      this.renderState.selectedId = '';
      this.selectedPath = '';
      this.draw();
      return;
    }
    if (hit.onCollapse) {
      this.toggleCollapse(hit.path);
      return;
    }
    this.renderState.selectedId = hit.nodeId;
    const node = this.graph.node(hit.nodeId);
    this.selectedPath = node === undefined ? '' : node.path;
    this.draw();
    this.openNodeDetail(hit.nodeId);
  }

  private toggleCollapse(path: string): void {
    if (this.collapsed.has(path)) {
      this.collapsed.delete(path);
    } else {
      this.collapsed.add(path);
    }
    this.rebuildGraph();
    this.selectedPath = '';
  }

  private collapseAll(): void {
    if (this.root === null) {
      return;
    }
    this.collapsed.clear();
    this.collectContainers(this.root, '$');
    this.rebuildGraph();
    if (this.viewMode === 'graph') {
      this.userAdjusted = false;
      this.fitView();
    }
    this.toast('已折叠 ' + this.collapsed.size + ' 个容器');
  }

  private collectContainers(value: JValue, path: string): void {
    if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.keys.length; i++) {
        const child = value.values[i];
        const cp = path + '.' + value.keys[i];
        if (child.isContainer() && child.childCount() > 0) {
          this.collapsed.add(cp);
          this.collectContainers(child, cp);
        }
      }
    } else if (value.kind === JKind.Arr) {
      for (let i = 0; i < value.items.length; i++) {
        const child = value.items[i];
        const cp = path + '[' + i + ']';
        if (child.isContainer() && child.childCount() > 0) {
          this.collapsed.add(cp);
          this.collectContainers(child, cp);
        }
      }
    }
  }

  private expandAll(): void {
    this.collapsed.clear();
    this.treeCollapsed.clear();
    this.rebuildGraph();
    if (this.viewMode === 'tree') {
      this.refreshTree();
    } else {
      this.userAdjusted = false;
      this.fitView();
    }
  }

  private openNodeDetail(nodeId: string): void {
    const node = this.graph.node(nodeId);
    if (node === undefined || this.root === null) {
      return;
    }
    const jp = jsonPathEngine.query(this.root, node.path);
    const content = jp.values.length > 0 ? stringifyJson(jp.values[0], 2, false) : '';
    this.outputText = content;
    this.sheetTitle = '节点详情';
    this.modalType = 'node';
    this.sheetVisible = true;
  }

  private flattenTree(value: JValue, path: string, depth: number, label: string, out: TreeItem[]): void {
    const item = new TreeItem();
    item.depth = depth;
    item.label = label;
    item.path = path;
    item.kind = value.kind;
    item.isContainer = value.isContainer();
    item.hasChildren = value.childCount() > 0;
    item.collapsed = this.treeCollapsed.has(path);
    item.value = value.isContainer() ?
      (value.kind === JKind.Obj ? '{' + value.childCount() + ' keys}' : '[' + value.childCount() + ' items]') :
      value.text;
    out.push(item);
    if (!item.isContainer || !item.hasChildren || item.collapsed) {
      return;
    }
    if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.keys.length; i++) {
        this.flattenTree(value.values[i], path + '.' + value.keys[i], depth + 1, value.keys[i], out);
      }
    } else {
      for (let i = 0; i < value.items.length; i++) {
        this.flattenTree(value.items[i], path + '[' + i + ']', depth + 1, '[' + i + ']', out);
      }
    }
  }

  private refreshTree(): void {
    if (this.root === null) {
      this.treeItems = [];
      return;
    }
    const items: TreeItem[] = [];
    this.flattenTree(this.root, '$', 0, 'root', items);
    this.treeItems = items;
  }

  private toggleTreeItem(path: string): void {
    if (this.treeCollapsed.has(path)) {
      this.treeCollapsed.delete(path);
    } else {
      this.treeCollapsed.add(path);
    }
    this.refreshTree();
  }

  /** ---------- 文件 ---------- */
  private async openFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const content = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
      this.jsonText = this.normalizeImport(uris[0], content);
      this.parseAndRender(true);
      this.autoFitEditorWidth();
      this.sheetVisible = false;
    } catch (e) {
      this.toast('打开文件失败');
    }
  }

  private normalizeImport(uri: string, content: string): string {
    const lower = uri.toLowerCase();
    try {
      if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
        return stringifyJson(yamlToJson(content), 2, false);
      }
      if (lower.endsWith('.csv')) {
        return stringifyJson(csvToJson(content), 2, false);
      }
      if (lower.endsWith('.xml')) {
        return stringifyJson(xmlToJson(content), 2, false);
      }
    } catch (e) {
      return content;
    }
    return content;
  }

  private async saveToFile(fileName: string, content: string): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      const uris = await documentPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      this.toast('已保存: ' + fileName);
    } catch (e) {
      this.toast('保存失败');
    }
  }

  private async exportImage(format: string): Promise<void> {
    if (this.graph.nodes.length === 0) {
      this.toast('没有可导出的图形');
      return;
    }
    try {
      this.busy = true;
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const options = new picker.DocumentSaveOptions();
      const ext = format === 'jpeg' ? '.jpg' : '.png';
      options.newFileNames = ['hello-json' + ext];
      const uris = await documentPicker.save(options);
      if (uris.length === 0) {
        this.busy = false;
        return;
      }
      const pixelMap = this.renderExportPixelMap(2);
      const info = pixelMap.getImageInfoSync();
      const packer = image.createImagePacker();
      const packOptions: image.PackingOption = {
        format: format === 'jpeg' ? 'image/jpeg' : 'image/png',
        quality: 100
      };
      const buffer = await packer.packToData(pixelMap, packOptions);
      const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buffer);
      fs.closeSync(file);
      packer.release();
      pixelMap.release();
      this.busy = false;
      this.toast('图片已导出（' + info.size.width + '×' + info.size.height + '）');
    } catch (e) {
      this.busy = false;
      const err = e as BusinessError;
      this.toast('导出失败: ' + err.message);
    }
  }

  /**
   * 离屏按 ratio 倍分辨率重绘整张图（不受当前缩放/平移影响）。
   * 组件快照只有屏幕像素密度，文字和线条会发虚，这里直接按目标像素重绘。
   */
  private renderExportPixelMap(ratio: number): image.PixelMap {
    const bounds = computeBounds(this.graph.nodes);
    const pad = 48;
    const baseW = Math.max(1, Math.ceil(bounds.width + pad * 2));
    const baseH = Math.max(1, Math.ceil(bounds.height + pad * 2));
    const maxEdge = 4096;
    let r = ratio;
    const longest = Math.max(baseW, baseH);
    if (longest * r > maxEdge) {
      r = maxEdge / longest;
    }
    const pxW = Math.max(1, Math.round(baseW * r));
    const pxH = Math.max(1, Math.round(baseH * r));
    const off = new OffscreenCanvas(pxW, pxH);
    const offCtx: OffscreenCanvasRenderingContext2D = off.getContext('2d', new RenderingContextSettings(true));
    const state = new RenderState();
    state.theme = this.theme();
    state.direction = this.layoutDir;
    state.scale = r;
    state.offsetX = pad * r - bounds.minX * r;
    state.offsetY = pad * r - bounds.minY * r;
    renderGraph(offCtx, this.graph, state, pxW, pxH);
    return offCtx.getPixelMap(0, 0, pxW, pxH);
  }

  private exportSvg(): void {
    if (this.graph.nodes.length === 0) {
      this.toast('没有可导出的图形');
      return;
    }
    const svg = buildSvg(this.graph, this.theme(), this.layoutDir, 40);
    this.saveToFile('hello-json.svg', svg);
  }

  private async copyText(text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('已复制到剪贴板');
    } catch (e) {
      this.toast('复制失败');
    }
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      if (text !== undefined && text.length > 0) {
        this.jsonText = text;
        this.parseAndRender(true);
        this.autoFitEditorWidth();
        this.sheetVisible = false;
        this.toast('已粘贴');
      }
    } catch (e) {
      this.toast('读取剪贴板失败');
    }
  }

  private async importFromUrl(): Promise<void> {
    const url = this.urlInput.trim();
    if (url.length === 0) {
      this.toast('请输入 URL');
      return;
    }
    this.busy = true;
    try {
      const req = http.createHttp();
      const res = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      req.destroy();
      if (res.responseCode === 200) {
        this.jsonText = res.result as string;
        this.parseAndRender(true);
        this.autoFitEditorWidth();
        this.sheetVisible = false;
        this.toast('已导入');
      } else {
        this.toast('请求失败: HTTP ' + res.responseCode);
      }
    } catch (e) {
      const err = e as BusinessError;
      this.toast('网络错误: ' + err.message);
    }
    this.busy = false;
  }

  /** 用系统浏览器打开链接 */
  private openLink(url: string): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.openLink(url).catch((err: BusinessError) => {
        hilog.warn(0x0000, 'HelloJson', 'openLink failed: ' + err.message);
        this.toast('打开链接失败');
      });
    } catch (e) {
      this.toast('打开链接失败');
    }
  }

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 1800 });
    } catch (e) {
      hilog.warn(0x0000, 'HelloJson', 'toast failed');
    }
  }

  /** ---------- 工具 ---------- */
  private showHighlighted(): void {
    this.highlighted = true;
    this.refreshHighlight();
  }

  private applyFormat(indent: number): void {
    if (this.root === null) {
      this.toast('JSON 无效，无法格式化');
      return;
    }
    this.jsonText = stringifyJson(this.root, indent, false);
    this.parseAndRender(false);
    this.showHighlighted();
    this.autoFitEditorWidth();
    this.sheetVisible = false;
  }

  private doSortKeys(): void {
    if (this.root === null) {
      return;
    }
    const sorted = sortKeysDeep(this.root);
    this.jsonText = stringifyJson(sorted, 2, false);
    this.parseAndRender(false);
    this.showHighlighted();
    this.autoFitEditorWidth();
    this.sheetVisible = false;
  }

  private doEscape(): void {
    this.jsonText = escapeWholeText(this.jsonText);
    this.parseAndRender(false);
    this.showHighlighted();
    this.autoFitEditorWidth();
    this.sheetVisible = false;
  }

  private doUnescape(): void {
    this.jsonText = unescapeWholeText(this.jsonText);
    this.parseAndRender(true);
    this.showHighlighted();
    this.autoFitEditorWidth();
    this.sheetVisible = false;
  }

  private buildTypes(language: string): string {
    if (this.root === null) {
      return '';
    }
    if (language === 'go') {
      return typeGenerator.go(this.root, 'Root');
    }
    if (language === 'kotlin') {
      return typeGenerator.kotlin(this.root, 'Root');
    }
    if (language === 'rust') {
      return typeGenerator.rust(this.root, 'Root');
    }
    return typeGenerator.ts(this.root, 'Root');
  }

  private buildConvert(format: string): string {
    if (this.root === null) {
      return '';
    }
    if (format === 'yaml') {
      return jsonToYaml(this.root);
    }
    if (format === 'csv') {
      return jsonToCsv(this.root);
    }
    if (format === 'xml') {
      return jsonToXml(this.root);
    }
    return '';
  }

  private runJq(): void {
    if (this.root === null) {
      this.outputText = 'JSON 无效';
      return;
    }
    const res: JqResult = jqEngine.evaluate(this.root, this.expressionInput);
    if (!res.ok) {
      this.outputText = '错误: ' + res.message;
      return;
    }
    const parts: string[] = [];
    for (let i = 0; i < res.values.length; i++) {
      parts.push(stringifyJson(res.values[i], 2, false));
    }
    this.outputText = parts.length === 0 ? '(空结果)' : parts.join('\n');
  }

  private runJsonPath(): void {
    if (this.root === null) {
      this.outputText = 'JSON 无效';
      return;
    }
    const res: JPathResult = jsonPathEngine.query(this.root, this.expressionInput);
    if (!res.ok) {
      this.outputText = '错误: ' + res.message;
      return;
    }
    if (res.values.length === 0) {
      this.outputText = '(没有匹配结果)';
      return;
    }
    const parts: string[] = [];
    for (let i = 0; i < res.values.length; i++) {
      parts.push(stringifyJson(res.values[i], 2, false));
    }
    this.outputText = parts.join('\n');
  }

  private applyConvert(): void {
    if (this.outputText.length === 0) {
      return;
    }
    this.jsonText = this.outputText;
    this.parseAndRender(true);
    this.autoFitEditorWidth();
    this.sheetVisible = false;
    this.toast('已应用转换结果');
  }

  /** ---------- 工具栏动作分发 ---------- */
  private dispatch(key: string): void {
    if (key === 'format') {
      this.applyFormat(2);
    } else if (key === 'compact') {
      this.applyFormat(0);
    } else if (key === 'collapseAll') {
      this.collapseAll();
    } else if (key === 'expandAll') {
      this.expandAll();
    } else if (key === 'about') {
      this.modalType = 'about';
      this.sheetTitle = '关于';
      this.sheetVisible = true;
    } else if (key === 'theme') {
      this.darkMode = !this.darkMode;
      this.renderState.theme = this.theme();
      this.draw();
      if (this.highlighted) {
        this.refreshHighlight();
      }
      this.persist();
    } else if (key === 'toggleEditor') {
      this.showEditor = !this.showEditor;
    }
  }

  /** 切换图形 / 树视图 */
  private setViewMode(mode: string): void {
    if (this.viewMode === mode) {
      return;
    }
    this.viewMode = mode;
    if (mode === 'tree') {
      this.refreshTree();
    }
    this.persist();
  }

  /** 切换编辑 / 高亮 */
  private setEditMode(highlight: boolean): void {
    if (this.highlighted === highlight) {
      return;
    }
    this.samplePicker = false;
    this.highlighted = highlight;
    if (highlight) {
      this.refreshHighlight();
    } else if (this.findVisible) {
      this.findVisible = false;
      this.findMatches = [];
      this.findTotal = 0;
      this.findIndex = 0;
    }
  }

  private dispatchSheet(key: string): void {
    if (key === 'openFile') {
      this.openFile();
    } else if (key === 'paste') {
      this.pasteFromClipboard();
    } else if (key === 'saveJson') {
      this.saveToFile('hello-json.json', this.jsonText);
    } else if (key === 'samplePick') {
      this.showEditor = true;
      this.samplePicker = true;
    } else if (key === 'clear') {
      this.jsonText = '';
      this.parseAndRender(true);
      this.sheetVisible = false;
    } else if (key === 'url') {
      this.modalType = 'url';
      this.sheetTitle = '从 URL 导入';
      this.sheetVisible = true;
    } else if (key === 'fmt2') {
      this.applyFormat(2);
    } else if (key === 'fmt0') {
      this.applyFormat(0);
    } else if (key === 'sort') {
      this.doSortKeys();
    } else if (key === 'escape') {
      this.doEscape();
    } else if (key === 'unescape') {
      this.doUnescape();
    } else if (key === 'validate') {
      const r = jsonParser.parse(this.jsonText);
      this.outputText = r.ok ? ('JSON 有效，共 ' + r.lineCount + ' 行') :
        ('第 ' + (r.error === null ? 0 : r.error.line) + ' 行: ' + (r.error === null ? '' : r.error.message));
      this.modalType = 'result';
      this.sheetTitle = '校验结果';
      this.sheetVisible = true;
    } else if (key === 'jq') {
      this.modalType = 'jq';
      this.sheetTitle = 'jq 查询';
      this.expressionInput = '.features';
      this.outputText = '';
      this.sheetVisible = true;
    } else if (key === 'path') {
      this.modalType = 'path';
      this.sheetTitle = 'JSONPath 查询';
      this.expressionInput = '$.features[*]';
      this.outputText = '';
      this.sheetVisible = true;
    } else if (key === 'search') {
      this.sheetVisible = false;
      this.openFind();
    } else if (key === 'schema') {
      this.modalType = 'schema';
      this.sheetTitle = 'JSON Schema';
      this.outputText = this.root === null ? '' : schemaGenerator.generate(this.root, 'Root');
      this.sheetVisible = true;
    } else if (key === 'types') {
      this.modalType = 'type';
      this.sheetTitle = '类型生成';
      this.outputText = this.buildTypes(this.genLanguage);
      this.sheetVisible = true;
    } else if (key === 'convert') {
      this.modalType = 'convert';
      this.sheetTitle = '格式转换';
      this.outputText = this.buildConvert(this.targetFormat);
      this.sheetVisible = true;
    } else if (key === 'svg') {
      this.exportSvg();
      this.sheetVisible = false;
    } else if (key === 'png') {
      this.exportImage('png');
      this.sheetVisible = false;
    } else if (key === 'jpeg') {
      this.exportImage('jpeg');
      this.sheetVisible = false;
    } else if (key === 'copyJson') {
      this.copyText(this.jsonText);
      this.sheetVisible = false;
    } else if (key === 'copyResult') {
      this.copyText(this.outputText);
    }
  }

  /** ---------- UI ---------- */
  /**
   * 注意：@Builder 的值参数不会随状态刷新，所以凡是外观依赖状态的按钮
   * （菜单、分段控制器、深浅色/全屏切换）都必须写成无参 Builder 或直接内联。
   */
  /** 鸿蒙风格顶栏按钮：胶囊、透明底、按下有反馈（仅用于文字不变的按钮） */
  @Builder
  navButton(label: string, key: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .stateStyles({
        normal: { .backgroundColor('#00000000') },
        pressed: { .backgroundColor(this.theme().isDark ? '#26FFFFFF' : '#14000000') }
      })
      .onClick(() => this.dispatch(key))
  }

  /** 顶栏分组分隔线 */
  @Builder
  barDivider() {
    Divider()
      .vertical(true)
      .height(18)
      .color(this.theme().panelBorder)
      .margin({ left: 8, right: 8 })
  }

  /** 顶栏：深浅色切换（文字随状态变化，必须无参） */
  @Builder
  themeButton() {
    Text(this.darkMode ? '浅色' : '深色')
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .stateStyles({
        normal: { .backgroundColor('#00000000') },
        pressed: { .backgroundColor(this.theme().isDark ? '#26FFFFFF' : '#14000000') }
      })
      .onClick(() => this.dispatch('theme'))
  }

  /** 顶栏：全屏图形 / 显示编辑 */
  @Builder
  editorToggleButton() {
    Text(this.showEditor ? '全屏图形' : '显示编辑')
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .stateStyles({
        normal: { .backgroundColor('#00000000') },
        pressed: { .backgroundColor(this.theme().isDark ? '#26FFFFFF' : '#14000000') }
      })
      .onClick(() => this.dispatch('toggleEditor'))
  }

  /** 顶栏：图形 / 树视图 分段控制器 */
  @Builder
  viewSegment() {
    Row() {
      Text('图形')
        .fontSize(12)
        .fontWeight(this.viewMode === 'graph' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.viewMode === 'graph' ? this.theme().text : this.theme().dimText)
        .padding({ left: 13, right: 13, top: 5, bottom: 5 })
        .borderRadius(13)
        .backgroundColor(this.viewMode === 'graph' ? this.theme().canvasBg : '#00000000')
        .shadow(this.viewMode === 'graph' ? { radius: 4, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.setViewMode('graph'))
      Text('树视图')
        .fontSize(12)
        .fontWeight(this.viewMode === 'tree' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.viewMode === 'tree' ? this.theme().text : this.theme().dimText)
        .padding({ left: 13, right: 13, top: 5, bottom: 5 })
        .borderRadius(13)
        .backgroundColor(this.viewMode === 'tree' ? this.theme().canvasBg : '#00000000')
        .shadow(this.viewMode === 'tree' ? { radius: 4, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.setViewMode('tree'))
    }
    .padding(2)
    .borderRadius(15)
    .backgroundColor(this.theme().nodeBgAlt)
  }

  /** 编辑区头部：编辑 / 高亮 分段控制器 */
  @Builder
  modeSegment() {
    Row() {
      Text('编辑')
        .fontSize(12)
        .fontWeight(!this.highlighted ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(!this.highlighted ? this.theme().text : this.theme().dimText)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(!this.highlighted ? this.theme().canvasBg : '#00000000')
        .shadow(!this.highlighted ? { radius: 3, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.setEditMode(false))
      Text('高亮')
        .fontSize(12)
        .fontWeight(this.highlighted ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.highlighted ? this.theme().text : this.theme().dimText)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(this.highlighted ? this.theme().canvasBg : '#00000000')
        .shadow(this.highlighted ? { radius: 3, color: '#1A000000', offsetY: 1 } : { radius: 0, color: '#00000000' })
        .onClick(() => this.setEditMode(true))
    }
    .padding(2)
    .borderRadius(14)
    .backgroundColor(this.theme().nodeBgAlt)
  }

  @Builder
  fileMenuButton() {
    Text('文件 ▾')
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.fileMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.theme().panelBg
      })
  }

  @Builder
  toolMenuButton() {
    Text('工具 ▾')
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.toolMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.theme().panelBg
      })
  }

  @Builder
  queryMenuButton() {
    Text('查询 ▾')
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.queryMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.theme().panelBg
      })
  }

  @Builder
  generateMenuButton() {
    Text('生成 ▾')
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.generateMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.theme().panelBg
      })
  }

  @Builder
  exportMenuButton() {
    Text('导出 ▾')
      .fontSize(13)
      .fontColor(this.theme().text)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .bindMenu(this.exportMenu, {
        placement: Placement.BottomLeft,
        enableArrow: false,
        borderRadius: 10,
        outlineWidth: 0,
        backgroundColor: this.theme().panelBg
      })
  }

  /** 下拉菜单中的一项（自绘行，便于控制行高与分组） */
  @Builder
  menuItem(label: string, act: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.theme().text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .layoutWeight(1)
    }
    .width('100%')
    .height(34)
    .padding({ left: 14, right: 14 })
    .borderRadius(6)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.dispatchSheet(act))
  }

  /** 菜单分组分割线 */
  @Builder
  menuDivider() {
    Divider()
      .strokeWidth(1)
      .color(this.darkMode ? '#4a4a4e' : '#cdd3db')
      .margin({ left: 10, right: 10, top: 5, bottom: 5 })
  }

  @Builder
  fileMenu() {
    Column() {
      this.menuItem('打开文件…', 'openFile')
      this.menuItem('从 URL 导入…', 'url')
      this.menuItem('从剪贴板粘贴', 'paste')
      this.menuDivider()
      this.menuItem('保存为 JSON 文件', 'saveJson')
      this.menuDivider()
      this.menuItem('载入示例数据…', 'samplePick')
      this.menuItem('清空编辑器', 'clear')
    }
    .width(216)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.darkMode ? '#454549' : '#d8dee5' })
  }

  /** “工具”下拉菜单 */
  @Builder
  toolMenu() {
    Column() {
      this.menuItem('格式化（2 空格缩进）', 'fmt2')
      this.menuItem('压缩为单行', 'fmt0')
      this.menuDivider()
      this.menuItem('递归排序键名', 'sort')
      this.menuDivider()
      this.menuItem('转义为 JSON 字符串', 'escape')
      this.menuItem('反转义', 'unescape')
      this.menuDivider()
      this.menuItem('校验 JSON', 'validate')
    }
    .width(232)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.darkMode ? '#454549' : '#d8dee5' })
  }

  @Builder
  queryMenu() {
    Column() {
      this.menuItem('jq 查询', 'jq')
      this.menuItem('JSONPath 查询', 'path')
      this.menuDivider()
      this.menuItem('文本查找（Ctrl+F）', 'search')
    }
    .width(216)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.darkMode ? '#454549' : '#d8dee5' })
  }

  @Builder
  generateMenu() {
    Column() {
      this.menuItem('JSON Schema', 'schema')
      this.menuDivider()
      this.menuItem('类型定义（TS / Go / Kotlin / Rust）', 'types')
      this.menuDivider()
      this.menuItem('格式转换（YAML / CSV / XML）', 'convert')
    }
    .width(292)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.darkMode ? '#454549' : '#d8dee5' })
  }

  @Builder
  exportMenu() {
    Column() {
      this.menuItem('导出 SVG（矢量，整图）', 'svg')
      this.menuItem('导出 PNG（整图高清）', 'png')
      this.menuItem('导出 JPEG（整图高清）', 'jpeg')
      this.menuDivider()
      this.menuItem('复制 JSON 文本', 'copyJson')
    }
    .width(236)
    .padding({ top: 6, bottom: 6, left: 4, right: 4 })
    .backgroundColor(this.theme().panelBg)
    .borderRadius(10)
    .border({ width: 0.5, color: this.darkMode ? '#454549' : '#d8dee5' })
  }

  @Builder
  topBar() {
    Row() {
      Image($r('app.media.logo'))
        .width(26)
        .height(26)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .margin({ right: 8 })
      Text('HelloJson')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().text)
      this.barDivider()
      Scroll() {
        Row() {
          this.fileMenuButton()
          this.navButton('格式化', 'format')
          this.navButton('压缩', 'compact')
          this.barDivider()
          this.toolMenuButton()
          this.queryMenuButton()
          this.generateMenuButton()
          this.exportMenuButton()
          this.barDivider()
          this.navButton('折叠', 'collapseAll')
          this.navButton('展开', 'expandAll')
          this.barDivider()
          this.viewSegment()
          this.barDivider()
          this.themeButton()
          this.editorToggleButton()
          this.navButton('关于', 'about')
        }
        .height('100%')
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .align(Alignment.Start)
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 8 })
    .backgroundColor(this.theme().toolbarBg)
    .border({ width: { bottom: 0.5 }, color: this.theme().panelBorder })
  }

  /** 浏览器风格查找栏：输入 → 回车/下一个 */
  @Builder
  findBar() {
    Row() {
      TextInput({ text: this.findQuery, placeholder: '文本查找' })
        .layoutWeight(1)
        .height(32)
        .fontSize(12)
        .fontFamily('monospace')
        .padding({ left: 8, right: 8, top: 0, bottom: 0 })
        .borderRadius(5)
        .backgroundColor(this.theme().canvasBg)
        .fontColor(this.theme().text)
        .placeholderColor(this.theme().dimText)
        .placeholderFont({ size: 12 })
        .caretColor(this.theme().accent)
        .onChange((v: string) => {
          this.findQuery = v;
          this.doFind(true);
        })
        .onSubmit(() => {
          this.findStep(1);
        })
      this.findButton('查找', 'find')
      this.findButton('上一个', 'prev')
      this.findButton('下一个', 'next')
      this.findButton('关闭', 'close')
      Text(this.findTotal === 0 ? (this.findQuery.length > 0 ? '无结果' : '0 / 0') :
        (this.findIndex + ' / ' + this.findTotal))
        .fontSize(11)
        .fontColor(this.findTotal === 0 ? this.theme().errorColor : this.theme().dimText)
        .margin({ left: 6, right: 4 })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.theme().toolbarBg)
    .border({ width: { bottom: 0.5 }, color: this.theme().panelBorder })
  }

  @Builder
  findButton(label: string, act: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.theme().text)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .borderRadius(5)
      .backgroundColor(this.theme().nodeBgAlt)
      .margin({ left: 6 })
      .onClick(() => {
        if (act === 'find') {
          this.doFind(true);
        } else if (act === 'prev') {
          this.findStep(-1);
        } else if (act === 'next') {
          this.findStep(1);
        } else {
          this.closeFind();
        }
      })
  }

  @Builder
  editorPanel() {
    Column() {
      Row() {
        Text('JSON')
          .fontSize(12)
          .fontColor(this.theme().dimText)
        Blank()
        if (this.errorMsg.length > 0) {
          Text('第 ' + this.errorLine + ' 行: ' + this.errorMsg)
            .fontSize(11)
            .fontColor(this.theme().errorColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        } else {
          Text(this.nodeCount + ' 节点 / ' + this.edgeCount + ' 边')
            .fontSize(11)
            .fontColor(this.theme().dimText)
            .margin({ right: 4 })
        }
        this.modeSegment()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })

      if (this.findVisible) {
        this.findBar()
      }

      if (this.samplePicker) {
        Column() {
          Row() {
            Text('选择示例数据格式')
              .fontSize(12)
              .fontColor(this.theme().text)
            Blank()
            Text('✕')
              .fontSize(13)
              .fontColor(this.theme().dimText)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .onClick(() => {
                this.samplePicker = false;
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })

          Scroll() {
            Column() {
              this.sampleCard('JSON', '标准 JSON 文档，直接可视化', 'json')
              this.sampleCard('YAML', 'YAML 配置，自动转换为 JSON', 'yaml')
              this.sampleCard('CSV', '表格数据，自动转换为对象数组', 'csv')
              this.sampleCard('XML', '节点结构，自动转换为 JSON', 'xml')
              Text('载入前会先清空当前编辑内容与图形')
                .fontSize(10)
                .fontColor(this.theme().dimText)
                .margin({ top: 2 })
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 12 })
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.TopStart)
          .scrollBar(BarState.Auto)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(this.theme().canvasBg)
      } else if (this.highlighted) {
        Scroll(this.textScroller) {
          Text() {
            ForEach(this.spans, (sp: HSpan, idx: number) => {
              if (sp.bg.length > 0) {
                Span(sp.text).fontColor(sp.color).textBackgroundStyle({ color: sp.bg, radius: 2 })
              } else {
                Span(sp.text).fontColor(sp.color)
              }
            }, (sp: HSpan, idx: number) => this.spanSeq.toString() + '_' + idx.toString())
          }
          .fontSize(12)
          .fontFamily('monospace')
          .width('100%')
          .textAlign(TextAlign.Start)
          .wordBreak(WordBreak.BREAK_ALL)
          .copyOption(CopyOptions.LocalDevice)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.textContentH = Number(newValue.height);
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.theme().canvasBg)
        .scrollBar(BarState.Auto)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.textViewH = Number(newValue.height);
        })
        .onClick(() => {
          if (!this.findVisible) {
            this.highlighted = false;
          }
        })
      } else {
        TextArea({ text: this.jsonText, placeholder: '在此输入 JSON / YAML / CSV / XML' })
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.theme().text)
          .backgroundColor(this.theme().canvasBg)
          .layoutWeight(1)
          .width('100%')
          .onChange((value: string) => {
            this.onTextChanged(value);
          })
          .onKeyEvent((e: KeyEvent) => {
            this.onGlobalKey(e);
          })
      }
    }
    .height(this.stackVertical ? ((this.splitRatio * 100).toFixed(1) + '%') : '100%')
    .width(this.stackVertical ? '100%' : ((this.splitRatio * 100).toFixed(1) + '%'))
    .backgroundColor(this.theme().panelBg)
    .border({
      width: {
        right: this.stackVertical ? 0 : 0.5,
        bottom: this.stackVertical ? 0.5 : 0
      }, color: this.theme().panelBorder
    })
  }

  @Builder
  sampleCard(title: string, desc: string, kind: string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme().accent)
        .width(54)
      Text(desc)
        .fontSize(11)
        .fontColor(this.theme().text)
        .layoutWeight(1)
        .maxLines(2)
      Text('载入')
        .fontSize(11)
        .fontColor(this.theme().canvasBg)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(4)
        .backgroundColor(this.theme().accent)
    }
    .width('100%')
    .padding(12)
    .margin({ bottom: 8 })
    .borderRadius(8)
    .backgroundColor(this.theme().nodeBgAlt)
    .onClick(() => {
      this.loadSample(kind);
      this.samplePicker = false;
    })
  }

  /** 左右（上下）分栏拖拽条 */
  @Builder
  splitter() {
    Stack() {
      Column()
        .width(this.stackVertical ? '100%' : 2)
        .height(this.stackVertical ? 2 : '100%')
        .backgroundColor(this.theme().panelBorder)
    }
    .width(this.stackVertical ? '100%' : 16)
    .height(this.stackVertical ? 16 : '100%')
    .backgroundColor(this.theme().panelBg)
    .gesture(
      PanGesture({ fingers: 1, distance: 1 })
        .onActionStart(() => {
          this.splitStart = this.splitRatio;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.stackVertical) {
            if (this.flexH > 0) {
              this.splitRatio = this.clampRatio(this.splitStart + event.offsetY / this.flexH);
            }
          } else if (this.flexW > 0) {
            this.splitRatio = this.clampRatio(this.splitStart + event.offsetX / this.flexW);
          }
        })
    )
  }

  @Builder
  graphToolbar() {
    Column() {
      Text('+')
        .fontSize(16)
        .fontColor(this.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.theme().nodeBg)
        .onClick(() => this.zoomBy(1.25))
      Text('−')
        .fontSize(16)
        .fontColor(this.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.theme().nodeBg)
        .margin({ top: 6 })
        .onClick(() => this.zoomBy(0.8))
      Text(this.showEditor ? '⤢' : '⤡')
        .fontSize(15)
        .fontColor(this.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.theme().nodeBg)
        .margin({ top: 6 })
        .onClick(() => {
          this.showEditor = !this.showEditor;
          this.userAdjusted = false;
          this.fitPending = true;
        })
      Text(this.layoutDir === 'RIGHT' ? '→' : (this.layoutDir === 'DOWN' ? '↓' :
        (this.layoutDir === 'LEFT' ? '←' : '↑')))
        .fontSize(15)
        .fontColor(this.theme().text)
        .width(30).height(30).textAlign(TextAlign.Center)
        .borderRadius(6)
        .backgroundColor(this.theme().nodeBg)
        .margin({ top: 6 })
        .onClick(() => {
          if (this.layoutDir === 'RIGHT') {
            this.layoutDir = 'DOWN';
          } else if (this.layoutDir === 'DOWN') {
            this.layoutDir = 'LEFT';
          } else if (this.layoutDir === 'LEFT') {
            this.layoutDir = 'UP';
          } else {
            this.layoutDir = 'RIGHT';
          }
          treeLayout.layout(this.graph, this.layoutDir);
          this.userAdjusted = false;
          this.fitView();
          this.persist();
        })
    }
    .padding(8)
    .borderRadius(10)
    .backgroundColor(this.theme().panelBg)
    .border({ width: 0.5, color: this.theme().panelBorder })
    .shadow({ radius: 8, color: '#22000000' })
  }

  @Builder
  treePanel() {
    List() {
      ForEach(this.treeItems, (item: TreeItem, index: number) => {
        ListItem() {
          Row() {
            if (item.isContainer && item.hasChildren) {
              Text(item.collapsed ? '▸' : '▾')
                .fontSize(11)
                .fontColor(this.theme().dimText)
                .width(14)
                .margin({ left: item.depth * 14 })
                .onClick(() => this.toggleTreeItem(item.path))
            } else {
              Text('')
                .width(14)
                .margin({ left: item.depth * 14 })
            }
            Text(item.label)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.theme().keyText)
              .margin({ left: 2 })
            Text(item.isContainer ? ' ' + item.value : ': ' + item.value)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(item.isContainer ? this.theme().dimText : rowColor(this.theme(), item.kind))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 4 })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(index % 2 === 0 ? this.theme().canvasBg : this.theme().panelBg)
          .onClick(() => {
            if (item.isContainer && item.hasChildren) {
              this.toggleTreeItem(item.path);
            }
          })
        }
      }, (item: TreeItem) => item.path + '_' + item.collapsed)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().canvasBg)
    .cachedCount(10)
  }

  @Builder
  graphPanel() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Canvas(this.ctx)
        .id('graphCanvas')
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme().canvasBg)
        .onReady(() => {
          this.draw();
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.canvasW = Number(newValue.width);
          this.canvasH = Number(newValue.height);
          this.inited = true;
          if (this.canvasW > 10 && this.canvasH > 10) {
            if (this.fitPending || !this.userAdjusted) {
              this.fitPending = false;
              this.fitView();
            } else {
              this.draw();
            }
          }
        })
        .onClick((event: ClickEvent) => {
          this.onCanvasClick(event);
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PanGesture({ fingers: 1, distance: 2 })
              .onActionStart(() => {
                this.userAdjusted = true;
                this.panStartX = this.offsetX;
                this.panStartY = this.offsetY;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.offsetX = this.panStartX + event.offsetX;
                this.offsetY = this.panStartY + event.offsetY;
                this.draw();
              }),
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.userAdjusted = true;
                this.lastPinchScale = 1;
              })
              .onActionUpdate((event: GestureEvent) => {
                const factor = event.scale / this.lastPinchScale;
                this.lastPinchScale = event.scale;
                const cx = event.pinchCenterX;
                const cy = event.pinchCenterY;
                const wx = (cx - this.offsetX) / this.zoomLevel;
                const wy = (cy - this.offsetY) / this.zoomLevel;
                this.zoomLevel = this.clampScale(this.zoomLevel * factor);
                this.offsetX = cx - wx * this.zoomLevel;
                this.offsetY = cy - wy * this.zoomLevel;
                this.draw();
              })
              .onActionEnd(() => {
                this.syncZoomText();
              })
          )
        )

      if (this.viewMode === 'tree') {
        this.treePanel()
      }

      if (this.graph.nodes.length === 0) {
        Text(this.errorMsg.length > 0 ? 'JSON 解析失败: ' + this.errorMsg : '输入 JSON 以生成图形')
          .fontSize(13)
          .fontColor(this.theme().dimText)
          .align(Alignment.Center)
          .padding(24)
          .textAlign(TextAlign.Center)
      }

      this.graphToolbar()
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  bottomBar() {
    Row() {
      Text(this.viewMode === 'graph' ? ('节点 ' + this.nodeCount) : ('树行 ' + this.treeItems.length))
        .fontSize(10)
        .fontColor(this.theme().text)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('边 ' + this.edgeCount)
        .fontSize(10)
        .fontColor(this.theme().text)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('行 ' + this.lineCount + ' / 字符 ' + this.charCount)
        .fontSize(10)
        .fontColor(this.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text(this.errorMsg.length > 0 ? ('第 ' + this.errorLine + ' 行有错') : 'JSON 有效')
        .fontSize(10)
        .fontColor(this.errorMsg.length > 0 ? this.theme().errorColor : this.theme().successColor)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
        .margin({ right: 6 })
      if (this.selectedPath.length > 0) {
        Text(this.selectedPath)
          .fontSize(11)
          .fontColor(this.theme().accent)
          .maxLines(1)
          .layoutWeight(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 4, right: 6 })
      } else {
        Blank()
      }
      if (this.findVisible) {
        Text('查找 ' + this.findIndex + ' / ' + this.findTotal)
          .fontSize(10)
          .fontColor(this.theme().searchHit)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.theme().nodeBgAlt)
          .margin({ right: 6 })
      }
      Text(this.highlighted ? '高亮模式' : '编辑模式')
        .fontSize(10)
        .fontColor(this.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text(this.viewMode === 'graph' ? '图形视图' : '树视图')
        .fontSize(10)
        .fontColor(this.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('布局 ' + (this.layoutDir === 'RIGHT' ? '→' :
        (this.layoutDir === 'DOWN' ? '↓' : (this.layoutDir === 'LEFT' ? '←' : '↑'))))
        .fontSize(10)
        .fontColor(this.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
        .margin({ right: 6 })
      Text('缩放 ' + this.zoomText)
        .fontSize(10)
        .fontColor(this.theme().dimText)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.theme().nodeBgAlt)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .backgroundColor(this.theme().toolbarBg)
    .border({ width: { top: 0.5 }, color: this.theme().panelBorder })
  }

  @Builder
  resultArea() {
    Column() {
      Row() {
        Text('结果').fontSize(12).fontColor(this.theme().dimText)
        Blank()
        Text('复制')
          .fontSize(12)
          .fontColor(this.theme().accent)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.copyText(this.outputText);
          })
      }
      .width('100%')
      .margin({ bottom: 6 })
      Scroll() {
        Text(this.outputText.length === 0 ? '（空）' : this.outputText)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.theme().text)
          .width('100%')
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.LocalDevice)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .padding(8)
      .borderRadius(8)
      .backgroundColor(this.theme().canvasBg)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  aboutRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.theme().dimText)
        .width(84)
      Text(value)
        .fontSize(12)
        .fontColor(this.theme().text)
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
        .fontColor(this.theme().dimText)
        .width(84)
      Text(url)
        .fontSize(12)
        .fontColor(this.theme().accent)
        .decoration({ type: TextDecorationType.Underline, color: this.theme().accent })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick(() => {
          this.openLink(url);
        })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  aboutTag(label: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.theme().text)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(10)
      .backgroundColor(this.theme().nodeBgAlt)
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
              .fontColor(this.theme().text)
            Text('原生鸿蒙 JSON 可视化工具')
              .fontSize(11)
              .fontColor(this.theme().dimText)
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
          Blank()
          Text('v' + this.appVersion)
            .fontSize(11)
            .fontColor(this.theme().dimText)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.theme().nodeBgAlt)
        }
        .width('100%')
        .margin({ bottom: 14 })

        this.aboutRow('版本', this.appVersion + '（versionCode 1000000）')
        this.aboutRow('包名', 'com.yi.json')
        this.aboutRow('技术栈', 'ArkTS · ArkUI · Canvas 自绘')
        this.aboutRow('运行环境', 'HarmonyOS 6.1.1+（API 24+）')
        this.aboutRow('作者', '一叶秋枫')
        this.aboutLink('项目地址', 'https://github.com/HWYWL/HelloJson')

        Text('主要功能')
          .fontSize(12)
          .fontColor(this.theme().dimText)
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
          .fontColor(this.theme().dimText)
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
  sheetContent() {
    Column() {
      Row() {
        Text(this.sheetTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme().text)
        Blank()
        if (this.busy) {
          LoadingProgress().width(18).height(18).margin({ right: 8 })
        }
        Text('✕')
          .fontSize(16)
          .fontColor(this.theme().dimText)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .onClick(() => {
            this.sheetVisible = false;
          })
      }
      .width('100%')
      .padding({ bottom: 10 })

      if (this.modalType === 'url') {
        Column() {
          TextInput({ text: this.urlInput, placeholder: 'https://example.com/data.json' })
            .fontSize(13)
            .backgroundColor(this.theme().canvasBg)
            .fontColor(this.theme().text)
            .margin({ bottom: 12 })
            .onChange((v: string) => {
              this.urlInput = v;
            })
            .onSubmit(() => {
              this.importFromUrl();
            })
          Button('导入')
            .width('100%')
            .onClick(() => {
              this.importFromUrl();
            })
        }
        .width('100%')
      }

      if (this.modalType === 'about') {
        this.aboutContent()
      }

      if (this.modalType === 'result' || this.modalType === 'node') {
        this.resultArea()
      }

      if (this.modalType === 'jq' || this.modalType === 'path') {
        Column() {
          Row() {
            TextInput({
              text: this.expressionInput,
              placeholder: this.modalType === 'jq' ? '.foo | .[]' : '$.foo[*]'
            })
              .layoutWeight(1)
              .fontSize(13)
              .fontFamily('monospace')
              .backgroundColor(this.theme().canvasBg)
              .fontColor(this.theme().text)
              .onChange((v: string) => {
                this.expressionInput = v;
              })
              .onSubmit(() => {
                this.runActiveQuery();
              })
            Text('运行')
              .fontSize(13)
              .fontColor(this.theme().canvasBg)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(6)
              .backgroundColor(this.theme().accent)
              .margin({ left: 8 })
              .onClick(() => {
                this.runActiveQuery();
              })
          }
          .width('100%')
          .margin({ bottom: 8 })
          this.resultArea()
        }
        .width('100%')
        .layoutWeight(1)
      }

      if (this.modalType === 'schema' || this.modalType === 'type') {
        Column() {
          if (this.modalType === 'type') {
            Row() {
              Text('TypeScript')
                .fontSize(12)
                .fontColor(this.genLanguage === 'typescript' ? this.theme().canvasBg : this.theme().text)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(6)
                .backgroundColor(this.genLanguage === 'typescript' ? this.theme().accent : this.theme().nodeBgAlt)
                .margin({ right: 6 })
                .onClick(() => {
                  this.genLanguage = 'typescript';
                  this.outputText = this.buildTypes('typescript');
                })
              Text('Go')
                .fontSize(12)
                .fontColor(this.genLanguage === 'go' ? this.theme().canvasBg : this.theme().text)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(6)
                .backgroundColor(this.genLanguage === 'go' ? this.theme().accent : this.theme().nodeBgAlt)
                .margin({ right: 6 })
                .onClick(() => {
                  this.genLanguage = 'go';
                  this.outputText = this.buildTypes('go');
                })
              Text('Kotlin')
                .fontSize(12)
                .fontColor(this.genLanguage === 'kotlin' ? this.theme().canvasBg : this.theme().text)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(6)
                .backgroundColor(this.genLanguage === 'kotlin' ? this.theme().accent : this.theme().nodeBgAlt)
                .margin({ right: 6 })
                .onClick(() => {
                  this.genLanguage = 'kotlin';
                  this.outputText = this.buildTypes('kotlin');
                })
              Text('Rust')
                .fontSize(12)
                .fontColor(this.genLanguage === 'rust' ? this.theme().canvasBg : this.theme().text)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(6)
                .backgroundColor(this.genLanguage === 'rust' ? this.theme().accent : this.theme().nodeBgAlt)
                .onClick(() => {
                  this.genLanguage = 'rust';
                  this.outputText = this.buildTypes('rust');
                })
            }
            .width('100%')
            .margin({ bottom: 8 })
          }
          this.resultArea()
        }
        .width('100%')
        .layoutWeight(1)
      }

      if (this.modalType === 'convert') {
        Column() {
          Row() {
            Text('YAML')
              .fontSize(12)
              .fontColor(this.targetFormat === 'yaml' ? this.theme().canvasBg : this.theme().text)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(6)
              .backgroundColor(this.targetFormat === 'yaml' ? this.theme().accent : this.theme().nodeBgAlt)
              .margin({ right: 6 })
              .onClick(() => {
                this.targetFormat = 'yaml';
                this.outputText = this.buildConvert('yaml');
              })
            Text('CSV')
              .fontSize(12)
              .fontColor(this.targetFormat === 'csv' ? this.theme().canvasBg : this.theme().text)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(6)
              .backgroundColor(this.targetFormat === 'csv' ? this.theme().accent : this.theme().nodeBgAlt)
              .margin({ right: 6 })
              .onClick(() => {
                this.targetFormat = 'csv';
                this.outputText = this.buildConvert('csv');
              })
            Text('XML')
              .fontSize(12)
              .fontColor(this.targetFormat === 'xml' ? this.theme().canvasBg : this.theme().text)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(6)
              .backgroundColor(this.targetFormat === 'xml' ? this.theme().accent : this.theme().nodeBgAlt)
              .margin({ right: 6 })
              .onClick(() => {
                this.targetFormat = 'xml';
                this.outputText = this.buildConvert('xml');
              })
            Blank()
            Text('应用到编辑器')
              .fontSize(12)
              .fontColor(this.theme().canvasBg)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(6)
              .backgroundColor(this.theme().accent)
              .onClick(() => {
                this.applyConvert();
              })
          }
          .width('100%')
          .margin({ bottom: 8 })
          this.resultArea()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.theme().panelBg)
  }

  private runActiveQuery(): void {
    if (this.modalType === 'jq') {
      this.runJq();
    } else if (this.modalType === 'path') {
      this.runJsonPath();
    }
  }

  /** 面板高度：表单类贴合内容，结果类占大半屏 */
  private panelHeight(): Length {
    if (this.modalType === 'url') {
      return 220;
    }
    if (this.modalType === 'about') {
      return 440;
    }
    return '74%';
  }

  /** 居中浮动面板（替代 bindSheet，位置固定居中，不再偏下） */
  @Builder
  panelHost() {
    Column() {
      this.sheetContent()
    }
    .width('88%')
    .height(this.panelHeight())
    .constraintSize({ maxWidth: 880, maxHeight: 760 })
    .borderRadius(18)
    .clip(true)
    .shadow({ radius: 28, color: '#66000000', offsetY: 8 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.topBar()
        Flex({ direction: this.stackVertical ? FlexDirection.Column : FlexDirection.Row }) {
          if (this.showEditor) {
            this.editorPanel()
            this.splitter()
          }
          this.graphPanel()
        }
        .layoutWeight(1)
        .width('100%')
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.flexW = Number(newValue.width);
          this.flexH = Number(newValue.height);
          if (this.pendingAutoFit) {
            this.autoFitEditorWidth();
          }
        })
        this.bottomBar()
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const vertical = Number(newValue.width) < 720;
        if (this.stackVertical !== vertical) {
          this.stackVertical = vertical;
          this.pendingAutoFit = true;
        }
        if (this.pendingAutoFit) {
          this.autoFitEditorWidth();
        }
      })
      .onKeyEvent((e: KeyEvent) => {
        this.onGlobalKey(e);
      })

      if (this.sheetVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => {
            this.sheetVisible = false;
          })
        this.panelHost()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().canvasBg)
  }
}
