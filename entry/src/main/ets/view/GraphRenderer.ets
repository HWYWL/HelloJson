import { GraphData, GraphNode, GraphTheme, NODE_FONT_SIZE, NODE_PADDING_X, NODE_PADDING_Y, ROW_HEIGHT, NodeRow, rowColor, KEY_VALUE_GAP } from '../core/GraphModel';
import { JKind, estimateTextWidth, truncateText } from '../core/JValue';
import { edgePath } from '../core/EdgeGeometry';

export class RenderState {
  offsetX: number = 0;
  offsetY: number = 0;
  scale: number = 1;
  selectedId: string = '';
  hitPaths: Set<string> = new Set<string>();
  /** schema 校验出错的节点路径（含祖先），描红显示 */
  errorPaths: Set<string> = new Set<string>();
  theme: GraphTheme = new GraphTheme();
  direction: string = 'DOWN';
}

export class HitResult {
  nodeId: string = '';
  rowIndex: number = -1;
  onCollapse: boolean = false;
  path: string = '';
  hit: boolean = false;
}

function roundRect(ctx: CanvasRenderer, x: number, y: number, w: number, h: number, r: number): void {
  const radius = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + w - radius, y);
  ctx.arcTo(x + w, y, x + w, y + radius, radius);
  ctx.lineTo(x + w, y + h - radius);
  ctx.arcTo(x + w, y + h, x + w - radius, y + h, radius);
  ctx.lineTo(x + radius, y + h);
  ctx.arcTo(x, y + h, x, y + h - radius, radius);
  ctx.lineTo(x, y + radius);
  ctx.arcTo(x, y, x + radius, y, radius);
  ctx.closePath();
}

function rowText(row: NodeRow): string {
  const value = truncateText(row.value, 82);
  if (row.hasKey) {
    return row.key + ': ' + value;
  }
  return value;
}

