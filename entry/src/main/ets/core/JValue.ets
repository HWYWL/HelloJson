/**
 * JSON 值模型：解析器、图构建、查询、转换、序列化共用的统一数据结构。
 * 避免 ArkTS 中对普通对象做动态属性访问的限制。
 */
export enum JKind {
  Null = 0,
  Bool = 1,
  Num = 2,
  Str = 3,
  Arr = 4,
  Obj = 5
}

export class JValue {
  kind: JKind = JKind.Null;
  boolVal: boolean = false;
  numVal: number = 0;
  text: string = '';
  raw: string = '';
  items: JValue[] = [];
  keys: string[] = [];
  values: JValue[] = [];
  start: number = 0;
  end: number = 0;

  static ofNull(): JValue {
    const v = new JValue();
    v.kind = JKind.Null;
    v.text = 'null';
    v.raw = 'null';
    return v;
  }

  static ofBool(b: boolean): JValue {
    const v = new JValue();
    v.kind = JKind.Bool;
    v.boolVal = b;
    v.text = b ? 'true' : 'false';
    v.raw = v.text;
    return v;
  }

  static ofNum(n: number, raw?: string): JValue {
    const v = new JValue();
    v.kind = JKind.Num;
    v.numVal = n;
    v.text = raw === undefined ? String(n) : raw;
    v.raw = v.text;
    return v;
  }

  static ofStr(s: string): JValue {
    const v = new JValue();
    v.kind = JKind.Str;
    v.text = s;
    v.raw = s;
    return v;
  }

  static ofArr(): JValue {
    const v = new JValue();
    v.kind = JKind.Arr;
    return v;
  }

  static ofObj(): JValue {
    const v = new JValue();
    v.kind = JKind.Obj;
    return v;
  }

  isContainer(): boolean {
    return this.kind === JKind.Arr || this.kind === JKind.Obj;
  }

  childCount(): number {
    if (this.kind === JKind.Arr) {
      return this.items.length;
    }
    if (this.kind === JKind.Obj) {
      return this.keys.length;
    }
    return 0;
  }

  /** 对象按键取值，找不到返回 null */
  get(key: string): JValue | null {
    if (this.kind !== JKind.Obj) {
      return null;
    }
    for (let i = 0; i < this.keys.length; i++) {
      if (this.keys[i] === key) {
        return this.values[i];
      }
    }
    return null;
  }

  /** 数组按下标取值，越界返回 null */
  at(index: number): JValue | null {
    if (this.kind !== JKind.Arr || index < 0 || index >= this.items.length) {
      return null;
    }
    return this.items[index];
  }

  set(key: string, value: JValue): void {
    for (let i = 0; i < this.keys.length; i++) {
      if (this.keys[i] === key) {
        this.values[i] = value;
        return;
      }
    }
    this.keys.push(key);
    this.values.push(value);
  }

  remove(key: string): void {
    for (let i = 0; i < this.keys.length; i++) {
      if (this.keys[i] === key) {
        this.keys.splice(i, 1);
        this.values.splice(i, 1);
        return;
      }
    }
  }

  clone(): JValue {
    const v = new JValue();
    v.kind = this.kind;
    v.boolVal = this.boolVal;
    v.numVal = this.numVal;
    v.text = this.text;
    v.raw = this.raw;
    v.start = this.start;
    v.end = this.end;
    for (let i = 0; i < this.items.length; i++) {
      v.items.push(this.items[i].clone());
    }
    for (let i = 0; i < this.keys.length; i++) {
      v.keys.push(this.keys[i]);
      v.values.push(this.values[i].clone());
    }
    return v;
  }
}

export function kindName(kind: JKind): string {
  if (kind === JKind.Obj) {
    return 'object';
  }
  if (kind === JKind.Arr) {
    return 'array';
  }
  if (kind === JKind.Str) {
    return 'string';
  }
  if (kind === JKind.Num) {
    return 'number';
  }
  if (kind === JKind.Bool) {
    return 'boolean';
  }
  return 'null';
}

/** 估算文本宽度：ASCII 0.62em，CJK 1em */
export function estimateTextWidth(text: string, fontSize: number): number {
  let w = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code > 0x2e80) {
      w += fontSize;
    } else if (code === 32) {
      w += fontSize * 0.34;
    } else {
      w += fontSize * 0.62;
    }
  }
  return w;
}

/** 截断过长文本，避免单行节点过宽 */
export function truncateText(text: string, max: number): string {
  if (text.length <= max) {
    return text;
  }
  return text.substring(0, max) + '…';
}
