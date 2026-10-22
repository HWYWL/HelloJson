import { JKind, JValue } from './JValue';

/** jq 子集：支持字段/索引/迭代/管道/逗号/构造/内置函数/比较与算术 */
class JqNode {
  op: string = 'identity';
  name: string = '';
  num: number = 0;
  str: string = '';
  children: JqNode[] = [];
  keys: string[] = [];
}

class JqToken {
  type: string = '';
  text: string = '';
  num: number = 0;
}

export class JqResult {
  ok: boolean = true;
  message: string = '';
  values: JValue[] = [];
}

class JqError extends Error {
  constructor(message: string) {
    super(message);
  }
}

function tokenize(src: string): JqToken[] {
  const tokens: JqToken[] = [];
  let i = 0;
  while (i < src.length) {
    const c = src.charAt(i);
    if (c === ' ' || c === '\t' || c === '\n' || c === '\r') {
      i++;
      continue;
    }
    const t = new JqToken();
    if (c === '"') {
      i++;
      let s = '';
      while (i < src.length && src.charAt(i) !== '"') {
        if (src.charAt(i) === '\\' && i + 1 < src.length) {
          i++;
          const esc = src.charAt(i);
          if (esc === 'n') {
            s += '\n';
          } else if (esc === 't') {
            s += '\t';
          } else {
            s += esc;
          }
        } else {
          s += src.charAt(i);
        }
        i++;
      }
      i++;
      t.type = 'str';
      t.text = s;
      tokens.push(t);
      continue;
    }
    if ((c >= '0' && c <= '9') || (c === '-' && i + 1 < src.length &&
      src.charAt(i + 1) >= '0' && src.charAt(i + 1) <= '9')) {
      let s = c;
      i++;
      while (i < src.length) {
        const d = src.charAt(i);
        if ((d >= '0' && d <= '9') || d === '.') {
          s += d;
          i++;
        } else {
          break;
        }
      }
      t.type = 'num';
      t.text = s;
      t.num = Number(s);
      tokens.push(t);
      continue;
    }
    if (/[A-Za-z_]/.test(c)) {
      let s = '';
      while (i < src.length && /[A-Za-z0-9_]/.test(src.charAt(i))) {
        s += src.charAt(i);
        i++;
      }
      t.type = 'ident';
      t.text = s;
      tokens.push(t);
      continue;
    }
    const two = src.substring(i, i + 2);
    if (two === '==' || two === '!=' || two === '<=' || two === '>=' || two === '//' || two === '..') {
      t.type = 'op';
      t.text = two;
      i += 2;
      tokens.push(t);
      continue;
    }
    if (c === '<' || c === '>') {
      t.type = 'op';
      t.text = c;
      i++;
      tokens.push(t);
      continue;
    }
    if ('.|,()[]{}:+-*/<>='.indexOf(c) >= 0) {
      t.type = 'punct';
      t.text = c;
      i++;
      tokens.push(t);
      continue;
    }
    throw new JqError(`无法识别的字符 '${c}'`);
  }
  const end = new JqToken();
  end.type = 'eof';
  tokens.push(end);
  return tokens;
}

class JqParser {
  private tokens: JqToken[] = [];
  private pos: number = 0;

  parse(src: string): JqNode {
    this.tokens = tokenize(src);
    this.pos = 0;
    const node = this.parsePipe();
    if (this.peek().type !== 'eof') {
      throw new JqError(`语法错误：意外的 '${this.peek().text}'`);
    }
    return node;
  }

  private peek(): JqToken {
    return this.tokens[this.pos];
  }

  private next(): JqToken {
    const t = this.tokens[this.pos];
    this.pos++;
    return t;
  }

  private expect(text: string): void {
    const t = this.next();
    if (t.text !== text) {
      throw new JqError(`语法错误：期望 '${text}'`);
    }
  }

  private accept(text: string): boolean {
    if (this.peek().text === text && (this.peek().type === 'punct' || this.peek().type === 'op')) {
      this.pos++;
      return true;
    }
    return false;
  }

  private parsePipe(): JqNode {
    let left = this.parseComma();
    while (this.peek().text === '|') {
      this.pos++;
      const right = this.parseComma();
      const node = new JqNode();
      node.op = 'pipe';
      node.children = [left, right];
      left = node;
    }
    return left;
  }

