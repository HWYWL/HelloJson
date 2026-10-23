/** 差异行的类型：ctx 相同 / add 新增 / del 删除 */
export class DiffLine {
  kind: string = 'ctx';
  /** 在 A 文档中的行号，0 表示该行不存在 */
  aLine: number = 0;
  /** 在 B 文档中的行号，0 表示该行不存在 */
  bLine: number = 0;
  text: string = '';
}

export class DiffResult {
  lines: DiffLine[] = [];
  added: number = 0;
  removed: number = 0;
  /** 差异过大时降级为整块替换 */
  truncated: boolean = false;
}

/** LCS 动态规划的最大格子数，超过则退化为整块替换，避免卡死 */
const MAX_CELLS: number = 1000000;

function ctxLine(aLine: number, bLine: number, text: string): DiffLine {
  const line = new DiffLine();
  line.kind = 'ctx';
  line.aLine = aLine;
  line.bLine = bLine;
  line.text = text;
  return line;
}

function addLine(bLine: number, text: string): DiffLine {
  const line = new DiffLine();
  line.kind = 'add';
  line.bLine = bLine;
  line.text = text;
  return line;
}

function delLine(aLine: number, text: string): DiffLine {
  const line = new DiffLine();
  line.kind = 'del';
  line.aLine = aLine;
  line.text = text;
  return line;
}

/** 对中间差异块做 LCS，生成按顺序排列的差异行 */
function lcsBlock(a: string[], b: string[], start: number, n: number, m: number, r: DiffResult): void {
  const w = m + 1;
  const dp: number[] = [];
  const total = (n + 1) * w;
  for (let i = 0; i < total; i++) {
    dp.push(0);
  }
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      if (a[start + i] === b[start + j]) {
        dp[i * w + j] = dp[(i + 1) * w + j + 1] + 1;
      } else {
        const down = dp[(i + 1) * w + j];
        const right = dp[i * w + j + 1];
        dp[i * w + j] = down >= right ? down : right;
      }
    }
  }
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[start + i] === b[start + j]) {
      r.lines.push(ctxLine(start + i + 1, start + j + 1, a[start + i]));
      i++;
      j++;
    } else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) {
      r.lines.push(delLine(start + i + 1, a[start + i]));
      i++;
    } else {
      r.lines.push(addLine(start + j + 1, b[start + j]));
      j++;
    }
  }
  while (i < n) {
    r.lines.push(delLine(start + i + 1, a[start + i]));
    i++;
  }
  while (j < m) {
    r.lines.push(addLine(start + j + 1, b[start + j]));
    j++;
  }
}

/**
 * 逐行比较两段文本。
 * 先剥掉首尾相同的行，再对中间部分做 LCS；中间块过大时整块按「删除 + 新增」处理。
 */
export function diffLines(aText: string, bText: string): DiffResult {
  const r = new DiffResult();
  const a = aText.replace(/\r\n/g, '\n').split('\n');
  const b = bText.replace(/\r\n/g, '\n').split('\n');

  let start = 0;
  while (start < a.length && start < b.length && a[start] === b[start]) {
    start++;
  }
  let endA = a.length - 1;
  let endB = b.length - 1;
  while (endA >= start && endB >= start && a[endA] === b[endB]) {
    endA--;
    endB--;
  }

  for (let i = 0; i < start; i++) {
    r.lines.push(ctxLine(i + 1, i + 1, a[i]));
  }

  const n = endA - start + 1;
  const m = endB - start + 1;
  if (n > 0 || m > 0) {
    if (n * m > MAX_CELLS) {
      r.truncated = true;
      for (let i = 0; i < n; i++) {
        r.lines.push(delLine(start + i + 1, a[start + i]));
      }
      for (let j = 0; j < m; j++) {
        r.lines.push(addLine(start + j + 1, b[start + j]));
      }
    } else {
      lcsBlock(a, b, start, n, m, r);
    }
  }

  const suffix = a.length - 1 - endA;
  for (let k = 0; k < suffix; k++) {
    const ai = endA + 1 + k;
    const bi = endB + 1 + k;
    r.lines.push(ctxLine(ai + 1, bi + 1, a[ai]));
  }

  for (let i = 0; i < r.lines.length; i++) {
    const kind = r.lines[i].kind;
    if (kind === 'add') {
      r.added++;
    } else if (kind === 'del') {
      r.removed++;
    }
  }
  return r;
}
