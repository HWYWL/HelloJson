import { JKind, JValue } from './JValue';
import { jsonParser } from './JsonParser';

/** 生成结果：失败时 message 说明原因 */
export class MockResult {
  ok: boolean = false;
  message: string = '';
  value: JValue | null = null;
}

/**
 * 按 JSON Schema（draft-07 子集）生成示例数据。
 * 支持 type/properties/required、items/prefixItems、enum/const/default/example、
 * minimum/maximum、minLength/maxLength、minItems/maxItems、format、$ref、oneOf/anyOf/allOf。
 */
export class MockGenerator {
  private schemaRoot: JValue | null = null;
  private maxDepth: number = 10;
  private refDepth: number = 0;

  generate(schemaText: string): MockResult {
    const res = new MockResult();
    const parsed = jsonParser.parse(schemaText);
    if (!parsed.ok || parsed.root === null) {
      res.message = parsed.error === null ? 'schema 解析失败' : parsed.error.message;
      return res;
    }
    this.schemaRoot = parsed.root;
    this.refDepth = 0;
    res.value = this.mock(parsed.root, 0);
    res.ok = true;
    return res;
  }

  private mock(schema: JValue, depth: number): JValue {
    if (schema.kind !== JKind.Obj || depth > this.maxDepth) {
      return JValue.ofNull();
    }
    const ref = schema.get('$ref');
    if (ref !== null && ref.kind === JKind.Str) {
      const target = this.resolveRef(ref.text);
      if (target !== null && this.refDepth < 12) {
        this.refDepth++;
        const v = this.mock(target, depth + 1);
        this.refDepth--;
        return v;
      }
    }
    const example = schema.get('example');
    if (example !== null) {
      return example.clone();
    }
    const examples = schema.get('examples');
    if (examples !== null && examples.kind === JKind.Arr && examples.items.length > 0) {
      return examples.items[0].clone();
    }
    const def = schema.get('default');
    if (def !== null) {
      return def.clone();
    }
    const konst = schema.get('const');
    if (konst !== null) {
      return konst.clone();
    }
    const en = schema.get('enum');
    if (en !== null && en.kind === JKind.Arr && en.items.length > 0) {
      return en.items[0].clone();
    }
    const combo = this.comboSchema(schema);
    if (combo !== null) {
      return this.mock(combo, depth + 1);
    }

    const type = this.typeOf(schema);
    if (type === 'object') {
      return this.mockObject(schema, depth);
    }
    if (type === 'array') {
      return this.mockArray(schema, depth);
    }
    if (type === 'string') {
      return JValue.ofStr(this.mockString(schema));
    }
    if (type === 'integer') {
      return JValue.ofNum(this.mockNumber(schema, true));
    }
    if (type === 'number') {
      return JValue.ofNum(this.mockNumber(schema, false));
    }
    if (type === 'boolean') {
      return JValue.ofBool(true);
    }
    if (type === 'null') {
      return JValue.ofNull();
    }
    const props = schema.get('properties');
    if (props !== null && props.kind === JKind.Obj) {
      return this.mockObject(schema, depth);
    }
    const items = schema.get('items');
    if (items !== null) {
      return this.mockArray(schema, depth);
    }
    return JValue.ofNull();
  }

  private typeOf(schema: JValue): string {
    const t = schema.get('type');
    if (t === null) {
      return '';
    }
    if (t.kind === JKind.Str) {
      return t.text;
    }
    if (t.kind === JKind.Arr) {
      for (let i = 0; i < t.items.length; i++) {
        if (t.items[i].kind === JKind.Str && t.items[i].text !== 'null') {
          return t.items[i].text;
        }
      }
    }
    return '';
  }

  /** oneOf / anyOf 取第一支；allOf 合并 properties 与 required */
  private comboSchema(schema: JValue): JValue | null {
    const all = schema.get('allOf');
    if (all !== null && all.kind === JKind.Arr && all.items.length > 0) {
      const merged = JValue.ofObj();
      for (let i = 0; i < schema.keys.length; i++) {
        if (schema.keys[i] !== 'allOf') {
          merged.set(schema.keys[i], schema.values[i]);
        }
      }
      for (let j = 0; j < all.items.length; j++) {
        let sub = all.items[j];
        const subRef = sub.get('$ref');
        if (subRef !== null && subRef.kind === JKind.Str) {
          const target = this.resolveRef(subRef.text);
          if (target !== null) {
            sub = target;
          }
        }
        this.mergeInto(merged, sub);
      }
      return merged;
    }
    const one = schema.get('oneOf');
    if (one !== null && one.kind === JKind.Arr && one.items.length > 0) {
      return one.items[0];
    }
    const any = schema.get('anyOf');
    if (any !== null && any.kind === JKind.Arr && any.items.length > 0) {
      return any.items[0];
    }
    return null;
  }

  private mergeInto(target: JValue, sub: JValue): void {
    if (sub.kind !== JKind.Obj) {
      return;
    }
    for (let k = 0; k < sub.keys.length; k++) {
      const key = sub.keys[k];
      const value = sub.values[k];
      if (key === 'properties' && value.kind === JKind.Obj) {
        let props = target.get('properties');
        if (props === null || props.kind !== JKind.Obj) {
          props = JValue.ofObj();
          target.set('properties', props);
        }
        for (let p = 0; p < value.keys.length; p++) {
          props.set(value.keys[p], value.values[p]);
        }
      } else if (key === 'required' && value.kind === JKind.Arr) {
        let req = target.get('required');
        if (req === null || req.kind !== JKind.Arr) {
          req = JValue.ofArr();
          target.set('required', req);
        }
        for (let r = 0; r < value.items.length; r++) {
          req.items.push(value.items[r]);
        }
      } else if (key !== '$ref') {
        target.set(key, value);
      }
    }
  }

