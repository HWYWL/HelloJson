import { JKind, JValue } from './JValue';
import { GraphData, GraphEdge, GraphNode, NodeRow, measureNode } from './GraphModel';

/**
 * 将 JSON 值构建为可视化图：一个 object 折叠成一个节点，其标量属性作为行展示；
 * 数组属性展开为多个子节点（与 jsoncrack 的 parseGraph 行为一致）。
 */
export class GraphBuilder {
  private graph: GraphData = new GraphData();
  private collapsed: Set<string> = new Set<string>();
  private nodeSeq: number = 1;
  private edgeSeq: number = 1;

  build(root: JValue, collapsedPaths: Set<string>): GraphData {
    this.graph = new GraphData();
    this.collapsed = collapsedPaths;
    this.nodeSeq = 1;
    this.edgeSeq = 1;
    if (root === null) {
      return this.graph;
    }
    this.graph.rootId = this.traverse(root, '$', false, true, 0);
    return this.graph;
  }

  private newId(): string {
    const id = String(this.nodeSeq);
    this.nodeSeq++;
    return id;
  }

  private addNode(node: GraphNode): void {
    this.graph.nodes.push(node);
    this.graph.nodeMap.set(node.id, node);
    if (node.depth > this.graph.maxDepth) {
      this.graph.maxDepth = node.depth;
    }
  }

  private addEdge(from: string, to: string, label: string): void {
    const e = new GraphEdge();
    e.id = String(this.edgeSeq);
    this.edgeSeq++;
    e.from = from;
    e.to = to;
    e.label = label;
    this.graph.edges.push(e);
    const parent = this.graph.nodeMap.get(from);
    if (parent !== undefined) {
      parent.childrenIds.push(to);
    }
  }

  private childPath(basePath: string, key: string): string {
    if (key.length > 0 && /^[0-9]+$/.test(key)) {
      return basePath + '[' + key + ']';
    }
    return basePath + '.' + key;
  }

  private traverse(value: JValue, path: string, parentIsArray: boolean, isRoot: boolean,
    depth: number): string {
    const id = this.newId();
    const node = new GraphNode();
    node.id = id;
    node.path = path;
    node.isRoot = isRoot;
    node.depth = depth;
    this.addNode(node);
    const rows: NodeRow[] = [];

    const isRootLikeArray = value.kind === JKind.Arr && (isRoot || parentIsArray);

    if (isRootLikeArray) {
      const count = value.items.length;
      const header = new NodeRow();
      header.hasKey = false;
      header.value = `[${count} items]`;
      header.kind = JKind.Arr;
      header.childrenCount = count;
      header.collapsible = false;
      header.path = path;
      rows.push(header);

      for (let i = 0; i < count; i++) {
        const itemPath = path + '[' + i + ']';
        const childId = this.traverse(value.items[i], itemPath, true, false, depth + 1);
        this.addEdge(id, childId, '');
      }
    } else if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.keys.length; i++) {
        const key = value.keys[i];
        const child = value.values[i];
        const cp = this.childPath(path, key);
        if (child.kind === JKind.Arr) {
          const count = child.items.length;
          const isCollapsed = this.collapsed.has(cp);
          const row = new NodeRow();
          row.key = key;
          row.hasKey = true;
          row.kind = JKind.Arr;
          row.childrenCount = count;
          row.collapsible = count > 0;
          row.collapsed = isCollapsed;
          row.path = cp;
          row.value = isCollapsed ? `⋯ ${count} items` : `[${count} items]`;
          rows.push(row);
          if (!isCollapsed) {
            for (let j = 0; j < count; j++) {
              const itemPath = cp + '[' + j + ']';
              const childId = this.traverse(child.items[j], itemPath, true, false, depth + 1);
              this.addEdge(id, childId, key);
            }
          }
        } else if (child.kind === JKind.Obj) {
          const count = child.keys.length;
          const isCollapsed = this.collapsed.has(cp);
          const row = new NodeRow();
          row.key = key;
          row.hasKey = true;
          row.kind = JKind.Obj;
          row.childrenCount = count;
          row.collapsible = count > 0;
          row.collapsed = isCollapsed;
          row.path = cp;
          row.value = isCollapsed ? `⋯ ${count} keys` : `{${count} keys}`;
          rows.push(row);
          if (!isCollapsed) {
            const childId = this.traverse(child, cp, false, false, depth + 1);
            this.addEdge(id, childId, key);
          }
        } else {
          const row = new NodeRow();
          row.key = key;
          row.hasKey = true;
          row.kind = child.kind;
          row.value = child.kind === JKind.Str ? child.text : child.text;
          rows.push(row);
        }
      }
      if (rows.length === 0) {
        const row = new NodeRow();
        row.hasKey = false;
        row.value = '{0 keys}';
        row.kind = JKind.Obj;
        row.childrenCount = 0;
        rows.push(row);
      }
    } else {
      const row = new NodeRow();
      row.hasKey = false;
      row.kind = value.kind;
      row.value = value.text;
      rows.push(row);
    }

    node.rows = rows;
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].collapsible) {
        node.hasCollapsibleRow = true;
        break;
      }
    }
    const size = measureNode(rows);
    node.width = size[0];
    node.height = size[1];
    return id;
  }
}
