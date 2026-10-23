import { common, bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JKind, JValue } from '../core/JValue';
import { jsonParser, ParseResult } from '../core/JsonParser';
import { stringifyJson, sortKeysDeep, escapeWholeText, unescapeWholeText } from '../core/JsonWriter';
import { GraphData, GraphTheme, darkTheme, lightTheme } from '../core/GraphModel';
import { GraphBuilder } from '../core/GraphBuilder';
import { treeLayout } from '../core/TreeLayout';
import { RenderState, findNodeByPath, renderGraph } from '../view/GraphRenderer';
import { computeBounds } from '../core/EdgeGeometry';
import { jqEngine, JqResult } from '../core/JqEngine';
import { jsonPathEngine, JPathResult } from '../core/JsonPathEngine';
import { schemaGenerator, typeGenerator } from '../core/CodeGen';
import { jsonToYaml, yamlToJson, jsonToCsv, csvToJson, jsonToXml, xmlToJson } from '../core/Convert';
import { buildSvg } from '../core/SvgExport';
import { DiffLine, DiffResult, diffLines } from '../core/JsonDiff';
import { SchemaError, SchemaValidator } from '../core/SchemaValidator';
import { AppConfig, configStore, TabRecord } from '../core/Storage';
import { DocTab, HSpan, TabInfo, TreeItem } from './Types';
import { SAMPLE, SAMPLE_CSV, SAMPLE_XML, SAMPLE_YAML } from './Samples';

/** 撤销栈最大步数 */
const HISTORY_LIMIT: number = 60;
/** 单条历史文本上限，超出则不记录，避免超大文档撑爆内存 */
const HISTORY_TEXT_LIMIT: number = 262144;
/** 连续输入的合并窗口（毫秒） */
const HISTORY_MERGE_MS: number = 700;
/** 树视图最多展开的条目数 */
const TREE_ITEM_LIMIT: number = 3000;

/**
 * 页面共享状态与业务逻辑。
 *
 * 由页面通过 @Provide 注入、各子组件通过 @Consume 订阅：
 * 页面只负责布局，顶栏 / 编辑区 / 图形区 / 结果区共用同一份状态与动作。
 *
 * 视图相关的命令式操作（Canvas 绘制、滚动定位）由子组件在挂载时
 * 注册到 onRepaint / onRequestFit / onScrollToMatch 钩子上，数据层不直接持有 UI 对象。
 */
@Observed
export class EditorStore {
  // ---------- 共享视图状态（UI 观察）----------
  jsonText: string = SAMPLE;
  errorMsg: string = '';
  errorLine: number = 0;
  nodeCount: number = 0;
  edgeCount: number = 0;
  darkMode: boolean = false;
  layoutDir: string = 'DOWN';
  viewMode: string = 'graph';
  zoomText: string = '100%';
  selectedPath: string = '';
  selectedNodeId: string = '';
  showEditor: boolean = true;
  sheetVisible: boolean = false;
  sheetTitle: string = '';
  modalType: string = '';
  expressionInput: string = '';
  urlInput: string = '';
  outputText: string = '';
  genLanguage: string = 'typescript';
  /** Java 生成模式：false = getter/setter，true = Lombok @Data */
  javaLombok: boolean = false;
  targetFormat: string = 'yaml';
  findVisible: boolean = false;
  findQuery: string = '';
  findIndex: number = 0;
  findTotal: number = 0;
  stackVertical: boolean = true;
  treeItems: TreeItem[] = [];
  busy: boolean = false;
  highlighted: boolean = false;
  spans: HSpan[] = [];
  lineCount: number = 1;
  charCount: number = 0;
  samplePicker: boolean = false;
  splitRatio: number = 0.46;
  appVersion: string = '1.0.0';
  appVersionCode: number = 0;
  /** 内容区尺寸，供分栏拖拽与自动宽度计算使用 */
  flexW: number = 0;
  flexH: number = 0;
  /** 片段版本号，变化时强制重建 Span（查找高亮切换用） */
  spanSeq: number = 0;

  // ---------- 标签 ----------
  /** 标签条展示数据：整组重建，保证 UI 能观察到变化 */
  tabs: TabInfo[] = [];
  activeTabId: string = '';
  private docs: DocTab[] = [];
  private tabSeq: number = 0;
  /** 标签条内容签名，用于跳过无意义的刷新 */
  private tabSignature: string = '';

  // ---------- 撤销 / 重做 ----------
  /** 是否还有可撤销 / 可重做的操作（供菜单置灰） */
  canUndo: boolean = false;
  canRedo: boolean = false;
  /** 图形/树视图是否因文档过大被截断 */
  graphTruncated: boolean = false;
  treeTruncated: boolean = false;

  // ---------- JSON 差异对比 ----------
  /** 左侧（A）标签 id */
  diffA: string = '';
  /** 右侧（B）标签 id */
  diffB: string = '';
  diffRows: DiffLine[] = [];
  diffAdded: number = 0;
  diffRemoved: number = 0;
  /** 差异过大，只展示前若干行 */
  diffTruncated: boolean = false;
  /** 差异结果版本号：参与 List 的 key，保证内容变化时整表重建 */
  diffSeq: number = 0;

  // ---------- JSON Schema 校验 ----------
  /** 当前载入的 schema 文件名 */
  schemaName: string = '';
  /** schema 原文，切换面板后仍保留 */
  schemaText: string = '';
  /** 是否已经执行过校验（false 表示结果已失效或尚未校验） */
  schemaChecked: boolean = false;
  schemaOk: boolean = false;
  /** 载入/校验过程中的提示（schema 解析失败、需重新校验等） */
  schemaMessage: string = '';
  schemaErrors: SchemaError[] = [];
  /** 出错节点路径（含祖先），供图形视图描红 */
  schemaErrorPaths: string[] = [];

