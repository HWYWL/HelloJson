import { JKind, JValue } from './JValue';
import { jsonParser } from './JsonParser';
import { stringifyJson } from './JsonWriter';

/** ---------- JSON -> YAML ---------- */
function yamlScalar(v: JValue): string {
  if (v.kind === JKind.Null) {
    return 'null';
  }
  if (v.kind === JKind.Bool) {
    return v.boolVal ? 'true' : 'false';
  }
  if (v.kind === JKind.Num) {
    return v.raw.length > 0 ? v.raw : String(v.numVal);
  }
  const t = v.text;
  if (t.length === 0) {
    return '""';
  }
  const needQuote = /^[\s]|[\s]$/.test(t) || /[:#\-\[\]{}&*!|>'"%@`]/.test(t) ||
    t === 'true' || t === 'false' || t === 'null' || !Number.isNaN(Number(t));
  return needQuote ? JSON.stringify(t) : t;
}

function yamlLines(v: JValue, indent: string, lines: string[]): void {
  if (v.kind === JKind.Obj) {
    for (let i = 0; i < v.keys.length; i++) {
      const key = v.keys[i];
      const child = v.values[i];
      if (child.isContainer() && child.childCount() > 0) {
        lines.push(indent + key + ':');
        yamlLines(child, indent + '  ', lines);
      } else {
        lines.push(indent + key + ': ' + yamlValueInline(child));
      }
    }
    return;
  }
  if (v.kind === JKind.Arr) {
    for (let i = 0; i < v.items.length; i++) {
      const item = v.items[i];
      if (item.isContainer() && item.childCount() > 0) {
        const sub: string[] = [];
        yamlLines(item, indent + '  ', sub);
        if (sub.length > 0) {
          lines.push(indent + '- ' + sub[0].substring(indent.length + 2));
          for (let j = 1; j < sub.length; j++) {
            lines.push(sub[j]);
          }
        }
      } else {
        lines.push(indent + '- ' + yamlValueInline(item));
      }
    }
  }
}

function yamlValueInline(v: JValue): string {
  if (v.kind === JKind.Obj) {
    return '{}';
  }
  if (v.kind === JKind.Arr) {
    return '[]';
  }
  return yamlScalar(v);
}

export function jsonToYaml(root: JValue): string {
  if (!root.isContainer()) {
    return yamlScalar(root);
  }
  const lines: string[] = [];
  yamlLines(root, '', lines);
  return lines.join('\n');
}

/** ---------- YAML -> JSON ---------- */
class YamlLine {
  indent: number = 0;
  content: string = '';
  raw: string = '';
}

function preprocessYaml(text: string): YamlLine[] {
  const rawLines = text.split('\n');
  const out: YamlLine[] = [];
  for (let i = 0; i < rawLines.length; i++) {
    let line = rawLines[i];
    const hashIdx = line.indexOf('#');
    if (hashIdx >= 0 && (hashIdx === 0 || line.charAt(hashIdx - 1) === ' ')) {
      line = line.substring(0, hashIdx);
    }
    if (line.trim().length === 0) {
      continue;
    }
    let indent = 0;
    while (indent < line.length && line.charAt(indent) === ' ') {
      indent++;
    }
    const l = new YamlLine();
    l.indent = indent;
    l.content = line.substring(indent).trim();
    l.raw = line;
    if (l.content === '---' || l.content === '...') {
      continue;
    }
    out.push(l);
  }
  return out;
}

function parseYamlScalar(raw: string): JValue {
  const t = raw.trim();
  if (t.length === 0) {
    return JValue.ofStr('');
  }
  if (t === 'null' || t === '~') {
    return JValue.ofNull();
  }
  if (t === 'true') {
    return JValue.ofBool(true);
  }
  if (t === 'false') {
    return JValue.ofBool(false);
  }
  if (t === '{}') {
    return JValue.ofObj();
  }
  if (t === '[]') {
    return JValue.ofArr();
  }
  if (t.charAt(0) === '"' && t.endsWith('"') && t.length >= 2) {
    try {
      const s = JSON.parse(t) as string;
      return JValue.ofStr(s);
    } catch (e) {
      return JValue.ofStr(t.substring(1, t.length - 1));
    }
  }
  if (t.charAt(0) === '\'' && t.endsWith('\'') && t.length >= 2) {
    return JValue.ofStr(t.substring(1, t.length - 1).replace(new RegExp('\'\'', 'g'), '\''));
  }
  if (!Number.isNaN(Number(t)) && t.length > 0) {
    return JValue.ofNum(Number(t), t);
  }
  return JValue.ofStr(t);
}

function parseBlock(lines: YamlLine[], start: number, indent: number): JValue {
  if (start >= lines.length) {
    return JValue.ofNull();
  }
  const first = lines[start];
  if (first.content.startsWith('- ') || first.content === '-') {
    const arr = JValue.ofArr();
    let i = start;
    while (i < lines.length && lines[i].indent === indent &&
      (lines[i].content.startsWith('- ') || lines[i].content === '-')) {
      const content = lines[i].content;
      if (content === '-') {
        const child = parseBlock(lines, i + 1, indent + 2);
        arr.items.push(child);
        i++;
        continue;
      }
      const itemText = content.substring(2).trim();
      const colonIdx = itemText.indexOf(':');
      if (colonIdx > 0 && !itemText.startsWith('"') && !itemText.startsWith('{')) {
        const obj = JValue.ofObj();
        const key = itemText.substring(0, colonIdx).trim();
        const rest = itemText.substring(colonIdx + 1).trim();
        const virtualIndent = indent + 2 + colonIdx + 1;
        if (rest.length > 0) {
          obj.set(key, parseYamlScalar(rest));
          i++;
        } else {
          const child = parseBlock(lines, i + 1, virtualIndent);
          obj.set(key, child);
          i++;
        }
        while (i < lines.length && lines[i].indent > indent) {
          const sub = lines[i];
          const subColon = sub.content.indexOf(':');
          if (subColon > 0) {
            const k = sub.content.substring(0, subColon).trim();
            const v = sub.content.substring(subColon + 1).trim();
            if (v.length > 0) {
              obj.set(k, parseYamlScalar(v));
              i++;
            } else {
              const child = parseBlock(lines, i + 1, lines[i].indent + 2);
              obj.set(k, child);
              i++;
              while (i < lines.length && lines[i].indent > sub.indent) {
                i++;
              }
            }
          } else {
            i++;
          }
        }
        arr.items.push(obj);
      } else {
        arr.items.push(parseYamlScalar(itemText));
        i++;
      }
    }
    return arr;
  }

  const obj = JValue.ofObj();
  let i = start;
  while (i < lines.length && lines[i].indent === indent) {
    const line = lines[i];
    const colonIdx = line.content.indexOf(':');
    if (colonIdx < 0) {
      i++;
      continue;
    }
    const key = line.content.substring(0, colonIdx).trim();
    const rest = line.content.substring(colonIdx + 1).trim();
    if (rest.length > 0) {
      obj.set(key, parseYamlScalar(rest));
      i++;
    } else {
      let j = i + 1;
      while (j < lines.length && lines[j].indent <= indent) {
        break;
      }
      if (j < lines.length) {
        const childIndent = lines[j].indent;
        const child = parseBlock(lines, j, childIndent);
        obj.set(key, child);
        i = j;
        while (i < lines.length && lines[i].indent > indent) {
          i++;
        }
      } else {
        obj.set(key, JValue.ofNull());
        i++;
      }
    }
  }
  return obj;
}

export function yamlToJson(text: string): JValue {
  const lines = preprocessYaml(text);
  if (lines.length === 0) {
    return JValue.ofNull();
  }
  return parseBlock(lines, 0, lines[0].indent);
}

/** ---------- CSV ---------- */
function splitCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = '';
  let inQuote = false;
  for (let i = 0; i < line.length; i++) {
    const c = line.charAt(i);
    if (inQuote) {
      if (c === '"') {
        if (i + 1 < line.length && line.charAt(i + 1) === '"') {
          cur += '"';
          i++;
        } else {
          inQuote = false;
        }
      } else {
        cur += c;
      }
    } else {
      if (c === '"') {
        inQuote = true;
      } else if (c === ',') {
        out.push(cur);
        cur = '';
      } else {
        cur += c;
      }
    }
  }
  out.push(cur);
  return out;
}

