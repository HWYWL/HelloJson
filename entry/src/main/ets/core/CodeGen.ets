import { JKind, JValue } from './JValue';

function pascalCase(input: string): string {
  const cleaned = input.replace(new RegExp('[^A-Za-z0-9]+', 'g'), ' ').trim();
  if (cleaned.length === 0) {
    return 'Item';
  }
  const parts = cleaned.split(' ');
  let out = '';
  for (let i = 0; i < parts.length; i++) {
    const p = parts[i];
    if (p.length === 0) {
      continue;
    }
    out += p.charAt(0).toUpperCase() + p.substring(1);
  }
  if (out.length === 0) {
    return 'Item';
  }
  return /^[0-9]/.test(out) ? 'N' + out : out;
}

function singular(name: string): string {
  if (name.endsWith('ies')) {
    return name.substring(0, name.length - 3) + 'y';
  }
  if (name.endsWith('ses')) {
    return name.substring(0, name.length - 2);
  }
  if (name.endsWith('s') && name.length > 1) {
    return name.substring(0, name.length - 1);
  }
  return name + 'Item';
}

/** 生成 JSON Schema (draft-07) */
export class SchemaGenerator {
  generate(root: JValue, title: string): string {
    const out: string[] = [];
    out.push('{');
    out.push('  "$schema": "http://json-schema.org/draft-07/schema#",');
    out.push('  "title": ' + JSON.stringify(title) + ',');
    this.writeSchema(root, '  ', 2, out, true);
    out.push('}');
    return out.join('\n');
  }

  private writeSchema(value: JValue, indent: string, level: number, out: string[], top: boolean): void {
    if (value.kind === JKind.Obj) {
      out.push(indent + '"type": "object",');
      if (value.keys.length === 0) {
        out.push(indent + '"properties": {}');
        return;
      }
      out.push(indent + '"properties": {');
      for (let i = 0; i < value.keys.length; i++) {
        out.push(indent + '  ' + JSON.stringify(value.keys[i]) + ': {');
        this.writeSchema(value.values[i], indent + '    ', level + 1, out, false);
        out.push(indent + '  }' + (i < value.keys.length - 1 ? ',' : ''));
      }
      out.push(indent + '},');
      const req: string[] = [];
      for (let i = 0; i < value.keys.length; i++) {
        req.push(JSON.stringify(value.keys[i]));
      }
      out.push(indent + '"required": [' + req.join(', ') + ']');
      return;
    }
    if (value.kind === JKind.Arr) {
      out.push(indent + '"type": "array",');
      if (value.items.length === 0) {
        out.push(indent + '"items": {}');
        return;
      }
      out.push(indent + '"items": {');
      this.writeSchema(value.items[0], indent + '  ', level + 1, out, false);
      out.push(indent + '}');
      return;
    }
    out.push(indent + '"type": "' + this.jsonType(value) + '",');
    out.push(indent + '"examples": [' + this.exampleLiteral(value) + ']');
  }

  private jsonType(v: JValue): string {
    if (v.kind === JKind.Str) {
      return 'string';
    }
    if (v.kind === JKind.Num) {
      return 'number';
    }
    if (v.kind === JKind.Bool) {
      return 'boolean';
    }
    if (v.kind === JKind.Arr) {
      return 'array';
    }
    if (v.kind === JKind.Obj) {
      return 'object';
    }
    return 'null';
  }

  private exampleLiteral(v: JValue): string {
    if (v.kind === JKind.Null) {
      return 'null';
    }
    if (v.kind === JKind.Str) {
      const t = v.text.length > 40 ? v.text.substring(0, 40) : v.text;
      return JSON.stringify(t);
    }
    return v.text;
  }
}

/** Java 保留字：生成的字段名撞上时要改名，否则无法编译 */
const JAVA_KEYWORDS: Set<string> = new Set<string>([
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const',
  'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float',
  'for', 'goto', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native',
  'new', 'package', 'private', 'protected', 'public', 'return', 'short', 'static', 'strictfp',
  'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'try', 'void',
  'volatile', 'while', 'true', 'false', 'null'
]);

