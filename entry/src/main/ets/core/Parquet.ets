import { JKind, JValue } from './JValue';

/**
 * Parquet → JSON（行数组）最简读取器。
 *
 * 支持范围（够用优先，不做全量实现）：
 * - 扁平表：根 group 下全部是叶子列，不支持嵌套 group / repeated
 * - 压缩：UNCOMPRESSED、SNAPPY（自研解压），其他 codec 明确报错
 * - 编码：PLAIN、PLAIN_DICTIONARY / RLE_DICTIONARY，页格式 v1 / v2
 * - 类型：BOOLEAN / INT32 / INT64 / FLOAT / DOUBLE / BYTE_ARRAY(UTF8) / FIXED_LEN_BYTE_ARRAY
 * - 可选列（definition level 0/1）与 null
 */

export class ParquetResult {
  ok: boolean = false;
  message: string = '';
  rows: JValue[] = [];
  columns: string[] = [];
  rowCount: number = 0;
  totalRows: number = 0;
  /** 超过行数上限被截断 */
  truncated: boolean = false;
}

class SchemaField {
  name: string = '';
  physType: number = -1;
  typeLength: number = 0;
  /** 0 REQUIRED / 1 OPTIONAL / 2 REPEATED */
  repetition: number = 0;
  numChildren: number = 0;
  convertedType: number = -1;
  /** DECIMAL 小数位数 */
  scale: number = 0;
  precision: number = 0;
}

class ColChunkInfo {
  name: string = '';
  path: string = '';
  physType: number = -1;
  codec: number = 0;
  numValues: number = 0;
  dataPageOffset: number = 0;
  dictPageOffset: number = -1;
  totalCompressedSize: number = 0;
}

class RowGroupInfo {
  numRows: number = 0;
  columns: ColChunkInfo[] = [];
}

class FileMeta {
  numRows: number = 0;
  schema: SchemaField[] = [];
  rowGroups: RowGroupInfo[] = [];
}

class ListHeader {
  size: number = 0;
  elemType: number = 0;
}

class RleResult {
  values: number[] = [];
  consumed: number = 0;
}

const PHYS_BOOLEAN: number = 0;
const PHYS_INT32: number = 1;
const PHYS_INT64: number = 2;
const PHYS_INT96: number = 3;
const PHYS_FLOAT: number = 4;
const PHYS_DOUBLE: number = 5;
const PHYS_BYTE_ARRAY: number = 6;
const PHYS_FLBA: number = 7;

const CODEC_UNCOMPRESSED: number = 0;
const CODEC_SNAPPY: number = 1;

const ENC_PLAIN: number = 0;
const ENC_PLAIN_DICTIONARY: number = 2;
const ENC_RLE: number = 3;
const ENC_RLE_DICTIONARY: number = 8;

const PAGE_DATA: number = 0;
const PAGE_DICT: number = 2;
const PAGE_DATA_V2: number = 3;

/** 整表导入行数上限：超过时截断并提示，避免一次性构建超大 JSON */
const MAX_ROWS: number = 200000;

/** UTF-8 解码（不依赖系统 TextDecoder，保证 core 层可单测） */
function utf8Decode(bytes: Uint8Array, start: number, len: number): string {
  let out = '';
  let i = start;
  const end = start + len;
  while (i < end) {
    const b0 = bytes[i];
    i++;
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
    } else if (b0 >= 0xc2 && b0 < 0xe0 && i < end) {
      const b1 = bytes[i];
      i++;
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (b1 & 0x3f));
    } else if (b0 >= 0xe0 && b0 < 0xf0 && i + 1 < end) {
      const b1 = bytes[i];
      const b2 = bytes[i + 1];
      i += 2;
      out += String.fromCharCode(((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f));
    } else if (b0 >= 0xf0 && i + 2 < end) {
      const b1 = bytes[i];
      const b2 = bytes[i + 1];
      const b3 = bytes[i + 2];
      i += 3;
      let cp = ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
      cp -= 0x10000;
      out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
    } else {
      out += '\ufffd';
    }
  }
  return out;
}

function readUInt32LE(bytes: Uint8Array, pos: number): number {
  return bytes[pos] + bytes[pos + 1] * 256 + bytes[pos + 2] * 65536 + bytes[pos + 3] * 16777216;
}

function readInt32LE(bytes: Uint8Array, pos: number): number {
  const v = readUInt32LE(bytes, pos);
  return v >= 2147483648 ? v - 4294967296 : v;
}

function readInt64LE(bytes: Uint8Array, pos: number): number {
  const lo = readUInt32LE(bytes, pos);
  const hi = readUInt32LE(bytes, pos + 4);
  return hi * 4294967296 + lo;
}

function readFloatLE(bytes: Uint8Array, pos: number): number {
  const view = new DataView(bytes.buffer, bytes.byteOffset + pos, 4);
  return view.getFloat32(0, true);
}

