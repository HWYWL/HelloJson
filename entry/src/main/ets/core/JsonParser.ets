import { JKind, JValue } from './JValue';

export class ParseErrorInfo {
  message: string = '';
  offset: number = 0;
  line: number = 1;
  column: number = 1;
}

export class ParseResult {
  ok: boolean = false;
  root: JValue | null = null;
  error: ParseErrorInfo | null = null;
  /** 文本行数，用于编辑器行号展示 */
  lineCount: number = 1;
}

/**
 * JSON / JSONC 解析器：支持注释与尾随逗号，记录节点偏移量用于源码定位。
 */
export class JsonParser {
  private src: string = '';
  private pos: number = 0;
  private len: number = 0;
  private failed: boolean = false;
  private errMsg: string = '';
  private errOffset: number = -1;

  parse(src: string): ParseResult {
    this.src = src;
    this.pos = 0;
    this.len = src.length;
    this.failed = false;
    this.errMsg = '';
    this.errOffset = -1;

    const result = new ParseResult();
    result.lineCount = this.countLines(src);
    if (src.trim().length === 0) {
      return result;
    }

    this.skipWs();
    const root = this.parseValue();
    if (root !== null) {
      this.skipWs();
    }
    if (!this.failed && this.pos < this.len && root !== null) {
      this.fail('解析结束后仍有剩余内容');
    }
    if (this.failed || root === null) {
      const err = new ParseErrorInfo();
      err.message = this.errMsg.length > 0 ? this.errMsg : '无效的 JSON';
      err.offset = this.errOffset < 0 ? this.pos : this.errOffset;
      const lc = this.offsetToLineCol(err.offset);
      err.line = lc[0];
      err.column = lc[1];
      result.error = err;
      return result;
    }
    result.ok = true;
    result.root = root;
    return result;
  }

  private countLines(text: string): number {
    let n = 1;
    for (let i = 0; i < text.length; i++) {
      if (text.charCodeAt(i) === 10) {
        n++;
      }
    }
    return n;
  }

  private offsetToLineCol(offset: number): number[] {
    let line = 1;
    let col = 1;
    const limit = Math.min(offset, this.len);
    for (let i = 0; i < limit; i++) {
      if (this.src.charCodeAt(i) === 10) {
        line++;
        col = 1;
      } else {
        col++;
      }
    }
    return [line, col];
  }

  private fail(msg: string): void {
    if (!this.failed) {
      this.failed = true;
      this.errMsg = msg;
      this.errOffset = this.pos;
    }
  }

  private skipWs(): void {
    while (this.pos < this.len) {
      const c = this.src.charCodeAt(this.pos);
      if (c === 32 || c === 9 || c === 10 || c === 13) {
        this.pos++;
        continue;
      }
      if (c === 47) {
        if (this.pos + 1 < this.len && this.src.charCodeAt(this.pos + 1) === 47) {
          this.pos += 2;
          while (this.pos < this.len && this.src.charCodeAt(this.pos) !== 10) {
            this.pos++;
          }
          continue;
        }
        if (this.pos + 1 < this.len && this.src.charCodeAt(this.pos + 1) === 42) {
          this.pos += 2;
          while (this.pos + 1 < this.len &&
            !(this.src.charCodeAt(this.pos) === 42 && this.src.charCodeAt(this.pos + 1) === 47)) {
            this.pos++;
          }
          this.pos = Math.min(this.len, this.pos + 2);
          continue;
        }
      }
      break;
    }
  }

  private parseValue(): JValue | null {
    this.skipWs();
    if (this.pos >= this.len) {
      this.fail('意外的文本结束');
      return null;
    }
    const c = this.src.charAt(this.pos);
    if (c === '{') {
      return this.parseObject();
    }
    if (c === '[') {
      return this.parseArray();
    }
    if (c === '"') {
      const node = new JValue();
      node.kind = JKind.Str;
      node.start = this.pos;
      const text = this.parseString();
      if (text === null) {
        return null;
      }
      node.text = text;
      node.raw = this.src.substring(node.start, this.pos);
      node.end = this.pos;
      return node;
    }
    if (c === 't' || c === 'f' || c === 'n') {
      return this.parseLiteral();
    }
    const code = this.src.charCodeAt(this.pos);
    if (c === '-' || (code >= 48 && code <= 57)) {
      return this.parseNumber();
    }
    this.fail(`意外的字符 '${c}'`);
    return null;
  }

  private parseLiteral(): JValue | null {
    const start = this.pos;
    if (this.src.startsWith('true', this.pos)) {
      this.pos += 4;
      const v = JValue.ofBool(true);
      v.start = start;
      v.end = this.pos;
      return v;
    }
    if (this.src.startsWith('false', this.pos)) {
      this.pos += 5;
      const v = JValue.ofBool(false);
      v.start = start;
      v.end = this.pos;
      return v;
    }
    if (this.src.startsWith('null', this.pos)) {
      this.pos += 4;
      const v = JValue.ofNull();
      v.start = start;
      v.end = this.pos;
      return v;
    }
    this.fail('无法识别的字面量');
    return null;
  }

