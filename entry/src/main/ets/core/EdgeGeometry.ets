import { GraphNode } from './GraphModel';

/** 返回三次贝塞尔路径参数 [x1,y1,c1x,c1y,c2x,c2y,x2,y2] */
export function edgePath(from: GraphNode, to: GraphNode, direction: string): number[] {
  const fx = from.x;
  const fy = from.y;
  const fw = from.width;
  const fh = from.height;
  const tx = to.x;
  const ty = to.y;
  const tw = to.width;
  const th = to.height;

  if (direction === 'LEFT') {
    const x1 = fx;
    const y1 = fy + fh / 2;
    const x2 = tx + tw;
    const y2 = ty + th / 2;
    const dx = Math.max(28, Math.abs(x1 - x2) * 0.45);
    return [x1, y1, x1 - dx, y1, x2 + dx, y2, x2, y2];
  }
  if (direction === 'DOWN') {
    const x1 = fx + fw / 2;
    const y1 = fy + fh;
    const x2 = tx + tw / 2;
    const y2 = ty;
    const dy = Math.max(28, Math.abs(y1 - y2) * 0.45);
    return [x1, y1, x1, y1 + dy, x2, y2 - dy, x2, y2];
  }
  if (direction === 'UP') {
    const x1 = fx + fw / 2;
    const y1 = fy;
    const x2 = tx + tw / 2;
    const y2 = ty + th;
    const dy = Math.max(28, Math.abs(y1 - y2) * 0.45);
    return [x1, y1, x1, y1 - dy, x2, y2 + dy, x2, y2];
  }
  const x1 = fx + fw;
  const y1 = fy + fh / 2;
  const x2 = tx;
  const y2 = ty + th / 2;
  const dx = Math.max(28, Math.abs(x2 - x1) * 0.45);
  return [x1, y1, x1 + dx, y1, x2 - dx, y2, x2, y2];
}

export class Bounds {
  minX: number = 0;
  minY: number = 0;
  maxX: number = 0;
  maxY: number = 0;
  width: number = 0;
  height: number = 0;
}

export function computeBounds(nodes: GraphNode[]): Bounds {
  const b = new Bounds();
  if (nodes.length === 0) {
    return b;
  }
  b.minX = nodes[0].x;
  b.minY = nodes[0].y;
  b.maxX = nodes[0].x + nodes[0].width;
  b.maxY = nodes[0].y + nodes[0].height;
  for (let i = 1; i < nodes.length; i++) {
    const n = nodes[i];
    if (n.x < b.minX) {
      b.minX = n.x;
    }
    if (n.y < b.minY) {
      b.minY = n.y;
    }
    if (n.x + n.width > b.maxX) {
      b.maxX = n.x + n.width;
    }
    if (n.y + n.height > b.maxY) {
      b.maxY = n.y + n.height;
    }
  }
  b.width = b.maxX - b.minX;
  b.height = b.maxY - b.minY;
  return b;
}