export function renderGraph(ctx: CanvasRenderer, graph: GraphData, state: RenderState,
  viewWidth: number, viewHeight: number): void {
  const theme = state.theme;
  ctx.fillStyle = theme.canvasBg;
  ctx.fillRect(0, 0, viewWidth, viewHeight);

  ctx.save();
  ctx.translate(state.offsetX, state.offsetY);
  ctx.scale(state.scale, state.scale);

  const w = viewWidth / state.scale;
  const h = viewHeight / state.scale;
  const left = -state.offsetX / state.scale - 40;
  const top = -state.offsetY / state.scale - 40;
  const right = left + w + 80;
  const bottom = top + h + 80;

  ctx.lineWidth = 1.4;
  ctx.strokeStyle = theme.edgeColor;
  for (let i = 0; i < graph.edges.length; i++) {
    const edge = graph.edges[i];
    const from = graph.nodeMap.get(edge.from);
    const to = graph.nodeMap.get(edge.to);
    if (from === undefined || to === undefined) {
      continue;
    }
    if (to.x > right || to.y > bottom || from.x > right || from.y > bottom) {
      continue;
    }
    if (to.x + to.width < left || to.y + to.height < top) {
      continue;
    }
    const p = edgePath(from, to, state.direction);
    ctx.beginPath();
    ctx.moveTo(p[0], p[1]);
    ctx.bezierCurveTo(p[2], p[3], p[4], p[5], p[6], p[7]);
    ctx.stroke();

    if (edge.label.length > 0 && state.scale > 0.55) {
      const midX = (p[0] + p[6]) / 2;
      const midY = (p[1] + p[7]) / 2;
      ctx.font = `11px sans-serif`;
      const tw = estimateTextWidth(edge.label, 11) + 8;
      ctx.fillStyle = theme.edgeLabelBg;
      ctx.fillRect(midX - tw / 2, midY - 8, tw, 16);
      ctx.fillStyle = theme.dimText;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(truncateText(edge.label, 24), midX, midY);
    }
  }

  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  for (let i = 0; i < graph.nodes.length; i++) {
    const node = graph.nodes[i];
    if (node.x > right || node.y > bottom || node.x + node.width < left || node.y + node.height < top) {
      continue;
    }
    const isSelected = node.id === state.selectedId;
    const isHit = state.hitPaths.has(node.path);
    const isError = state.errorPaths.has(node.path);
    ctx.fillStyle = theme.nodeBg;
    roundRect(ctx, node.x, node.y, node.width, node.height, 7);
    ctx.fill();
    if (isSelected) {
      ctx.strokeStyle = theme.nodeBorderActive;
      ctx.lineWidth = 2;
    } else if (isError) {
      ctx.strokeStyle = theme.errorColor;
      ctx.lineWidth = 2;
    } else if (isHit) {
      ctx.strokeStyle = theme.searchHit;
      ctx.lineWidth = 2;
    } else if (node.isRoot) {
      ctx.strokeStyle = theme.accent;
      ctx.lineWidth = 1.4;
    } else {
      ctx.strokeStyle = theme.nodeBorder;
      ctx.lineWidth = 1;
    }
    roundRect(ctx, node.x, node.y, node.width, node.height, 7);
    ctx.stroke();

    for (let r = 0; r < node.rows.length; r++) {
      const row = node.rows[r];
      const centerY = node.y + NODE_PADDING_Y + r * ROW_HEIGHT + ROW_HEIGHT / 2;
      let textX = node.x + NODE_PADDING_X;
      if (row.collapsible) {
        const bx = node.x + 9;
        const by = centerY - 7;
        ctx.fillStyle = row.collapsed ? theme.accent : theme.nodeBgAlt;
        ctx.strokeStyle = row.collapsed ? theme.accent : theme.nodeBorder;
        ctx.lineWidth = 1;
        roundRect(ctx, bx, by, 14, 14, 3);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = row.collapsed ? theme.canvasBg : theme.dimText;
        ctx.font = `11px sans-serif`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(row.collapsed ? '+' : '−', bx + 7, by + 7.5);
        textX = bx + 20;
      }
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.font = `${NODE_FONT_SIZE}px monospace`;
      if (row.hasKey) {
        const keyText = truncateText(row.key, 60) + ':';
        ctx.fillStyle = theme.keyText;
        ctx.fillText(keyText, textX, centerY);
        // 用实际字形宽度定位 value，避免估算偏差在冒号后留下大段空白
        const offset = ctx.measureText(keyText).width + KEY_VALUE_GAP;
        ctx.fillStyle = rowColor(theme, row.kind);
        ctx.fillText(truncateText(row.value, 82), textX + offset, centerY);
      } else {
        ctx.fillStyle = rowColor(theme, row.kind);
        ctx.fillText(truncateText(row.value, 82), textX, centerY);
      }
      if (row.collapsible && row.collapsed) {
        ctx.fillStyle = theme.dimText;
      }
    }
  }
  ctx.restore();
}

/** 世界坐标命中测试 */
export function hitTest(graph: GraphData, worldX: number, worldY: number): HitResult {
  const result = new HitResult();
  for (let i = graph.nodes.length - 1; i >= 0; i--) {
    const node = graph.nodes[i];
    if (worldX >= node.x && worldX <= node.x + node.width &&
      worldY >= node.y && worldY <= node.y + node.height) {
      result.hit = true;
      result.nodeId = node.id;
      result.path = node.path;
      const rowIndex = Math.floor((worldY - node.y - NODE_PADDING_Y) / ROW_HEIGHT);
      if (rowIndex >= 0 && rowIndex < node.rows.length) {
        result.rowIndex = rowIndex;
        const row = node.rows[rowIndex];
        if (row.collapsible && worldX <= node.x + 30) {
          result.onCollapse = true;
          result.path = row.path;
        }
      }
      return result;
    }
  }
  return result;
}

export function findNodeByPath(graph: GraphData, path: string): GraphNode | null {
  for (let i = 0; i < graph.nodes.length; i++) {
    if (graph.nodes[i].path === path) {
      return graph.nodes[i];
    }
  }
  return null;
}

export function kindOfRow(row: NodeRow): JKind {
  return row.kind;
}
