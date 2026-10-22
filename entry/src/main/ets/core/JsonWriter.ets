import { JKind, JValue } from './JValue';

const ESCAPE_MAP: Map<string, string> = new Map<string, string>();

function initEscapeMap(): void {
  if (ESCAPE_MAP.size > 0) {
    return;
  }
  ESCAPE_MAP.set('"', '\\"');
  ESCAPE_MAP.set('\\', '\\\\');
  ESCAPE_MAP.set('\b', '\\b');
  ESCAPE_MAP.set('\f', '\\f');
  ESCAPE_MAP.set('\n', '\\n');
  ESCAPE_MAP.set('\r', '\\r');
  ESCAPE_MAP.set('\t', '\\t');
}

export function escapeJsonString(input: string): string {
  initEscapeMap();
  let out = '"';
  for (let i = 0; i < input.length; i++) {
    const ch = input.charAt(i);
    const mapped = ESCAPE_MAP.get(ch);
    if (mapped !== undefined) {
      out += mapped;
      continue;
    }
    const code = input.charCodeAt(i);
    if (code < 0x20) {
      let hex = code.toString(16);
      while (hex.length < 4) {
        hex = '0' + hex;
      }
      out += '\\u' + hex;
    } else {
      out += ch;
    }
  }
  return out + '"';
}

class WriteOptions {
  indent: number = 2;
  sortKeys: boolean = false;
  keepNumberRaw: boolean = true;
}

function pad(indent: number, level: number): string {
  if (indent <= 0) {
    return '';
  }
  let s = '';
  for (let i = 0; i < indent * level; i++) {
    s += ' ';
  }
  return s;
}

function writeValue(v: JValue, opt: WriteOptions, level: number, out: string[]): void {
  if (v.kind === JKind.Obj) {
    const count = v.keys.length;
    if (count === 0) {
      out.push('{}');
      return;
    }
    out.push('{');
    const order: number[] = [];
    for (let i = 0; i < count; i++) {
      order.push(i);
    }
    if (opt.sortKeys) {
      order.sort((a: number, b: number): number => {
        const ka = v.keys[a];
        const kb = v.keys[b];
        if (ka < kb) {
          return -1;
        }
        return ka > kb ? 1 : 0;
      });
    }
    for (let idx = 0; idx < order.length; idx++) {
      const i = order[idx];
      if (opt.indent > 0) {
        out.push('\n' + pad(opt.indent, level + 1));
      }
      out.push(escapeJsonString(v.keys[i]));
      out.push(opt.indent > 0 ? ': ' : ':');
      writeValue(v.values[i], opt, level + 1, out);
      if (idx < order.length - 1) {
        out.push(',');
      }
    }
    if (opt.indent > 0) {
      out.push('\n' + pad(opt.indent, level));
    }
    out.push('}');
    return;
  }
  if (v.kind === JKind.Arr) {
    if (v.items.length === 0) {
      out.push('[]');
      return;
    }
    out.push('[');
    for (let i = 0; i < v.items.length; i++) {
      if (opt.indent > 0) {
        out.push('\n' + pad(opt.indent, level + 1));
      }
      writeValue(v.items[i], opt, level + 1, out);
      if (i < v.items.length - 1) {
        out.push(',');
      }
    }
    if (opt.indent > 0) {
      out.push('\n' + pad(opt.indent, level));
    }
    out.push(']');
    return;
  }
  if (v.kind === JKind.Str) {
    out.push(escapeJsonString(v.text));
    return;
  }
  if (v.kind === JKind.Num) {
    out.push(opt.keepNumberRaw && v.raw.length > 0 ? v.raw : String(v.numVal));
    return;
  }
  if (v.kind === JKind.Bool) {
    out.push(v.boolVal ? 'true' : 'false');
    return;
  }
  out.push('null');
}

export function stringifyJson(value: JValue | null, indent: number, sortKeys: boolean): string {
  if (value === null) {
    return '';
  }
  const opt = new WriteOptions();
  opt.indent = indent;
  opt.sortKeys = sortKeys;
  const out: string[] = [];
  writeValue(value, opt, 0, out);
  return out.join('');
}

/** 递归排序对象键，返回新值 */
export function sortKeysDeep(value: JValue): JValue {
  const copy = value.clone();
  if (copy.kind === JKind.Obj) {
    const pairs: Map<string, JValue> = new Map<string, JValue>();
    const keys = copy.keys.slice();
    keys.sort();
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const idx = copy.keys.indexOf(k);
      pairs.set(k, copy.values[idx]);
    }
    copy.keys = [];
    copy.values = [];
    keys.forEach((k: string) => {
      copy.keys.push(k);
      const v = pairs.get(k);
      if (v !== undefined) {
        copy.values.push(sortKeysDeep(v));
      }
    });
    return copy;
  }
  if (copy.kind === JKind.Arr) {
    for (let i = 0; i < copy.items.length; i++) {
      copy.items[i] = sortKeysDeep(copy.items[i]);
    }
  }
  return copy;
}

export function escapeWholeText(text: string): string {
  return escapeJsonString(text);
}

export function unescapeWholeText(text: string): string {
  let body = text.trim();
  if (body.length >= 2 && body.charAt(0) === '"' && body.charAt(body.length - 1) === '"') {
    body = body.substring(1, body.length - 1);
  }
  try {
    const parsed = JSON.parse('"' + body + '"') as string;
    return parsed;
  } catch (e) {
    return body;
  }
}
