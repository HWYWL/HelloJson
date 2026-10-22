import { GraphData, GraphNode } from './GraphModel';

export class LayoutConfig {
  /** 层间距 */
  gapLayer: number = 86;
  /** 同级节点间距 */
  gapSibling: number = 18;
}

/**
 * 树形分层布局（替代 ELK）：层轴按每层最大尺寸累加，顺序轴按叶子依次分配，
 * 父节点在顺序轴上居中于其子节点。
 */
export class TreeLayout {
  private graph: GraphData = new GraphData();
  private vertical: boolean = false;
  private cursor: number = 0;
  private layerStart: number[] = [];
  private posU: Map<string, number> = new Map<string, number>();
  private posV: Map<string, number> = new Map<string, number>();
  private cfg: LayoutConfig = new LayoutConfig();

  layout(graph: GraphData, direction: string): void {
    this.graph = graph;
    this.vertical = direction === 'DOWN' || direction === 'UP';
    this.cursor = 0;
    this.posU.clear();
    this.posV.clear();
    this.layerStart = [];
    if (graph.nodes.length === 0 || graph.rootId.length === 0) {
      return;
    }

    const layerSize: number[] = [];
    for (let i = 0; i < graph.nodes.length; i++) {
      const n = graph.nodes[i];
      const size = this.vertical ? n.height : n.width;
      while (layerSize.length <= n.depth) {
        layerSize.push(0);
      }
      if (size > layerSize[n.depth]) {
        layerSize[n.depth] = size;
      }
    }
    let acc = 0;
    for (let d = 0; d < layerSize.length; d++) {
      this.layerStart.push(acc);
      acc += layerSize[d] + this.cfg.gapLayer;
    }
    const totalLayer = acc;

    this.place(graph.rootId);

    for (let i = 0; i < graph.nodes.length; i++) {
      const n = graph.nodes[i];
      const u = this.posU.get(n.id);
      const v = this.posV.get(n.id);
      if (u === undefined || v === undefined) {
        continue;
      }
      if (direction === 'RIGHT') {
        n.x = u;
        n.y = v;
      } else if (direction === 'LEFT') {
        n.x = totalLayer - u - n.width;
        n.y = v;
      } else if (direction === 'DOWN') {
        n.x = v;
        n.y = u;
      } else {
        n.x = v;
        n.y = totalLayer - u - n.height;
      }
    }
  }

  private place(id: string): void {
    const node = this.graph.nodeMap.get(id);
    if (node === undefined) {
      return;
    }
    const u = this.layerStart[node.depth];
    const children = node.childrenIds;
    if (children.length === 0) {
      this.posU.set(node.id, u);
      this.posV.set(node.id, this.cursor);
      this.cursor += this.siblingSize(node) + this.cfg.gapSibling;
      return;
    }

    let firstV = 0;
    let lastV = 0;
    for (let i = 0; i < children.length; i++) {
      this.place(children[i]);
      const child = this.graph.nodeMap.get(children[i]);
      if (child === undefined) {
        continue;
      }
      const cv = this.posV.get(child.id);
      if (cv === undefined) {
        continue;
      }
      if (i === 0) {
        firstV = cv + this.siblingSize(child) / 2;
      }
      lastV = cv + this.siblingSize(child) / 2;
    }
    const v = (firstV + lastV) / 2 - this.siblingSize(node) / 2;
    this.posU.set(node.id, u);
    this.posV.set(node.id, v);
  }

  private siblingSize(node: GraphNode): number {
    return this.vertical ? node.width : node.height;
  }
}

export const treeLayout: TreeLayout = new TreeLayout();