/** 生成 TypeScript / Go / Kotlin / Rust / Java 类型定义 */
export class TypeGenerator {
  ts(root: JValue, rootName: string): string {
    const lines: string[] = [];
    this.tsObject(root, pascalCase(rootName), lines, 0);
    return lines.join('\n');
  }

  private tsType(value: JValue, name: string, indent: string): string {
    if (value.kind === JKind.Obj) {
      const fields: string[] = [];
      for (let i = 0; i < value.keys.length; i++) {
        const k = value.keys[i];
        const safeKey = /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(k) ? k : JSON.stringify(k);
        const t = this.tsType(value.values[i], k, indent);
        fields.push(k + ': ' + t);
        void safeKey;
      }
      return '{ ' + fields.join('; ') + ' }';
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return 'unknown[]';
      }
      return this.tsType(value.items[0], name, indent) + '[]';
    }
    if (value.kind === JKind.Str) {
      return 'string';
    }
    if (value.kind === JKind.Num) {
      return 'number';
    }
    if (value.kind === JKind.Bool) {
      return 'boolean';
    }
    return 'null';
  }

  private tsObject(value: JValue, name: string, lines: string[], depth: number): void {
    if (value.kind !== JKind.Obj) {
      lines.push('type ' + name + ' = ' + this.tsType(value, name, '') + ';');
      return;
    }
    lines.push('interface ' + name + ' {');
    for (let i = 0; i < value.keys.length; i++) {
      const k = value.keys[i];
      const child = value.values[i];
      const isIdent = /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(k);
      const keyText = isIdent ? k : JSON.stringify(k);
      if (child.kind === JKind.Obj) {
        const childName = pascalCase(k);
        this.tsObject(child, childName, lines, depth + 1);
        lines.push('  ' + keyText + ': ' + childName + ';');
      } else {
        lines.push('  ' + keyText + ': ' + this.tsType(child, k, '  ') + ';');
      }
    }
    lines.push('}');
    lines.push('');
  }

  go(root: JValue, rootName: string): string {
    const lines: string[] = [];
    lines.push('package main');
    lines.push('');
    this.goStruct(root, pascalCase(rootName), lines);
    return lines.join('\n');
  }

  private goType(value: JValue, keyName: string, lines: string[]): string {
    if (value.kind === JKind.Obj) {
      const name = pascalCase(keyName);
      this.goStruct(value, name, lines);
      return name;
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return '[]interface{}';
      }
      return '[]' + this.goType(value.items[0], singular(keyName), lines);
    }
    if (value.kind === JKind.Str) {
      return 'string';
    }
    if (value.kind === JKind.Num) {
      return 'float64';
    }
    if (value.kind === JKind.Bool) {
      return 'bool';
    }
    return 'interface{}';
  }

  private goStruct(value: JValue, name: string, lines: string[]): void {
    if (value.kind !== JKind.Obj) {
      lines.push('type ' + name + ' ' + this.goType(value, name, lines));
      return;
    }
    lines.push('type ' + name + ' struct {');
    for (let i = 0; i < value.keys.length; i++) {
      const k = value.keys[i];
      const fieldName = pascalCase(k);
      const t = this.goType(value.values[i], k, lines);
      lines.push('\t' + fieldName + ' ' + t + ' `json:"' + k + '"`');
    }
    lines.push('}');
    lines.push('');
  }

  kotlin(root: JValue, rootName: string): string {
    const lines: string[] = [];
    this.kotlinClass(root, pascalCase(rootName), lines);
    return lines.join('\n');
  }

  private kotlinType(value: JValue, keyName: string, lines: string[]): string {
    if (value.kind === JKind.Obj) {
      const name = pascalCase(keyName);
      this.kotlinClass(value, name, lines);
      return name;
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return 'List<Any>';
      }
      return 'List<' + this.kotlinType(value.items[0], singular(keyName), lines) + '>';
    }
    if (value.kind === JKind.Str) {
      return 'String';
    }
    if (value.kind === JKind.Num) {
      return 'Double';
    }
    if (value.kind === JKind.Bool) {
      return 'Boolean';
    }
    return 'Any?';
  }

  private kotlinClass(value: JValue, name: string, lines: string[]): void {
    if (value.kind !== JKind.Obj) {
      lines.push('typealias ' + name + ' = ' + this.kotlinType(value, name, lines));
      return;
    }
    const fields: string[] = [];
    for (let i = 0; i < value.keys.length; i++) {
      const k = value.keys[i];
      const propName = /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : '`' + k + '`';
      fields.push('    val ' + propName + ': ' + this.kotlinType(value.values[i], k, lines));
    }
    lines.push('data class ' + name + '(');
    lines.push(fields.join(',\n'));
    lines.push(')');
    lines.push('');
  }

  rust(root: JValue, rootName: string): string {
    const lines: string[] = [];
    lines.push('use serde::{Deserialize, Serialize};');
    lines.push('');
    this.rustStruct(root, pascalCase(rootName), lines, false);
    return lines.join('\n');
  }

  private rustType(value: JValue, keyName: string, lines: string[], boxed: boolean): string {
    if (value.kind === JKind.Obj) {
      const name = pascalCase(keyName);
      this.rustStruct(value, name, lines, false);
      return name;
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return 'Vec<serde_json::Value>';
      }
      return 'Vec<' + this.rustType(value.items[0], singular(keyName), lines, true) + '>';
    }
    if (value.kind === JKind.Str) {
      return boxed ? 'String' : 'String';
    }
    if (value.kind === JKind.Num) {
      return 'f64';
    }
    if (value.kind === JKind.Bool) {
      return 'bool';
    }
    return 'Option<serde_json::Value>';
  }

  private rustStruct(value: JValue, name: string, lines: string[], nested: boolean): void {
    if (value.kind !== JKind.Obj) {
      lines.push('pub type ' + name + ' = ' + this.rustType(value, name, lines, false) + ';');
      return;
    }
    lines.push('#[derive(Debug, Clone, Serialize, Deserialize)]');
    lines.push('pub struct ' + name + ' {');
    for (let i = 0; i < value.keys.length; i++) {
      const k = value.keys[i];
      const fieldName = pascalCase(k).charAt(0).toLowerCase() + pascalCase(k).substring(1);
      const t = this.rustType(value.values[i], k, lines, false);
      lines.push('    #[serde(rename = "' + k + '")]');
      lines.push('    pub ' + fieldName + ': ' + t + ',');
    }
    lines.push('}');
    lines.push('');
    void nested;
  }

  // ---------- Java ----------

  private javaUsed: Set<string> = new Set<string>();

  /**
   * 生成 POJO：嵌套静态类 + 私有字段，key 与字段名不一致时加 @JsonProperty。
   * lombok 为 true 时用 @Data 代替 getter/setter。
   */
  java(root: JValue, rootName: string, lombok: boolean = false): string {
    this.javaUsed = new Set<string>();
    const lines: string[] = [];
    if (root.kind !== JKind.Obj) {
      lines.push('// 根节点不是 JSON 对象，无法生成 Java POJO');
      return lines.join('\n');
    }
    if (this.javaNeedsRename(root)) {
      lines.push('import com.fasterxml.jackson.annotation.JsonProperty;');
    }
    if (this.javaHasArray(root)) {
      lines.push('import java.util.List;');
    }
    if (lombok) {
      lines.push('import lombok.Data;');
    }
    if (lines.length > 0) {
      lines.push('');
    }
    this.javaClass(root, this.uniqueJavaName(pascalCase(rootName)), lines, 0, lombok);
    return lines.join('\n');
  }

  private javaPad(depth: number): string {
    let pad = '';
    for (let i = 0; i < depth; i++) {
      pad += '    ';
    }
    return pad;
  }

  private uniqueJavaName(base: string): string {
    let name = base;
    let seq = 2;
    while (this.javaUsed.has(name)) {
      name = base + seq.toString();
      seq++;
    }
    this.javaUsed.add(name);
    return name;
  }

  /** JSON key → Java 字段名（首单词小写驼峰，非法字符转驼峰分隔，保留字加后缀） */
  private javaFieldName(key: string): string {
    const cleaned = key.replace(new RegExp('[^A-Za-z0-9]+', 'g'), ' ').trim();
    const parts = cleaned.length === 0 ? [] : cleaned.split(' ');
    let out = '';
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (p.length === 0) {
        continue;
      }
      if (out.length === 0) {
        out += p.charAt(0).toLowerCase() + p.substring(1);
      } else {
        out += p.charAt(0).toUpperCase() + p.substring(1);
      }
    }
    if (out.length === 0) {
      out = 'value';
    }
    if (/^[0-9]/.test(out)) {
      out = 'n' + out;
    }
    if (JAVA_KEYWORDS.has(out)) {
      out = out + 'Value';
    }
    return out;
  }

  private javaEscape(key: string): string {
    return key.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }

  private javaHasArray(value: JValue): boolean {
    if (value.kind === JKind.Arr) {
      return true;
    }
    if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.values.length; i++) {
        if (this.javaHasArray(value.values[i])) {
          return true;
        }
      }
    }
    return false;
  }

  private javaNeedsRename(value: JValue): boolean {
    if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.keys.length; i++) {
        if (this.javaFieldName(value.keys[i]) !== value.keys[i]) {
          return true;
        }
        if (this.javaNeedsRename(value.values[i])) {
          return true;
        }
      }
    } else if (value.kind === JKind.Arr) {
      for (let i = 0; i < value.items.length; i++) {
        if (this.javaNeedsRename(value.items[i])) {
          return true;
        }
      }
    }
    return false;
  }

  /** 只解析类型，子对象登记到 nested 供外层类输出后统一生成 */
  private javaType(value: JValue, keyName: string, nested: JValue[], nestedNames: string[]): string {
    if (value.kind === JKind.Obj) {
      const name = this.uniqueJavaName(pascalCase(keyName));
      nested.push(value);
      nestedNames.push(name);
      return name;
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return 'List<Object>';
      }
      return 'List<' + this.javaType(value.items[0], singular(keyName), nested, nestedNames) + '>';
    }
    if (value.kind === JKind.Str) {
      return 'String';
    }
    if (value.kind === JKind.Num) {
      return 'Double';
    }
    if (value.kind === JKind.Bool) {
      return 'Boolean';
    }
    return 'Object';
  }

  private javaClass(value: JValue, name: string, lines: string[], depth: number, lombok: boolean): void {
    const pad = this.javaPad(depth);
    const inner = pad + '    ';
    const keys = value.keys;
    const fields: string[] = [];
    const types: string[] = [];
    const nested: JValue[] = [];
    const nestedNames: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      fields.push(this.javaFieldName(keys[i]));
      types.push(this.javaType(value.values[i], keys[i], nested, nestedNames));
    }

    if (lombok) {
      lines.push(pad + '@Data');
    }
    lines.push(pad + (depth === 0 ? 'public class ' : 'public static class ') + name + ' {');
    for (let i = 0; i < fields.length; i++) {
      if (fields[i] !== keys[i]) {
        lines.push(inner + '@JsonProperty("' + this.javaEscape(keys[i]) + '")');
      }
      lines.push(inner + 'private ' + types[i] + ' ' + fields[i] + ';');
    }
    if (fields.length > 0) {
      lines.push('');
    }
    if (!lombok) {
      for (let i = 0; i < fields.length; i++) {
        const cap = fields[i].charAt(0).toUpperCase() + fields[i].substring(1);
        lines.push(inner + 'public ' + types[i] + ' get' + cap + '() {');
        lines.push(inner + '    return ' + fields[i] + ';');
        lines.push(inner + '}');
        lines.push('');
        lines.push(inner + 'public void set' + cap + '(' + types[i] + ' ' + fields[i] + ') {');
        lines.push(inner + '    this.' + fields[i] + ' = ' + fields[i] + ';');
        lines.push(inner + '}');
        if (i < fields.length - 1) {
          lines.push('');
        }
      }
    }
    for (let i = 0; i < nested.length; i++) {
      if (!lombok || i > 0) {
        lines.push('');
      }
      this.javaClass(nested[i], nestedNames[i], lines, depth + 1, lombok);
    }
    lines.push(pad + '}');
    lines.push('');
  }
}

export const schemaGenerator: SchemaGenerator = new SchemaGenerator();
export const typeGenerator: TypeGenerator = new TypeGenerator();