function readDoubleLE(bytes: Uint8Array, pos: number): number {
  const view = new DataView(bytes.buffer, bytes.byteOffset + pos, 8);
  return view.getFloat64(0, true);
}

/** 无 BigInt 的 64 位无符号十进制输出：hi/lo 均为无符号 32 位 */
function u64ToDecimal(hi: number, lo: number): string {
  const parts: number[] = [0];
  const mul65536 = (): void => {
    let carry = 0;
    for (let i = 0; i < parts.length; i++) {
      const v = parts[i] * 65536 + carry;
      parts[i] = v % 10000000;
      carry = Math.floor(v / 10000000);
    }
    while (carry > 0) {
      parts.push(carry % 10000000);
      carry = Math.floor(carry / 10000000);
    }
  };
  const addSmall = (v: number): void => {
    let carry = v;
    let i = 0;
    while (carry > 0) {
      if (i >= parts.length) {
        parts.push(0);
      }
      const cur = parts[i] + carry;
      parts[i] = cur % 10000000;
      carry = Math.floor(cur / 10000000);
      i++;
    }
  };
  mul65536();
  mul65536();
  addSmall(hi);
  mul65536();
  mul65536();
  addSmall(lo);
  let out = parts[parts.length - 1].toString();
  for (let i = parts.length - 2; i >= 0; i--) {
    let seg = parts[i].toString();
    while (seg.length < 7) {
      seg = '0' + seg;
    }
    out += seg;
  }
  return out;
}

/** INT64 -> JValue：超过 2^53 时用 raw 十进制文本，序列化时不丢精度 */
function int64Value(bytes: Uint8Array, pos: number): JValue {
  const lo = readUInt32LE(bytes, pos);
  const hiRaw = readUInt32LE(bytes, pos + 4);
  if (hiRaw < 0x200000) {
    return JValue.ofNum(hiRaw * 4294967296 + lo);
  }
  if (hiRaw >= 0x80000000) {
    // 负数：求补码绝对值
    const negLo = (~lo + 1) >>> 0;
    const carry = negLo === 0 ? 1 : 0;
    const negHi = (~hiRaw + carry) >>> 0;
    return JValue.ofNum(-(negHi * 4294967296 + negLo), '-' + u64ToDecimal(negHi, negLo));
  }
  return JValue.ofNum(hiRaw * 4294967296 + lo, u64ToDecimal(hiRaw, lo));
}

/** 大端有符号整数 -> 十进制字符串（DECIMAL 的 FLBA 存储） */
function bigEndianToDecimal(data: Uint8Array, start: number, len: number): string {
  const negative = len > 0 && (data[start] & 0x80) !== 0;
  const bytes: number[] = [];
  for (let i = 0; i < len; i++) {
    bytes.push(data[start + i]);
  }
  if (negative) {
    let carry = 1;
    for (let i = len - 1; i >= 0; i--) {
      const v = (255 - bytes[i]) + carry;
      bytes[i] = v & 0xff;
      carry = v >> 8;
    }
  }
  const parts: number[] = [0];
  for (let i = 0; i < len; i++) {
    let carry = bytes[i];
    for (let j = 0; j < parts.length; j++) {
      const v = parts[j] * 256 + carry;
      parts[j] = v % 10000000;
      carry = Math.floor(v / 10000000);
    }
    while (carry > 0) {
      parts.push(carry % 10000000);
      carry = Math.floor(carry / 10000000);
    }
  }
  let out = parts[parts.length - 1].toString();
  for (let i = parts.length - 2; i >= 0; i--) {
    let seg = parts[i].toString();
    while (seg.length < 7) {
      seg = '0' + seg;
    }
    out += seg;
  }
  return negative ? '-' + out : out;
}

function applyDecimalScale(digits: string, scale: number): string {
  if (scale <= 0) {
    return digits;
  }
  const negative = digits.startsWith('-');
  let body = negative ? digits.substring(1) : digits;
  while (body.length <= scale) {
    body = '0' + body;
  }
  const cut = body.length - scale;
  const out = body.substring(0, cut) + '.' + body.substring(cut);
  return negative ? '-' + out : out;
}

function decimalValue(digits: string): JValue {
  return JValue.ofNum(Number(digits), digits);
}

function formatDate(days: number): string {
  const d = new Date(days * 86400000);
  return d.toISOString().substring(0, 10);
}

function formatTimestampMs(ms: number): string {
  const d = new Date(ms);
  return d.toISOString();
}

/** Thrift Compact Protocol 游标 */
class ThriftCursor {
  bytes: Uint8Array;
  pos: number = 0;

  constructor(bytes: Uint8Array, pos: number) {
    this.bytes = bytes;
    this.pos = pos;
  }

