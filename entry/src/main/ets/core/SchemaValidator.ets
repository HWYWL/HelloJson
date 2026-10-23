import { JKind, JValue, kindName } from './JValue';

/** 一条 Schema 校验错误 */
export class SchemaError {
  /** 出错位置在文档中的 JSON 路径，如 $.items[3].name */
  path: string = '';
  message: string = '';
  /** 在源文本中的字符偏移，用于定位行号与滚动 */
  offset: number = 0;
  /** 编辑器行号（1 基），由调用方根据 offset 计算 */
  line: number = 0;
}

/** 路径拼接：数组下标用 [i]，合法标识符用 .key，其余用 ["key"] */
function childPath(base: string, key: string): string {
  if (/^[0-9]+$/.test(key)) {
    return base + '[' + key + ']';
  }
  if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key)) {
    return base + '.' + key;
  }
  return base + '["' + key.replace(/"/g, '\\"') + '"]';
}

function typeMatches(value: JValue, t: string): boolean {
  if (t === 'null') {
    return value.kind === JKind.Null;
  }
  if (t === 'boolean') {
    return value.kind === JKind.Bool;
  }
  if (t === 'string') {
    return value.kind === JKind.Str;
  }
  if (t === 'number') {
    return value.kind === JKind.Num;
  }
  if (t === 'integer') {
    return value.kind === JKind.Num && Math.floor(value.numVal) === value.numVal;
  }
  if (t === 'array') {
    return value.kind === JKind.Arr;
  }
  if (t === 'object') {
    return value.kind === JKind.Obj;
  }
  return true;
}

/** 深比较两个 JSON 值（enum / const / uniqueItems 用） */
function deepEqual(a: JValue, b: JValue): boolean {
  if (a.kind !== b.kind) {
    return false;
  }
  if (a.kind === JKind.Null) {
    return true;
  }
  if (a.kind === JKind.Bool) {
    return a.boolVal === b.boolVal;
  }
  if (a.kind === JKind.Num) {
    return a.numVal === b.numVal;
  }
  if (a.kind === JKind.Str) {
    return a.text === b.text;
  }
  if (a.kind === JKind.Arr) {
    if (a.items.length !== b.items.length) {
      return false;
    }
    for (let i = 0; i < a.items.length; i++) {
      if (!deepEqual(a.items[i], b.items[i])) {
        return false;
      }
    }
    return true;
  }
  if (a.keys.length !== b.keys.length) {
    return false;
  }
  for (let i = 0; i < a.keys.length; i++) {
    const other = b.get(a.keys[i]);
    if (other === null || !deepEqual(a.values[i], other)) {
      return false;
    }
  }
  return true;
}

/**
 * JSON Schema（draft-07 子集）校验器。
 *
 * 支持：type、enum、const、properties、required、additionalProperties、
 * items、minItems、maxItems、uniqueItems、minLength、maxLength、pattern、
 * minimum、maximum、exclusiveMinimum、exclusiveMaximum、multipleOf、
 * allOf、anyOf、oneOf、not、本地 $ref（#/definitions、#/$defs）。
 *
 * 不校验 format（需要额外规则集），也不支持远程 $ref。
 */
export class SchemaValidator {
  private static readonly MAX_ERRORS: number = 200;
  private static readonly MAX_DEPTH: number = 120;
  private schemaRoot: JValue | null = null;
  private errors: SchemaError[] = [];

  validate(doc: JValue, schema: JValue): SchemaError[] {
    this.schemaRoot = schema;
    this.errors = [];
    this.walk(doc, schema, '$', 0);
    return this.errors;
  }

  private add(value: JValue, path: string, message: string): void {
    if (this.errors.length >= SchemaValidator.MAX_ERRORS) {
      return;
    }
    const e = new SchemaError();
    e.path = path;
    e.message = message;
    e.offset = value.start;
    this.errors.push(e);
  }

  private full(): boolean {
    return this.errors.length >= SchemaValidator.MAX_ERRORS;
  }

  private resolveRef(ref: string): JValue | null {
    if (ref === '#' || ref.length === 0) {
      return this.schemaRoot;
    }
    if (!ref.startsWith('#/')) {
      return null;
    }
    let cur: JValue | null = this.schemaRoot;
    const parts = ref.substring(2).split('/');
    for (let i = 0; i < parts.length; i++) {
      if (cur === null) {
        return null;
      }
      cur = cur.get(parts[i].replace(/~1/g, '/').replace(/~0/g, '~'));
    }
    return cur;
  }

