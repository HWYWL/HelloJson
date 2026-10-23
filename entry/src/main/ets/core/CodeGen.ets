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

  // ---------- C# ----------

  private csUsed: Set<string> = new Set<string>();

  /** 生成 C# 类：属性 PascalCase，key 与属性名不一致时加 [JsonPropertyName] */
  csharp(root: JValue, rootName: string): string {
    this.csUsed = new Set<string>();
    const lines: string[] = [];
    if (root.kind !== JKind.Obj) {
      lines.push('// 根节点不是 JSON 对象，无法生成 C# 类');
      return lines.join('\n');
    }
    if (this.csHasCollection(root)) {
      lines.push('using System.Collections.Generic;');
    }
    if (this.csNeedsRename(root)) {
      lines.push('using System.Text.Json.Serialization;');
    }
    if (lines.length > 0) {
      lines.push('');
    }
    this.csClass(root, this.uniqueCsName(pascalCase(rootName)), lines, 0);
    return lines.join('\n');
  }

  private swiftPad(depth: number): string {
    let pad = '';
    for (let i = 0; i < depth; i++) {
      pad += '    ';
    }
    return pad;
  }

  private uniqueCsName(base: string): string {
    let name = base;
    let seq = 2;
    while (this.csUsed.has(name)) {
      name = base + seq.toString();
      seq++;
    }
    this.csUsed.add(name);
    return name;
  }

  private csPropName(key: string): string {
    const name = pascalCase(key);
    return name.length === 0 ? 'Value' : name;
  }

  private csHasCollection(value: JValue): boolean {
    if (value.kind === JKind.Arr) {
      return true;
    }
    if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.values.length; i++) {
        if (this.csHasCollection(value.values[i])) {
          return true;
        }
      }
    }
    return false;
  }

  private csNeedsRename(value: JValue): boolean {
    if (value.kind === JKind.Obj) {
      for (let i = 0; i < value.keys.length; i++) {
        if (this.csPropName(value.keys[i]) !== value.keys[i]) {
          return true;
        }
        if (this.csNeedsRename(value.values[i])) {
          return true;
        }
      }
    } else if (value.kind === JKind.Arr) {
      for (let i = 0; i < value.items.length; i++) {
        if (this.csNeedsRename(value.items[i])) {
          return true;
        }
      }
    }
    return false;
  }

  private csType(value: JValue, keyName: string, nested: JValue[], nestedNames: string[]): string {
    if (value.kind === JKind.Obj) {
      const name = this.uniqueCsName(pascalCase(keyName));
      nested.push(value);
      nestedNames.push(name);
      return name;
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return 'List<object>';
      }
      return 'List<' + this.csType(value.items[0], singular(keyName), nested, nestedNames) + '>';
    }
    if (value.kind === JKind.Str) {
      return 'string';
    }
    if (value.kind === JKind.Num) {
      return 'double';
    }
    if (value.kind === JKind.Bool) {
      return 'bool';
    }
    return 'object';
  }

  private csClass(value: JValue, name: string, lines: string[], depth: number): void {
    const pad = this.swiftPad(depth);
    const inner = pad + '    ';
    const keys = value.keys;
    const props: string[] = [];
    const types: string[] = [];
    const nested: JValue[] = [];
    const nestedNames: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      props.push(this.csPropName(keys[i]));
      types.push(this.csType(value.values[i], keys[i], nested, nestedNames));
    }

    lines.push(pad + 'public class ' + name);
    lines.push(pad + '{');
    for (let i = 0; i < props.length; i++) {
      if (props[i] !== keys[i]) {
        lines.push(inner + '[JsonPropertyName("' + this.javaEscape(keys[i]) + '")]');
      }
      lines.push(inner + 'public ' + types[i] + ' ' + props[i] + ' { get; set; }');
      lines.push('');
    }
    for (let i = 0; i < nested.length; i++) {
      this.csClass(nested[i], nestedNames[i], lines, depth + 1);
    }
    lines.push(pad + '}');
    lines.push('');
  }

  // ---------- Swift ----------

  private swiftUsed: Set<string> = new Set<string>();

  /** 生成 Swift struct（Codable），对象字段生成为嵌套 struct */
  swift(root: JValue, rootName: string): string {
    this.swiftUsed = new Set<string>();
    const lines: string[] = [];
    this.swiftStruct(root, this.uniqueSwiftName(pascalCase(rootName)), lines, 0);
    return lines.join('\n');
  }

  private uniqueSwiftName(base: string): string {
    let name = base;
    let seq = 2;
    while (this.swiftUsed.has(name)) {
      name = base + seq.toString();
      seq++;
    }
    this.swiftUsed.add(name);
    return name;
  }

  /** JSON key → Swift 属性名：小写驼峰，保留字用反引号 */
  private swiftFieldName(key: string): string {
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
    if (SWIFT_KEYWORDS.has(out)) {
      return '`' + out + '`';
    }
    return out;
  }

  private swiftType(value: JValue, keyName: string, nested: JValue[], nestedNames: string[]): string {
    if (value.kind === JKind.Obj) {
      const name = this.uniqueSwiftName(pascalCase(keyName));
      nested.push(value);
      nestedNames.push(name);
      return name;
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return '[Any]';
      }
      return '[' + this.swiftType(value.items[0], singular(keyName), nested, nestedNames) + ']';
    }
    if (value.kind === JKind.Str) {
      return 'String';
    }
    if (value.kind === JKind.Num) {
      return 'Double';
    }
    if (value.kind === JKind.Bool) {
      return 'Bool';
    }
    return 'Any';
  }

  private swiftStruct(value: JValue, name: string, lines: string[], depth: number): void {
    const pad = this.swiftPad(depth);
    const inner = pad + '    ';
    if (value.kind !== JKind.Obj) {
      lines.push('typealias ' + name + ' = ' + this.swiftType(value, name, [], []) + '?');
      lines.push('');
      return;
    }
    const keys = value.keys;
    const props: string[] = [];
    const types: string[] = [];
    const nested: JValue[] = [];
    const nestedNames: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      props.push(this.swiftFieldName(keys[i]));
      types.push(this.swiftType(value.values[i], keys[i], nested, nestedNames));
    }
    let needMap = false;
    for (let i = 0; i < props.length; i++) {
      if (props[i].replace(new RegExp('`', 'g'), '') !== keys[i]) {
        needMap = true;
      }
    }

    lines.push(pad + 'struct ' + name + ': Codable {');
    for (let i = 0; i < props.length; i++) {
      lines.push(inner + 'let ' + props[i] + ': ' + types[i] + '?');
    }
    if (needMap) {
      lines.push('');
      lines.push(inner + 'enum CodingKeys: String, CodingKey {');
      for (let i = 0; i < props.length; i++) {
        if (props[i].replace(new RegExp('`', 'g'), '') !== keys[i]) {
          lines.push(inner + '    case ' + props[i] + ' = "' + this.javaEscape(keys[i]) + '"');
        }
      }
      lines.push(inner + '}');
    }
    for (let i = 0; i < nested.length; i++) {
      lines.push('');
      this.swiftStruct(nested[i], nestedNames[i], lines, depth + 1);
    }
    lines.push(pad + '}');
    lines.push('');
  }

  // ---------- Dart ----------

  /** Dart 不支持嵌套类：所有对象拍平成同级类，靠唯一类名区分 */
  private dartValues: JValue[] = [];
  private dartNames: string[] = [];
  private dartUsed: Set<string> = new Set<string>();

  dart(root: JValue, rootName: string): string {
    this.dartValues = [];
    this.dartNames = [];
    this.dartUsed = new Set<string>();
    const lines: string[] = [];
    if (root.kind !== JKind.Obj) {
      lines.push('/// 根节点不是 JSON 对象，无法生成 Dart 类');
      return lines.join('\n');
    }
    this.dartRegister(root, this.uniqueDartName(pascalCase(rootName)));
    for (let i = 0; i < this.dartValues.length; i++) {
      this.dartClass(this.dartValues[i], this.dartNames[i], lines);
      if (i < this.dartValues.length - 1) {
        lines.push('');
      }
    }
    return lines.join('\n');
  }

  private uniqueDartName(base: string): string {
    let name = base;
    let seq = 2;
    while (this.dartUsed.has(name)) {
      name = base + seq.toString();
      seq++;
    }
    this.dartUsed.add(name);
    return name;
  }

  private dartRegistered(value: JValue): string {
    for (let i = 0; i < this.dartValues.length; i++) {
      if (this.dartValues[i] === value) {
        return this.dartNames[i];
      }
    }
    return '';
  }

  private dartRegister(value: JValue, name: string): void {
    this.dartValues.push(value);
    this.dartNames.push(name);
    for (let i = 0; i < value.keys.length; i++) {
      this.dartType(value.values[i], value.keys[i]);
    }
  }

  /** JSON key → Dart 字段名：小写驼峰，保留字加 Value 后缀 */
  private dartFieldName(key: string): string {
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
    if (DART_KEYWORDS.has(out)) {
      out = out + 'Value';
    }
    return out;
  }

  private dartType(value: JValue, keyName: string): string {
    if (value.kind === JKind.Obj) {
      const registered = this.dartRegistered(value);
      if (registered.length > 0) {
        return registered;
      }
      const name = this.uniqueDartName(pascalCase(keyName));
      this.dartRegister(value, name);
      return name;
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return 'List<dynamic>';
      }
      return 'List<' + this.dartType(value.items[0], singular(keyName)) + '>';
    }
    if (value.kind === JKind.Str) {
      return 'String';
    }
    if (value.kind === JKind.Num) {
      return 'double';
    }
    if (value.kind === JKind.Bool) {
      return 'bool';
    }
    return 'dynamic';
  }

  /** fromJson 中该字段的取值表达式 */
  private dartFromExpr(value: JValue, keyText: string): string {
    const src = 'json[' + keyText + ']';
    if (value.kind === JKind.Obj) {
      const name = this.dartRegistered(value);
      if (name.length === 0) {
        return src;
      }
      return src + ' != null ? ' + name + '.fromJson(' + src + ' as Map<String, dynamic>) : null';
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length === 0) {
        return src + ' as List?';
      }
      const head = value.items[0];
      if (head.kind === JKind.Obj) {
        const name = this.dartRegistered(head);
        if (name.length === 0) {
          return src + ' as List?';
        }
        return '(' + src + ' as List?)?.map((e) => ' + name +
          '.fromJson(e as Map<String, dynamic>)).toList()';
      }
      if (head.kind === JKind.Num) {
        return '(' + src + ' as List?)?.map((e) => (e as num).toDouble()).toList()';
      }
      if (head.kind === JKind.Str) {
        return '(' + src + ' as List?)?.map((e) => e as String).toList()';
      }
      if (head.kind === JKind.Bool) {
        return '(' + src + ' as List?)?.map((e) => e as bool).toList()';
      }
      return src + ' as List?';
    }
    if (value.kind === JKind.Num) {
      return '(' + src + ' as num?)?.toDouble()';
    }
    if (value.kind === JKind.Bool) {
      return src + ' as bool?';
    }
    if (value.kind === JKind.Str) {
      return src + ' as String?';
    }
    return src;
  }

  /** toJson 中该字段的写入语句 */
  private dartToStmt(value: JValue, keyText: string, field: string): string {
    if (value.kind === JKind.Obj) {
      return 'map[' + keyText + '] = ' + field + '?.toJson();';
    }
    if (value.kind === JKind.Arr) {
      if (value.items.length > 0 && value.items[0].kind === JKind.Obj) {
        return 'map[' + keyText + '] = ' + field + '?.map((e) => e.toJson()).toList();';
      }
      return 'map[' + keyText + '] = ' + field + ';';
    }
    return 'map[' + keyText + '] = ' + field + ';';
  }

  private dartClass(value: JValue, name: string, lines: string[]): void {
    const keys = value.keys;
    const fields: string[] = [];
    const types: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      fields.push(this.dartFieldName(keys[i]));
      types.push(this.dartType(value.values[i], keys[i]));
    }
    lines.push('class ' + name + ' {');
    for (let i = 0; i < fields.length; i++) {
      lines.push('  ' + types[i] + '? ' + fields[i] + ';');
    }
    lines.push('');
    lines.push('  ' + name + '();');
    lines.push('');
    lines.push('  ' + name + '.fromJson(Map<String, dynamic> json) {');
    for (let i = 0; i < fields.length; i++) {
      lines.push('    ' + fields[i] + ' = ' + this.dartFromExpr(value.values[i], JSON.stringify(keys[i])) + ';');
    }
    lines.push('  }');
    lines.push('');
    lines.push('  Map<String, dynamic> toJson() {');
    lines.push('    final map = <String, dynamic>{};');
    for (let i = 0; i < fields.length; i++) {
      lines.push('    ' + this.dartToStmt(value.values[i], JSON.stringify(keys[i]), fields[i]));
    }
    lines.push('    return map;');
    lines.push('  }');
    lines.push('}');
  }
}