export function csvToJson(text: string): JValue {
  const rows = text.split(new RegExp('\r?\n')).filter((l: string) => l.trim().length > 0);
  if (rows.length === 0) {
    return JValue.ofArr();
  }
  const headers = splitCsvLine(rows[0]).map((h: string) => h.trim());
  const arr = JValue.ofArr();
  for (let i = 1; i < rows.length; i++) {
    const cells = splitCsvLine(rows[i]);
    const obj = JValue.ofObj();
    for (let j = 0; j < headers.length; j++) {
      obj.set(headers[j], JValue.ofStr(j < cells.length ? cells[j] : ''));
    }
    arr.items.push(obj);
  }
  return arr;
}

export function jsonToCsv(root: JValue): string {
  if (root.kind !== JKind.Arr || root.items.length === 0) {
    return '';
  }
  const headers: string[] = [];
  const first = root.items[0];
  if (first.kind === JKind.Obj) {
    for (let i = 0; i < first.keys.length; i++) {
      headers.push(first.keys[i]);
    }
  }
  const lines: string[] = [];
  lines.push(headers.join(','));
  for (let i = 0; i < root.items.length; i++) {
    const row = root.items[i];
    const cells: string[] = [];
    for (let j = 0; j < headers.length; j++) {
      const v = row.get(headers[j]);
      if (v === null) {
        cells.push('');
      } else if (v.kind === JKind.Str) {
        cells.push(v.text.indexOf(',') >= 0 || v.text.indexOf('"') >= 0 ?
          '"' + v.text.replace(new RegExp('"', 'g'), '""') + '"' : v.text);
      } else if (v.isContainer()) {
        cells.push('"' + JSON.stringify(v.text) + '"');
      } else {
        cells.push(v.text);
      }
    }
    lines.push(cells.join(','));
  }
  return lines.join('\n');
}