  private walk(value: JValue, schema: JValue, path: string, depth: number): void {
    if (depth > SchemaValidator.MAX_DEPTH || this.full()) {
      return;
    }
    if (schema.kind !== JKind.Obj) {
      return;
    }

    const refVal = schema.get('$ref');
    if (refVal !== null && refVal.kind === JKind.Str) {
      const target = this.resolveRef(refVal.text);
      if (target === null) {
        this.add(value, path, '无法解析 $ref：' + refVal.text);
      } else {
        this.walk(value, target, path, depth + 1);
      }
      return;
    }

    const typeVal = schema.get('type');
    if (typeVal !== null && !this.checkType(value, typeVal, path)) {
      return;
    }

    const enumVal = schema.get('enum');
    if (enumVal !== null && enumVal.kind === JKind.Arr) {
      let found = false;
      for (let i = 0; i < enumVal.items.length; i++) {
        if (deepEqual(value, enumVal.items[i])) {
          found = true;
          break;
        }
      }
      if (!found) {
        this.add(value, path, '取值必须是 enum 中的枚举值之一');
      }
    }

    const constVal = schema.get('const');
    if (constVal !== null && !deepEqual(value, constVal)) {
      this.add(value, path, '取值必须等于 const 指定的值');
    }

    if (value.kind === JKind.Num) {
      this.checkNumber(value, schema, path);
    } else if (value.kind === JKind.Str) {
      this.checkString(value, schema, path);
    } else if (value.kind === JKind.Arr) {
      this.checkArray(value, schema, path, depth);
    } else if (value.kind === JKind.Obj) {
      this.checkObject(value, schema, path, depth);
    }

    this.checkCombinators(value, schema, path, depth);
  }

  private checkType(value: JValue, typeVal: JValue, path: string): boolean {
    if (typeVal.kind === JKind.Str) {
      if (typeMatches(value, typeVal.text)) {
        return true;
      }
      this.add(value, path, '类型应为 ' + typeVal.text + '，实际为 ' + kindName(value.kind));
      return false;
    }
    if (typeVal.kind === JKind.Arr) {
      const names: string[] = [];
      for (let i = 0; i < typeVal.items.length; i++) {
        const item = typeVal.items[i];
        if (item.kind !== JKind.Str) {
          continue;
        }
        names.push(item.text);
        if (typeMatches(value, item.text)) {
          return true;
        }
      }
      this.add(value, path, '类型应为 ' + names.join(' 或 ') + '，实际为 ' + kindName(value.kind));
      return false;
    }
    return true;
  }

  private checkNumber(value: JValue, schema: JValue, path: string): void {
    const n = value.numVal;
    const min = schema.get('minimum');
    if (min !== null && min.kind === JKind.Num && n < min.numVal) {
      this.add(value, path, '不应小于 ' + min.text);
    }
    const max = schema.get('maximum');
    if (max !== null && max.kind === JKind.Num && n > max.numVal) {
      this.add(value, path, '不应大于 ' + max.text);
    }
    const exMin = schema.get('exclusiveMinimum');
    if (exMin !== null && exMin.kind === JKind.Num && n <= exMin.numVal) {
      this.add(value, path, '应大于 ' + exMin.text);
    }
    const exMax = schema.get('exclusiveMaximum');
    if (exMax !== null && exMax.kind === JKind.Num && n >= exMax.numVal) {
      this.add(value, path, '应小于 ' + exMax.text);
    }
    const mult = schema.get('multipleOf');
    if (mult !== null && mult.kind === JKind.Num && mult.numVal > 0) {
      const q = n / mult.numVal;
      if (Math.abs(q - Math.round(q)) > 1e-9) {
        this.add(value, path, '应为 ' + mult.text + ' 的整数倍');
      }
    }
  }

  private checkString(value: JValue, schema: JValue, path: string): void {
    const len = value.text.length;
    const minLen = schema.get('minLength');
    if (minLen !== null && minLen.kind === JKind.Num && len < minLen.numVal) {
      this.add(value, path, '长度不应小于 ' + minLen.text + '（当前 ' + len.toString() + '）');
    }
    const maxLen = schema.get('maxLength');
    if (maxLen !== null && maxLen.kind === JKind.Num && len > maxLen.numVal) {
      this.add(value, path, '长度不应大于 ' + maxLen.text + '（当前 ' + len.toString() + '）');
    }
    const pattern = schema.get('pattern');
    if (pattern !== null && pattern.kind === JKind.Str) {
      try {
        const re = new RegExp(pattern.text);
        if (!re.test(value.text)) {
          this.add(value, path, '不符合正则 ' + pattern.text);
        }
      } catch (e) {
        // 非法正则视为约束无效，不打断校验
      }
    }
  }