  private parseNumber(): JValue | null {
    const start = this.pos;
    if (this.src.charAt(this.pos) === '-') {
      this.pos++;
    }
    while (this.pos < this.len) {
      const c = this.src.charCodeAt(this.pos);
      if ((c >= 48 && c <= 57) || c === 46 || c === 101 || c === 69 || c === 43 || c === 45) {
        this.pos++;
      } else {
        break;
      }
    }
    const raw = this.src.substring(start, this.pos);
    const value = Number(raw);
    if (Number.isNaN(value)) {
      this.pos = start;
      this.fail(`无效的数字 '${raw}'`);
      return null;
    }
    const node = JValue.ofNum(value, raw);
    node.start = start;
    node.end = this.pos;
    return node;
  }

  private parseString(): string | null {
    if (this.src.charAt(this.pos) !== '"') {
      this.fail('期望字符串起始引号');
      return null;
    }
    this.pos++;
    let out = '';
    while (this.pos < this.len) {
      const ch = this.src.charAt(this.pos);
      if (ch === '"') {
        this.pos++;
        return out;
      }
      if (ch === '\\') {
        this.pos++;
        if (this.pos >= this.len) {
          break;
        }
        const esc = this.src.charAt(this.pos);
        if (esc === '"') {
          out += '"';
        } else if (esc === '\\') {
          out += '\\';
        } else if (esc === '/') {
          out += '/';
        } else if (esc === 'b') {
          out += '\b';
        } else if (esc === 'f') {
          out += '\f';
        } else if (esc === 'n') {
          out += '\n';
        } else if (esc === 'r') {
          out += '\r';
        } else if (esc === 't') {
          out += '\t';
        } else if (esc === 'u') {
          if (this.pos + 4 >= this.len) {
            this.fail('非法的 \\u 转义');
            return null;
          }
          const hex = this.src.substring(this.pos + 1, this.pos + 5);
          const codePoint = parseInt(hex, 16);
          if (Number.isNaN(codePoint)) {
            this.fail('非法的 \\u 转义');
            return null;
          }
          out += String.fromCharCode(codePoint);
          this.pos += 4;
        } else {
          this.fail(`非法的转义字符 '\\${esc}'`);
          return null;
        }
        this.pos++;
        continue;
      }
      const code = this.src.charCodeAt(this.pos);
      if (code < 0x20) {
        this.fail('字符串中包含未转义的控制字符');
        return null;
      }
      out += ch;
      this.pos++;
    }
    this.fail('字符串未闭合');
    return null;
  }

  private parseObject(): JValue | null {
    const node = JValue.ofObj();
    node.start = this.pos;
    this.pos++;
    this.skipWs();
    if (this.src.charAt(this.pos) === '}') {
      this.pos++;
      node.end = this.pos;
      return node;
    }
    while (this.pos < this.len) {
      this.skipWs();
      if (this.src.charAt(this.pos) === '}') {
        this.pos++;
        node.end = this.pos;
        return node;
      }
      if (this.src.charAt(this.pos) !== '"') {
        this.fail('对象的键必须是字符串');
        return null;
      }
      const keyStart = this.pos;
      const key = this.parseString();
      if (key === null) {
        return null;
      }
      this.skipWs();
      if (this.src.charAt(this.pos) !== ':') {
        this.fail('缺少冒号 ":"');
        return null;
      }
      this.pos++;
      const value = this.parseValue();
      if (value === null) {
        return null;
      }
      node.keys.push(key);
      node.values.push(value);
      void keyStart;
      this.skipWs();
      const ch = this.src.charAt(this.pos);
      if (ch === ',') {
        this.pos++;
        continue;
      }
      if (ch === '}') {
        this.pos++;
        node.end = this.pos;
        return node;
      }
      this.fail('对象缺少 "," 或 "}"');
      return null;
    }
    this.fail('对象未闭合');
    return null;
  }

  private parseArray(): JValue | null {
    const node = JValue.ofArr();
    node.start = this.pos;
    this.pos++;
    this.skipWs();
    if (this.src.charAt(this.pos) === ']') {
      this.pos++;
      node.end = this.pos;
      return node;
    }
    while (this.pos < this.len) {
      this.skipWs();
      if (this.src.charAt(this.pos) === ']') {
        this.pos++;
        node.end = this.pos;
        return node;
      }
      const value = this.parseValue();
      if (value === null) {
        return null;
      }
      node.items.push(value);
      this.skipWs();
      const ch = this.src.charAt(this.pos);
      if (ch === ',') {
        this.pos++;
        continue;
      }
      if (ch === ']') {
        this.pos++;
        node.end = this.pos;
        return node;
      }
      this.fail('数组缺少 "," 或 "]"');
      return null;
    }
    this.fail('数组未闭合');
    return null;
  }
}

export const jsonParser: JsonParser = new JsonParser();