  byte(): number {
    const v = this.bytes[this.pos];
    this.pos++;
    return v;
  }

  varint(): number {
    let result = 0;
    let shift = 0;
    while (true) {
      const b = this.byte();
      result += (b & 0x7f) * Math.pow(2, shift);
      if ((b & 0x80) === 0) {
        break;
      }
      shift += 7;
      if (shift > 63) {
        break;
      }
    }
    return result;
  }

  zigzag(): number {
    const n = this.varint();
    const half = Math.floor(n / 2);
    return n % 2 === 1 ? -half - 1 : half;
  }

  doubleValue(): number {
    const v = readDoubleLE(this.bytes, this.pos);
    this.pos += 8;
    return v;
  }

  binary(): Uint8Array {
    const len = this.varint();
    const out = this.bytes.subarray(this.pos, this.pos + len);
    this.pos += len;
    return out;
  }

  binaryString(): string {
    const len = this.varint();
    const s = utf8Decode(this.bytes, this.pos, len);
    this.pos += len;
    return s;
  }

  listHeader(): ListHeader {
    const b = this.byte();
    const h = new ListHeader();
    h.size = b >> 4;
    h.elemType = b & 0x0f;
    if (h.size === 15) {
      h.size = this.varint();
    }
    return h;
  }

  skip(type: number): void {
    if (type === 1 || type === 2) {
      return;
    }
    if (type === 3) {
      this.pos += 1;
      return;
    }
    if (type === 4 || type === 5 || type === 6) {
      this.varint();
      return;
    }
    if (type === 7) {
      this.pos += 8;
      return;
    }
    if (type === 8) {
      const len = this.varint();
      this.pos += len;
      return;
    }
    if (type === 9 || type === 10) {
      const h = this.listHeader();
      for (let i = 0; i < h.size; i++) {
        this.skip(h.elemType);
      }
      return;
    }
    if (type === 11) {
      const size = this.varint();
      if (size > 0) {
        const kv = this.byte();
        const kt = kv >> 4;
        const vt = kv & 0x0f;
        for (let i = 0; i < size; i++) {
          this.skip(kt);
          this.skip(vt);
        }
      }
      return;
    }
    if (type === 12) {
      let lastId = 0;
      while (true) {
        const b = this.byte();
        if (b === 0) {
          break;
        }
        const ft = b & 0x0f;
        const delta = (b >> 4) & 0x0f;
        if (delta === 0) {
          this.zigzag();
        }
        lastId = 0;
        void lastId;
        this.skip(ft);
      }
    }
  }
}

/** Snappy 解压（raw block 格式，含 4 字节解压后长度） */
function snappyDecompress(data: Uint8Array): Uint8Array {
  let pos = 0;
  let expected = 0;
  let shift = 0;
  while (pos < data.length) {
    const b = data[pos];
    pos++;
    expected += (b & 0x7f) * Math.pow(2, shift);
    if ((b & 0x80) === 0) {
      break;
    }
    shift += 7;
  }
  const out = new Uint8Array(expected);
  let o = 0;
  while (pos < data.length && o < expected) {
    const tag = data[pos];
    pos++;
    const kind = tag & 0x03;
    if (kind === 0) {
      let len = (tag >> 2) + 1;
      if (len > 60) {
        const extra = len - 60;
        let v = 0;
        for (let i = 0; i < extra; i++) {
          v += data[pos] * Math.pow(2, 8 * i);
          pos++;
        }
        len = v + 1;
      }
      for (let i = 0; i < len; i++) {
        out[o] = data[pos];
        pos++;
        o++;
      }
    } else {
      let len = 0;
      let offset = 0;
      if (kind === 1) {
        len = ((tag >> 2) & 0x07) + 4;
        offset = ((tag >> 5) << 8) | data[pos];
        pos++;
      } else if (kind === 2) {
        len = (tag >> 2) + 1;
        offset = data[pos] | (data[pos + 1] << 8);
        pos += 2;
      } else {
        len = (tag >> 2) + 1;
        offset = data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24);
        pos += 4;
      }
      if (offset <= 0 || offset > o) {
        throw new Error('Snappy 数据损坏');
      }
      for (let i = 0; i < len; i++) {
        out[o] = out[o - offset];
        o++;
      }
    }
  }
  return out;
}

function bitWidthOf(maxValue: number): number {
  let w = 0;
  let v = maxValue;
  while (v > 0) {
    w++;
    v >>= 1;
  }
  return w;
}

