/*!
 * cai/js/tools.js — CAI 하네스가 제공하는 브라우저 내장 도구
 *
 * 도구 정의는 제공자 중립(JSON Schema)이며, providers.js 가 각 API 형식으로 변환한다.
 * 모든 도구는 브라우저 안에서만 동작하고, 결과는 문자열로 모델에 돌아간다.
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});

  var MAX_RESULT = 24000;

  function clip(text, limit) {
    var s = typeof text === 'string' ? text : JSON.stringify(text, null, 2);
    s = s === undefined ? '' : String(s);
    var max = limit || MAX_RESULT;
    if (s.length <= max) return s;
    return s.slice(0, max) + '\n… (출력이 잘렸습니다. 총 ' + s.length + '자)';
  }

  // ------------------------------------------------------------- 가상 파일시스템

  async function loadFiles() {
    return (await CAI.auth.loadVault('files', {})) || {};
  }
  async function saveFiles(files) {
    await CAI.auth.saveVault('files', files);
  }
  function normPath(p) {
    var s = String(p || '').trim().replace(/^\.?\/+/, '');
    if (!s) throw new Error('경로가 비어 있습니다.');
    if (s.length > 200) throw new Error('경로가 너무 깁니다.');
    return s;
  }

  // ------------------------------------------------------------- 기억(메모리)

  async function loadMemory() {
    var m = await CAI.auth.loadVault('memory', []);
    return Array.isArray(m) ? m : [];
  }
  async function saveMemory(list) {
    await CAI.auth.saveVault('memory', list.slice(-300));
  }

  // ------------------------------------------------------------- JS 샌드박스

  var WORKER_SOURCE = [
    'function fmt(v){',
    '  if (typeof v === "string") return v;',
    '  if (v === undefined) return "undefined";',
    '  if (v === null) return "null";',
    '  if (v instanceof Error) return v.name + ": " + v.message;',
    '  try { return JSON.stringify(v, null, 2); } catch (e) { return String(v); }',
    '}',
    'self.onmessage = async function (e) {',
    '  var logs = [];',
    '  var push = function () {',
    '    logs.push(Array.prototype.map.call(arguments, fmt).join(" "));',
    '  };',
    '  self.console = { log: push, info: push, warn: push, error: push, debug: push };',
    '  try {',
    '    var fn = new Function("\\"use strict\\"; return (async function(){\\n" + e.data.code + "\\n})();");',
    '    var result = await fn();',
    '    self.postMessage({ ok: true, result: fmt(result), logs: logs });',
    '  } catch (err) {',
    '    self.postMessage({ ok: false, error: (err && (err.stack || err.message)) || String(err), logs: logs });',
    '  }',
    '};',
  ].join('\n');

  var workerURL = null;
  function getWorkerURL() {
    if (!workerURL) {
      workerURL = URL.createObjectURL(new Blob([WORKER_SOURCE], { type: 'text/javascript' }));
    }
    return workerURL;
  }

  function runInWorker(code, timeoutMs) {
    return new Promise(function (resolve) {
      var worker;
      try {
        worker = new Worker(getWorkerURL());
      } catch (e) {
        resolve({ ok: false, error: 'Web Worker 를 만들 수 없습니다: ' + e.message, logs: [] });
        return;
      }
      var finished = false;
      var timer = setTimeout(function () {
        if (finished) return;
        finished = true;
        worker.terminate();
        resolve({
          ok: false,
          error: '실행 시간 초과 (' + timeoutMs + 'ms). 무한 루프가 있는지 확인하세요.',
          logs: [],
        });
      }, timeoutMs);

      worker.onmessage = function (e) {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        worker.terminate();
        resolve(e.data);
      };
      worker.onerror = function (e) {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        worker.terminate();
        resolve({ ok: false, error: e.message || '워커 오류', logs: [] });
      };
      worker.postMessage({ code: code });
    });
  }

  // ------------------------------------------------------------- 도구 정의

  var DEFS = [
    {
      name: 'run_javascript',
      group: '실행',
      description:
        '격리된 Web Worker 안에서 JavaScript 를 실행하고 반환값과 console.log 출력을 돌려준다. ' +
        '계산, 데이터 변환, 알고리즘 검증에 사용한다. DOM·네트워크·저장소에는 접근할 수 없다. ' +
        '최상위 await 사용 가능. 마지막에 return 으로 값을 돌려줄 것.',
      input_schema: {
        type: 'object',
        properties: {
          code: { type: 'string', description: '실행할 JavaScript 코드 (함수 본문으로 감싸여 실행됨)' },
        },
        required: ['code'],
      },
      async run(input) {
        var code = String(input.code || '');
        if (!code.trim()) throw new Error('code 가 비어 있습니다.');
        var out = await runInWorker(code, 8000);
        var lines = [];
        if (out.logs && out.logs.length) lines.push('[console]\n' + out.logs.join('\n'));
        if (out.ok) lines.push('[return]\n' + (out.result === undefined ? 'undefined' : out.result));
        else lines.push('[error]\n' + out.error);
        return { content: clip(lines.join('\n\n')), is_error: !out.ok };
      },
    },

    {
      name: 'write_file',
      group: '파일',
      description:
        '가상 작업공간에 텍스트 파일을 저장한다(기존 파일은 덮어쓴다). ' +
        '브라우저 안에서만 존재하며 암호화되어 보관되고, 대화가 바뀌어도 유지된다.',
      input_schema: {
        type: 'object',
        properties: {
          path: { type: 'string', description: '파일 경로 (예: notes/plan.md)' },
          content: { type: 'string', description: '파일 전체 내용' },
        },
        required: ['path', 'content'],
      },
      async run(input) {
        var files = await loadFiles();
        var p = normPath(input.path);
        var content = String(input.content == null ? '' : input.content);
        if (content.length > 400000) throw new Error('파일이 너무 큽니다(400,000자 제한).');
        files[p] = content;
        await saveFiles(files);
        return { content: p + ' 저장 완료 (' + content.length + '자)' };
      },
    },

    {
      name: 'read_file',
      group: '파일',
      description: '가상 작업공간의 파일 내용을 읽는다.',
      input_schema: {
        type: 'object',
        properties: { path: { type: 'string', description: '읽을 파일 경로' } },
        required: ['path'],
      },
      async run(input) {
        var files = await loadFiles();
        var p = normPath(input.path);
        if (!(p in files)) {
          return { content: p + ' 파일이 없습니다. list_files 로 목록을 확인하세요.', is_error: true };
        }
        return { content: clip(files[p]) };
      },
    },

    {
      name: 'list_files',
      group: '파일',
      description: '가상 작업공간에 저장된 모든 파일 목록과 크기를 보여 준다.',
      input_schema: { type: 'object', properties: {} },
      async run() {
        var files = await loadFiles();
        var names = Object.keys(files).sort();
        if (!names.length) return { content: '작업공간이 비어 있습니다.' };
        return {
          content: names
            .map(function (n) {
              return n + '  (' + files[n].length + '자)';
            })
            .join('\n'),
        };
      },
    },

    {
      name: 'delete_file',
      group: '파일',
      description: '가상 작업공간의 파일을 삭제한다.',
      input_schema: {
        type: 'object',
        properties: { path: { type: 'string', description: '삭제할 파일 경로' } },
        required: ['path'],
      },
      async run(input) {
        var files = await loadFiles();
        var p = normPath(input.path);
        if (!(p in files)) return { content: p + ' 파일이 없습니다.', is_error: true };
        delete files[p];
        await saveFiles(files);
        return { content: p + ' 삭제 완료' };
      },
    },

    {
      name: 'remember',
      group: '기억',
      description:
        '사용자에 대한 오래 남길 사실(선호, 배경, 진행 중인 작업 등)을 장기 기억에 적어 둔다. ' +
        '모든 대화에서 다시 꺼내 쓸 수 있다. 사용자가 명시적으로 알려 준 내용만 저장할 것.',
      input_schema: {
        type: 'object',
        properties: { note: { type: 'string', description: '기억할 한 문장' } },
        required: ['note'],
      },
      async run(input) {
        var note = String(input.note || '').trim();
        if (!note) throw new Error('note 가 비어 있습니다.');
        var list = await loadMemory();
        list.push({ id: CAI.crypto.randomId(6), text: note.slice(0, 500), ts: Date.now() });
        await saveMemory(list);
        return { content: '기억했습니다: ' + note.slice(0, 500) };
      },
    },

    {
      name: 'recall',
      group: '기억',
      description: '장기 기억에 저장된 내용을 모두 불러온다. 키워드를 주면 해당 항목만 거른다.',
      input_schema: {
        type: 'object',
        properties: { query: { type: 'string', description: '선택: 걸러낼 키워드' } },
      },
      async run(input) {
        var list = await loadMemory();
        var q = String((input && input.query) || '').trim().toLowerCase();
        if (q) {
          list = list.filter(function (m) {
            return m.text.toLowerCase().indexOf(q) >= 0;
          });
        }
        if (!list.length) return { content: '저장된 기억이 없습니다.' };
        return {
          content: clip(
            list
              .map(function (m) {
                return '- ' + m.text + '  (' + new Date(m.ts).toLocaleDateString('ko-KR') + ')';
              })
              .join('\n')
          ),
        };
      },
    },

    {
      name: 'fetch_url',
      group: '웹',
      description:
        'URL 을 GET 요청해 본문 텍스트를 가져온다. 브라우저에서 직접 호출하므로 ' +
        'CORS 를 허용하지 않는 사이트는 실패할 수 있다 — 실패하면 사용자에게 내용을 붙여넣어 달라고 요청할 것.',
      input_schema: {
        type: 'object',
        properties: {
          url: { type: 'string', description: 'https:// 로 시작하는 주소' },
        },
        required: ['url'],
      },
      async run(input) {
        var url = String(input.url || '').trim();
        if (!/^https?:\/\//i.test(url)) throw new Error('http(s):// 로 시작하는 주소가 필요합니다.');
        var res;
        try {
          res = await fetch(url, { redirect: 'follow' });
        } catch (e) {
          return {
            content:
              '가져오지 못했습니다 (CORS 차단이거나 네트워크 오류): ' +
              String(e.message || e) +
              '\n이 사이트는 브라우저에서 직접 읽을 수 없습니다.',
            is_error: true,
          };
        }
        if (!res.ok) return { content: 'HTTP ' + res.status + ' ' + res.statusText, is_error: true };
        var text = await res.text();
        var type = res.headers.get('content-type') || '';
        if (/html/i.test(type)) {
          var doc = new DOMParser().parseFromString(text, 'text/html');
          doc.querySelectorAll('script, style, noscript, svg').forEach(function (n) {
            n.remove();
          });
          text = (doc.body ? doc.body.innerText || doc.body.textContent : text) || text;
          text = text.replace(/\n{3,}/g, '\n\n').trim();
        }
        return { content: clip(text) };
      },
    },

    {
      name: 'show_artifact',
      group: '출력',
      description:
        '오른쪽 미리보기 패널에 결과물을 렌더링한다. 완성된 HTML 페이지·SVG·마크다운 문서처럼 ' +
        '사용자가 눈으로 봐야 하는 산출물에 사용한다. 대화 본문에 코드를 또 붙여넣지 말 것.',
      input_schema: {
        type: 'object',
        properties: {
          title: { type: 'string', description: '결과물 제목' },
          kind: {
            type: 'string',
            description: '결과물 종류',
            enum: ['html', 'svg', 'markdown', 'text'],
          },
          content: { type: 'string', description: '결과물 전체 내용' },
        },
        required: ['title', 'kind', 'content'],
      },
      async run(input, ctx) {
        var payload = {
          title: String(input.title || '결과물'),
          kind: String(input.kind || 'html'),
          content: String(input.content || ''),
        };
        if (ctx && typeof ctx.onArtifact === 'function') ctx.onArtifact(payload);
        return { content: '"' + payload.title + '" 을(를) 미리보기 패널에 렌더링했습니다.' };
      },
    },
  ];

  var byName = {};
  DEFS.forEach(function (d) {
    byName[d.name] = d;
  });

  /** 설정에서 꺼둔 도구를 제외한 스키마 목록 */
  function schemasFor(settings) {
    if (!settings || settings.toolsEnabled === false) return [];
    var off = settings.disabledTools || [];
    return DEFS.filter(function (d) {
      return off.indexOf(d.name) < 0;
    }).map(function (d) {
      return { name: d.name, description: d.description, input_schema: d.input_schema };
    });
  }

  async function execute(name, input, ctx) {
    var def = byName[name];
    if (!def) {
      return { content: '알 수 없는 도구입니다: ' + name, is_error: true };
    }
    try {
      var out = await def.run(input || {}, ctx || {});
      return { content: clip(out.content), is_error: !!out.is_error };
    } catch (e) {
      return { content: '도구 오류: ' + String((e && e.message) || e), is_error: true };
    }
  }

  CAI.tools = {
    defs: DEFS,
    byName: byName,
    schemasFor: schemasFor,
    execute: execute,
    loadFiles: loadFiles,
    loadMemory: loadMemory,
    saveMemory: saveMemory,
  };
})(window);