/** ---------- XML ---------- */
function xmlEscape(s: string): string {
  return s.replace(new RegExp('&', 'g'), '&amp;')
    .replace(new RegExp('<', 'g'), '&lt;')
    .replace(new RegExp('>', 'g'), '&gt;')
    .replace(new RegExp('"', 'g'), '&quot;');
}

function xmlSafeTag(name: string): string {
  let out = name.replace(new RegExp('[^A-Za-z0-9_.-]', 'g'), '_');
  if (out.length === 0) {
    out = 'item';
  }
  if (/^[0-9]/.test(out)) {
    out = 'n_' + out;
  }
  return out;
}

function xmlValue(v: JValue, tag: string, indent: string, lines: string[]): void {
  const safe = xmlSafeTag(tag);
  if (v.kind === JKind.Arr) {
    for (let i = 0; i < v.items.length; i++) {
      xmlValue(v.items[i], safe, indent, lines);
    }
    return;
  }
  if (v.kind === JKind.Obj) {
    if (v.keys.length === 0) {
      lines.push(indent + '<' + safe + '/>');
      return;
    }
    lines.push(indent + '<' + safe + '>');
    for (let i = 0; i < v.keys.length; i++) {
      xmlValue(v.values[i], v.keys[i], indent + '  ', lines);
    }
    lines.push(indent + '</' + safe + '>');
    return;
  }
  lines.push(indent + '<' + safe + '>' + xmlEscape(v.text) + '</' + safe + '>');
}

export function jsonToXml(root: JValue): string {
  const lines: string[] = ['<?xml version="1.0" encoding="UTF-8"?>'];
  if (root.kind === JKind.Obj && root.keys.length === 1 && root.values[0].kind === JKind.Obj) {
    xmlValue(root.values[0], root.keys[0], '', lines);
  } else {
    xmlValue(root, 'root', '', lines);
  }
  return lines.join('\n');
}

class XmlParser {
  private src: string = '';
  private pos: number = 0;

  parse(text: string): JValue {
    this.src = text;
    this.pos = 0;
    this.skipMisc();
    const root = JValue.ofObj();
    const first = this.parseElement();
    if (first !== null) {
      const name = first[0] as string;
      const value = first[1] as JValue;
      root.set(name, value);
    }
    return root;
  }

  private skipMisc(): void {
    while (this.pos < this.src.length) {
      const c = this.src.charAt(this.pos);
      if (c === ' ' || c === '\n' || c === '\r' || c === '\t') {
        this.pos++;
        continue;
      }
      if (this.src.startsWith('<?', this.pos)) {
        const end = this.src.indexOf('?>', this.pos);
        this.pos = end < 0 ? this.src.length : end + 2;
        continue;
      }
      if (this.src.startsWith('<!--', this.pos)) {
        const end = this.src.indexOf('-->', this.pos);
        this.pos = end < 0 ? this.src.length : end + 3;
        continue;
      }
      if (this.src.startsWith('<!', this.pos)) {
        const end = this.src.indexOf('>', this.pos);
        this.pos = end < 0 ? this.src.length : end + 1;
        continue;
      }
      break;
    }
  }

