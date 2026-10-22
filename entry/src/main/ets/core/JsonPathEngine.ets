import { JKind, JValue } from './JValue';

export class JPathResult {
  ok: boolean = true;
  message: string = '';
  values: JValue[] = [];
  paths: string[] = [];
}

class PathToken {
  type: string = ''; // field / index / wildcard / recursive / filter / slice
  name: string = '';
  index: number = 0;
  start: number = 0;
  end: number = 0;
  filterField: string = '';
  filterOp: string = '';
  filterValue: string = '';
}

/** JSONPath 子集：$ .key ['key'] [n] [*] ..key [?(@.a op v)] [a:b] */
export class JsonPathEngine {
  query(root: JValue, path: string): JPathResult {
    const result = new JPathResult();
    let src = path.trim();
    if (src.length === 0) {
      src = '$';
    }
    if (src.charAt(0) !== '$') {
      src = '$' + (src.charAt(0) === '.' || src.charAt(0) === '[' ? '' : '.') + src;
    }
    let tokens: PathToken[] = [];
    try {
      tokens = this.tokenize(src);
    } catch (e) {
      result.ok = false;
      result.message = (e as Error).message;
      return result;
    }

    let current: JValue[] = [root];
    let currentPaths: string[] = ['$'];
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      const next: JValue[] = [];
      const nextPaths: string[] = [];
      for (let c = 0; c < current.length; c++) {
        this.applyToken(t, current[c], currentPaths[c], next, nextPaths);
      }
      current = next;
      currentPaths = nextPaths;
    }
    result.values = current;
    result.paths = currentPaths;
    return result;
  }

  private applyToken(t: PathToken, value: JValue, path: string, out: JValue[], outPaths: string[]): void {
    if (t.type === 'field') {
      const v = value.get(t.name);
      if (v !== null) {
        out.push(v);
        outPaths.push(path + '.' + t.name);
      }
      return;
    }
    if (t.type === 'index') {
      const v = value.at(t.index);
      if (v !== null) {
        out.push(v);
        outPaths.push(path + '[' + t.index + ']');
      }
      return;
    }
    if (t.type === 'wildcard') {
      if (value.kind === JKind.Arr) {
        for (let i = 0; i < value.items.length; i++) {
          out.push(value.items[i]);
          outPaths.push(path + '[' + i + ']');
        }
      } else if (value.kind === JKind.Obj) {
        for (let i = 0; i < value.keys.length; i++) {
          out.push(value.values[i]);
          outPaths.push(path + '.' + value.keys[i]);
        }
      }
      return;
    }
    if (t.type === 'recursive') {
      if (t.name.length === 0) {
        this.walk(value, path, out, outPaths);
      } else {
        this.walkFind(value, path, t.name, out, outPaths);
      }
      return;
    }
    if (t.type === 'slice') {
      if (value.kind === JKind.Arr) {
        const end = t.end <= 0 ? value.items.length : Math.min(t.end, value.items.length);
        for (let i = t.start; i < end; i++) {
          if (i >= 0) {
            out.push(value.items[i]);
            outPaths.push(path + '[' + i + ']');
          }
        }
      }
      return;
    }
    if (t.type === 'filter') {
      if (value.kind === JKind.Arr) {
        for (let i = 0; i < value.items.length; i++) {
          if (this.matchFilter(value.items[i], t)) {
            out.push(value.items[i]);
            outPaths.push(path + '[' + i + ']');
          }
        }
      } else if (value.kind === JKind.Obj) {
        for (let i = 0; i < value.values.length; i++) {
          if (this.matchFilter(value.values[i], t)) {
            out.push(value.values[i]);
            outPaths.push(path + '.' + value.keys[i]);
          }
        }
      }
    }
  }

  private walk(value: JValue, path: string, out: JValue[], outPaths: string[]): void {
    if (value.kind === JKind.Arr) {
      for (let i = 0; i < value.items.length; i++) {
        out.push(value.items[i]);
        outPaths.push(path + '[' + i + ']');
        this.walk(value.items[i], path + '[' + i + ']', out, outPaths);
      }
    } else if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.values.length; i++) {
        out.push(value.values[i]);
        outPaths.push(path + '.' + value.keys[i]);
        this.walk(value.values[i], path + '.' + value.keys[i], out, outPaths);
      }
    }
  }

  private walkFind(value: JValue, path: string, name: string, out: JValue[], outPaths: string[]): void {
    if (value.kind === JKind.Arr) {
      for (let i = 0; i < value.items.length; i++) {
        this.walkFind(value.items[i], path + '[' + i + ']', name, out, outPaths);
      }
    } else if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.values.length; i++) {
        const key = value.keys[i];
        if (key === name) {
          out.push(value.values[i]);
          outPaths.push(path + '.' + key);
        }
        this.walkFind(value.values[i], path + '.' + key, name, out, outPaths);
      }
    }
  }

  private matchFilter(value: JValue, t: PathToken): boolean {
    let target = value;
    if (t.filterField.length > 0) {
      const found = value.get(t.filterField);
      if (found === null) {
        return false;
      }
      target = found;
    }
    if (t.filterOp.length === 0) {
      return target.kind !== JKind.Null;
    }
    const expected = t.filterValue;
    if (t.filterOp === '==') {
      return this.textOf(target) === expected;
    }
    if (t.filterOp === '!=') {
      return this.textOf(target) !== expected;
    }
    const a = target.kind === JKind.Num ? target.numVal : Number(expected);
    const b = Number(expected);
    if (Number.isNaN(b)) {
      return false;
    }
    if (t.filterOp === '>') {
      return a > b;
    }
    if (t.filterOp === '<') {
      return a < b;
    }
    if (t.filterOp === '>=') {
      return a >= b;
    }
    if (t.filterOp === '<=') {
      return a <= b;
    }
    return false;
  }

  private textOf(v: JValue): string {
    if (v.kind === JKind.Str) {
      return v.text;
    }
    return v.text;
  }

  private tokenize(src: string): PathToken[] {
    const tokens: PathToken[] = [];
    let i = 0;
    if (src.charAt(0) === '$') {
      i = 1;
    }
    while (i < src.length) {
      const c = src.charAt(i);
      if (c === '.') {
        if (src.charAt(i + 1) === '.') {
          i += 2;
          const t = new PathToken();
          t.type = 'recursive';
          let name = '';
          while (i < src.length && /[A-Za-z0-9_$\-]/.test(src.charAt(i))) {
            name += src.charAt(i);
            i++;
          }
          t.name = name;
          tokens.push(t);
          continue;
        }
        i++;
        if (src.charAt(i) === '*') {
          i++;
          const t = new PathToken();
          t.type = 'wildcard';
          tokens.push(t);
          continue;
        }
        let name = '';
        while (i < src.length && /[A-Za-z0-9_$\-]/.test(src.charAt(i))) {
          name += src.charAt(i);
          i++;
        }
        if (name.length === 0) {
          throw new Error('JSONPath 语法错误：缺少字段名');
        }
        const t = new PathToken();
        t.type = 'field';
        t.name = name;
        tokens.push(t);
        continue;
      }
      if (c === '[') {
        const end = src.indexOf(']', i);
        if (end < 0) {
          throw new Error('JSONPath 语法错误：缺少 "]"');
        }
        const body = src.substring(i + 1, end).trim();
        i = end + 1;
        if (body === '*') {
          const t = new PathToken();
          t.type = 'wildcard';
          tokens.push(t);
          continue;
        }
        if (body.startsWith('?')) {
          tokens.push(this.parseFilter(body));
          continue;
        }
        if (body.indexOf(':') > 0) {
          const parts = body.split(':');
          const t = new PathToken();
          t.type = 'slice';
          t.start = parts[0].trim().length > 0 ? parseInt(parts[0].trim()) : 0;
          t.end = parts.length > 1 && parts[1].trim().length > 0 ? parseInt(parts[1].trim()) : 0;
          tokens.push(t);
          continue;
        }
        const cleaned = body.replace(new RegExp('^[\'"]|[\'"]$', 'g'), '');
        const t = new PathToken();
        if (/^-?[0-9]+$/.test(cleaned)) {
          t.type = 'index';
          t.index = parseInt(cleaned);
        } else {
          t.type = 'field';
          t.name = cleaned;
        }
        tokens.push(t);
        continue;
      }
      i++;
    }
    return tokens;
  }

  private parseFilter(body: string): PathToken {
    const t = new PathToken();
    t.type = 'filter';
    let expr = body.substring(1).trim();
    if (expr.startsWith('(') && expr.endsWith(')')) {
      expr = expr.substring(1, expr.length - 1).trim();
    }
    if (expr.startsWith('@.')) {
      expr = expr.substring(2);
    }
    const ops = ['==', '!=', '>=', '<=', '>', '<'];
    for (let i = 0; i < ops.length; i++) {
      const idx = expr.indexOf(ops[i]);
      if (idx > 0) {
        t.filterField = expr.substring(0, idx).trim().replace(new RegExp('^[\'"]|[\'"]$', 'g'), '');
        t.filterOp = ops[i];
        let val = expr.substring(idx + ops[i].length).trim();
        val = val.replace(new RegExp('^[\'"]|[\'"]$', 'g'), '');
        t.filterValue = val;
        return t;
      }
    }
    t.filterField = expr.trim().replace(new RegExp('^[\'"]|[\'"]$', 'g'), '');
    return t;
  }
}

export const jsonPathEngine: JsonPathEngine = new JsonPathEngine();