/** RLE / Bit-Packing hybrid 解码（definition levels、字典索引共用） */
function decodeRleHybrid(data: Uint8Array, start: number, bitWidth: number, count: number): RleResult {
  const result = new RleResult();
  const out: number[] = [];
  let pos = start;
  const byteWidth = Math.ceil(bitWidth / 8);
  while (out.length < count && pos < data.length) {
    let header = 0;
    let shift = 0;
    while (pos < data.length) {
      const b = data[pos];
      pos++;
      header += (b & 0x7f) * Math.pow(2, shift);
      if ((b & 0x80) === 0) {
        break;
      }
      shift += 7;
    }
    if ((header & 1) === 0) {
      const runLen = header >> 1;
      let value = 0;
      for (let i = 0; i < byteWidth; i++) {
        value |= data[pos] << (8 * i);
        pos++;
      }
      for (let i = 0; i < runLen && out.length < count; i++) {
        out.push(value);
      }
    } else {
      const groups = header >> 1;
      const total = groups * 8;
      const totalBytes = groups * bitWidth;
      let bitPos = 0;
      for (let i = 0; i < total && out.length < count; i++) {
        let v = 0;
        for (let b = 0; b < bitWidth; b++) {
          const byteIndex = pos + ((bitPos + b) >> 3);
          const bitIndex = (bitPos + b) & 7;
          if (byteIndex < data.length && ((data[byteIndex] >> bitIndex) & 1) !== 0) {
            v |= Math.pow(2, b);
          }
        }
        bitPos += bitWidth;
        out.push(v);
      }
      pos += totalBytes;
    }
  }
  result.values = out;
  result.consumed = pos - start;
  return result;
}

/** BIT_PACKED 旧式 levels 编码（已废弃，仅兼容老文件） */
function decodeBitPackedLevels(data: Uint8Array, start: number, maxLevel: number, count: number): number[] {
  const width = bitWidthOf(maxLevel);
  const out: number[] = [];
  const totalBytes = Math.ceil((count * width) / 8);
  let bitPos = 0;
  for (let i = 0; i < count; i++) {
    let v = 0;
    for (let b = 0; b < width; b++) {
      const byteIndex = start + ((bitPos + b) >> 3);
      const bitIndex = (bitPos + b) & 7;
      if (byteIndex < start + totalBytes && byteIndex < data.length && ((data[byteIndex] >> bitIndex) & 1) !== 0) {
        v |= Math.pow(2, b);
      }
    }
    bitPos += width;
    out.push(v);
  }
  return out;
}

class PageHeaderInfo {
  type: number = 0;
  uncompressedSize: number = 0;
  compressedSize: number = 0;
  numValues: number = 0;
  encoding: number = 0;
  defEncoding: number = 0;
  repEncoding: number = 0;
  v2NumNulls: number = 0;
  v2DefLen: number = 0;
  v2RepLen: number = 0;
  v2Compressed: boolean = true;
  dictNumValues: number = 0;
  dictEncoding: number = 0;
}

function readDataPageHeader(cur: ThriftCursor, h: PageHeaderInfo): void {
  let lastId = 0;
  while (true) {
    const b = cur.byte();
    if (b === 0) {
      break;
    }
    const type = b & 0x0f;
    const delta = (b >> 4) & 0x0f;
    const id = delta === 0 ? cur.zigzag() : lastId + delta;
    lastId = id;
    if (id === 1) {
      h.numValues = cur.zigzag();
    } else if (id === 2) {
      h.encoding = cur.zigzag();
    } else if (id === 3) {
      h.defEncoding = cur.zigzag();
    } else if (id === 4) {
      h.repEncoding = cur.zigzag();
    } else {
      cur.skip(type);
    }
  }
}

function readDictPageHeader(cur: ThriftCursor, h: PageHeaderInfo): void {
  let lastId = 0;
  while (true) {
    const b = cur.byte();
    if (b === 0) {
      break;
    }
    const type = b & 0x0f;
    const delta = (b >> 4) & 0x0f;
    const id = delta === 0 ? cur.zigzag() : lastId + delta;
    lastId = id;
    if (id === 1) {
      h.dictNumValues = cur.zigzag();
    } else if (id === 2) {
      h.dictEncoding = cur.zigzag();
    } else {
      cur.skip(type);
    }
  }
}

function readDataPageHeaderV2(cur: ThriftCursor, h: PageHeaderInfo): void {
  let lastId = 0;
  while (true) {
    const b = cur.byte();
    if (b === 0) {
      break;
    }
    const type = b & 0x0f;
    const delta = (b >> 4) & 0x0f;
    const id = delta === 0 ? cur.zigzag() : lastId + delta;
    lastId = id;
    if (id === 1) {
      h.numValues = cur.zigzag();
    } else if (id === 2) {
      h.v2NumNulls = cur.zigzag();
    } else if (id === 4) {
      h.encoding = cur.zigzag();
    } else if (id === 5) {
      h.v2DefLen = cur.zigzag();
    } else if (id === 6) {
      h.v2RepLen = cur.zigzag();
    } else if (id === 7) {
      h.v2Compressed = type === 1;
    } else {
      cur.skip(type);
    }
  }
}

