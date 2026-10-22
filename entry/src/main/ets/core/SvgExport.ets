import { GraphData, GraphTheme, NODE_FONT_SIZE, NODE_PADDING_X, NODE_PADDING_Y, ROW_HEIGHT, rowColor } from './GraphModel';
import { truncateText } from './JValue';
import { Bounds, computeBounds, edgePath } from './EdgeGeometry';

function esc(s: string): string {
  return s.replace(new RegExp('&', 'g'), '&amp;')
    .replace(new RegExp('<', 'g'), '&lt;')
    .replace(new RegExp('>', 'g'), '&gt;');
}

/** 生成完整图的 SVG 文本 */
export function buildSvg(graph: GraphData, theme: GraphTheme, direction: string, padding: number): string {
  const bounds: Bounds = computeBounds(graph.nodes);
  const width = Math.ceil(bounds.width + padding * 2);
  const height = Math.ceil(bounds.height + padding * 2);
  const lines: string[] = [];
  lines.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" ` +
    `viewBox="0 0 ${width} ${height}" font-family="ui-monospace, Menlo, Consolas, monospace">`);
  lines.push(`<rect x="0" y="0" width="${width}" height="${height}" fill="${theme.canvasBg}"/>`);
  lines.push(`<g transform="translate(${padding - bounds.minX}, ${padding - bounds.minY})">`);

  for (let i = 0; i < graph.edges.length; i++) {
    const edge = graph.edges[i];
    const from = graph.nodeMap.get(edge.from);
    const to = graph.nodeMap.get(edge.to);
    if (from === undefined || to === undefined) {
      continue;
    }
    const p = edgePath(from, to, direction);
    lines.push(`<path d="M ${p[0]} ${p[1]} C ${p[2]} ${p[3]}, ${p[4]} ${p[5]}, ${p[6]} ${p[7]}" ` +
      `fill="none" stroke="${theme.edgeColor}" stroke-width="1.4"/>`);
    if (edge.label.length > 0) {
      const midX = (p[0] + p[6]) / 2;
      const midY = (p[1] + p[7]) / 2;
      lines.push(`<text x="${midX}" y="${midY}" fill="${theme.dimText}" font-size="11" ` +
        `text-anchor="middle">${esc(truncateText(edge.label, 24))}</text>`);
    }
  }

  for (let i = 0; i < graph.nodes.length; i++) {
    const node = graph.nodes[i];
    const stroke = node.isRoot ? theme.accent : theme.nodeBorder;
    lines.push(`<rect x="${node.x}" y="${node.y}" width="${node.width}" height="${node.height}" ` +
      `rx="7" fill="${theme.nodeBg}" stroke="${stroke}" stroke-width="1"/>`);
    for (let r = 0; r < node.rows.length; r++) {
      const row = node.rows[r];
      const centerY = node.y + NODE_PADDING_Y + r * ROW_HEIGHT + ROW_HEIGHT / 2 + 4;
      let textX = node.x + NODE_PADDING_X;
      if (row.collapsible) {
        lines.push(`<rect x="${node.x + 9}" y="${centerY - 12}" width="14" height="14" rx="3" ` +
          `fill="${theme.nodeBgAlt}" stroke="${theme.dimText}"/>`);
        textX = node.x + 9 + 20;
      }
      if (row.hasKey) {
        lines.push(`<text x="${textX}" y="${centerY}" fill="${theme.keyText}" font-size="${NODE_FONT_SIZE}">` +
          `${esc(truncateText(row.key, 60))}: </text>`);
        const keyW = (truncateText(row.key, 60).length + 2) * NODE_FONT_SIZE * 0.62;
        lines.push(`<text x="${textX + keyW}" y="${centerY}" fill="${rowColor(theme, row.kind)}" ` +
          `font-size="${NODE_FONT_SIZE}">${esc(truncateText(row.value, 82))}</text>`);
      } else {
        lines.push(`<text x="${textX}" y="${centerY}" fill="${rowColor(theme, row.kind)}" ` +
          `font-size="${NODE_FONT_SIZE}">${esc(truncateText(row.value, 82))}</text>`);
      }
    }
  }

  lines.push('</g>');
  lines.push('</svg>');
  return lines.join('\n');
}