  private parseElement(): (string | JValue)[] | null {
    this.skipMisc();
    if (this.pos >= this.src.length || this.src.charAt(this.pos) !== '<') {
      return null;
    }
    this.pos++;
    let name = '';
    while (this.pos < this.src.length && /[A-Za-z0-9_:.\-]/.test(this.src.charAt(this.pos))) {
      name += this.src.charAt(this.pos);
      this.pos++;
    }
    const element = JValue.ofObj();
    while (this.pos < this.src.length) {
      const c = this.src.charAt(this.pos);
      if (c === '/' && this.src.charAt(this.pos + 1) === '>') {
        this.pos += 2;
        return [name, element];
      }
      if (c === '>') {
        this.pos++;
        break;
      }
      if (c === ' ' || c === '\n' || c === '\r' || c === '\t') {
        this.pos++;
        continue;
      }
      let attrName = '';
      while (this.pos < this.src.length && /[A-Za-z0-9_:.\-]/.test(this.src.charAt(this.pos))) {
        attrName += this.src.charAt(this.pos);
        this.pos++;
      }
      while (this.pos < this.src.length && this.src.charAt(this.pos) !== '=') {
        this.pos++;
      }
      this.pos++;
      const quote = this.src.charAt(this.pos);
      this.pos++;
      let attrValue = '';
      while (this.pos < this.src.length && this.src.charAt(this.pos) !== quote) {
        attrValue += this.src.charAt(this.pos);
        this.pos++;
      }
      this.pos++;
      if (attrName.length > 0) {
        element.set('@' + attrName, JValue.ofStr(attrValue));
      }
    }

    let textContent = '';
    const children: string[] = [];
    const childValues: JValue[] = [];
    while (this.pos < this.src.length) {
      if (this.src.startsWith('</', this.pos)) {
        const end = this.src.indexOf('>', this.pos);
        this.pos = end < 0 ? this.src.length : end + 1;
        break;
      }
      if (this.src.charAt(this.pos) === '<') {
        const child = this.parseElement();
        if (child !== null) {
          const childName = child[0] as string;
          const childValue = child[1] as JValue;
          const existing = children.indexOf(childName);
          if (existing >= 0) {
            const cur = childValues[existing];
            if (cur.kind === JKind.Arr) {
              cur.items.push(childValue);
            } else {
              const arr = JValue.ofArr();
              arr.items.push(cur);
              arr.items.push(childValue);
              childValues[existing] = arr;
            }
          } else {
            children.push(childName);
            childValues.push(childValue);
          }
        }
        continue;
      }
      const c = this.src.charAt(this.pos);
      if (c !== '\n' && c !== '\r' && c !== '\t') {
        textContent += c;
      }
      this.pos++;
    }

    for (let i = 0; i < children.length; i++) {
      element.set(children[i], childValues[i]);
    }
    const trimmed = textContent.trim();
    if (trimmed.length > 0) {
      if (children.length === 0) {
        return [name, JValue.ofStr(trimmed)];
      }
      element.set('#text', JValue.ofStr(trimmed));
    }
    return [name, element];
  }
}

export function xmlToJson(text: string): JValue {
  const parser = new XmlParser();
  return parser.parse(text);
}

/** ---------- 搜索 ---------- */
export class SearchHit {
  path: string = '';
  matchType: string = '';
  snippet: string = '';
}

export function searchJson(root: JValue, query: string): SearchHit[] {
  const hits: SearchHit[] = [];
  const q = query.toLowerCase();
  if (q.length === 0) {
    return hits;
  }
  const walk = (value: JValue, path: string): void => {
    if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.keys.length; i++) {
        const key = value.keys[i];
        const childPath = path + '.' + key;
        if (key.toLowerCase().indexOf(q) >= 0) {
          const hit = new SearchHit();
          hit.path = childPath;
          hit.matchType = 'key';
          hit.snippet = key + ': ' + value.values[i].text;
          hits.push(hit);
        }
        walk(value.values[i], childPath);
      }
      return;
    }
    if (value.kind === JKind.Arr) {
      for (let i = 0; i < value.items.length; i++) {
        walk(value.items[i], path + '[' + i + ']');
      }
      return;
    }
    if (value.text.toLowerCase().indexOf(q) >= 0) {
      const hit = new SearchHit();
      hit.path = path;
      hit.matchType = 'value';
      hit.snippet = value.text;
      hits.push(hit);
    }
  };
  walk(root, '$');
  return hits;
}

/** ---------- 扁平键值（properties / URL 查询串共用） ---------- */
function flattenPairs(v: JValue, prefix: string, keys: string[], values: JValue[]): void {
  if (v.kind === JKind.Obj) {
    for (let i = 0; i < v.keys.length; i++) {
      const key = prefix.length === 0 ? v.keys[i] : prefix + '.' + v.keys[i];
      flattenPairs(v.values[i], key, keys, values);
    }
    return;
  }
  if (v.kind === JKind.Arr) {
    for (let i = 0; i < v.items.length; i++) {
      const key = prefix.length === 0 ? i.toString() : prefix + '.' + i.toString();
      flattenPairs(v.items[i], key, keys, values);
    }
    return;
  }
  if (prefix.length === 0) {
    return;
  }
  keys.push(prefix);
  values.push(v);
}

