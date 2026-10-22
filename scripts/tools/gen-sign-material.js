/*
 * 生成 HarmonyOS 签名配置所需的 material 目录与加密密码。
 *
 * 背景：build-profile.json5 的 storePassword/keyPassword 必须是 hvigor 可解密的密文
 * （长度 >= 32 的 hex 串，AES-128-GCM）。解密所需的工作密钥存放在
 * <p12 所在目录>/material/{fd,ac,ce} 下，由 hvigor 的 DecipherUtil 派生。
 *
 * 用法:
 *   node scripts/tools/gen-sign-material.js "<签名材料目录>" "<p12密码>"
 * 例:
 *   node scripts/tools/gen-sign-material.js "F:\OpenHarmony\Key\HelloJson\Release" "yourpwd"
 *
 * 输出: JSON，storePassword / keyPassword 两个密文字段（直接粘到 build-profile.json5）。
 */
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// 与 hvigor DecipherUtil.component 完全一致的固定字节
const COMPONENT = Buffer.from([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]);

function xorAll(parts) {
  const acc = Buffer.from(parts[0]);
  for (let i = 1; i < parts.length; i++) {
    for (let k = 0; k < 16; k++) {
      acc[k] ^= parts[i][k];
    }
  }
  return acc;
}

/** 密文格式: [4字节大端 (密文长度+16)] + [12字节 IV] + [密文] + [16字节 GCM tag] */
function encryptPayload(key, plain) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-128-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(plain), cipher.final()]);
  const tag = cipher.getAuthTag();
  const head = Buffer.alloc(4);
  head.writeUInt32BE(ct.length + 16, 0);
  return Buffer.concat([head, iv, ct, tag]);
}

/** 与 DecipherUtil.decryptPwd 等价的解密实现，用于自检 */
function decryptPayload(key, buf) {
  const e = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
  const i = buf.length - 4 - e;
  const iv = buf.slice(4, 4 + i);
  const decipher = crypto.createDecipheriv('aes-128-gcm', key, iv);
  decipher.setAuthTag(buf.slice(buf.length - 16));
  return Buffer.concat([
    decipher.update(buf.subarray(4 + i, buf.length - 16)),
    decipher.final()
  ]);
}

function writeSingleFile(dir, content) {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, crypto.randomBytes(16).toString('hex')), content);
}

function main() {
  const target = process.argv[2];
  const pwd = process.argv[3];
  if (!target || !pwd) {
    console.error('用法: node gen-sign-material.js "<签名材料目录>" "<p12密码>"');
    process.exit(1);
  }
  const matDir = path.join(target, 'material');
  if (fs.existsSync(matDir)) {
    console.error('material 已存在，先删除再重新生成: ' + matDir);
    process.exit(2);
  }

  // fd: 3 个子目录，各放 1 个 16 字节文件
  const fdParts = [];
  for (let i = 0; i < 3; i++) {
    const part = crypto.randomBytes(16);
    fdParts.push(part);
    writeSingleFile(path.join(matDir, 'fd', String(i)), part);
  }
  // ac: salt
  const salt = crypto.randomBytes(16);
  writeSingleFile(path.join(matDir, 'ac'), salt);

  const keyBase = xorAll([...fdParts, COMPONENT]);
  const rootKey = crypto.pbkdf2Sync(keyBase.toString(), salt, 10000, 16, 'sha256');
  const workKey = crypto.randomBytes(16);
  // ce: 用根密钥加密的工作密钥
  writeSingleFile(path.join(matDir, 'ce'), encryptPayload(rootKey, workKey));

  const enc = encryptPayload(workKey, Buffer.from(pwd, 'utf8')).toString('hex');

  // 自检
  const back = decryptPayload(workKey, Buffer.from(enc, 'hex')).toString('utf8');
  if (back !== pwd) {
    console.error('自检失败: 解密结果与输入密码不一致');
    process.exit(3);
  }

  console.log(JSON.stringify({
    materialDir: matDir,
    storePassword: enc,
    keyPassword: enc
  }, null, 2));
}

main();