  // ---------- 内部数据（不参与 UI 观察）----------
  graph: GraphData = new GraphData();
  private root: JValue | null = null;
  private collapsed: Set<string> = new Set<string>();
  private treeCollapsed: Set<string> = new Set<string>();
  /** 文本查找命中位置（字符偏移，升序） */
  private findMatches: number[] = [];
  private parseTimer: number = -1;
  /** 激活标签的落盘节流定时器 */
  private persistTimer: number = -1;
  /** 每个标签独立的撤销 / 重做栈（存修改前的文本） */
  private undoStacks: Map<string, string[]> = new Map<string, string[]>();
  private redoStacks: Map<string, string[]> = new Map<string, string[]>();
  /** 最近一次历史记录的时间与标签，用于合并连续输入 */
  private lastEditAt: number = 0;
  private lastEditTabId: string = '';
  private darkThemeRef: GraphTheme = darkTheme();
  private lightThemeRef: GraphTheme = lightTheme();
  private pendingAutoFit: boolean = false;
  private context: common.UIAbilityContext | null = null;

  // ---------- 视图层注入的钩子 ----------
  /** 图形区：立即重绘 */
  onRepaint: () => void = () => {
  };
  /** 图形区：请求适配视图；immediate=false 时延迟到下一次布局 */
  onRequestFit: (immediate: boolean) => void = (immediate: boolean) => {
  };
  /** 编辑区：滚动到当前查找命中 */
  onScrollToMatch: () => void = () => {
  };
  /** 编辑区：滚动到指定字符偏移（schema 报错定位用） */
  onScrollToOffset: (offset: number) => void = (offset: number) => {
  };

