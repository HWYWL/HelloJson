import { JKind, estimateTextWidth, truncateText } from './JValue';

export class NodeRow {
  key: string = '';
  hasKey: boolean = false;
  value: string = '';
  kind: JKind = JKind.Null;
  childrenCount: number = 0;
  collapsible: boolean = false;
  collapsed: boolean = false;
  /** 该行指向子容器时的完整路径 */
  path: string = '';
}

export class GraphNode {
  id: string = '';
  rows: NodeRow[] = [];
  width: number = 120;
  height: number = 34;
  x: number = 0;
  y: number = 0;
  path: string = '$';
  parentId: string = '';
  depth: number = 0;
  childrenIds: string[] = [];
  isRoot: boolean = false;
  /** 是否展开状态下的容器节点（含可折叠子行） */
  hasCollapsibleRow: boolean = false;
}

export class GraphEdge {
  id: string = '';
  from: string = '';
  to: string = '';
  label: string = '';
}

export class GraphData {
  nodes: GraphNode[] = [];
  edges: GraphEdge[] = [];
  rootId: string = '';
  nodeMap: Map<string, GraphNode> = new Map<string, GraphNode>();
  maxDepth: number = 0;

  node(id: string): GraphNode | undefined {
    return this.nodeMap.get(id);
  }

  reset(): void {
    this.nodes = [];
    this.edges = [];
    this.nodeMap.clear();
    this.rootId = '';
    this.maxDepth = 0;
  }
}

export class GraphTheme {
  isDark: boolean = true;
  canvasBg: string = '#1e1e1e';
  nodeBg: string = '#2b2b2b';
  nodeBgAlt: string = '#323232';
  nodeBorder: string = '#3d3d3d';
  nodeBorderActive: string = '#e5a00d';
  text: string = '#d4d4d4';
  keyText: string = '#9cdcfe';
  stringColor: string = '#ce9178';
  numberColor: string = '#b5cea8';
  boolColor: string = '#569cd6';
  nullColor: string = '#808080';
  edgeColor: string = '#5f5f5f';
  edgeLabelBg: string = '#1e1e1e';
  accent: string = '#e5a00d';
  searchHit: string = '#ffd166';
  selectionBg: string = '#3a3a3a';
  panelBg: string = '#252526';
  panelBorder: string = '#3c3c3c';
  toolbarBg: string = '#252526';
  dimText: string = '#8b8b8b';
  errorColor: string = '#f14c4c';
  successColor: string = '#4ec9b0';
}

export function darkTheme(): GraphTheme {
  return new GraphTheme();
}

export function lightTheme(): GraphTheme {
  const t = new GraphTheme();
  t.isDark = false;
  t.canvasBg = '#ffffff';
  t.nodeBg = '#ffffff';
  t.nodeBgAlt = '#f6f8fa';
  t.nodeBorder = '#d0d7de';
  t.nodeBorderActive = '#0969da';
  t.text = '#24292f';
  t.keyText = '#0550ae';
  t.stringColor = '#0a7d33';
  t.numberColor = '#b35900';
  t.boolColor = '#8250df';
  t.nullColor = '#6e7781';
  t.edgeColor = '#b8c0c8';
  t.edgeLabelBg = '#ffffff';
  t.accent = '#0969da';
  t.searchHit = '#bf8700';
  t.selectionBg = '#eaeef2';
  t.panelBg = '#f6f8fa';
  t.panelBorder = '#d0d7de';
  t.toolbarBg = '#f6f8fa';
  t.dimText = '#57606a';
  t.errorColor = '#cf222e';
  t.successColor = '#1a7f37';
  return t;
}

export function rowColor(theme: GraphTheme, kind: JKind): string {
  if (kind === JKind.Str) {
    return theme.stringColor;
  }
  if (kind === JKind.Num) {
    return theme.numberColor;
  }
  if (kind === JKind.Bool) {
    return theme.boolColor;
  }
  if (kind === JKind.Null) {
    return theme.nullColor;
  }
  if (kind === JKind.Obj || kind === JKind.Arr) {
    return theme.keyText;
  }
  return theme.text;
}

export const NODE_FONT_SIZE: number = 12;
export const ROW_HEIGHT: number = 26;
export const NODE_PADDING_X: number = 12;
export const NODE_PADDING_Y: number = 5;
export const NODE_MAX_WIDTH: number = 660;
export const COLLAPSE_BUTTON_WIDTH: number = 20;

export class RowLayoutInfo {
  text: string = '';
  keyPart: string = '';
  valuePart: string = '';
  width: number = 0;
}

/** 计算节点尺寸，与渲染保持同一套度量方式 */
export function measureNode(rows: NodeRow[]): number[] {
  let maxWidth = 60;
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    let text = '';
    if (row.hasKey) {
      text += row.key + ': ';
    }
    text += row.value;
    const truncated = truncateText(text, 82);
    let w = estimateTextWidth(truncated, NODE_FONT_SIZE) + NODE_PADDING_X * 2;
    if (row.collapsible) {
      w += COLLAPSE_BUTTON_WIDTH;
    }
    if (w > maxWidth) {
      maxWidth = w;
    }
  }
  if (maxWidth > NODE_MAX_WIDTH) {
    maxWidth = NODE_MAX_WIDTH;
  }
  const height = rows.length * ROW_HEIGHT + NODE_PADDING_Y * 2;
  return [Math.ceil(maxWidth), Math.ceil(height)];
}