  private parseComma(): JqNode {
    let left = this.parseUnary();
    while (this.peek().text === ',') {
      this.pos++;
      const right = this.parseUnary();
      const node = new JqNode();
      node.op = 'comma';
      node.children = [left, right];
      left = node;
    }
    return left;
  }

  private parseUnary(): JqNode {
    if (this.peek().text === '-') {
      this.pos++;
      const node = new JqNode();
      node.op = 'negate';
      node.children = [this.parseUnary()];
      return node;
    }
    if (this.peek().text === 'not') {
      this.pos++;
      const node = new JqNode();
      node.op = 'not';
      node.children = [this.parseUnary()];
      return node;
    }
    return this.parsePostfix();
  }

  private parsePostfix(): JqNode {
    let node = this.parsePrimary();
    while (true) {
      const t = this.peek();
      if (t.type === 'punct' && t.text === '.') {
        this.pos++;
        const nameTok = this.peek();
        if (nameTok.type === 'ident') {
          this.pos++;
          node = this.makeField(node, nameTok.text);
        } else if (nameTok.type === 'str') {
          this.pos++;
          node = this.makeField(node, nameTok.text);
        }
        continue;
      }
      if (t.type === 'punct' && t.text === '[') {
        this.pos++;
        if (this.accept(']')) {
          const iter = new JqNode();
          iter.op = 'iterate';
          iter.children = [node];
          node = iter;
          continue;
        }
        if (this.peek().text === '"' || this.peek().type === 'str') {
          const key = this.next().text;
          this.expect(']');
          node = this.makeField(node, key);
          continue;
        }
        const first = this.parsePipe();
        if (this.accept(':')) {
          const endVal = this.parsePipe();
          this.expect(']');
          const slice = new JqNode();
          slice.op = 'slice';
          slice.children = [node, first, endVal];
          node = slice;
          continue;
        }
        this.expect(']');
        const idx = new JqNode();
        idx.op = 'index';
        idx.children = [node, first];
        node = idx;
        continue;
      }
      if (t.type === 'punct' && t.text === '(' && node.op === 'callref') {
        this.pos++;
        const args: JqNode[] = [];
        if (!this.accept(')')) {
          args.push(this.parsePipe());
          while (this.accept(',')) {
            args.push(this.parsePipe());
          }
          this.expect(')');
        }
        node.op = 'call';
        node.children = args;
        continue;
      }
      if ((t.type === 'op' || t.type === 'punct') && (t.text === '==' || t.text === '!=' ||
        t.text === '<' || t.text === '>' || t.text === '<=' || t.text === '>=' || t.text === '//')) {
        this.pos++;
        const right = this.parseUnary();
        const bin = new JqNode();
        bin.op = 'binary';
        bin.name = t.text;
        bin.children = [node, right];
        node = bin;
        continue;
      }
      if (t.type === 'punct' && (t.text === '+' || t.text === '-' || t.text === '*' || t.text === '/')) {
        this.pos++;
        const right = this.parseUnary();
        const bin = new JqNode();
        bin.op = 'binary';
        bin.name = t.text;
        bin.children = [node, right];
        node = bin;
        continue;
      }
      break;
    }
    return node;
  }

  private makeField(base: JqNode, name: string): JqNode {
    const node = new JqNode();
    node.op = 'field';
    node.name = name;
    node.children = [base];
    return node;
  }