function readPageHeader(cur: ThriftCursor): PageHeaderInfo {
  const h = new PageHeaderInfo();
  let lastId = 0;
  while (true) {
    const b = cur.byte();
    if (b === 0) {
      break;
    }
    const type = b & 0x0f;
    const delta = (b >> 4) & 0x0f;
    const id = delta === 0 ? cur.zigzag() : lastId + delta;
    lastId = id;
    if (id === 1) {
      h.type = cur.zigzag();
    } else if (id === 2) {
      h.uncompressedSize = cur.zigzag();
    } else if (id === 3) {
      h.compressedSize = cur.zigzag();
    } else if (id === 5 && type === 12) {
      readDataPageHeader(cur, h);
    } else if (id === 7 && type === 12) {
      readDictPageHeader(cur, h);
    } else if (id === 8 && type === 12) {
      readDataPageHeaderV2(cur, h);
    } else {
      cur.skip(type);
    }
  }
  return h;
}

export class ParquetReader {
  private bytes: Uint8Array = new Uint8Array(0);

  /** 解析 Parquet 二进制，返回按行展开的 JSON 数组 */
  parse(buffer: ArrayBuffer): ParquetResult {
    const res = new ParquetResult();
    try {
      this.bytes = new Uint8Array(buffer);
      const total = this.bytes.length;
      if (total < 12) {
        res.message = '不是有效的 Parquet 文件';
        return res;
      }
      if (utf8Decode(this.bytes, total - 4, 4) !== 'PAR1') {
        res.message = '缺少 PAR1 文件尾，可能不是 Parquet';
        return res;
      }
      const footerLen = readUInt32LE(this.bytes, total - 8);
      const metaStart = total - 8 - footerLen;
      if (metaStart < 4 || metaStart >= total) {
        res.message = '文件元数据偏移非法';
        return res;
      }
      const meta = this.readFileMetaData(new ThriftCursor(this.bytes, metaStart));
      res.totalRows = meta.numRows;
      if (meta.schema.length < 2) {
        res.message = '文件没有可读的列';
        return res;
      }
      const leaves: SchemaField[] = [];
      for (let i = 1; i < meta.schema.length; i++) {
        const f = meta.schema[i];
        if (f.numChildren > 0) {
          res.message = '暂不支持嵌套结构（字段 ' + f.name + ' 是 group）';
          return res;
        }
        leaves.push(f);
        res.columns.push(f.name);
      }

      const rows: JValue[] = [];
      let truncated = false;
      for (let g = 0; g < meta.rowGroups.length; g++) {
        const rg = meta.rowGroups[g];
        if (rows.length >= MAX_ROWS) {
          truncated = true;
          break;
        }
        const take = Math.min(rg.numRows, MAX_ROWS - rows.length);
        const columnValues: JValue[][] = [];
        const columnNames: string[] = [];
        for (let c = 0; c < rg.columns.length; c++) {
          const col = rg.columns[c];
          const leaf = this.findLeaf(leaves, col.path);
          if (leaf === null) {
            continue;
          }
          columnNames.push(col.name);
          columnValues.push(this.decodeColumn(col, leaf));
        }
        for (let r = 0; r < take; r++) {
          const row = JValue.ofObj();
          for (let c = 0; c < columnValues.length; c++) {
            const vals = columnValues[c];
            row.set(columnNames[c], r < vals.length ? vals[r].clone() : JValue.ofNull());
          }
          rows.push(row);
        }
        if (take < rg.numRows) {
          truncated = true;
        }
      }
      res.rows = rows;
      res.rowCount = rows.length;
      res.truncated = truncated;
      res.ok = true;
      return res;
    } catch (e) {
      res.message = String(e).split('Error: ').join('');
      return res;
    }
  }

  private findLeaf(leaves: SchemaField[], path: string): SchemaField | null {
    const short = path.indexOf('.') >= 0 ? path.substring(path.lastIndexOf('.') + 1) : path;
    for (let i = 0; i < leaves.length; i++) {
      if (leaves[i].name === path || leaves[i].name === short) {
        return leaves[i];
      }
    }
    return null;
  }

  private readFileMetaData(cur: ThriftCursor): FileMeta {
    const meta = new FileMeta();
    let lastId = 0;
    while (true) {
      const b = cur.byte();
      if (b === 0) {
        break;
      }
      const type = b & 0x0f;
      const delta = (b >> 4) & 0x0f;
      const id = delta === 0 ? cur.zigzag() : lastId + delta;
      lastId = id;
      if (id === 2 && type === 9) {
        const list = cur.listHeader();
        for (let i = 0; i < list.size; i++) {
          meta.schema.push(this.readSchemaElement(cur));
        }
      } else if (id === 3) {
        meta.numRows = cur.zigzag();
      } else if (id === 4 && type === 9) {
        const list = cur.listHeader();
        for (let i = 0; i < list.size; i++) {
          meta.rowGroups.push(this.readRowGroup(cur));
        }
      } else {
        cur.skip(type);
      }
    }
    return meta;
  }