  private resolveRef(ref: string): JValue | null {
    if (!ref.startsWith('#/')) {
      return null;
    }
    if (this.schemaRoot === null) {
      return null;
    }
    const parts = ref.substring(2).split('/');
    let cur: JValue = this.schemaRoot;
    for (let i = 0; i < parts.length; i++) {
      if (cur.kind !== JKind.Obj) {
        return null;
      }
      const next = cur.get(parts[i].replace(new RegExp('~1', 'g'), '/').replace(new RegExp('~0', 'g'), '~'));
      if (next === null) {
        return null;
      }
      cur = next;
    }
    return cur;
  }

  private mockObject(schema: JValue, depth: number): JValue {
    const out = JValue.ofObj();
    const props = schema.get('properties');
    if (props !== null && props.kind === JKind.Obj) {
      for (let i = 0; i < props.keys.length; i++) {
        out.set(props.keys[i], this.mock(props.values[i], depth + 1));
      }
    }
    if (out.keys.length === 0) {
      const add = schema.get('additionalProperties');
      if (add !== null && add.kind === JKind.Obj) {
        out.set('additionalProp1', this.mock(add, depth + 1));
      }
    }
    return out;
  }

  private mockArray(schema: JValue, depth: number): JValue {
    const arr = JValue.ofArr();
    let count = 2;
    const min = schema.get('minItems');
    const max = schema.get('maxItems');
    if (min !== null && min.kind === JKind.Num) {
      count = Math.max(count, Math.ceil(min.numVal));
    }
    if (max !== null && max.kind === JKind.Num) {
      count = Math.min(count, Math.floor(max.numVal));
    }
    if (count > 5) {
      count = 5;
    }
    if (count < 0) {
      count = 0;
    }
    const prefix = schema.get('prefixItems');
    const items = schema.get('items');
    for (let i = 0; i < count; i++) {
      if (prefix !== null && prefix.kind === JKind.Arr && i < prefix.items.length) {
        arr.items.push(this.mock(prefix.items[i], depth + 1));
      } else if (items !== null && items.kind === JKind.Obj) {
        arr.items.push(this.mock(items, depth + 1));
      } else if (items !== null && items.kind === JKind.Arr && items.items.length > 0) {
        arr.items.push(this.mock(items.items[0], depth + 1));
      } else {
        arr.items.push(JValue.ofStr('string'));
      }
    }
    return arr;
  }

  private mockString(schema: JValue): string {
    const format = schema.get('format');
    if (format !== null && format.kind === JKind.Str) {
      const f = format.text;
      if (f === 'date') {
        return '2026-01-01';
      }
      if (f === 'date-time') {
        return '2026-01-01T00:00:00Z';
      }
      if (f === 'time') {
        return '00:00:00';
      }
      if (f === 'email') {
        return 'user@example.com';
      }
      if (f === 'uri' || f === 'url') {
        return 'https://example.com';
      }
      if (f === 'uuid') {
        return '00000000-0000-4000-8000-000000000000';
      }
      if (f === 'hostname') {
        return 'example.com';
      }
      if (f === 'ipv4') {
        return '192.0.2.1';
      }
      if (f === 'ipv6') {
        return '2001:db8::1';
      }
    }
    let s = 'string';
    const min = schema.get('minLength');
    if (min !== null && min.kind === JKind.Num) {
      while (s.length < min.numVal) {
        s += 'x';
      }
    }
    const max = schema.get('maxLength');
    if (max !== null && max.kind === JKind.Num && s.length > max.numVal) {
      s = s.substring(0, Math.max(0, Math.floor(max.numVal)));
    }
    return s;
  }

  private mockNumber(schema: JValue, integer: boolean): number {
    const min = schema.get('minimum');
    const exMin = schema.get('exclusiveMinimum');
    const max = schema.get('maximum');
    const exMax = schema.get('exclusiveMaximum');
    let value = integer ? 1 : 1.5;
    let hasBound = false;
    if (min !== null && min.kind === JKind.Num) {
      value = min.numVal;
      hasBound = true;
    }
    if (exMin !== null && exMin.kind === JKind.Num) {
      value = exMin.numVal + (integer ? 1 : 0.1);
      hasBound = true;
    }
    let upper = 0;
    let hasUpper = false;
    if (max !== null && max.kind === JKind.Num) {
      upper = max.numVal;
      hasUpper = true;
    }
    if (exMax !== null && exMax.kind === JKind.Num) {
      upper = exMax.numVal - (integer ? 1 : 0.1);
      hasUpper = true;
    }
    if (hasUpper && value > upper) {
      value = upper;
    }
    if (!hasBound && !hasUpper) {
      value = integer ? 1 : 1.5;
    }
    if (integer) {
      return Math.round(value);
    }
    return value;
  }
}

export const mockGenerator: MockGenerator = new MockGenerator();
