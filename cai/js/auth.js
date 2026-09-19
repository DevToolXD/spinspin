/*!
 * cai/js/auth.js — 로컬 로그인 / 금고(vault)
 *
 * 서버가 없는 정적 사이트이므로 계정은 브라우저 안에서만 존재한다.
 * 비밀번호는 저장하지 않고, 비밀번호로 유도한 AES 키로 모든 데이터를 암호화한다.
 * → 비밀번호를 모르면 API 키도 대화 기록도 복호화할 수 없다.
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});
  var SESSION_FLAG = 'cai.lastUser';

  function defaultSettings() {
    return {
      provider: 'anthropic',
      keys: { anthropic: '', openai: '', google: '' },
      models: {
        anthropic: 'claude-opus-5',
        openai: 'gpt-4.1',
        google: 'gemini-2.5-pro',
      },
      baseUrls: { anthropic: '', openai: '', google: '' },
      modelCache: { anthropic: [], openai: [], google: [] },
      harnessId: 'cai-redteam',
      harnessCustom: '',
      userName: '',
      temperature: 1,
      maxTokens: 4096,
      maxSteps: 12,
      streaming: true,
      toolsEnabled: true,
      disabledTools: [],
      // 팀(레드팀 조별과제) 모드
      team: {
        mode: 'solo',   // 'solo' = 1:1, 'team' = 여러 조원이 함께 토론
        goal: '',       // 공동 목표 / 챌린지 설명
        rounds: 1,      // 한 번 보낼 때 각 조원이 발언하는 라운드 수
        members: [],    // [{ id, name, provider, model, role, color, keyOverride }]
      },
    };
  }

  function mergeSettings(saved) {
    var base = defaultSettings();
    if (!saved || typeof saved !== 'object') return base;
    Object.keys(base).forEach(function (k) {
      var v = saved[k];
      if (v === undefined || v === null) return;
      if (typeof base[k] === 'object' && !Array.isArray(base[k])) {
        base[k] = Object.assign({}, base[k], v);
      } else {
        base[k] = v;
      }
    });
    return base;
  }

  var state = {
    username: null,
    key: null,
    settings: null,
  };

  function requireUnlocked() {
    if (!state.key) throw new Error('먼저 로그인해 주세요.');
  }

  function normalizeName(username) {
    return String(username || '').trim().toLowerCase();
  }

  async function signup(username, password) {
    var name = normalizeName(username);
    if (name.length < 2) throw new Error('아이디는 2자 이상이어야 합니다.');
    if (!/^[a-z0-9._-]+$/.test(name)) {
      throw new Error('아이디는 영문 소문자·숫자·. _ - 만 사용할 수 있습니다.');
    }
    if (String(password || '').length < 6) throw new Error('비밀번호는 6자 이상이어야 합니다.');

    var existing = await CAI.store.getAccount(name);
    if (existing) throw new Error('이미 존재하는 아이디입니다.');

    var salt = CAI.crypto.newSalt();
    var key = await CAI.crypto.deriveKey(password, salt);
    var check = await CAI.crypto.encryptJSON(key, { ok: true, user: name });

    await CAI.store.putAccount({
      username: name,
      salt: salt,
      check: check,
      createdAt: Date.now(),
    });

    state.username = name;
    state.key = key;
    state.settings = defaultSettings();
    await saveSettings();
    try { sessionStorage.setItem(SESSION_FLAG, name); } catch (e) {}
    return name;
  }

  async function login(username, password) {
    var name = normalizeName(username);
    var account = await CAI.store.getAccount(name);
    if (!account) throw new Error('존재하지 않는 아이디입니다.');

    var key = await CAI.crypto.deriveKey(password, account.salt);
    try {
      await CAI.crypto.decryptJSON(key, account.check);
    } catch (e) {
      throw new Error('비밀번호가 올바르지 않습니다.');
    }

    state.username = name;
    state.key = key;
    state.settings = mergeSettings(await loadVault('settings'));
    try { sessionStorage.setItem(SESSION_FLAG, name); } catch (e) {}
    return name;
  }

  function logout() {
    state.username = null;
    state.key = null;
    state.settings = null;
    try { sessionStorage.removeItem(SESSION_FLAG); } catch (e) {}
  }

  async function changePassword(currentPassword, nextPassword) {
    requireUnlocked();
    if (String(nextPassword || '').length < 6) throw new Error('새 비밀번호는 6자 이상이어야 합니다.');

    var account = await CAI.store.getAccount(state.username);
    var oldKey = await CAI.crypto.deriveKey(currentPassword, account.salt);
    try {
      await CAI.crypto.decryptJSON(oldKey, account.check);
    } catch (e) {
      throw new Error('현재 비밀번호가 올바르지 않습니다.');
    }

    // 기존 데이터를 모두 복호화해 두고, 새 키로 다시 암호화한다.
    var sessions = await CAI.store.listSessions(state.username);
    var decrypted = [];
    for (var i = 0; i < sessions.length; i++) {
      decrypted.push({
        row: sessions[i],
        value: await CAI.crypto.decryptJSON(oldKey, sessions[i].data),
      });
    }
    var kvNames = ['settings', 'memory', 'files'];
    var kvValues = {};
    for (var j = 0; j < kvNames.length; j++) {
      var rec = await CAI.store.getKV(state.username, kvNames[j]);
      if (rec && rec.data) kvValues[kvNames[j]] = await CAI.crypto.decryptJSON(oldKey, rec.data);
    }

    var salt = CAI.crypto.newSalt();
    var newKey = await CAI.crypto.deriveKey(nextPassword, salt);
    var check = await CAI.crypto.encryptJSON(newKey, { ok: true, user: state.username });
    await CAI.store.putAccount({
      username: state.username,
      salt: salt,
      check: check,
      createdAt: account.createdAt,
    });

    for (var k = 0; k < decrypted.length; k++) {
      var row = decrypted[k].row;
      row.data = await CAI.crypto.encryptJSON(newKey, decrypted[k].value);
      await CAI.store.putSession(row);
    }
    for (var name in kvValues) {
      if (!Object.prototype.hasOwnProperty.call(kvValues, name)) continue;
      await CAI.store.putKV(
        state.username,
        name,
        await CAI.crypto.encryptJSON(newKey, kvValues[name])
      );
    }

    state.key = newKey;
  }

  async function deleteAccount() {
    requireUnlocked();
    var name = state.username;
    await CAI.store.deleteSessionsOf(name);
    await CAI.store.deleteKVOf(name);
    await CAI.store.deleteAccount(name);
    logout();
  }

  // ---- 금고 헬퍼 (임의 이름의 암호화 값) ----
  async function loadVault(name, fallback) {
    requireUnlocked();
    var rec = await CAI.store.getKV(state.username, name);
    if (!rec || !rec.data) return fallback;
    try {
      return await CAI.crypto.decryptJSON(state.key, rec.data);
    } catch (e) {
      return fallback;
    }
  }

  async function saveVault(name, value) {
    requireUnlocked();
    var blob = await CAI.crypto.encryptJSON(state.key, value);
    await CAI.store.putKV(state.username, name, blob);
  }

  async function saveSettings() {
    requireUnlocked();
    await saveVault('settings', state.settings);
  }

  CAI.auth = {
    defaultSettings: defaultSettings,
    mergeSettings: mergeSettings,
    state: state,
    isUnlocked: function () {
      return !!state.key;
    },
    username: function () {
      return state.username;
    },
    settings: function () {
      return state.settings;
    },
    lastUser: function () {
      try { return sessionStorage.getItem(SESSION_FLAG); } catch (e) { return null; }
    },
    signup: signup,
    login: login,
    logout: logout,
    changePassword: changePassword,
    deleteAccount: deleteAccount,
    loadVault: loadVault,
    saveVault: saveVault,
    saveSettings: saveSettings,
    encrypt: function (value) {
      requireUnlocked();
      return CAI.crypto.encryptJSON(state.key, value);
    },
    decrypt: function (blob) {
      requireUnlocked();
      return CAI.crypto.decryptJSON(state.key, blob);
    },
  };
})(window);
