import { JKind, JValue } from './JValue';

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