function scalarText(v: JValue): string {
  if (v.kind === JKind.Null) {
    return '';
  }
  return v.text;
}

/** 字符串标量尽量还原成数字 / 布尔，其余保持字符串 */
function parseScalar(raw: string): JValue {
  const t = raw.trim();
  if (t === 'true') {
    return JValue.ofBool(true);
  }
  if (t === 'false') {
    return JValue.ofBool(false);
  }
  if (t === 'null') {
    return JValue.ofNull();
  }
  if (t.length === 0) {
    return JValue.ofStr('');
  }
  if (/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(t)) {
    return JValue.ofNum(Number(t), t);
  }
  return JValue.ofStr(t);
}

/** 按 a.b.0.c 形式的路径写入，数字段在数组上按下标处理 */
function setPathValue(root: JValue, path: string, value: JValue): void {
  const parts = path.split('.');
  let cur: JValue = root;
  for (let i = 0; i < parts.length; i++) {
    const key = parts[i];
    const last = i === parts.length - 1;
    const isIndex = /^[0-9]+$/.test(key);
    if (last) {
      if (isIndex && cur.kind === JKind.Arr) {
        const idx = Number(key);
        while (cur.items.length <= idx) {
          cur.items.push(JValue.ofNull());
        }
        cur.items[idx] = value;
      } else if (cur.kind === JKind.Obj) {
        cur.set(key, value);
      }
      return;
    }
    const nextIsIndex = /^[0-9]+$/.test(parts[i + 1]);
    if (isIndex && cur.kind === JKind.Arr) {
      const idx = Number(key);
      while (cur.items.length <= idx) {
        cur.items.push(nextIsIndex ? JValue.ofArr() : JValue.ofObj());
      }
      if (cur.items[idx].kind !== JKind.Arr && cur.items[idx].kind !== JKind.Obj) {
        cur.items[idx] = nextIsIndex ? JValue.ofArr() : JValue.ofObj();
      }
      cur = cur.items[idx];
      continue;
    }
    if (cur.kind !== JKind.Obj) {
      return;
    }
    const exist = cur.get(key);
    if (exist === null || (exist.kind !== JKind.Obj && exist.kind !== JKind.Arr)) {
      const created = nextIsIndex ? JValue.ofArr() : JValue.ofObj();
      cur.set(key, created);
      cur = created;
    } else {
      cur = exist;
    }
  }
}

/** ---------- Properties ---------- */
function propEscapeKey(key: string): string {
  let out = '';
  for (let i = 0; i < key.length; i++) {
    const ch = key.charAt(i);
    if (ch === '\\' || ch === '=' || ch === ':' || ch === ' ') {
      out += '\\' + ch;
    } else {
      out += ch;
    }
  }
  return out;
}

function propEscapeValue(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === '\\') {
      out += '\\\\';
    } else if (ch === '\n') {
      out += '\\n';
    } else if (ch === '\r') {
      out += '\\r';
    } else {
      out += ch;
    }
  }
  return out;
}

function propUnescape(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === '\\' && i + 1 < text.length) {
      const nx = text.charAt(i + 1);
      i++;
      if (nx === 'n') {
        out += '\n';
      } else if (nx === 'r') {
        out += '\r';
      } else if (nx === 't') {
        out += '\t';
      } else {
        out += nx;
      }
    } else {
      out += ch;
    }
  }
  return out;
}

export function jsonToProperties(root: JValue): string {
  const keys: string[] = [];
  const values: JValue[] = [];
  flattenPairs(root, '', keys, values);
  const lines: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    lines.push(propEscapeKey(keys[i]) + '=' + propEscapeValue(scalarText(values[i])));
  }
  return lines.join('\n');
}

export function propertiesToJson(text: string): JValue {
  const root = JValue.ofObj();
  const lines = text.split(new RegExp('\r?\n'));
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0 || line.startsWith('#') || line.startsWith('!')) {
      continue;
    }
    let sep = -1;
    for (let j = 0; j < line.length; j++) {
      const ch = line.charAt(j);
      if (ch === '=' || ch === ':') {
        sep = j;
        break;
      }
    }
    const rawKey = sep >= 0 ? line.substring(0, sep) : line;
    const rawVal = sep >= 0 ? line.substring(sep + 1) : '';
    setPathValue(root, propUnescape(rawKey.trim()), parseScalar(propUnescape(rawVal.trim())));
  }
  return root;
}