  private readSchemaElement(cur: ThriftCursor): SchemaField {
    const s = new SchemaField();
    let lastId = 0;
    while (true) {
      const b = cur.byte();
      if (b === 0) {
        break;
      }
      const type = b & 0x0f;
      const delta = (b >> 4) & 0x0f;
      const id = delta === 0 ? cur.zigzag() : lastId + delta;
      lastId = id;
      if (id === 1) {
        s.physType = cur.zigzag();
      } else if (id === 2) {
        s.typeLength = cur.zigzag();
      } else if (id === 3) {
        s.repetition = cur.zigzag();
      } else if (id === 4 && type === 8) {
        s.name = cur.binaryString();
      } else if (id === 5) {
        s.numChildren = cur.zigzag();
      } else if (id === 6) {
        s.convertedType = cur.zigzag();
      } else if (id === 7) {
        s.scale = cur.zigzag();
      } else if (id === 8) {
        s.precision = cur.zigzag();
      } else {
        cur.skip(type);
      }
    }
    return s;
  }

  private readRowGroup(cur: ThriftCursor): RowGroupInfo {
    const rg = new RowGroupInfo();
    let lastId = 0;
    while (true) {
      const b = cur.byte();
      if (b === 0) {
        break;
      }
      const type = b & 0x0f;
      const delta = (b >> 4) & 0x0f;
      const id = delta === 0 ? cur.zigzag() : lastId + delta;
      lastId = id;
      if (id === 1 && type === 9) {
        const list = cur.listHeader();
        for (let i = 0; i < list.size; i++) {
          const col = this.readColumnChunk(cur);
          if (col !== null) {
            rg.columns.push(col);
          }
        }
      } else if (id === 3) {
        rg.numRows = cur.zigzag();
      } else {
        cur.skip(type);
      }
    }
    return rg;
  }

  private readColumnChunk(cur: ThriftCursor): ColChunkInfo | null {
    let col: ColChunkInfo | null = null;
    let lastId = 0;
    while (true) {
      const b = cur.byte();
      if (b === 0) {
        break;
      }
      const type = b & 0x0f;
      const delta = (b >> 4) & 0x0f;
      const id = delta === 0 ? cur.zigzag() : lastId + delta;
      lastId = id;
      if (id === 3 && type === 12) {
        col = this.readColumnMetaData(cur);
      } else {
        cur.skip(type);
      }
    }
    return col;
  }

  private readColumnMetaData(cur: ThriftCursor): ColChunkInfo {
    const col = new ColChunkInfo();
    let lastId = 0;
    while (true) {
      const b = cur.byte();
      if (b === 0) {
        break;
      }
      const type = b & 0x0f;
      const delta = (b >> 4) & 0x0f;
      const id = delta === 0 ? cur.zigzag() : lastId + delta;
      lastId = id;
      if (id === 1) {
        col.physType = cur.zigzag();
      } else if (id === 3 && type === 9) {
        const list = cur.listHeader();
        const parts: string[] = [];
        for (let i = 0; i < list.size; i++) {
          parts.push(cur.binaryString());
        }
        col.path = parts.join('.');
        col.name = parts.length > 0 ? parts[parts.length - 1] : col.path;
      } else if (id === 4) {
        col.codec = cur.zigzag();
      } else if (id === 5) {
        col.numValues = cur.zigzag();
      } else if (id === 7) {
        col.totalCompressedSize = cur.zigzag();
      } else if (id === 9) {
        col.dataPageOffset = cur.zigzag();
      } else if (id === 11) {
        col.dictPageOffset = cur.zigzag();
      } else {
        cur.skip(type);
      }
    }
    return col;
  }

  private decompress(codec: number, data: Uint8Array): Uint8Array {
    if (codec === CODEC_UNCOMPRESSED) {
      return data;
    }
    if (codec === CODEC_SNAPPY) {
      return snappyDecompress(data);
    }
    throw new Error('暂不支持该压缩方式（codec=' + codec + '），请用 snappy 或 uncompressed 重新导出');
  }