  /** 页面初始化：读配置、恢复状态、首次解析 */
  init(context: common.UIAbilityContext): void {
    this.context = context;
    configStore.init(context);
    const cfg = configStore.load();
    this.darkMode = cfg.darkMode;
    this.layoutDir = cfg.direction;
    this.viewMode = cfg.viewMode;

    const records: TabRecord[] = configStore.loadTabs();
    hilog.info(0x0000, 'HelloJson', 'init tabs=' + records.length + ' cfgActive=' + cfg.activeTabId);
    if (records.length > 0) {
      for (let i = 0; i < records.length; i++) {
        const r = records[i];
        const d = new DocTab();
        d.id = r.id;
        d.title = r.title;
        d.text = r.text;
        d.savedText = r.savedText;
        d.collapsed = r.collapsed;
        d.treeCollapsed = r.treeCollapsed;
        d.selectedPath = r.selectedPath;
        this.docs.push(d);
      }
      this.tabSeq = records.length;
      let activeId = records[0].id;
      for (let i = 0; i < records.length; i++) {
        if (records[i].id === cfg.activeTabId) {
          activeId = records[i].id;
        }
      }
      this.activeTabId = activeId;
    } else {
      // 旧版本只有单份文本，迁移成第一个标签
      const text = cfg.jsonText.length > 0 ? cfg.jsonText : SAMPLE;
      const created = this.createDoc('未命名 1', text, text);
      this.activeTabId = created.id;
    }
    const active = this.activeDoc();
    if (active !== null) {
      this.applyDoc(active);
    }
    this.refreshTabBar();
    // 立即落盘一次，保证首次迁移/新建的标签在下次启动时能恢复
    this.persist();
    this.parseAndRender(true);
    this.autoFitEditorWidth();
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
      this.appVersionCode = info.versionCode;
    } catch (e) {
      hilog.warn(0x0000, 'HelloJson', 'read bundle version failed');
    }
  }

  persist(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer);
      this.persistTimer = -1;
    }
    this.snapshotActive();
    const records: TabRecord[] = [];
    for (let i = 0; i < this.docs.length; i++) {
      records.push(this.toRecord(this.docs[i]));
    }
    const cfg = new AppConfig();
    cfg.darkMode = this.darkMode;
    cfg.direction = this.layoutDir;
    cfg.viewMode = this.viewMode;
    cfg.jsonText = this.jsonText;
    cfg.activeTabId = this.activeTabId;
    configStore.save(cfg);
    configStore.saveTabs(records, this.activeTabId);
    this.refreshTabBar();
  }

  /** 只保存激活标签（编辑正文时高频调用，做节流避免每次按键都写盘） */
  private persistActive(): void {
    this.snapshotActive();
    const d = this.activeDoc();
    if (d === null) {
      return;
    }
    const rec: TabRecord = this.toRecord(d);
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer);
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = -1;
      configStore.saveTab(rec);
    }, 600);
    this.refreshTabBar();
  }

  private toRecord(d: DocTab): TabRecord {
    const r = new TabRecord();
    r.id = d.id;
    r.title = d.title;
    r.text = d.text;
    r.savedText = d.savedText;
    r.collapsed = d.collapsed;
    r.treeCollapsed = d.treeCollapsed;
    r.selectedPath = d.selectedPath;
    return r;
  }

  // ---------- 标签管理 ----------

  private indexOfDoc(id: string): number {
    for (let i = 0; i < this.docs.length; i++) {
      if (this.docs[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private findDoc(id: string): DocTab | null {
    const idx = this.indexOfDoc(id);
    return idx < 0 ? null : this.docs[idx];
  }

  private activeDoc(): DocTab | null {
    return this.findDoc(this.activeTabId);
  }

  private createDoc(title: string, text: string, saved: string): DocTab {
    this.tabSeq++;
    const d = new DocTab();
    d.id = 'doc-' + Date.now().toString() + '-' + this.tabSeq.toString();
    d.title = title;
    d.text = text;
    d.savedText = saved;
    this.docs.push(d);
    return d;
  }

  /** 把标签快照写入视图状态（不触发解析） */
  private applyDoc(d: DocTab): void {
    this.jsonText = d.text;
    // 切换标签时先丢弃上一个文档的图形与统计，避免残留
    this.graph = new GraphData();
    this.nodeCount = 0;
    this.edgeCount = 0;
    this.treeItems = [];
    this.spans = [];
    this.errorMsg = '';
    this.errorLine = 0;
    this.collapsed.clear();
    for (let i = 0; i < d.collapsed.length; i++) {
      this.collapsed.add(d.collapsed[i]);
    }
    this.treeCollapsed.clear();
    for (let i = 0; i < d.treeCollapsed.length; i++) {
      this.treeCollapsed.add(d.treeCollapsed[i]);
    }
    this.selectedPath = d.selectedPath;
    this.selectedNodeId = '';
    this.updateHistoryState();
  }

  /** 把当前视图状态写回激活标签 */
  private snapshotActive(): void {
    const d = this.activeDoc();
    if (d === null) {
      return;
    }
    d.text = this.jsonText;
    d.selectedPath = this.selectedPath;
    const collapsed: string[] = [];
    this.collapsed.forEach((p: string) => {
      collapsed.push(p);
    });
    d.collapsed = collapsed;
    const treeCollapsed: string[] = [];
    this.treeCollapsed.forEach((p: string) => {
      treeCollapsed.push(p);
    });
    d.treeCollapsed = treeCollapsed;
  }

  /** 重建标签条数据（内容没变时跳过，避免每次解析都刷新 UI） */
  private refreshTabBar(): void {
    const list: TabInfo[] = [];
    let sig = '';
    for (let i = 0; i < this.docs.length; i++) {
      const d = this.docs[i];
      const text = d.id === this.activeTabId ? this.jsonText : d.text;
      const dirty = text !== d.savedText;
      list.push(new TabInfo(d.id, d.title, dirty));
      sig += d.id + '\u0001' + d.title + '\u0001' + (dirty ? '1' : '0') + '\u0002';
    }
    if (sig === this.tabSignature) {
      return;
    }
    this.tabSignature = sig;
    this.tabs = list;
  }

  /** 切换到指定标签并重新解析、重绘 */
  private loadDoc(d: DocTab): void {
    this.applyDoc(d);
    this.findVisible = false;
    this.findQuery = '';
    this.findMatches = [];
    this.findIndex = 0;
    this.findTotal = 0;
    this.refreshTabBar();
    // 先落盘再解析：即使解析/绘制异常，标签结构也已经保存
    this.persist();
    this.parseAndRender(true);
  }

  activateTab(id: string): void {
    if (id === this.activeTabId) {
      return;
    }
    const d = this.findDoc(id);
    if (d === null) {
      return;
    }
    this.snapshotActive();
    this.activeTabId = id;
    this.loadDoc(d);
  }

  newTab(): void {
    this.snapshotActive();
    const d = this.createDoc('未命名 ' + (this.tabSeq + 1).toString(), '', '');
    hilog.info(0x0000, 'HelloJson', 'newTab id=' + d.id + ' docs=' + this.docs.length);
    this.activeTabId = d.id;
    this.loadDoc(d);
  }

  closeTab(id: string): void {
    const idx = this.indexOfDoc(id);
    if (idx < 0) {
      return;
    }
    const wasActive = id === this.activeTabId;
    if (wasActive) {
      this.snapshotActive();
    }
    this.docs.splice(idx, 1);
    this.dropHistory(id);
    configStore.deleteTab(id);
    if (this.docs.length === 0) {
      const d = this.createDoc('未命名 ' + (this.tabSeq + 1).toString(), '', '');
      this.activeTabId = d.id;
      this.loadDoc(d);
      return;
    }
    if (wasActive) {
      const next = this.docs[idx < this.docs.length ? idx : this.docs.length - 1];
      this.activeTabId = next.id;
      this.loadDoc(next);
    } else {
      this.refreshTabBar();
      this.persist();
    }
  }

  /** 关闭除指定标签以外的全部标签 */
  closeOtherTabs(id: string): void {
    const keep = this.findDoc(id);
    if (keep === null) {
      return;
    }
    const removed: string[] = [];
    const remain: DocTab[] = [];
    for (let i = 0; i < this.docs.length; i++) {
      const d = this.docs[i];
      if (d.id === id) {
        remain.push(d);
      } else {
        removed.push(d.id);
      }
    }
    if (removed.length === 0) {
      return;
    }
    this.docs = remain;
    for (let i = 0; i < removed.length; i++) {
      this.dropHistory(removed[i]);
      configStore.deleteTab(removed[i]);
    }
    this.activeTabId = id;
    this.loadDoc(keep);
  }

  /** 关闭全部标签，并留下一个空标签 */
  closeAllTabs(): void {
    const removed: string[] = [];
    for (let i = 0; i < this.docs.length; i++) {
      removed.push(this.docs[i].id);
    }
    this.docs = [];
    for (let i = 0; i < removed.length; i++) {
      this.dropHistory(removed[i]);
      configStore.deleteTab(removed[i]);
    }
    const d = this.createDoc('未命名 ' + (this.tabSeq + 1).toString(), '', '');
    this.activeTabId = d.id;
    this.loadDoc(d);
  }

  // ---------- JSON 差异对比 ----------

  /** 打开差异面板：默认对比当前标签与下一个标签 */
  openDiff(): void {
    if (this.docs.length < 2) {
      this.toast('至少需要两个标签才能对比');
      return;
    }
    this.snapshotActive();
    this.diffA = this.activeTabId;
    let other = '';
    for (let i = 0; i < this.docs.length; i++) {
      if (this.docs[i].id !== this.activeTabId) {
        other = this.docs[i].id;
        break;
      }
    }
    this.diffB = other;
    this.computeDiffNow();
    this.modalType = 'diff';
    this.sheetTitle = 'JSON 差异对比';
    this.sheetVisible = true;
  }

  /** 切换参与对比的标签，side 为 'a' 或 'b' */
  setDiffSide(side: string, id: string): void {
    if (side === 'a') {
      this.diffA = id;
    } else {
      this.diffB = id;
    }
    this.computeDiffNow();
  }

  private docText(id: string): string {
    if (id === this.activeTabId) {
      return this.jsonText;
    }
    const d = this.findDoc(id);
    return d === null ? '' : d.text;
  }

  private computeDiffNow(): void {
    const res: DiffResult = diffLines(this.docText(this.diffA), this.docText(this.diffB));
    this.diffAdded = res.added;
    this.diffRemoved = res.removed;
    const overflow = res.lines.length > 4000;
    this.diffTruncated = res.truncated || overflow;
    this.diffRows = overflow ? res.lines.slice(0, 4000) : res.lines;
    this.diffSeq++;
  }

  /** 在新标签中打开外部内容 */
  private openDoc(title: string, text: string): void {
    this.snapshotActive();
    const d = this.createDoc(title, text, text);
    this.activeTabId = d.id;
    this.loadDoc(d);
  }

  /** 保存成功后清除未保存标记 */
  private markSaved(title: string): void {
    const d = this.activeDoc();
    if (d === null) {
      return;
    }
    d.text = this.jsonText;
    d.savedText = this.jsonText;
    if (title.length > 0) {
      d.title = title;
    }
    this.refreshTabBar();
    this.persist();
  }

  private fileNameOf(uri: string): string {
    const idx = uri.lastIndexOf('/');
    const name = idx >= 0 ? uri.substring(idx + 1) : uri;
    return name.length > 0 ? name : '未命名';
  }

  private titleFromUrl(url: string): string {
    let s = url;
    const q = s.indexOf('?');
    if (q >= 0) {
      s = s.substring(0, q);
    }
    const slash = s.lastIndexOf('/');
    const name = slash >= 0 ? s.substring(slash + 1) : s;
    return name.length > 0 ? name : 'URL 导入';
  }

  theme(): GraphTheme {
    return this.darkMode ? this.darkThemeRef : this.lightThemeRef;
  }

  clampRatio(value: number): number {
    if (value < 0.18) {
      return 0.18;
    }
    if (value > 0.82) {
      return 0.82;
    }
    return value;
  }

  // ---------- 布局 ----------

  /** 整页尺寸变化：决定左右分栏还是上下分栏 */
  onRootResize(width: number): void {
    const vertical = width < 720;
    if (this.stackVertical !== vertical) {
      this.stackVertical = vertical;
      this.pendingAutoFit = true;
    }
    if (this.pendingAutoFit) {
      this.autoFitEditorWidth();
    }
  }

  /** 内容区尺寸变化：分栏拖拽与自动宽度依赖这里 */
  onContentResize(width: number, height: number): void {
    this.flexW = width;
    this.flexH = height;
    if (this.pendingAutoFit) {
      this.autoFitEditorWidth();
    }
  }

  /** 按最长一行自动收缩编辑栏宽度（不超过总宽一半） */
  autoFitEditorWidth(): void {
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
      this.onRequestFit(false);
    }
  }

  // ---------- 解析与渲染 ----------

  private repaint(): void {
    this.onRepaint();
  }

  parseAndRender(autoFit: boolean): void {
    this.updateTextStats();
    // 正文已定稿，先持久化激活标签，避免进程被杀后丢失
    this.persistActive();
    if (this.jsonText.trim().length === 0) {
      // 空文档：清空图形与错误提示，避免沿用上一个标签的内容
      this.errorMsg = '';
      this.errorLine = 0;
      this.root = null;
      this.graph = new GraphData();
      this.nodeCount = 0;
      this.edgeCount = 0;
      this.treeItems = [];
      this.spans = [];
      this.graphTruncated = false;
      this.treeTruncated = false;
      this.invalidateSchemaResult();
      this.onRequestFit(true);
      this.refreshTabBar();
      return;
    }
    const result: ParseResult = jsonParser.parse(this.jsonText);
    if (!result.ok || result.root === null) {
      this.errorMsg = result.error === null ? '解析失败' : result.error.message;
      this.errorLine = result.error === null ? 0 : result.error.line;
      this.refreshHighlight();
      this.refreshTabBar();
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
      this.onRequestFit(true);
    } else {
      this.repaint();
    }
    this.invalidateSchemaResult();
    this.refreshTabBar();
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
  refreshHighlight(): void {
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

  // ---------- 文本查找（浏览器风格） ----------

  /** 打开查找栏，并切到高亮视图（TextArea 无法做局部高亮） */
  openFind(): void {
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

  /**
   * 全局快捷键。
   * Ctrl+S 保存 / Ctrl+Z 撤销 / Ctrl+Shift+Z、Ctrl+Y 重做 /
   * Ctrl+O 打开 / Ctrl+N 新建标签 / Ctrl+W 关闭标签 /
   * Ctrl+F 查找 / Ctrl+Shift+F 格式化 / Esc 关闭查找。
   */
  onGlobalKey(e: KeyEvent): void {
    if (e.type !== KeyType.Down) {
      return;
    }
    const ctrl = this.modState(e, 'Ctrl') || this.modState(e, 'ctrl');
    const shift = this.modState(e, 'Shift') || this.modState(e, 'shift');
    if (ctrl) {
      switch (e.keyCode) {
        case KeyCode.KEYCODE_S:
          this.saveToFile('hello-json.json', this.jsonText);
          e.stopPropagation();
          return;
        case KeyCode.KEYCODE_Z:
          if (shift) {
            this.redo();
          } else {
            this.undo();
          }
          e.stopPropagation();
          return;
        case KeyCode.KEYCODE_Y:
          this.redo();
          e.stopPropagation();
          return;
        case KeyCode.KEYCODE_O:
          this.openFile();
          e.stopPropagation();
          return;
        case KeyCode.KEYCODE_N:
          this.newTab();
          e.stopPropagation();
          return;
        case KeyCode.KEYCODE_W:
          this.closeTab(this.activeTabId);
          e.stopPropagation();
          return;
        case KeyCode.KEYCODE_F:
          if (shift) {
            this.applyFormat(2);
          } else {
            this.openFind();
          }
          e.stopPropagation();
          return;
        default:
          break;
      }
    }
    if (this.findVisible && e.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closeFind();
      e.stopPropagation();
    }
  }

  closeFind(): void {
    this.findVisible = false;
    this.findMatches = [];
    this.findTotal = 0;
    this.findIndex = 0;
    this.refreshHighlight();
  }

  /** 重新计算命中位置；jump 为 true 时跳到首个命中 */
  doFind(jump: boolean): void {
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
      this.onScrollToMatch();
    } else if (this.findIndex > this.findTotal) {
      this.findIndex = this.findTotal;
    }
    this.refreshHighlight();
  }

  /** step: 1 下一个，-1 上一个 */
  findStep(step: number): void {
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
    this.onScrollToMatch();
  }

  /** 当前命中在全文中的字符偏移，无有效命中时返回 -1 */
  /** 当前文档是否为空（空文档不显示为 JSON 有效） */
  isEmpty(): boolean {
    return this.jsonText.trim().length === 0;
  }

  matchOffset(): number {
    if (this.findIndex < 1 || this.findIndex > this.findMatches.length) {
      return -1;
    }
    return this.findMatches[this.findIndex - 1];
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
    this.selectedNodeId = '';
    this.findMatches = [];
    this.findTotal = 0;
    this.findIndex = 0;
    this.collapsed.clear();
    this.treeCollapsed.clear();
    this.spans = [];
    this.errorMsg = '';
    this.errorLine = 0;
    this.samplePicker = false;
    this.repaint();
  }

  loadSample(kind: string): void {
    this.recordHistory(this.jsonText, false);
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

  /** 按文档体量选择图形节点上限，0 表示不限制 */
  private graphNodeLimit(): number {
    const n = this.jsonText.length;
    if (n > 300000) {
      return 600;
    }
    if (n > 80000) {
      return 1500;
    }
    return 0;
  }

  private rebuildGraph(): void {
    if (this.root === null) {
      return;
    }
    const builder = new GraphBuilder();
    this.graph = builder.build(this.root, this.collapsed, this.graphNodeLimit());
    const truncated = builder.wasTruncated();
    if (truncated && !this.graphTruncated) {
      this.toast('文档较大，图形仅渲染前 ' + this.graph.nodes.length.toString() + ' 个节点');
    }
    this.graphTruncated = truncated;
    treeLayout.layout(this.graph, this.layoutDir);
    this.nodeCount = this.graph.nodes.length;
    this.edgeCount = this.graph.edges.length;
    this.repaint();
  }

  onTextChanged(value: string): void {
    const before = this.jsonText;
    if (value !== before) {
      this.recordHistory(before, true);
    }
    this.jsonText = value;
    this.refreshTabBar();
    if (this.parseTimer >= 0) {
      clearTimeout(this.parseTimer);
    }
    // 大文档把解析防抖拉长，避免每次按键都触发一次完整解析
    const delay = value.length > 120000 ? 700 : 320;
    this.parseTimer = setTimeout(() => {
      this.parseTimer = -1;
      this.parseAndRender(false);
    }, delay);
  }

  // ---------- 撤销 / 重做 ----------

  /**
   * 记录一次可撤销的修改。
   * coalesce 为 true 时把短时间内的连续输入合并成一步，避免每个字符一条历史。
   */
  private recordHistory(before: string, coalesce: boolean): void {
    if (before.length > HISTORY_TEXT_LIMIT) {
      return;
    }
    const id = this.activeTabId;
    let stack = this.undoStacks.get(id);
    if (stack === undefined) {
      stack = [];
      this.undoStacks.set(id, stack);
    }
    const now = Date.now();
    if (coalesce && this.lastEditTabId === id && now - this.lastEditAt < HISTORY_MERGE_MS && stack.length > 0) {
      this.lastEditAt = now;
      return;
    }
    stack.push(before);
    if (stack.length > HISTORY_LIMIT) {
      stack.shift();
    }
    this.redoStacks.set(id, []);
    this.lastEditAt = now;
    this.lastEditTabId = id;
    this.updateHistoryState();
  }

  private updateHistoryState(): void {
    const u = this.undoStacks.get(this.activeTabId);
    const r = this.redoStacks.get(this.activeTabId);
    this.canUndo = u !== undefined && u.length > 0;
    this.canRedo = r !== undefined && r.length > 0;
  }

  /** 撤销后/重做后统一回到"未合并"状态，避免紧接着的输入被吞掉 */
  private applyHistoryText(): void {
    this.lastEditAt = 0;
    this.lastEditTabId = '';
    this.parseAndRender(false);
    this.autoFitEditorWidth();
    this.updateHistoryState();
  }

  undo(): void {
    const id = this.activeTabId;
    const stack = this.undoStacks.get(id);
    if (stack === undefined || stack.length === 0) {
      this.toast('没有可撤销的操作');
      return;
    }
    const prev = stack.pop();
    if (prev === undefined) {
      return;
    }
    let redo = this.redoStacks.get(id);
    if (redo === undefined) {
      redo = [];
      this.redoStacks.set(id, redo);
    }
    redo.push(this.jsonText);
    this.jsonText = prev;
    this.applyHistoryText();
    this.toast('已撤销');
  }

  redo(): void {
    const id = this.activeTabId;
    const stack = this.redoStacks.get(id);
    if (stack === undefined || stack.length === 0) {
      this.toast('没有可重做的操作');
      return;
    }
    const next = stack.pop();
    if (next === undefined) {
      return;
    }
    let undo = this.undoStacks.get(id);
    if (undo === undefined) {
      undo = [];
      this.undoStacks.set(id, undo);
    }
    undo.push(this.jsonText);
    this.jsonText = next;
    this.applyHistoryText();
    this.toast('已重做');
  }

  /** 标签关闭时丢弃它的历史，避免 Map 长期持有大文本 */
  private dropHistory(id: string): void {
    this.undoStacks.delete(id);
    this.redoStacks.delete(id);
  }

  /** 图形区完成绘制后回写缩放比例文案 */
  updateZoom(scale: number): void {
    const text = Math.round(scale * 100) + '%';
    if (text !== this.zoomText) {
      this.zoomText = text;
    }
  }

  // ---------- 折叠 ----------

  toggleCollapse(path: string): void {
    if (this.collapsed.has(path)) {
      this.collapsed.delete(path);
    } else {
      this.collapsed.add(path);
    }
    this.rebuildGraph();
    this.selectedPath = '';
  }

  collapseAll(): void {
    if (this.root === null) {
      return;
    }
    this.collapsed.clear();
    this.collectContainers(this.root, '$');
    this.rebuildGraph();
    if (this.viewMode === 'graph') {
      this.onRequestFit(true);
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

  expandAll(): void {
    this.collapsed.clear();
    this.treeCollapsed.clear();
    this.rebuildGraph();
    if (this.viewMode === 'tree') {
      this.refreshTree();
    } else {
      this.onRequestFit(true);
    }
  }

  openNodeDetail(nodeId: string): void {
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

  // ---------- 树视图 ----------

  private flattenTree(value: JValue, path: string, depth: number, label: string, out: TreeItem[]): void {
    if (out.length >= TREE_ITEM_LIMIT) {
      this.treeTruncated = true;
      return;
    }
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

  refreshTree(): void {
    if (this.root === null) {
      this.treeItems = [];
      this.treeTruncated = false;
      return;
    }
    const items: TreeItem[] = [];
    this.treeTruncated = false;
    this.flattenTree(this.root, '$', 0, 'root', items);
    if (this.treeTruncated) {
      this.toast('文档较大，树视图仅展开前 ' + items.length.toString() + ' 项');
    }
    this.treeItems = items;
  }

  toggleTreeItem(path: string): void {
    if (this.treeCollapsed.has(path)) {
      this.treeCollapsed.delete(path);
    } else {
      this.treeCollapsed.add(path);
    }
    this.refreshTree();
  }

  // ---------- JSON Schema 校验 ----------

  /** 打开校验面板：已载入 schema 时立即重算一次 */
  openSchemaCheck(): void {
    this.modalType = 'schemaCheck';
    this.sheetTitle = 'JSON Schema 校验';
    this.sheetVisible = true;
    if (this.schemaText.length > 0 && !this.schemaChecked) {
      this.runSchemaCheck();
    }
  }

  /** 选择本地 .json 文件作为 schema */
  async pickSchemaFile(): Promise<void> {
    const ctx = this.context;
    if (ctx === null) {
      this.toast('无法打开文件选择器');
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(ctx);
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
      this.applySchema(content, this.fileNameOf(uris[0]));
    } catch (e) {
      this.toast('读取 schema 文件失败');
    }
  }

  /** 载入 schema 文本并立即校验（文件选择、剪贴板共用） */
  applySchema(text: string, name: string): void {
    this.schemaText = text;
    this.schemaName = name;
    this.schemaChecked = false;
    this.runSchemaCheck();
  }

  async pasteSchemaFromClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      if (text === undefined || text.trim().length === 0) {
        this.toast('剪贴板为空');
        return;
      }
      this.applySchema(text, '剪贴板 schema');
    } catch (e) {
      this.toast('读取剪贴板失败');
    }
  }

  /** 内置演示 schema：第一次用校验功能时可以一键跑通流程 */
  useDemoSchema(): void {
    const demo = '{"type":"object","required":["name","version","features"],' +
      '"properties":{"name":{"type":"string","minLength":1},' +
      '"version":{"type":"string","enum":["1.0.0","1.1.0","2.0.0"]},' +
      '"features":{"type":"array","minItems":3,"items":{"type":"string"}},' +
      '"stats":{"type":"object","properties":{"stars":{"type":"integer","minimum":0}}},' +
      '"tags":{"type":"array","items":{"type":"string"}}}}';
    this.applySchema(demo, '内置示例 schema');
  }

  clearSchema(): void {
    this.schemaText = '';
    this.schemaName = '';
    this.schemaChecked = false;
    this.schemaOk = false;
    this.schemaMessage = '';
    this.schemaErrors = [];
    this.schemaErrorPaths = [];
    this.repaint();
  }

  runSchemaCheck(): void {
    this.schemaErrors = [];
    this.schemaErrorPaths = [];
    this.schemaOk = false;
    if (this.schemaText.trim().length === 0) {
      this.schemaChecked = false;
      this.schemaMessage = '尚未载入 schema';
      this.repaint();
      return;
    }
    if (this.root === null) {
      this.schemaChecked = false;
      this.schemaMessage = '当前文档不是有效 JSON，无法校验';
      this.repaint();
      return;
    }
    const parsed = jsonParser.parse(this.schemaText);
    if (!parsed.ok || parsed.root === null) {
      this.schemaChecked = false;
      this.schemaMessage = 'schema 本身解析失败：' +
        (parsed.error === null ? '未知错误' : parsed.error.message);
      this.repaint();
      return;
    }
    const errors = new SchemaValidator().validate(this.root, parsed.root);
    const lines = this.linesOfOffsets(this.jsonText, errors);
    for (let i = 0; i < errors.length; i++) {
      errors[i].line = lines[i];
    }
    this.schemaErrors = errors;
    this.schemaOk = errors.length === 0;
    this.schemaChecked = true;
    this.schemaMessage = '';
    this.schemaErrorPaths = this.collectErrorPaths(errors);
    this.repaint();
    this.toast(this.schemaOk ? 'Schema 校验通过' :
      ('发现 ' + errors.length.toString() + ' 处不符合 schema 的地方'));
  }

  /** 文档变化后旧结果立即失效，避免继续显示过期的红框 */
  private invalidateSchemaResult(): void {
    if (!this.schemaChecked && this.schemaErrors.length === 0) {
      return;
    }
    this.schemaChecked = false;
    this.schemaOk = false;
    this.schemaErrors = [];
    this.schemaErrorPaths = [];
    this.schemaMessage = this.schemaText.length > 0 ? '文档已修改，请重新校验' : '';
    this.repaint();
  }

  /** 逐个错误换算行号：先扫一遍行首偏移，再二分查找 */
  private linesOfOffsets(text: string, errors: SchemaError[]): number[] {
    const out: number[] = [];
    if (errors.length === 0) {
      return out;
    }
    const starts: number[] = [0];
    for (let i = 0; i < text.length; i++) {
      if (text.charCodeAt(i) === 10) {
        starts.push(i + 1);
      }
    }
    for (let i = 0; i < errors.length; i++) {
      const off = errors[i].offset;
      let lo = 0;
      let hi = starts.length - 1;
      while (lo < hi) {
        const mid = Math.ceil((lo + hi) / 2);
        if (starts[mid] <= off) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      out.push(lo + 1);
    }
    return out;
  }

  /** 父级路径：$["a.b"][2] -> $["a.b"]；$.a.b -> $.a */
  private parentPathOf(p: string): string {
    if (p.length <= 1) {
      return '';
    }
    if (p.endsWith(']')) {
      const open = p.lastIndexOf('[');
      if (open > 0) {
        return p.substring(0, open);
      }
    }
    const dot = p.lastIndexOf('.');
    if (dot > 0) {
      return p.substring(0, dot);
    }
    return '$';
  }

  /** 出错节点及其全部祖先都要描红 */
  private collectErrorPaths(errors: SchemaError[]): string[] {
    const set: Set<string> = new Set<string>();
    for (let i = 0; i < errors.length; i++) {
      let p = errors[i].path;
      while (p.length > 0) {
        set.add(p);
        if (p === '$') {
          break;
        }
        p = this.parentPathOf(p);
      }
    }
    const out: string[] = [];
    set.forEach((p: string) => {
      out.push(p);
    });
    return out;
  }

  /** 点击错误：选中对应图形节点并把编辑区滚到出错位置 */
  gotoSchemaError(index: number): void {
    if (index < 0 || index >= this.schemaErrors.length) {
      return;
    }
    const err = this.schemaErrors[index];
    let p = err.path;
    let node = findNodeByPath(this.graph, p);
    while (node === null && p !== '$') {
      p = this.parentPathOf(p);
      node = findNodeByPath(this.graph, p);
    }
    this.selectedPath = node === null ? '' : node.path;
    this.selectedNodeId = node === null ? '' : node.id;
    this.sheetVisible = false;
    if (this.showEditor) {
      this.onScrollToOffset(err.offset);
    }
    this.repaint();
  }

  // ---------- 文件 ----------

  private async openFile(): Promise<void> {
    const ctx = this.context;
    if (ctx === null) {
      this.toast('打开文件失败');
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(ctx);
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
      this.openDoc(this.fileNameOf(uris[0]), this.normalizeImport(uris[0], content));
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

  async saveToFile(fileName: string, content: string): Promise<void> {
    const ctx = this.context;
    if (ctx === null) {
      this.toast('保存失败');
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      const uris = await documentPicker.save(options);
      if (uris.length === 0) {
        return;
      }
      const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      if (fileName.endsWith('.json')) {
        const saved = this.fileNameOf(uris[0]);
        this.markSaved(saved.endsWith('.json') ? saved.substring(0, saved.length - 5) : saved);
      }
      this.toast('已保存: ' + fileName);
    } catch (e) {
      this.toast('保存失败');
    }
  }

  async exportImage(format: string): Promise<void> {
    if (this.graph.nodes.length === 0) {
      this.toast('没有可导出的图形');
      return;
    }
    const ctx = this.context;
    if (ctx === null) {
      this.toast('导出失败');
      return;
    }
    try {
      this.busy = true;
      const documentPicker = new picker.DocumentViewPicker(ctx);
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

  exportSvg(): void {
    if (this.graph.nodes.length === 0) {
      this.toast('没有可导出的图形');
      return;
    }
    const svg = buildSvg(this.graph, this.theme(), this.layoutDir, 40);
    this.saveToFile('hello-json.svg', svg);
  }

  async copyText(text: string): Promise<void> {
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
        this.openDoc('粘贴', text);
        this.autoFitEditorWidth();
        this.sheetVisible = false;
        this.toast('已粘贴');
      }
    } catch (e) {
      this.toast('读取剪贴板失败');
    }
  }

  async importFromUrl(): Promise<void> {
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
        this.openDoc(this.titleFromUrl(url), res.result as string);
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
  openLink(url: string): void {
    const ctx = this.context;
    if (ctx === null) {
      this.toast('打开链接失败');
      return;
    }
    try {
      ctx.openLink(url).catch((err: BusinessError) => {
        hilog.warn(0x0000, 'HelloJson', 'openLink failed: ' + err.message);
        this.toast('打开链接失败');
      });
    } catch (e) {
      this.toast('打开链接失败');
    }
  }

  toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 1800 });
    } catch (e) {
      hilog.warn(0x0000, 'HelloJson', 'toast failed');
    }
  }

  // ---------- 工具 ----------

  private showHighlighted(): void {
    this.highlighted = true;
    this.refreshHighlight();
  }

  applyFormat(indent: number): void {
    if (this.root === null) {
      this.toast('JSON 无效，无法格式化');
      return;
    }
    this.recordHistory(this.jsonText, false);
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
    this.recordHistory(this.jsonText, false);
    this.jsonText = stringifyJson(sorted, 2, false);
    this.parseAndRender(false);
    this.showHighlighted();
    this.autoFitEditorWidth();
    this.sheetVisible = false;
  }

  private doEscape(): void {
    this.recordHistory(this.jsonText, false);
    this.jsonText = escapeWholeText(this.jsonText);
    this.parseAndRender(false);
    this.showHighlighted();
    this.autoFitEditorWidth();
    this.sheetVisible = false;
  }

  private doUnescape(): void {
    this.recordHistory(this.jsonText, false);
    this.jsonText = unescapeWholeText(this.jsonText);
    this.parseAndRender(true);
    this.showHighlighted();
    this.autoFitEditorWidth();
    this.sheetVisible = false;
  }

  buildTypes(language: string): string {
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
    if (language === 'java') {
      return typeGenerator.java(this.root, 'Root', this.javaLombok);
    }
    return typeGenerator.ts(this.root, 'Root');
  }

  buildConvert(format: string): string {
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

  runJq(): void {
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

  runJsonPath(): void {
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

  applyConvert(): void {
    if (this.outputText.length === 0) {
      return;
    }
    this.recordHistory(this.jsonText, false);
    this.jsonText = this.outputText;
    this.parseAndRender(true);
    this.autoFitEditorWidth();
    this.sheetVisible = false;
    this.toast('已应用转换结果');
  }

  // ---------- 工具栏动作分发 ----------

  dispatch(key: string): void {
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
      this.persist();
      if (this.highlighted) {
        this.refreshHighlight();
      }
      this.repaint();
    } else if (key === 'toggleEditor') {
      this.showEditor = !this.showEditor;
    }
  }

  /** 切换图形 / 树视图 */
  setViewMode(mode: string): void {
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
  setEditMode(highlight: boolean): void {
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

  dispatchSheet(key: string): void {
    if (key === 'undo') {
      this.undo();
      this.sheetVisible = false;
    } else if (key === 'redo') {
      this.redo();
      this.sheetVisible = false;
    } else if (key === 'openFile') {
      this.openFile();
    } else if (key === 'paste') {
      this.pasteFromClipboard();
    } else if (key === 'saveJson') {
      this.saveToFile('hello-json.json', this.jsonText);
    } else if (key === 'samplePick') {
      this.showEditor = true;
      this.samplePicker = true;
    } else if (key === 'clear') {
      this.recordHistory(this.jsonText, false);
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
    } else if (key === 'schemaCheck') {
      this.openSchemaCheck();
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
    } else if (key === 'diff') {
      this.openDiff();
    } else if (key === 'copyResult') {
      this.copyText(this.outputText);
    }
  }

  runActiveQuery(): void {
    if (this.modalType === 'jq') {
      this.runJq();
    } else if (this.modalType === 'path') {
      this.runJsonPath();
    }
  }

  /** 面板高度：表单类贴合内容，结果类占大半屏 */
  panelHeight(): Length {
    if (this.modalType === 'url') {
      return 220;
    }
    if (this.modalType === 'about') {
      return 440;
    }
    return '74%';
  }
}