  private parsePrimary(): JqNode {
    const t = this.peek();
    if (t.type === 'punct' && t.text === '.') {
      this.pos++;
      const nextTok = this.peek();
      if (nextTok.type === 'ident') {
        this.pos++;
        const field = new JqNode();
        field.op = 'field';
        field.name = nextTok.text;
        field.children = [this.identity()];
        return field;
      }
      if (nextTok.type === 'punct' && nextTok.text === '[') {
        return this.identity();
      }
      return this.identity();
    }
    if (t.type === 'op' && t.text === '..') {
      this.pos++;
      const node = new JqNode();
      node.op = 'recurse';
      return node;
    }
    if (t.type === 'str') {
      this.pos++;
      const node = new JqNode();
      node.op = 'literal';
      node.str = t.text;
      return node;
    }
    if (t.type === 'num') {
      this.pos++;
      const node = new JqNode();
      node.op = 'literal';
      node.num = t.num;
      node.str = 'number';
      return node;
    }
    if (t.type === 'ident') {
      this.pos++;
      if (t.text === 'true' || t.text === 'false') {
        const node = new JqNode();
        node.op = 'literal';
        node.str = 'bool';
        node.num = t.text === 'true' ? 1 : 0;
        return node;
      }
      if (t.text === 'null') {
        const node = new JqNode();
        node.op = 'literal';
        node.str = 'null';
        return node;
      }
      if (t.text === 'empty') {
        const node = new JqNode();
        node.op = 'empty';
        return node;
      }
      const node = new JqNode();
      node.op = 'callref';
      node.name = t.text;
      return node;
    }
    if (t.type === 'punct' && t.text === '(') {
      this.pos++;
      const inner = this.parsePipe();
      this.expect(')');
      return inner;
    }
    if (t.type === 'punct' && t.text === '[') {
      this.pos++;
      const node = new JqNode();
      node.op = 'array';
      if (!this.accept(']')) {
        node.children.push(this.parsePipe());
        this.expect(']');
      }
      return node;
    }
    if (t.type === 'punct' && t.text === '{') {
      this.pos++;
      const node = new JqNode();
      node.op = 'object';
      if (!this.accept('}')) {
        while (true) {
          const keyTok = this.next();
          let keyName = keyTok.text;
          if (keyTok.type === 'str' || keyTok.type === 'ident') {
            keyName = keyTok.text;
          } else {
            throw new JqError('对象构造键无效');
          }
          this.expect(':');
          const valExpr = this.parseUnary();
          node.keys.push(keyName);
          node.children.push(valExpr);
          if (!this.accept(',')) {
            break;
          }
        }
        this.expect('}');
      }
      return node;
    }
    throw new JqError(`语法错误：意外的 '${t.text}'`);
  }

  private identity(): JqNode {
    const node = new JqNode();
    node.op = 'identity';
    return node;
  }
}

function scalarEquals(a: JValue, b: JValue): boolean {
  if (a.kind !== b.kind) {
    return false;
  }
  if (a.kind === JKind.Str) {
    return a.text === b.text;
  }
  if (a.kind === JKind.Num) {
    return a.numVal === b.numVal;
  }
  if (a.kind === JKind.Bool) {
    return a.boolVal === b.boolVal;
  }
  return true;
}

function truthy(v: JValue): boolean {
  if (v.kind === JKind.Bool) {
    return v.boolVal;
  }
  if (v.kind === JKind.Null) {
    return false;
  }
  return true;
}

function compareValues(a: JValue, b: JValue): number {
  if (a.kind === JKind.Num && b.kind === JKind.Num) {
    return a.numVal - b.numVal;
  }
  if (a.kind === JKind.Str && b.kind === JKind.Str) {
    return a.text < b.text ? -1 : (a.text > b.text ? 1 : 0);
  }
  const sa = a.text;
  const sb = b.text;
  return sa < sb ? -1 : (sa > sb ? 1 : 0);
}

export class JqEngine {
  private src: string = '';

  evaluate(json: JValue, expression: string): JqResult {
    const result = new JqResult();
    this.src = expression.trim();
    if (this.src.length === 0) {
      result.values = [json];
      return result;
    }
    try {
      const parser = new JqParser();
      const ast = parser.parse(this.src);
      result.values = this.evalNode(ast, json);
      return result;
    } catch (e) {
      result.ok = false;
      const err = e as Error;
      result.message = err.message;
      return result;
    }
  }