  private decodeColumn(col: ColChunkInfo, leaf: SchemaField): JValue[] {
    const values: JValue[] = [];
    const maxDef = leaf.repetition === 1 ? 1 : 0;
    let offset = col.dictPageOffset >= 0 && col.dictPageOffset < col.dataPageOffset ?
      col.dictPageOffset : col.dataPageOffset;
    let dict: JValue[] = [];
    let hasDict = false;
    let produced = 0;
    let guard = 0;
    while (produced < col.numValues && guard < 100000) {
      guard++;
      if (offset <= 0 || offset >= this.bytes.length) {
        break;
      }
      const cur = new ThriftCursor(this.bytes, offset);
      const header = readPageHeader(cur);
      const dataStart = cur.pos;
      if (header.compressedSize <= 0 || dataStart + header.compressedSize > this.bytes.length) {
        break;
      }
      const raw = this.bytes.subarray(dataStart, dataStart + header.compressedSize);
      offset = dataStart + header.compressedSize;

      if (header.type === PAGE_DICT) {
        const page = this.decompress(col.codec, raw);
        const count = header.dictNumValues;
        dict = this.decodePlain(page, leaf, count);
        hasDict = true;
        continue;
      }
      if (header.type === PAGE_DATA) {
        const page = this.decompress(col.codec, raw);
        const pageValues = this.decodeDataPageV1(page, header, leaf, maxDef, dict, hasDict);
        for (let i = 0; i < pageValues.length; i++) {
          values.push(pageValues[i]);
        }
        produced += header.numValues;
        continue;
      }
      if (header.type === PAGE_DATA_V2) {
        const repLen = header.v2RepLen;
        const defLen = header.v2DefLen;
        const levelsEnd = repLen + defLen;
        const rawValues = raw.subarray(levelsEnd);
        const valuesData = header.v2Compressed ? this.decompress(col.codec, rawValues) : rawValues;
        const pageValues = this.decodeDataPageV2(raw.subarray(0, levelsEnd), repLen, header,
          valuesData, leaf, maxDef, dict, hasDict);
        for (let i = 0; i < pageValues.length; i++) {
          values.push(pageValues[i]);
        }
        produced += header.numValues;
        continue;
      }
      // 其他页（索引页等）直接跳过
    }
    if (values.length < col.numValues) {
      const missing = col.numValues - values.length;
      for (let i = 0; i < missing; i++) {
        values.push(JValue.ofNull());
      }
    }
    return values;
  }

  private decodeDataPageV1(page: Uint8Array, h: PageHeaderInfo, leaf: SchemaField,
    maxDef: number, dict: JValue[], hasDict: boolean): JValue[] {
    let pos = 0;
    let defLevels: number[] = [];
    if (maxDef > 0) {
      if (pos + 4 > page.length) {
        return [];
      }
      const defLen = readUInt32LE(page, pos);
      pos += 4;
      if (h.defEncoding === ENC_RLE) {
        const r = decodeRleHybrid(page, pos, bitWidthOf(maxDef), h.numValues);
        defLevels = r.values;
      } else {
        defLevels = decodeBitPackedLevels(page, pos, maxDef, h.numValues);
      }
      pos += defLen;
    }
    const valueCount = maxDef > 0 ? this.countDefined(defLevels, maxDef, h.numValues) : h.numValues;
    const values = this.decodeValues(page.subarray(pos), h.encoding, leaf, valueCount, dict, hasDict);
    return this.mergeNulls(values, defLevels, maxDef, h.numValues);
  }

  private decodeDataPageV2(levels: Uint8Array, repLen: number, h: PageHeaderInfo,
    valuesData: Uint8Array, leaf: SchemaField, maxDef: number,
    dict: JValue[], hasDict: boolean): JValue[] {
    let defLevels: number[] = [];
    if (maxDef > 0) {
      const r = decodeRleHybrid(levels, repLen, bitWidthOf(maxDef), h.numValues);
      defLevels = r.values;
    }
    const valueCount = Math.max(0, h.numValues - h.v2NumNulls);
    const values = this.decodeValues(valuesData, h.encoding, leaf, valueCount, dict, hasDict);
    return this.mergeNulls(values, defLevels, maxDef, h.numValues);
  }

  private countDefined(levels: number[], maxDef: number, count: number): number {
    let n = 0;
    for (let i = 0; i < count; i++) {
      if (i < levels.length && levels[i] === maxDef) {
        n++;
      }
    }
    return n;
  }

  private mergeNulls(values: JValue[], levels: number[], maxDef: number, count: number): JValue[] {
    const out: JValue[] = [];
    let vi = 0;
    for (let i = 0; i < count; i++) {
      if (maxDef === 0) {
        out.push(vi < values.length ? values[vi] : JValue.ofNull());
        vi++;
      } else if (i < levels.length && levels[i] === maxDef) {
        out.push(vi < values.length ? values[vi] : JValue.ofNull());
        vi++;
      } else {
        out.push(JValue.ofNull());
      }
    }
    return out;
  }