/** ---------- URL 查询串 ---------- */
function decodeComponent(text: string): string {
  try {
    return decodeURIComponent(text.replace(new RegExp('\\+', 'g'), ' '));
  } catch (e) {
    return text;
  }
}

export function jsonToQuery(root: JValue): string {
  const keys: string[] = [];
  const values: JValue[] = [];
  flattenPairs(root, '', keys, values);
  const parts: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    parts.push(encodeURIComponent(keys[i]) + '=' + encodeURIComponent(scalarText(values[i])));
  }
  return parts.join('&');
}

export function queryToJson(text: string): JValue {
  const root = JValue.ofObj();
  let q = text.trim();
  const qm = q.indexOf('?');
  if (qm >= 0) {
    q = q.substring(qm + 1);
  }
  const hash = q.indexOf('#');
  if (hash >= 0) {
    q = q.substring(0, hash);
  }
  if (q.length === 0) {
    return root;
  }
  const parts = q.split('&');
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (part.length === 0) {
      continue;
    }
    const eq = part.indexOf('=');
    const rawKey = eq >= 0 ? part.substring(0, eq) : part;
    const rawVal = eq >= 0 ? part.substring(eq + 1) : '';
    setPathValue(root, decodeComponent(rawKey), parseScalar(decodeComponent(rawVal)));
  }
  return root;
}

/** ---------- TOML ---------- */
function tomlKeyPart(key: string): string {
  if (/^[A-Za-z0-9_-]+$/.test(key)) {
    return key;
  }
  return JSON.stringify(key);
}

function tomlInline(v: JValue): string {
  if (v.kind === JKind.Str) {
    return JSON.stringify(v.text);
  }
  if (v.kind === JKind.Num) {
    return v.raw.length > 0 ? v.raw : String(v.numVal);
  }
  if (v.kind === JKind.Bool) {
    return v.boolVal ? 'true' : 'false';
  }
  if (v.kind === JKind.Null) {
    return '""';
  }
  const parts: string[] = [];
  if (v.kind === JKind.Arr) {
    for (let i = 0; i < v.items.length; i++) {
      parts.push(tomlInline(v.items[i]));
    }
    return '[' + parts.join(', ') + ']';
  }
  for (let i = 0; i < v.keys.length; i++) {
    parts.push(tomlKeyPart(v.keys[i]) + ' = ' + tomlInline(v.values[i]));
  }
  return '{ ' + parts.join(', ') + ' }';
}

function isTableArray(v: JValue): boolean {
  return v.kind === JKind.Arr && v.items.length > 0 && v.items[0].kind === JKind.Obj;
}

function tomlTable(obj: JValue, path: string, lines: string[]): void {
  for (let i = 0; i < obj.keys.length; i++) {
    const v = obj.values[i];
    if (v.kind === JKind.Obj || isTableArray(v)) {
      continue;
    }
    lines.push(tomlKeyPart(obj.keys[i]) + ' = ' + tomlInline(v));
  }
  for (let i = 0; i < obj.keys.length; i++) {
    const v = obj.values[i];
    const full = path.length === 0 ? tomlKeyPart(obj.keys[i]) : path + '.' + tomlKeyPart(obj.keys[i]);
    if (v.kind === JKind.Obj) {
      lines.push('');
      lines.push('[' + full + ']');
      tomlTable(v, full, lines);
    } else if (isTableArray(v)) {
      for (let j = 0; j < v.items.length; j++) {
        lines.push('');
        lines.push('[[' + full + ']]');
        tomlTable(v.items[j], full, lines);
      }
    }
  }
}

export function jsonToToml(root: JValue): string {
  if (root.kind !== JKind.Obj) {
    return 'value = ' + tomlInline(root);
  }
  const lines: string[] = [];
  tomlTable(root, '', lines);
  while (lines.length > 0 && lines[0].length === 0) {
    lines.splice(0, 1);
  }
  return lines.join('\n');
}

function stripTomlComment(line: string): string {
  let inStr = false;
  let quote = '';
  for (let i = 0; i < line.length; i++) {
    const ch = line.charAt(i);
    if (inStr) {
      if (ch === quote && line.charAt(i - 1) !== '\\') {
        inStr = false;
      }
    } else if (ch === '"' || ch === '\'') {
      inStr = true;
      quote = ch;
    } else if (ch === '#') {
      return line.substring(0, i);
    }
  }
  return line;
}

