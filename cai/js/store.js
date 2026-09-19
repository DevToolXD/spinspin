/*!
 * cai/js/store.js — IndexedDB 저장소
 *
 * accounts : { username, salt, check, createdAt }          — 계정(평문 메타 + 검증용 암호블록)
 * sessions : { id, owner, updatedAt, createdAt, data }     — data 는 암호화된 대화 전체
 * kv       : { key, owner, data }                          — 설정/메모리/가상파일 (암호화)
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});

  var DB_NAME = 'cai-harness';
  var DB_VERSION = 1;
  var dbPromise = null;

  function openDB() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise(function (resolve, reject) {
      if (!global.indexedDB) {
        reject(new Error('이 브라우저에서는 IndexedDB 를 사용할 수 없습니다.'));
        return;
      }
      var req = global.indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = function (e) {
        var db = req.result;
        if (!db.objectStoreNames.contains('accounts')) {
          db.createObjectStore('accounts', { keyPath: 'username' });
        }
        if (!db.objectStoreNames.contains('sessions')) {
          var s = db.createObjectStore('sessions', { keyPath: 'id' });
          s.createIndex('owner', 'owner', { unique: false });
        }
        if (!db.objectStoreNames.contains('kv')) {
          var k = db.createObjectStore('kv', { keyPath: 'key' });
          k.createIndex('owner', 'owner', { unique: false });
        }
      };
      req.onsuccess = function () {
        resolve(req.result);
      };
      req.onerror = function () {
        reject(req.error || new Error('IndexedDB 를 열 수 없습니다.'));
      };
    });
    return dbPromise;
  }

  function run(storeName, mode, fn) {
    return openDB().then(function (db) {
      return new Promise(function (resolve, reject) {
        var tx = db.transaction(storeName, mode);
        var store = tx.objectStore(storeName);
        var out;
        try {
          out = fn(store);
        } catch (err) {
          reject(err);
          return;
        }
        tx.oncomplete = function () {
          // reqValue 로 감싼 IDBRequest 면 그 결과를, 아니면 그대로 돌려준다.
          // (없는 레코드는 result 가 undefined 이므로 래퍼 자체를 반환하면 안 된다)
          resolve(out && out.__isRequest ? out.result : out);
        };
        tx.onerror = function () {
          reject(tx.error);
        };
        tx.onabort = function () {
          reject(tx.error || new Error('트랜잭션이 중단되었습니다.'));
        };
      });
    });
  }

  function reqValue(request) {
    return {
      __isRequest: true,
      get result() {
        return request.result;
      },
    };
  }

  var store = {
    // ---- accounts ----
    getAccount: function (username) {
      return run('accounts', 'readonly', function (s) {
        return reqValue(s.get(username));
      });
    },
    putAccount: function (account) {
      return run('accounts', 'readwrite', function (s) {
        s.put(account);
      });
    },
    deleteAccount: function (username) {
      return run('accounts', 'readwrite', function (s) {
        s.delete(username);
      });
    },
    listAccounts: function () {
      return run('accounts', 'readonly', function (s) {
        return reqValue(s.getAll());
      }).then(function (rows) {
        return (rows || []).map(function (r) {
          return { username: r.username, createdAt: r.createdAt };
        });
      });
    },

    // ---- sessions ----
    putSession: function (row) {
      return run('sessions', 'readwrite', function (s) {
        s.put(row);
      });
    },
    getSession: function (id) {
      return run('sessions', 'readonly', function (s) {
        return reqValue(s.get(id));
      });
    },
    deleteSession: function (id) {
      return run('sessions', 'readwrite', function (s) {
        s.delete(id);
      });
    },
    listSessions: function (owner) {
      return run('sessions', 'readonly', function (s) {
        return reqValue(s.index('owner').getAll(owner));
      }).then(function (rows) {
        return (rows || []).sort(function (a, b) {
          return (b.updatedAt || 0) - (a.updatedAt || 0);
        });
      });
    },
    deleteSessionsOf: function (owner) {
      return store.listSessions(owner).then(function (rows) {
        return Promise.all(
          rows.map(function (r) {
            return store.deleteSession(r.id);
          })
        );
      });
    },

    // ---- kv ----
    putKV: function (owner, name, data) {
      return run('kv', 'readwrite', function (s) {
        s.put({ key: owner + '::' + name, owner: owner, data: data });
      });
    },
    getKV: function (owner, name) {
      return run('kv', 'readonly', function (s) {
        return reqValue(s.get(owner + '::' + name));
      });
    },
    deleteKVOf: function (owner) {
      return run('kv', 'readwrite', function (s) {
        var idx = s.index('owner');
        var req = idx.openCursor(IDBKeyRange.only(owner));
        req.onsuccess = function () {
          var cur = req.result;
          if (cur) {
            cur.delete();
            cur.continue();
          }
        };
      });
    },
  };

  CAI.store = store;
})(window);