  private decodeValues(data: Uint8Array, encoding: number, leaf: SchemaField,
    count: number, dict: JValue[], hasDict: boolean): JValue[] {
    if (encoding === ENC_PLAIN) {
      return this.decodePlain(data, leaf, count);
    }
    if ((encoding === ENC_PLAIN_DICTIONARY || encoding === ENC_RLE_DICTIONARY || encoding === ENC_RLE) &&
      hasDict) {
      if (data.length === 0) {
        return [];
      }
      const bitWidth = data[0];
      const r = decodeRleHybrid(data, 1, bitWidth, count);
      const out: JValue[] = [];
      for (let i = 0; i < count; i++) {
        const idx = i < r.values.length ? r.values[i] : -1;
        out.push(idx >= 0 && idx < dict.length ? dict[idx] : JValue.ofNull());
      }
      return out;
    }
    throw new Error('暂不支持该列编码（encoding=' + encoding + '）');
  }

  private decodePlain(data: Uint8Array, leaf: SchemaField, count: number): JValue[] {
    const out: JValue[] = [];
    const t = leaf.physType;
    if (t === PHYS_BOOLEAN) {
      for (let i = 0; i < count; i++) {
        const byte = i >> 3 < data.length ? data[i >> 3] : 0;
        out.push(JValue.ofBool(((byte >> (i & 7)) & 1) === 1));
      }
      return out;
    }
    let pos = 0;
    for (let i = 0; i < count; i++) {
      if (t === PHYS_INT32) {
        if (pos + 4 > data.length) {
          break;
        }
        const v = readInt32LE(data, pos);
        pos += 4;
        if (leaf.convertedType === 6) {
          out.push(JValue.ofStr(formatDate(v)));
        } else if (leaf.convertedType === 5) {
          out.push(decimalValue(applyDecimalScale(v.toString(), leaf.scale)));
        } else {
          out.push(JValue.ofNum(v));
        }
      } else if (t === PHYS_INT64) {
        if (pos + 8 > data.length) {
          break;
        }
        const v = int64Value(data, pos);
        pos += 8;
        if (leaf.convertedType === 9) {
          out.push(JValue.ofStr(formatTimestampMs(v.numVal)));
        } else if (leaf.convertedType === 10) {
          out.push(JValue.ofStr(formatTimestampMs(Math.floor(v.numVal / 1000))));
        } else if (leaf.convertedType === 5) {
          const text = v.raw.length > 0 ? v.raw : String(v.numVal);
          out.push(decimalValue(applyDecimalScale(text, leaf.scale)));
        } else {
          out.push(v);
        }
      } else if (t === PHYS_FLOAT) {
        if (pos + 4 > data.length) {
          break;
        }
        out.push(JValue.ofNum(readFloatLE(data, pos)));
        pos += 4;
      } else if (t === PHYS_DOUBLE) {
        if (pos + 8 > data.length) {
          break;
        }
        out.push(JValue.ofNum(readDoubleLE(data, pos)));
        pos += 8;
      } else if (t === PHYS_BYTE_ARRAY) {
        if (pos + 4 > data.length) {
          break;
        }
        const len = readUInt32LE(data, pos);
        pos += 4;
        out.push(JValue.ofStr(utf8Decode(data, pos, len)));
        pos += len;
      } else if (t === PHYS_FLBA) {
        if (pos + leaf.typeLength > data.length) {
          break;
        }
        if (leaf.convertedType === 5) {
          out.push(decimalValue(applyDecimalScale(
            bigEndianToDecimal(data, pos, leaf.typeLength), leaf.scale)));
        } else {
          out.push(JValue.ofStr(utf8Decode(data, pos, leaf.typeLength)));
        }
        pos += leaf.typeLength;
      } else if (t === PHYS_INT96) {
        pos += 12;
        out.push(JValue.ofNull());
      } else {
        break;
      }
    }
    return out;
  }
}

export const parquetReader: ParquetReader = new ParquetReader();

/** 把解析结果组装成 JSON 数组文本 */
export function parquetRowsToJson(result: ParquetResult): JValue {
  const arr = JValue.ofArr();
  for (let i = 0; i < result.rows.length; i++) {
    arr.items.push(result.rows[i]);
  }
  return arr;
}

/** 类型名：用于错误提示与调试 */
export function parquetTypeName(t: number): string {
  if (t === PHYS_BOOLEAN) {
    return 'BOOLEAN';
  }
  if (t === PHYS_INT32) {
    return 'INT32';
  }
  if (t === PHYS_INT64) {
    return 'INT64';
  }
  if (t === PHYS_INT96) {
    return 'INT96';
  }
  if (t === PHYS_FLOAT) {
    return 'FLOAT';
  }
  if (t === PHYS_DOUBLE) {
    return 'DOUBLE';
  }
  if (t === PHYS_BYTE_ARRAY) {
    return 'BYTE_ARRAY';
  }
  if (t === PHYS_FLBA) {
    return 'FIXED_LEN_BYTE_ARRAY';
  }
  return 'UNKNOWN';
}