  private evalNode(node: JqNode, input: JValue): JValue[] {
    switch (node.op) {
      case 'identity':
        return [input];
      case 'empty':
        return [];
      case 'literal':
        return [this.literalValue(node)];
      case 'field': {
        const bases = this.evalNode(node.children[0], input);
        const out: JValue[] = [];
        for (let i = 0; i < bases.length; i++) {
          const v = bases[i].get(node.name);
          if (v !== null) {
            out.push(v);
          }
        }
        return out;
      }
      case 'index': {
        const bases = this.evalNode(node.children[0], input);
        const out: JValue[] = [];
        for (let i = 0; i < bases.length; i++) {
          const base = bases[i];
          if (base.kind === JKind.Arr) {
            for (let j = 0; j < node.children[1].num; j++) {
              void j;
            }
          }
        }
        const idxExpr = node.children[1];
        const idxVals = this.evalNode(idxExpr, input);
        const idx = idxVals.length > 0 ? Math.trunc(idxVals[0].numVal) : 0;
        for (let i = 0; i < bases.length; i++) {
          const v = bases[i].at(idx);
          if (v !== null) {
            out.push(v);
          }
        }
        return out;
      }
      case 'slice': {
        const bases = this.evalNode(node.children[0], input);
        const startVals = this.evalNode(node.children[1], input);
        const endVals = this.evalNode(node.children[2], input);
        const start = startVals.length > 0 ? Math.trunc(startVals[0].numVal) : 0;
        const end = endVals.length > 0 ? Math.trunc(endVals[0].numVal) : 2147483647;
        const out: JValue[] = [];
        for (let i = 0; i < bases.length; i++) {
          const base = bases[i];
          if (base.kind === JKind.Arr) {
            const slice = JValue.ofArr();
            for (let j = start; j < Math.min(end, base.items.length); j++) {
              if (j >= 0) {
                slice.items.push(base.items[j]);
              }
            }
            out.push(slice);
          }
        }
        return out;
      }
      case 'iterate': {
        const bases = this.evalNode(node.children[0], input);
        const out: JValue[] = [];
        for (let i = 0; i < bases.length; i++) {
          const base = bases[i];
          if (base.kind === JKind.Arr) {
            for (let j = 0; j < base.items.length; j++) {
              out.push(base.items[j]);
            }
          } else if (base.kind === JKind.Obj) {
            for (let j = 0; j < base.values.length; j++) {
              out.push(base.values[j]);
            }
          }
        }
        return out;
      }
      case 'recurse': {
        const out: JValue[] = [];
        this.collectRecursive(input, out);
        return out;
      }
      case 'pipe': {
        const left = this.evalNode(node.children[0], input);
        const out: JValue[] = [];
        for (let i = 0; i < left.length; i++) {
          const right = this.evalNode(node.children[1], left[i]);
          for (let j = 0; j < right.length; j++) {
            out.push(right[j]);
          }
        }
        return out;
      }
      case 'comma': {
        const out: JValue[] = [];
        const a = this.evalNode(node.children[0], input);
        const b = this.evalNode(node.children[1], input);
        for (let i = 0; i < a.length; i++) {
          out.push(a[i]);
        }
        for (let i = 0; i < b.length; i++) {
          out.push(b[i]);
        }
        return out;
      }
      case 'array': {
        const arr = JValue.ofArr();
        const vals = this.evalNode(node.children[0], input);
        for (let i = 0; i < vals.length; i++) {
          arr.items.push(vals[i]);
        }
        return [arr];
      }
      case 'object': {
        const obj = JValue.ofObj();
        for (let i = 0; i < node.keys.length; i++) {
          const vals = this.evalNode(node.children[i], input);
          if (vals.length > 0) {
            obj.set(node.keys[i], vals[0]);
          }
        }
        return [obj];
      }
      case 'negate': {
        const vals = this.evalNode(node.children[0], input);
        const out: JValue[] = [];
        for (let i = 0; i < vals.length; i++) {
          if (vals[i].kind === JKind.Num) {
            out.push(JValue.ofNum(-vals[i].numVal));
          }
        }
        return out;
      }
      case 'not': {
        const vals = this.evalNode(node.children[0], input);
        return [JValue.ofBool(!(vals.length > 0 && truthy(vals[0])))];
      }
      case 'call':
        return this.evalCall(node, input);
      case 'callref':
        return this.evalCall(node, input);
      case 'binary':
        return this.evalBinary(node, input);
      default:
        return [];
    }
  }