/** Dart 保留字：字段名撞上时加 Value 后缀 */
const DART_KEYWORDS: Set<string> = new Set<string>([
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', 'catch', 'class',
  'const', 'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum',
  'export', 'extends', 'extension', 'external', 'factory', 'false', 'final', 'finally', 'for',
  'function', 'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late',
  'library', 'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow', 'return',
  'sealed', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true', 'try',
  'typedef', 'var', 'void', 'while', 'with', 'yield'
]);

/** Swift 保留字：属性名冲突时用反引号包裹 */
const SWIFT_KEYWORDS: Set<string> = new Set<string>([
  'associatedtype', 'class', 'deinit', 'enum', 'extension', 'fileprivate', 'func', 'import',
  'init', 'inout', 'internal', 'let', 'open', 'operator', 'private', 'precedencegroup',
  'protocol', 'public', 'rethrows', 'static', 'struct', 'subscript', 'typealias', 'var',
  'break', 'case', 'catch', 'continue', 'default', 'defer', 'do', 'else', 'fallthrough',
  'for', 'guard', 'if', 'in', 'repeat', 'return', 'throw', 'switch', 'where', 'while',
  'any', 'as', 'await', 'false', 'is', 'nil', 'self', 'Self', 'super', 'throws', 'true', 'try'
]);

export const schemaGenerator: SchemaGenerator = new SchemaGenerator();
export const typeGenerator: TypeGenerator = new TypeGenerator();