  private checkArray(value: JValue, schema: JValue, path: string, depth: number): void {
    const count = value.items.length;
    const minItems = schema.get('minItems');
    if (minItems !== null && minItems.kind === JKind.Num && count < minItems.numVal) {
      this.add(value, path, '数组元素不应少于 ' + minItems.text + '（当前 ' + count.toString() + '）');
    }
    const maxItems = schema.get('maxItems');
    if (maxItems !== null && maxItems.kind === JKind.Num && count > maxItems.numVal) {
      this.add(value, path, '数组元素不应多于 ' + maxItems.text + '（当前 ' + count.toString() + '）');
    }
    const unique = schema.get('uniqueItems');
    if (unique !== null && unique.kind === JKind.Bool && unique.boolVal && count > 1 && count <= 200) {
      let dup = -1;
      for (let i = 0; i < count && dup < 0; i++) {
        for (let j = i + 1; j < count; j++) {
          if (deepEqual(value.items[i], value.items[j])) {
            dup = j;
            break;
          }
        }
      }
      if (dup >= 0) {
        this.add(value.items[dup], path + '[' + dup.toString() + ']', '数组元素应互不相同');
      }
    }
    const items = schema.get('items');
    if (items === null) {
      return;
    }
    if (items.kind === JKind.Arr) {
      const n = Math.min(items.items.length, count);
      for (let i = 0; i < n; i++) {
        this.walk(value.items[i], items.items[i], path + '[' + i.toString() + ']', depth + 1);
      }
      const extra = schema.get('additionalItems');
      if (extra !== null && extra.kind === JKind.Bool && !extra.boolVal && count > items.items.length) {
        this.add(value, path, '数组元素不应多于 schema 声明的 ' + items.items.length.toString() + ' 个');
      }
    } else if (items.kind === JKind.Obj) {
      for (let i = 0; i < count; i++) {
        this.walk(value.items[i], items, path + '[' + i.toString() + ']', depth + 1);
      }
    }
  }

  private checkObject(value: JValue, schema: JValue, path: string, depth: number): void {
    const required = schema.get('required');
    if (required !== null && required.kind === JKind.Arr) {
      for (let i = 0; i < required.items.length; i++) {
        const keyVal = required.items[i];
        if (keyVal.kind !== JKind.Str) {
          continue;
        }
        if (value.get(keyVal.text) === null) {
          this.add(value, path, '缺少必需字段 "' + keyVal.text + '"');
        }
      }
    }

    const props = schema.get('properties');
    const extra = schema.get('additionalProperties');
    for (let i = 0; i < value.keys.length; i++) {
      const key = value.keys[i];
      const child = value.values[i];
      const cp = childPath(path, key);
      const sub = props === null ? null : props.get(key);
      if (sub !== null) {
        this.walk(child, sub, cp, depth + 1);
      } else if (extra !== null) {
        if (extra.kind === JKind.Bool) {
          if (!extra.boolVal) {
            this.add(child, cp, '不允许出现额外字段 "' + key + '"');
          }
        } else if (extra.kind === JKind.Obj) {
          this.walk(child, extra, cp, depth + 1);
        }
      }
    }

    const minProps = schema.get('minProperties');
    if (minProps !== null && minProps.kind === JKind.Num && value.keys.length < minProps.numVal) {
      this.add(value, path, '字段数不应少于 ' + minProps.text);
    }
    const maxProps = schema.get('maxProperties');
    if (maxProps !== null && maxProps.kind === JKind.Num && value.keys.length > maxProps.numVal) {
      this.add(value, path, '字段数不应多于 ' + maxProps.text);
    }
  }

  /** 用独立实例跑一个分支，只关心是否通过 */
  private branchErrors(value: JValue, schema: JValue, path: string, depth: number): number {
    const sub = new SchemaValidator();
    sub.schemaRoot = this.schemaRoot;
    sub.errors = [];
    sub.walk(value, schema, path, depth + 1);
    return sub.errors.length;
  }

  private checkCombinators(value: JValue, schema: JValue, path: string, depth: number): void {
    const allOf = schema.get('allOf');
    if (allOf !== null && allOf.kind === JKind.Arr) {
      for (let i = 0; i < allOf.items.length; i++) {
        this.walk(value, allOf.items[i], path, depth + 1);
      }
    }

    const anyOf = schema.get('anyOf');
    if (anyOf !== null && anyOf.kind === JKind.Arr && anyOf.items.length > 0) {
      let passed = false;
      for (let i = 0; i < anyOf.items.length; i++) {
        if (this.branchErrors(value, anyOf.items[i], path, depth) === 0) {
          passed = true;
          break;
        }
      }
      if (!passed) {
        this.add(value, path, '不满足 anyOf 中任一分支');
      }
    }

    const oneOf = schema.get('oneOf');
    if (oneOf !== null && oneOf.kind === JKind.Arr && oneOf.items.length > 0) {
      let hits = 0;
      for (let i = 0; i < oneOf.items.length; i++) {
        if (this.branchErrors(value, oneOf.items[i], path, depth) === 0) {
          hits++;
        }
      }
      if (hits !== 1) {
        this.add(value, path, '应恰好满足 oneOf 中的一个分支（当前命中 ' + hits.toString() + ' 个）');
      }
    }

    const notVal = schema.get('not');
    if (notVal !== null && notVal.kind === JKind.Obj) {
      if (this.branchErrors(value, notVal, path, depth) === 0) {
        this.add(value, path, '不应满足 not 中声明的约束');
      }
    }
  }
}
