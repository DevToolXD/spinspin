/*!
 * cai/js/crypto.js — 로컬 금고(vault) 암호화 유틸
 *
 * 비밀번호 → PBKDF2(SHA-256, 250k) → AES-GCM 256bit 키를 유도한다.
 * API 키 · 대화 세션 · 가상 파일은 모두 이 키로 암호화되어 IndexedDB 에 저장된다.
 * 유도된 키는 메모리에만 존재하며 디스크에 저장되지 않는다.
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});
  var enc = new TextEncoder();
  var dec = new TextDecoder();

  var PBKDF2_ITERATIONS = 250000;

  function subtle() {
    if (!global.crypto || !global.crypto.subtle) {
      throw new Error(
        'WebCrypto 를 사용할 수 없습니다. https:// 또는 http://localhost 로 접속해 주세요.'
      );
    }
    return global.crypto.subtle;
  }

  function toB64(buffer) {
    var arr = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    var bin = '';
    var CHUNK = 0x8000;
    for (var i = 0; i < arr.length; i += CHUNK) {
      bin += String.fromCharCode.apply(null, arr.subarray(i, i + CHUNK));
    }
    return btoa(bin);
  }

  function fromB64(str) {
    var bin = atob(str);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function randomBytes(n) {
    var b = new Uint8Array(n);
    global.crypto.getRandomValues(b);
    return b;
  }

  function randomId(bytes) {
    return Array.prototype.map
      .call(randomBytes(bytes || 12), function (b) {
        return b.toString(16).padStart(2, '0');
      })
      .join('');
  }

  /** 비밀번호 + salt → AES-GCM 키 */
  async function deriveKey(password, salt) {
    var saltBytes = typeof salt === 'string' ? fromB64(salt) : salt;
    var base = await subtle().importKey('raw', enc.encode(password), 'PBKDF2', false, [
      'deriveKey',
    ]);
    return subtle().deriveKey(
      { name: 'PBKDF2', salt: saltBytes, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
      base,
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt']
    );
  }

  /** 임의 JSON 값을 암호화한 봉투(envelope)로 만든다. */
  async function encryptJSON(key, value) {
    var iv = randomBytes(12);
    var ct = await subtle().encrypt(
      { name: 'AES-GCM', iv: iv },
      key,
      enc.encode(JSON.stringify(value === undefined ? null : value))
    );
    return { v: 1, iv: toB64(iv), ct: toB64(ct) };
  }

  /** 암호화 봉투를 원래 JSON 값으로 되돌린다. 비밀번호가 틀리면 예외가 난다. */
  async function decryptJSON(key, envelope) {
    if (!envelope || !envelope.iv || !envelope.ct) throw new Error('손상된 암호 블록입니다.');
    var pt = await subtle().decrypt(
      { name: 'AES-GCM', iv: fromB64(envelope.iv) },
      key,
      fromB64(envelope.ct)
    );
    return JSON.parse(dec.decode(pt));
  }

  CAI.crypto = {
    ITERATIONS: PBKDF2_ITERATIONS,
    toB64: toB64,
    fromB64: fromB64,
    randomBytes: randomBytes,
    randomId: randomId,
    newSalt: function () {
      return toB64(randomBytes(16));
    },
    deriveKey: deriveKey,
    encryptJSON: encryptJSON,
    decryptJSON: decryptJSON,
  };
})(window);