function splitTopLevel(text: string, sep: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let inStr = false;
  let quote = '';
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    if (inStr) {
      if (ch === quote && text.charAt(i - 1) !== '\\') {
        inStr = false;
      }
      continue;
    }
    if (ch === '"' || ch === '\'') {
      inStr = true;
      quote = ch;
      continue;
    }
    if (ch === '[' || ch === '{') {
      depth++;
    } else if (ch === ']' || ch === '}') {
      depth--;
    } else if (ch === sep && depth === 0) {
      out.push(text.substring(start, i));
      start = i + 1;
    }
  }
  out.push(text.substring(start));
  return out;
}

function unescapeTomlString(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i);
    if (ch !== '\\' || i + 1 >= s.length) {
      out += ch;
      continue;
    }
    const nx = s.charAt(i + 1);
    i++;
    if (nx === 'n') {
      out += '\n';
    } else if (nx === 't') {
      out += '\t';
    } else if (nx === 'r') {
      out += '\r';
    } else if (nx === '"') {
      out += '"';
    } else if (nx === '\\') {
      out += '\\';
    } else {
      out += nx;
    }
  }
  return out;
}

function tomlParseValue(raw: string): JValue {
  const t = raw.trim();
  if (t.length === 0) {
    return JValue.ofStr('');
  }
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    return JValue.ofStr(unescapeTomlString(t.substring(1, t.length - 1)));
  }
  if (t.length >= 2 && t.startsWith('\'') && t.endsWith('\'')) {
    return JValue.ofStr(t.substring(1, t.length - 1));
  }
  if (t === 'true') {
    return JValue.ofBool(true);
  }
  if (t === 'false') {
    return JValue.ofBool(false);
  }
  if (t.startsWith('[') && t.endsWith(']')) {
    const arr = JValue.ofArr();
    const inner = t.substring(1, t.length - 1).trim();
    if (inner.length > 0) {
      const parts = splitTopLevel(inner, ',');
      for (let i = 0; i < parts.length; i++) {
        if (parts[i].trim().length > 0) {
          arr.items.push(tomlParseValue(parts[i]));
        }
      }
    }
    return arr;
  }
  if (t.startsWith('{') && t.endsWith('}')) {
    const obj = JValue.ofObj();
    const inner = t.substring(1, t.length - 1).trim();
    if (inner.length > 0) {
      const parts = splitTopLevel(inner, ',');
      for (let i = 0; i < parts.length; i++) {
        const eq = findTopLevelEq(parts[i]);
        if (eq < 0) {
          continue;
        }
        const key = tomlPath(parts[i].substring(0, eq));
        obj.set(key.length > 0 ? key[0] : '', tomlParseValue(parts[i].substring(eq + 1)));
      }
    }
    return obj;
  }
  return parseScalar(t);
}

function tomlPath(text: string): string[] {
  const out: string[] = [];
  const parts = splitTopLevel(text, '.');
  for (let i = 0; i < parts.length; i++) {
    let p = parts[i].trim();
    if (p.length >= 2 && p.startsWith('"') && p.endsWith('"')) {
      p = unescapeTomlString(p.substring(1, p.length - 1));
    } else if (p.length >= 2 && p.startsWith('\'') && p.endsWith('\'')) {
      p = p.substring(1, p.length - 1);
    }
    if (p.length > 0) {
      out.push(p);
    }
  }
  return out;
}

function findTopLevelEq(line: string): number {
  let inStr = false;
  let quote = '';
  for (let i = 0; i < line.length; i++) {
    const ch = line.charAt(i);
    if (inStr) {
      if (ch === quote && line.charAt(i - 1) !== '\\') {
        inStr = false;
      }
      continue;
    }
    if (ch === '"' || ch === '\'') {
      inStr = true;
      quote = ch;
      continue;
    }
    if (ch === '=') {
      return i;
    }
  }
  return -1;
}

function tomlTableAt(root: JValue, parts: string[], arrayTable: boolean): JValue {
  let cur: JValue = root;
  for (let i = 0; i < parts.length; i++) {
    const key = parts[i];
    const last = i === parts.length - 1;
    if (last && arrayTable) {
      let arr = cur.get(key);
      if (arr === null || arr.kind !== JKind.Arr) {
        arr = JValue.ofArr();
        cur.set(key, arr);
      }
      const item = JValue.ofObj();
      arr.items.push(item);
      return item;
    }
    if (last) {
      const exist = cur.get(key);
      if (exist !== null && exist.kind === JKind.Obj) {
        return exist;
      }
      const created = JValue.ofObj();
      cur.set(key, created);
      return created;
    }
    const next = cur.get(key);
    if (next === null || next.kind !== JKind.Obj) {
      const created = JValue.ofObj();
      cur.set(key, created);
      cur = created;
    } else {
      cur = next;
    }
  }
  return cur;
}

