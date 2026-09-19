/*!
 * cai/js/sessions.js — 대화 세션 저장/복원
 *
 * 세션 본문(제목·메시지·설정)은 통째로 암호화되어 IndexedDB 에 들어간다.
 * 목록 정렬에 필요한 updatedAt 만 평문으로 남긴다.
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});

  function create(settings) {
    var now = Date.now();
    return {
      id: 'sess_' + CAI.crypto.randomId(10),
      title: '새 대화',
      createdAt: now,
      updatedAt: now,
      provider: settings.provider,
      model: (settings.models && settings.models[settings.provider]) || '',
      harnessId: settings.harnessId,
      messages: [],
      usage: { input: 0, output: 0 },
    };
  }

  /** 첫 사용자 메시지에서 제목을 뽑는다. */
  function autoTitle(session) {
    if (session.titleLocked) return session.title;
    var first = null;
    for (var i = 0; i < session.messages.length; i++) {
      var m = session.messages[i];
      if (m.role !== 'user') continue;
      var text = (Array.isArray(m.content) ? m.content : [])
        .filter(function (p) {
          return p.type === 'text';
        })
        .map(function (p) {
          return p.text;
        })
        .join(' ')
        .trim();
      if (text) {
        first = text;
        break;
      }
    }
    if (!first) return session.title;
    var title = first.replace(/\s+/g, ' ').slice(0, 40);
    return first.length > 40 ? title + '…' : title;
  }

  async function save(session) {
    session.updatedAt = Date.now();
    session.title = autoTitle(session);
    await CAI.store.putSession({
      id: session.id,
      owner: CAI.auth.username(),
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      data: await CAI.auth.encrypt(session),
    });
    return session;
  }

  async function load(id) {
    var row = await CAI.store.getSession(id);
    if (!row) return null;
    try {
      return await CAI.auth.decrypt(row.data);
    } catch (e) {
      return null;
    }
  }

  /** 목록용: 제목만 복호화해서 가볍게 반환 */
  async function list() {
    var rows = await CAI.store.listSessions(CAI.auth.username());
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      try {
        var full = await CAI.auth.decrypt(rows[i].data);
        out.push({
          id: full.id,
          title: full.title || '제목 없음',
          updatedAt: rows[i].updatedAt,
          provider: full.provider,
          model: full.model,
          count: (full.messages || []).length,
        });
      } catch (e) {
        /* 복호화 실패한 행은 건너뛴다 */
      }
    }
    return out;
  }

  async function remove(id) {
    await CAI.store.deleteSession(id);
  }

  async function exportAll() {
    var rows = await CAI.store.listSessions(CAI.auth.username());
    var sessions = [];
    for (var i = 0; i < rows.length; i++) {
      try {
        sessions.push(await CAI.auth.decrypt(rows[i].data));
      } catch (e) {}
    }
    return {
      format: 'cai-harness-export',
      version: 1,
      exportedAt: new Date().toISOString(),
      sessions: sessions,
    };
  }

  async function importAll(payload) {
    if (!payload || payload.format !== 'cai-harness-export' || !Array.isArray(payload.sessions)) {
      throw new Error('CAI 하네스 내보내기 파일이 아닙니다.');
    }
    var n = 0;
    for (var i = 0; i < payload.sessions.length; i++) {
      var s = payload.sessions[i];
      if (!s || !Array.isArray(s.messages)) continue;
      s.id = 'sess_' + CAI.crypto.randomId(10); // 기존 세션과 충돌하지 않게 새 ID 부여
      s.createdAt = s.createdAt || Date.now();
      s.updatedAt = Date.now();
      s.titleLocked = true;
      await save(s);
      n++;
    }
    return n;
  }

  CAI.sessions = {
    create: create,
    save: save,
    load: load,
    list: list,
    remove: remove,
    exportAll: exportAll,
    importAll: importAll,
    autoTitle: autoTitle,
  };
})(window);