  private collectRecursive(value: JValue, out: JValue[]): void {
    out.push(value);
    if (value.kind === JKind.Arr) {
      for (let i = 0; i < value.items.length; i++) {
        this.collectRecursive(value.items[i], out);
      }
    } else if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.values.length; i++) {
        this.collectRecursive(value.values[i], out);
      }
    }
  }

  private literalValue(node: JqNode): JValue {
    if (node.str === 'number') {
      return JValue.ofNum(node.num);
    }
    if (node.str === 'bool') {
      return JValue.ofBool(node.num === 1);
    }
    if (node.str === 'null') {
      return JValue.ofNull();
    }
    return JValue.ofStr(node.str);
  }

  private evalBinary(node: JqNode, input: JValue): JValue[] {
    const left = this.evalNode(node.children[0], input);
    const right = this.evalNode(node.children[1], input);
    const out: JValue[] = [];
    const op = node.name;
    if (op === '//') {
      if (left.length > 0 && left[0].kind !== JKind.Null) {
        return left;
      }
      return right;
    }
    for (let i = 0; i < left.length; i++) {
      for (let j = 0; j < right.length; j++) {
        const a = left[i];
        const b = right[j];
        if (op === '==') {
          out.push(JValue.ofBool(scalarEquals(a, b)));
        } else if (op === '!=') {
          out.push(JValue.ofBool(!scalarEquals(a, b)));
        } else if (op === '<') {
          out.push(JValue.ofBool(compareValues(a, b) < 0));
        } else if (op === '>') {
          out.push(JValue.ofBool(compareValues(a, b) > 0));
        } else if (op === '<=') {
          out.push(JValue.ofBool(compareValues(a, b) <= 0));
        } else if (op === '>=') {
          out.push(JValue.ofBool(compareValues(a, b) >= 0));
        } else if (op === '+') {
          if (a.kind === JKind.Num && b.kind === JKind.Num) {
            out.push(JValue.ofNum(a.numVal + b.numVal));
          } else if (a.kind === JKind.Str && b.kind === JKind.Str) {
            out.push(JValue.ofStr(a.text + b.text));
          }
        } else if (op === '-') {
          if (a.kind === JKind.Num && b.kind === JKind.Num) {
            out.push(JValue.ofNum(a.numVal - b.numVal));
          }
        } else if (op === '*') {
          if (a.kind === JKind.Num && b.kind === JKind.Num) {
            out.push(JValue.ofNum(a.numVal * b.numVal));
          }
        } else if (op === '/') {
          if (a.kind === JKind.Num && b.kind === JKind.Num && b.numVal !== 0) {
            out.push(JValue.ofNum(a.numVal / b.numVal));
          }
        }
      }
    }
    return out;
  }

  private evalCall(node: JqNode, input: JValue): JValue[] {
    const name = node.name;
    const args = node.children;
    if (name === 'map') {
      const arr = JValue.ofArr();
      const items = input.kind === JKind.Arr ? input.items : (input.kind === JKind.Obj ? input.values : []);
      for (let i = 0; i < items.length; i++) {
        const vals = this.evalNode(args[0], items[i]);
        for (let j = 0; j < vals.length; j++) {
          arr.items.push(vals[j]);
        }
      }
      return [arr];
    }
    if (name === 'select') {
      const vals = this.evalNode(args[0], input);
      if (vals.length > 0 && truthy(vals[0])) {
        return [input];
      }
      return [];
    }
    if (name === 'keys' || name === 'keys_unsorted') {
      const arr = JValue.ofArr();
      if (input.kind === JKind.Obj) {
        const keys = input.keys.slice();
        if (name === 'keys') {
          keys.sort();
        }
        keys.forEach((k: string) => {
          arr.items.push(JValue.ofStr(k));
        });
      } else if (input.kind === JKind.Arr) {
        for (let i = 0; i < input.items.length; i++) {
          arr.items.push(JValue.ofNum(i));
        }
      }
      return [arr];
    }
    if (name === 'values') {
      const arr = JValue.ofArr();
      if (input.kind === JKind.Obj) {
        for (let i = 0; i < input.values.length; i++) {
          arr.items.push(input.values[i]);
        }
      } else if (input.kind === JKind.Arr) {
        for (let i = 0; i < input.items.length; i++) {
          arr.items.push(input.items[i]);
        }
      }
      return [arr];
    }
    if (name === 'length') {
      if (input.kind === JKind.Str) {
        return [JValue.ofNum(input.text.length)];
      }
      return [JValue.ofNum(input.childCount())];
    }
    if (name === 'type') {
      if (input.kind === JKind.Obj) {
        return [JValue.ofStr('object')];
      }
      if (input.kind === JKind.Arr) {
        return [JValue.ofStr('array')];
      }
      if (input.kind === JKind.Str) {
        return [JValue.ofStr('string')];
      }
      if (input.kind === JKind.Num) {
        return [JValue.ofStr('number')];
      }
      if (input.kind === JKind.Bool) {
        return [JValue.ofStr('boolean')];
      }
      return [JValue.ofStr('null')];
    }
    if (name === 'add') {
      if (input.kind === JKind.Arr) {
        if (input.items.length === 0) {
          return [JValue.ofNull()];
        }
        let acc = input.items[0].clone();
        for (let i = 1; i < input.items.length; i++) {
          const cur = input.items[i];
          if (acc.kind === JKind.Num && cur.kind === JKind.Num) {
            acc = JValue.ofNum(acc.numVal + cur.numVal);
          } else if (acc.kind === JKind.Str && cur.kind === JKind.Str) {
            acc = JValue.ofStr(acc.text + cur.text);
          } else if (acc.kind === JKind.Arr) {
            acc.items.push(cur);
          }
        }
        return [acc];
      }
      return [input];
    }
    if (name === 'sort' || name === 'unique' || name === 'reverse') {
      if (input.kind !== JKind.Arr) {
        return [input];
      }
      const items = input.items.slice();
      if (name === 'reverse') {
        items.reverse();
      } else {
        items.sort((a: JValue, b: JValue): number => compareValues(a, b));
      }
      const arr = JValue.ofArr();
      if (name === 'unique') {
        let last = '';
        for (let i = 0; i < items.length; i++) {
          const key = items[i].text;
          if (i === 0 || key !== last) {
            arr.items.push(items[i]);
            last = key;
          }
        }
      } else {
        for (let i = 0; i < items.length; i++) {
          arr.items.push(items[i]);
        }
      }
      return [arr];
    }
    if (name === 'sort_by') {
      if (input.kind !== JKind.Arr) {
        return [input];
      }
      const decorated: JValue[] = [];
      const keys: number[] = [];
      for (let i = 0; i < input.items.length; i++) {
        const vals = this.evalNode(args[0], input.items[i]);
        decorated.push(input.items[i]);
        keys.push(vals.length > 0 ? vals[0].numVal : 0);
      }
      const idx: number[] = [];
      for (let i = 0; i < decorated.length; i++) {
        idx.push(i);
      }
      idx.sort((a: number, b: number): number => keys[a] - keys[b]);
      const arr = JValue.ofArr();
      for (let i = 0; i < idx.length; i++) {
        arr.items.push(decorated[idx[i]]);
      }
      return [arr];
    }
    if (name === 'min' || name === 'max') {
      if (input.kind !== JKind.Arr || input.items.length === 0) {
        return [JValue.ofNull()];
      }
      let best = input.items[0];
      for (let i = 1; i < input.items.length; i++) {
        const cmp = compareValues(input.items[i], best);
        if ((name === 'min' && cmp < 0) || (name === 'max' && cmp > 0)) {
          best = input.items[i];
        }
      }
      return [best];
    }
    if (name === 'flatten') {
      const arr = JValue.ofArr();
      const flatten = (v: JValue): void => {
        if (v.kind === JKind.Arr) {
          for (let i = 0; i < v.items.length; i++) {
            flatten(v.items[i]);
          }
        } else {
          arr.items.push(v);
        }
      };
      flatten(input);
      return [arr];
    }
    if (name === 'to_entries') {
      const arr = JValue.ofArr();
      if (input.kind === JKind.Obj) {
        for (let i = 0; i < input.keys.length; i++) {
          const entry = JValue.ofObj();
          entry.set('key', JValue.ofStr(input.keys[i]));
          entry.set('value', input.values[i]);
          arr.items.push(entry);
        }
      }
      return [arr];
    }
    if (name === 'from_entries') {
      const obj = JValue.ofObj();
      if (input.kind === JKind.Arr) {
        for (let i = 0; i < input.items.length; i++) {
          const entry = input.items[i];
          const k = entry.get('key');
          const v = entry.get('value');
          if (k !== null && v !== null) {
            obj.set(k.kind === JKind.Str ? k.text : String(k.numVal), v);
          }
        }
      }
      return [obj];
    }
    if (name === 'tostring') {
      return [JValue.ofStr(this.compact(input))];
    }
    if (name === 'tonumber') {
      if (input.kind === JKind.Num) {
        return [input];
      }
      const n = Number(input.text);
      return [Number.isNaN(n) ? JValue.ofNull() : JValue.ofNum(n)];
    }
    if (name === 'split') {
      const sepVals = this.evalNode(args[0], input);
      const sep = sepVals.length > 0 ? sepVals[0].text : '';
      const arr = JValue.ofArr();
      const parts = input.text.split(sep);
      for (let i = 0; i < parts.length; i++) {
        arr.items.push(JValue.ofStr(parts[i]));
      }
      return [arr];
    }
    if (name === 'join') {
      const sepVals = this.evalNode(args[0], input);
      const sep = sepVals.length > 0 ? sepVals[0].text : '';
      const parts: string[] = [];
      if (input.kind === JKind.Arr) {
        for (let i = 0; i < input.items.length; i++) {
          parts.push(input.items[i].text);
        }
      }
      return [JValue.ofStr(parts.join(sep))];
    }
    if (name === 'has') {
      const argVals = this.evalNode(args[0], input);
      const key = argVals.length > 0 ? argVals[0] : JValue.ofNull();
      if (input.kind === JKind.Obj) {
        return [JValue.ofBool(input.get(key.text) !== null)];
      }
      if (input.kind === JKind.Arr) {
        return [JValue.ofBool(key.numVal >= 0 && key.numVal < input.items.length)];
      }
      return [JValue.ofBool(false)];
    }
    if (name === 'contains') {
      const argVals = this.evalNode(args[0], input);
      if (argVals.length === 0) {
        return [JValue.ofBool(false)];
      }
      return [JValue.ofBool(this.containsValue(input, argVals[0]))];
    }
    if (name === 'ascii_downcase') {
      return [JValue.ofStr(input.text.toLowerCase())];
    }
    if (name === 'ascii_upcase') {
      return [JValue.ofStr(input.text.toUpperCase())];
    }
    if (name === 'tojson') {
      return [JValue.ofStr(this.compact(input))];
    }
    if (name === 'first' || name === 'last') {
      if (input.kind === JKind.Arr && input.items.length > 0) {
        return [name === 'first' ? input.items[0] : input.items[input.items.length - 1]];
      }
      return [];
    }
    if (name === 'del') {
      const target = args.length > 0 ? args[0] : null;
      if (target !== null && target.op === 'field' && input.kind === JKind.Obj) {
        const copy = input.clone();
        copy.remove(target.name);
        return [copy];
      }
      return [input];
    }
    throw new JqError(`不支持的函数: ${name}`);
  }

  private containsValue(haystack: JValue, needle: JValue): boolean {
    if (needle.kind === JKind.Str && haystack.kind === JKind.Str) {
      return haystack.text.indexOf(needle.text) >= 0;
    }
    if (needle.kind === JKind.Obj && haystack.kind === JKind.Obj) {
      for (let i = 0; i < needle.keys.length; i++) {
        const v = haystack.get(needle.keys[i]);
        if (v === null || !this.containsValue(v, needle.values[i])) {
          return false;
        }
      }
      return true;
    }
    if (needle.kind === JKind.Arr && haystack.kind === JKind.Arr) {
      for (let i = 0; i < needle.items.length; i++) {
        let found = false;
        for (let j = 0; j < haystack.items.length; j++) {
          if (this.containsValue(haystack.items[j], needle.items[i])) {
            found = true;
            break;
          }
        }
        if (!found) {
          return false;
        }
      }
      return true;
    }
    return scalarEquals(haystack, needle);
  }

  private compact(value: JValue): string {
    if (value.kind === JKind.Obj) {
      const parts: string[] = [];
      for (let i = 0; i < value.keys.length; i++) {
        parts.push(JSON.stringify(value.keys[i]) + ':' + this.compact(value.values[i]));
      }
      return '{' + parts.join(',') + '}';
    }
    if (value.kind === JKind.Arr) {
      const parts: string[] = [];
      for (let i = 0; i < value.items.length; i++) {
        parts.push(this.compact(value.items[i]));
      }
      return '[' + parts.join(',') + ']';
    }
    if (value.kind === JKind.Str) {
      return JSON.stringify(value.text) as string;
    }
    return value.text;
  }
}

export const jqEngine: JqEngine = new JqEngine();