export function tomlToJson(text: string): JValue {
  const root = JValue.ofObj();
  let cur: JValue = root;
  const lines = text.split(new RegExp('\r?\n'));
  for (let i = 0; i < lines.length; i++) {
    const line = stripTomlComment(lines[i]).trim();
    if (line.length === 0) {
      continue;
    }
    if (line.startsWith('[[') && line.endsWith(']]')) {
      cur = tomlTableAt(root, tomlPath(line.substring(2, line.length - 2)), true);
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      cur = tomlTableAt(root, tomlPath(line.substring(1, line.length - 1)), false);
      continue;
    }
    const eq = findTopLevelEq(line);
    if (eq < 0) {
      continue;
    }
    const parts = tomlPath(line.substring(0, eq));
    const value = tomlParseValue(line.substring(eq + 1));
    if (parts.length === 1) {
      cur.set(parts[0], value);
    } else if (parts.length > 1) {
      setPathValue(cur, parts.join('.'), value);
    }
  }
  return root;
}

/** ---------- Markdown 表格 ---------- */
function mdCell(v: JValue): string {
  let text = '';
  if (v.isContainer()) {
    text = stringifyJson(v, 0, false);
  } else if (v.kind !== JKind.Null) {
    text = v.text;
  }
  return text.split('|').join('\\|').split('\n').join('<br>');
}

export function jsonToMarkdown(root: JValue): string {
  if (root.kind === JKind.Arr && root.items.length > 0 && root.items[0].kind === JKind.Obj) {
    const headers: string[] = [];
    for (let i = 0; i < root.items.length; i++) {
      const item = root.items[i];
      if (item.kind !== JKind.Obj) {
        continue;
      }
      for (let j = 0; j < item.keys.length; j++) {
        if (headers.indexOf(item.keys[j]) < 0) {
          headers.push(item.keys[j]);
        }
      }
    }
    if (headers.length === 0) {
      return '';
    }
    const lines: string[] = [];
    lines.push('| ' + headers.join(' | ') + ' |');
    const seps: string[] = [];
    for (let i = 0; i < headers.length; i++) {
      seps.push('---');
    }
    lines.push('| ' + seps.join(' | ') + ' |');
    for (let i = 0; i < root.items.length; i++) {
      const row = root.items[i];
      const cells: string[] = [];
      for (let j = 0; j < headers.length; j++) {
        const cell = row.kind === JKind.Obj ? row.get(headers[j]) : null;
        cells.push(cell === null ? '' : mdCell(cell));
      }
      lines.push('| ' + cells.join(' | ') + ' |');
    }
    return lines.join('\n');
  }
  return '```json\n' + stringifyJson(root, 2, false) + '\n```';
}

function mdCells(row: string): string[] {
  let body = row.trim();
  if (body.startsWith('|')) {
    body = body.substring(1);
  }
  if (body.endsWith('|')) {
    body = body.substring(0, body.length - 1);
  }
  const parts = body.split('|');
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    out.push(parts[i].trim().split('\\|').join('|').split('<br>').join('\n'));
  }
  return out;
}

function isMdSeparator(row: string): boolean {
  const cells = mdCells(row);
  if (cells.length === 0) {
    return false;
  }
  for (let i = 0; i < cells.length; i++) {
    if (!/^:?-{3,}:?$/.test(cells[i])) {
      return false;
    }
  }
  return true;
}

export function markdownToJson(text: string): JValue {
  const fence = text.indexOf('```');
  if (fence >= 0) {
    const start = text.indexOf('\n', fence);
    if (start >= 0) {
      const end = text.indexOf('```', start);
      if (end > start) {
        const parsed = jsonParser.parse(text.substring(start + 1, end));
        if (parsed.ok && parsed.root !== null) {
          return parsed.root;
        }
      }
    }
  }
  const lines = text.split(new RegExp('\r?\n'));
  const rows: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.startsWith('|') && line.endsWith('|')) {
      rows.push(line);
    }
  }
  if (rows.length < 2) {
    return JValue.ofArr();
  }
  const headers = mdCells(rows[0]);
  const arr = JValue.ofArr();
  let startRow = 1;
  if (isMdSeparator(rows[1])) {
    startRow = 2;
  }
  for (let i = startRow; i < rows.length; i++) {
    const cells = mdCells(rows[i]);
    const obj = JValue.ofObj();
    for (let j = 0; j < headers.length; j++) {
      obj.set(headers[j], parseScalar(j < cells.length ? cells[j] : ''));
    }
    arr.items.push(obj);
  }
  return arr;
}
