/*!
 * cai/js/app.js — UI 컨트롤러
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});
  var md = CAI.markdown;

  function $(id) { return document.getElementById(id); }
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  var state = {
    settings: null,
    session: null,
    index: [],
    running: false,
    abort: null,
    live: null,       // 진행 중인 assistant 메시지 DOM
    artifact: null,
    toolNodes: {},
  };

  // ───────────────────────────────────────── 토스트

  var toastTimer = null;
  function toast(message, bad) {
    var node = $('toast');
    node.textContent = message;
    node.className = 'toast' + (bad ? ' bad' : '');
    node.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { node.hidden = true; }, bad ? 6000 : 2600);
  }

  function errorText(e) {
    if (!e) return '알 수 없는 오류';
    if (e.name === 'AbortError') return '중단되었습니다.';
    return String(e.message || e);
  }

  // ───────────────────────────────────────── 로그인 화면

  var authMode = 'login';

  function setAuthMode(mode) {
    authMode = mode;
    Array.prototype.forEach.call(document.querySelectorAll('[data-auth-tab]'), function (b) {
      b.classList.toggle('is-active', b.dataset.authTab === mode);
    });
    $('authConfirmField').hidden = mode !== 'signup';
    $('authPass').setAttribute('autocomplete', mode === 'signup' ? 'new-password' : 'current-password');
    $('authSubmit').textContent = mode === 'signup' ? '계정 만들기' : '로그인';
    $('authError').hidden = true;
  }

  function authError(message) {
    var node = $('authError');
    node.textContent = message;
    node.hidden = false;
  }

  function wireAuth() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-auth-tab]'), function (b) {
      b.addEventListener('click', function () { setAuthMode(b.dataset.authTab); });
    });

    $('authForm').addEventListener('submit', async function (e) {
      e.preventDefault();
      var user = $('authUser').value;
      var pass = $('authPass').value;
      var btn = $('authSubmit');
      $('authError').hidden = true;

      if (authMode === 'signup' && pass !== $('authPass2').value) {
        authError('비밀번호가 서로 다릅니다.');
        return;
      }

      btn.disabled = true;
      btn.textContent = '처리 중…';
      try {
        if (authMode === 'signup') await CAI.auth.signup(user, pass);
        else await CAI.auth.login(user, pass);
        $('authPass').value = '';
        $('authPass2').value = '';
        await enterApp();
      } catch (err) {
        authError(errorText(err));
      } finally {
        btn.disabled = false;
        btn.textContent = authMode === 'signup' ? '계정 만들기' : '로그인';
      }
    });

    var last = CAI.auth.lastUser();
    if (last) $('authUser').value = last;

    CAI.store.listAccounts().then(function (accounts) {
      if (!accounts.length) setAuthMode('signup');
    }).catch(function () {});
  }

  // ───────────────────────────────────────── 앱 진입

  async function enterApp() {
    state.settings = CAI.auth.settings();
    // 예전 계정이 더 이상 없는 하네스 ID 를 갖고 있으면 기본값으로 되돌린다.
    if (!CAI.harness.byId[state.settings.harnessId]) state.settings.harnessId = 'cai-redteam';
    if (!state.settings.team) state.settings.team = { mode: 'solo', goal: '', rounds: 1, members: [] };
    $('authScreen').hidden = true;
    $('app').hidden = false;
    $('whoami').textContent = CAI.auth.username();

    populateProviders();
    populateHarnessSelect();
    populateModels();
    syncComposerNotice();
    syncModeUI();
    buildSettingsUI();

    $('footState').textContent = IDLE_HINT;

    await refreshSessionList();
    if (state.index.length) {
      await openSession(state.index[0].id);
    } else {
      newSession();
    }
    $('input').focus();
  }

  function leaveApp() {
    if (state.abort) state.abort.abort();
    CAI.auth.logout();
    state.session = null;
    state.settings = null;
    $('app').hidden = true;
    $('authScreen').hidden = false;
    $('messages').innerHTML = '';
    setAuthMode('login');
  }

  // ───────────────────────────────────────── 상단바

  function populateProviders() {
    var sel = $('providerSelect');
    sel.innerHTML = '';
    CAI.providers.list().forEach(function (p) {
      var o = el('option', null, p.label);
      o.value = p.id;
      sel.appendChild(o);
    });
    sel.value = state.settings.provider;
  }

  function populateHarnessSelect() {
    var sel = $('harnessSelect');
    sel.innerHTML = '';
    CAI.harness.presets.forEach(function (p) {
      var o = el('option', null, p.label);
      o.value = p.id;
      sel.appendChild(o);
    });
    sel.value = state.settings.harnessId;
  }

  function modelOptionsFor(providerId) {
    var provider = CAI.providers.get(providerId);
    var cached = (state.settings.modelCache && state.settings.modelCache[providerId]) || [];
    var list = cached.length
      ? cached.slice()
      : provider.fallbackModels.map(function (id) { return { id: id, label: id }; });
    var current = (state.settings.models && state.settings.models[providerId]) || '';
    var has = list.some(function (m) { return m.id === current; });
    if (current && !has) list.unshift({ id: current, label: current + ' (직접 입력)' });
    return list;
  }

  function populateModels() {
    var providerId = state.settings.provider;
    var sel = $('modelSelect');
    sel.innerHTML = '';
    modelOptionsFor(providerId).forEach(function (m) {
      var o = el('option', null, m.label || m.id);
      o.value = m.id;
      sel.appendChild(o);
    });
    var custom = el('option', null, '＋ 직접 입력…');
    custom.value = '__custom__';
    sel.appendChild(custom);
    sel.value = state.settings.models[providerId] || '';
    if (!sel.value && sel.options.length) {
      sel.selectedIndex = 0;
      state.settings.models[providerId] = sel.value;
    }
  }

  function syncComposerNotice() {
    var providerId = state.settings.provider;
    var provider = CAI.providers.get(providerId);
    var key = state.settings.keys[providerId];
    var notice = $('composerNotice');
    if (key) {
      notice.hidden = true;
      return;
    }
    notice.innerHTML = '';
    notice.appendChild(document.createTextNode(provider.label + ' API 키가 없습니다.'));
    var btn = el('button', 'link-btn', '설정 열기 →');
    btn.type = 'button';
    btn.addEventListener('click', function () { openSettings('keys'); });
    notice.appendChild(btn);
    notice.hidden = false;
  }

  function updateUsage() {
    var u = (state.session && state.session.usage) || { input: 0, output: 0 };
    $('usageBadge').textContent = u.input || u.output ? '↑' + u.input.toLocaleString() + ' ↓' + u.output.toLocaleString() : '';
  }

  var saveTimer = null;
  function saveSettingsSoon() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      CAI.auth.saveSettings().catch(function (e) { toast(errorText(e), true); });
    }, 300);
  }

  // ───────────────────────────────────────── 메시지 렌더링

  function nearBottom() {
    var m = $('messages');
    return m.scrollHeight - m.scrollTop - m.clientHeight < 140;
  }
  function scrollDown(force) {
    var m = $('messages');
    if (force || nearBottom()) m.scrollTop = m.scrollHeight;
  }

  function msgShell(role, label) {
    var wrap = el('div', 'msg ' + role);
    var avatar = el('div', 'msg-avatar', role === 'user' ? '나' : role === 'error' ? '!' : 'AI');
    var body = el('div', 'msg-body');
    if (label) body.appendChild(el('div', 'msg-role', label));
    var content = el('div', 'msg-content');
    body.appendChild(content);
    wrap.appendChild(avatar);
    wrap.appendChild(body);
    wrap._content = content;
    wrap._body = body;
    return wrap;
  }

  function appendUser(text) {
    var node = msgShell('user', null);
    node._content.innerHTML = md.render(text);
    $('messages').appendChild(node);
    scrollDown(true);
    return node;
  }

  function appendError(message, onRetry) {
    var node = msgShell('error', '오류');
    node._content.textContent = message;
    if (onRetry) {
      var actions = el('div', 'msg-actions');
      var retry = el('button', 'link-btn', '다시 시도');
      retry.type = 'button';
      retry.addEventListener('click', onRetry);
      actions.appendChild(retry);
      node._body.appendChild(actions);
    }
    $('messages').appendChild(node);
    scrollDown(true);
    return node;
  }

  function providerLabel() {
    var p = CAI.providers.all[state.settings.provider];
    return (p ? p.short : state.settings.provider) + ' · ' + (state.settings.models[state.settings.provider] || '');
  }

  function startAssistant(label) {
    var node = msgShell('assistant', label || providerLabel());
    node._content.remove();          // 블록들을 직접 붙인다
    node._blocks = node._body;
    $('messages').appendChild(node);
    return node;
  }

  function textBlock(parent) {
    var block = el('div', 'msg-content');
    parent._blocks.appendChild(block);
    return block;
  }

  function thinkingBlock(parent) {
    var d = el('details', 'thinking-box');
    var s = el('summary');
    s.appendChild(el('span', null, '💭 추론 과정'));
    d.appendChild(s);
    var pre = el('pre');
    d.appendChild(pre);
    parent._blocks.appendChild(d);
    d._pre = pre;
    return d;
  }

  function toolBlock(parent, name, input) {
    var d = el('details', 'tool-call');
    var s = el('summary');
    s.appendChild(el('span', 'spinner'));
    s.appendChild(el('span', 't-name', name));
    var status = el('span', 't-status', '실행 중…');
    s.appendChild(status);
    d.appendChild(s);

    d.appendChild(el('span', 't-label', '입력'));
    var inPre = el('pre');
    try { inPre.textContent = JSON.stringify(input, null, 2); }
    catch (e) { inPre.textContent = String(input); }
    d.appendChild(inPre);

    parent._blocks.appendChild(d);
    d._status = status;
    d._summary = s;
    return d;
  }

  function finishToolBlock(d, content, isError) {
    var spinner = d._summary.querySelector('.spinner');
    if (spinner) spinner.replaceWith(el('span', null, isError ? '⚠️' : '✔'));
    d._status.textContent = isError ? '실패' : '완료';
    if (isError) d.classList.add('is-error');
    d.appendChild(el('span', 't-label', '결과'));
    var pre = el('pre');
    pre.textContent = content;
    d.appendChild(pre);
  }

  function assistantActions(node, text) {
    var actions = el('div', 'msg-actions');
    var copy = el('button', 'link-btn', '복사');
    copy.type = 'button';
    copy.addEventListener('click', function () {
      copyText(text, copy);
    });
    actions.appendChild(copy);

    var again = el('button', 'link-btn', '다시 생성');
    again.type = 'button';
    again.addEventListener('click', regenerate);
    actions.appendChild(again);

    node._blocks.appendChild(actions);
  }

  function copyText(text, button) {
    var done = function () {
      if (!button) return;
      var old = button.textContent;
      button.textContent = '복사됨';
      setTimeout(function () { button.textContent = old; }, 1200);
    };

    // 클립보드 권한이 없거나 비보안 컨텍스트면 execCommand 로 되돌아간다.
    var legacy = function () {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      ta.remove();
      if (ok) done();
      else toast('복사에 실패했습니다. 직접 선택해 복사해 주세요.', true);
    };

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, legacy);
    } else {
      legacy();
    }
  }

  // 저장된 대화를 화면에 복원
  function renderHistory() {
    var box = $('messages');
    box.innerHTML = '';
    var messages = (state.session && state.session.messages) || [];

    if (!messages.length) {
      box.appendChild(emptyState());
      updateUsage();
      return;
    }

    // 도구를 여러 번 부른 한 번의 턴은 저장할 때 여러 메시지로 쪼개진다.
    // 화면에서는 스트리밍 때와 똑같이 하나의 말풍선으로 다시 합친다.
    var pending = {};
    var turn = null;      // 이어붙이는 중인 assistant 노드
    var turnText = '';    // 그 턴의 마지막 텍스트 (복사/재생성 버튼용)

    function closeTurn() {
      if (turn && turnText) assistantActions(turn, turnText);
      turn = null;
      turnText = '';
    }

    messages.forEach(function (m) {
      var parts = Array.isArray(m.content) ? m.content : [];

      if (m.role === 'user') {
        parts.forEach(function (p) {
          if (p.type !== 'tool_result') return;
          var node = pending[p.tool_use_id];
          if (node) finishToolBlock(node, p.content, p.is_error);
        });
        var text = parts.filter(function (p) { return p.type === 'text'; })
          .map(function (p) { return p.text; }).join('\n').trim();
        if (text) {
          // 사용자가 새로 말했다면 앞선 턴은 끝난 것이다.
          closeTurn();
          appendUser(text);
        }
        return;
      }

      // 팀 조원의 발언은 각자 색깔 있는 말풍선으로 복원한다.
      if (m.agent) {
        closeTurn();
        var mtext = parts.filter(function (p) { return p.type === 'text'; })
          .map(function (p) { return p.text; }).join('\n');
        var bubble = startMemberBubble({
          name: m.agent.name, provider: m.agent.provider,
          model: m.agent.model || '', color: m.agent.color,
        });
        bubble._content.innerHTML = md.render(mtext);
        return;
      }

      if (!turn) turn = startAssistant();
      if (m.thinking) {
        var think = thinkingBlock(turn);
        think._pre.textContent = m.thinking;
      }
      parts.forEach(function (p) {
        if (p.type === 'text') {
          if (!p.text) return;
          turnText = p.text;
          textBlock(turn).innerHTML = md.render(p.text);
        } else if (p.type === 'tool_use') {
          pending[p.id] = toolBlock(turn, p.name, p.input);
        }
      });
    });
    closeTurn();

    // 팀 세션이면 이어서 토론할 수 있는 버튼을 남긴다.
    if (state.session && state.session.isTeam && isTeamMode()) teamContinueBar();

    updateUsage();
    scrollDown(true);
  }

  var STARTERS = [
    { t: '접근 방법 잡기', p: '내 CTF 챌린지야. nmap 결과를 붙여넣을 테니, 정찰 관점에서 뭘 먼저 파고들지 우선순위를 잡아 줘.' },
    { t: '크립토 풀이', p: '이 문자열이 어떤 인코딩/암호인지 판별하고 run_javascript 로 디코딩해서 플래그를 찾아 줘: (여기에 붙여넣기)' },
    { t: 'pwn 분석', p: 'checksec 출력과 디스어셈블을 붙여넣을게. 보호기법을 정리하고 어떤 익스플로잇 기법이 가능한지 짚어 줘.' },
    { t: '팀으로 공략', p: '상단 👥 팀 모드로 바꾸고, 등록한 조원들과 이 웹 챌린지를 역할 나눠 함께 토론해 줘.' },
  ];

  function emptyState() {
    var wrap = el('div', 'empty-state');
    wrap.appendChild(el('div', 'es-logo', '🧩'));
    wrap.appendChild(el('h2', null, '무엇을 도와드릴까요?'));
    var p = el('p', null);
    p.innerHTML =
      '현재 <b>' + md.escapeHtml(providerLabel()) + '</b> 위에서 <b>' +
      md.escapeHtml((CAI.harness.byId[state.settings.harnessId] || {}).label || '') +
      '</b> 하네스로 동작합니다.';
    wrap.appendChild(p);

    var grid = el('div', 'starter-grid');
    STARTERS.forEach(function (s) {
      var b = el('button', 'starter');
      b.type = 'button';
      b.appendChild(el('b', null, s.t));
      b.appendChild(el('span', null, s.p));
      b.addEventListener('click', function () {
        $('input').value = s.p;
        autoGrow();
        send();
      });
      grid.appendChild(b);
    });
    wrap.appendChild(grid);
    return wrap;
  }

  // ───────────────────────────────────────── 전송

  var IDLE_HINT = 'Enter 전송 · Shift+Enter 줄바꿈 · Ctrl/⌘+K 새 대화';

  function setRunning(on) {
    state.running = on;
    $('sendBtn').hidden = on;
    $('stopBtn').hidden = !on;
    $('input').disabled = false;
    $('footState').textContent = on ? '응답 생성 중… (■ 를 누르면 중단)' : IDLE_HINT;
  }

  function isTeamMode() {
    var team = state.settings.team;
    return !!(team && team.mode === 'team' && (team.members || []).length);
  }

  async function send() {
    if (state.running) return;
    var box = $('input');
    var text = box.value.trim();
    if (!text) return;

    if (isTeamMode()) {
      box.value = '';
      autoGrow();
      var empty0 = $('messages').querySelector('.empty-state');
      if (empty0) empty0.remove();
      await runTeamTurn(text);
      return;
    }

    var providerId = state.settings.provider;
    if (!state.settings.keys[providerId]) {
      toast(CAI.providers.get(providerId).label + ' API 키를 먼저 입력해 주세요.', true);
      openSettings('keys');
      return;
    }

    box.value = '';
    autoGrow();
    var empty = $('messages').querySelector('.empty-state');
    if (empty) empty.remove();

    await runTurn(text);
  }

  async function regenerate() {
    if (state.running) return;
    var messages = state.session.messages;
    // 마지막 사용자 텍스트 메시지 뒤를 모두 지우고 다시 생성한다.
    var cut = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      var m = messages[i];
      if (m.role !== 'user') continue;
      var hasText = (m.content || []).some(function (p) { return p.type === 'text' && p.text; });
      if (hasText) { cut = i; break; }
    }
    if (cut < 0) { toast('다시 생성할 메시지가 없습니다.', true); return; }
    messages.length = cut + 1;
    state.session.usage = { input: 0, output: 0 };
    renderHistory();
    await runTurn(null);
  }

  async function runTurn(text) {
    setRunning(true);
    state.abort = new AbortController();

    if (text) appendUser(text);

    var node = startAssistant();
    state.live = node;
    var currentText = null;
    var currentThink = null;
    var frame = null;
    var buffered = '';

    function paint() {
      frame = null;
      if (currentText) currentText.innerHTML = md.render(buffered) + '<span class="cursor-blink"></span>';
      scrollDown(false);
    }

    function onEvent(ev) {
      if (ev.type === 'step_start') {
        currentText = null;
        currentThink = null;
        buffered = '';
      } else if (ev.type === 'text') {
        if (!currentText) currentText = textBlock(node);
        buffered = ev.text;
        if (!frame) frame = requestAnimationFrame(paint);
      } else if (ev.type === 'thinking') {
        if (!currentThink) currentThink = thinkingBlock(node);
        currentThink._pre.textContent = ev.text;
        scrollDown(false);
      } else if (ev.type === 'tool_start') {
        if (frame) { cancelAnimationFrame(frame); frame = null; }
        if (currentText) currentText.innerHTML = md.render(buffered);
        state.toolNodes[ev.id] = toolBlock(node, ev.name, ev.input);
        scrollDown(false);
      } else if (ev.type === 'tool_end') {
        var t = state.toolNodes[ev.id];
        if (t) finishToolBlock(t, ev.content, ev.is_error);
        delete state.toolNodes[ev.id];
        scrollDown(false);
      } else if (ev.type === 'usage') {
        updateUsage();
      }
    }

    try {
      await CAI.agent.run({
        session: state.session,
        settings: state.settings,
        text: text || undefined,
        onEvent: onEvent,
        onArtifact: showArtifact,
        signal: state.abort.signal,
      });

      if (frame) cancelAnimationFrame(frame);
      if (currentText) currentText.innerHTML = md.render(buffered);
      if (buffered) assistantActions(node, buffered);
      else if (!node._blocks.querySelector('.tool-call')) node.remove();

      await CAI.sessions.save(state.session);
      await refreshSessionList();
    } catch (err) {
      if (frame) cancelAnimationFrame(frame);
      if (currentText) currentText.innerHTML = md.render(buffered);
      if (!buffered && !node._blocks.querySelector('.tool-call')) node.remove();

      if (err && err.name === 'AbortError') {
        $('footState').textContent = '중단됨';
        setTimeout(function () {
          if (!state.running) $('footState').textContent = IDLE_HINT;
        }, 2000);
      } else {
        appendError(errorText(err), function () { runTurn(null); });
      }
      try { await CAI.sessions.save(state.session); } catch (e) {}
    } finally {
      state.live = null;
      state.abort = null;
      setRunning(false);
      updateUsage();
      $('input').focus();
    }
  }

  // ───────────────────────────────────────── 팀(레드팀 조별과제) 턴

  function startMemberBubble(member) {
    var node = el('div', 'msg assistant member');
    var avatar = el('div', 'msg-avatar', (member.name || '?').slice(0, 2));
    avatar.style.background = member.color || '#5b9dff';
    avatar.style.color = '#0f1226';
    var body = el('div', 'msg-body');
    var prov = CAI.providers.all[member.provider];
    var role = el('div', 'msg-role');
    role.innerHTML = '<b style="color:' + (member.color || '#5b9dff') + '">' + md.escapeHtml(member.name) +
      '</b> · ' + md.escapeHtml((prov ? prov.short : member.provider) + ' · ' + member.model);
    body.appendChild(role);
    var content = el('div', 'msg-content');
    body.appendChild(content);
    node.appendChild(avatar);
    node.appendChild(body);
    node._content = content;
    $('messages').appendChild(node);
    scrollDown(true);
    return node;
  }

  function teamContinueBar() {
    var old = $('messages').querySelector('.team-continue');
    if (old) old.remove();
    var bar = el('div', 'team-continue');
    var btn = el('button', 'btn', '🔁 한 라운드 더 토론');
    btn.type = 'button';
    btn.addEventListener('click', function () { bar.remove(); runTeamTurn(null); });
    bar.appendChild(btn);
    $('messages').appendChild(bar);
    scrollDown(true);
  }

  async function runTeamTurn(text) {
    setRunning(true);
    state.abort = new AbortController();
    var oldBar = $('messages').querySelector('.team-continue');
    if (oldBar) oldBar.remove();

    if (text) appendUser(text);

    var current = null;      // 현재 발언 조원 DOM
    var buffered = '';
    var frame = null;
    function paint() {
      frame = null;
      if (current) current._content.innerHTML = md.render(buffered) + '<span class="cursor-blink"></span>';
      scrollDown(false);
    }

    function onEvent(ev) {
      if (ev.type === 'member_start') {
        buffered = '';
        current = startMemberBubble(ev.member);
      } else if (ev.type === 'text') {
        buffered = ev.text;
        if (!frame) frame = requestAnimationFrame(paint);
      } else if (ev.type === 'member_done') {
        if (frame) { cancelAnimationFrame(frame); frame = null; }
        if (current) current._content.innerHTML = md.render(buffered);
        current = null;
      } else if (ev.type === 'usage') {
        updateUsage();
      }
    }

    try {
      await CAI.agent.runTeam({
        session: state.session,
        settings: state.settings,
        text: text || undefined,
        onEvent: onEvent,
        signal: state.abort.signal,
      });
      await CAI.sessions.save(state.session);
      await refreshSessionList();
      teamContinueBar();
    } catch (err) {
      if (frame) cancelAnimationFrame(frame);
      if (current && buffered) current._content.innerHTML = md.render(buffered);
      else if (current) current.remove();
      if (err && err.name === 'AbortError') {
        $('footState').textContent = '중단됨';
        setTimeout(function () { if (!state.running) $('footState').textContent = IDLE_HINT; }, 2000);
      } else {
        appendError(errorText(err), null);
      }
      try { await CAI.sessions.save(state.session); } catch (e) {}
    } finally {
      state.abort = null;
      setRunning(false);
      updateUsage();
      $('input').focus();
    }
  }

  // 모드(1:1 / 팀) 토글 UI 동기화
  function syncModeUI() {
    var team = state.settings.team || {};
    var isTeam = team.mode === 'team';
    var toggle = $('modeToggle');
    if (toggle) {
      Array.prototype.forEach.call(toggle.querySelectorAll('[data-mode]'), function (b) {
        b.classList.toggle('is-active', (b.dataset.mode === 'team') === isTeam);
      });
    }
    var count = (team.members || []).length;
    var badge = $('teamBadge');
    if (badge) {
      if (isTeam) { badge.textContent = '👥 팀 ' + count + '명'; badge.hidden = false; }
      else badge.hidden = true;
    }
    var input = $('input');
    if (input) {
      input.placeholder = isTeam
        ? (count ? '팀에게 과제를 던지세요 — 조원들이 함께 토론합니다' : '⚙️ 설정 → 팀 에서 조원을 먼저 추가하세요')
        : '메시지를 입력하세요';
    }
  }

  function setMode(mode) {
    if (!state.settings.team) state.settings.team = { mode: 'solo', goal: '', rounds: 1, members: [] };
    if (mode === 'team' && !(state.settings.team.members || []).length) {
      toast('팀에 조원이 없습니다. 설정에서 추가하거나 자동 구성하세요.');
      openSettings('team');
      state.settings.team.mode = 'team';
    } else {
      state.settings.team.mode = mode;
    }
    saveSettingsSoon();
    syncModeUI();
  }

  // ───────────────────────────────────────── 세션

  function newSession() {
    state.session = CAI.sessions.create(state.settings);
    renderHistory();
    highlightSession();
  }

  async function openSession(id) {
    var s = await CAI.sessions.load(id);
    if (!s) { toast('대화를 열지 못했습니다.', true); return; }
    state.session = s;
    if (s.provider && CAI.providers.all[s.provider]) {
      state.settings.provider = s.provider;
      if (s.model) state.settings.models[s.provider] = s.model;
      $('providerSelect').value = s.provider;
      populateModels();
      syncComposerNotice();
    }
    if (s.harnessId && CAI.harness.byId[s.harnessId]) {
      state.settings.harnessId = s.harnessId;
      $('harnessSelect').value = s.harnessId;
    }
    renderHistory();
    highlightSession();
    closeDrawer();
  }

  async function refreshSessionList() {
    state.index = await CAI.sessions.list();
    renderSessionList();
  }

  function renderSessionList() {
    var box = $('sessionList');
    var query = ($('sessionSearch').value || '').trim().toLowerCase();
    var rows = query
      ? state.index.filter(function (s) { return (s.title || '').toLowerCase().indexOf(query) >= 0; })
      : state.index;

    box.innerHTML = '';
    if (!rows.length) {
      box.appendChild(el('div', 'session-empty', query ? '검색 결과가 없습니다.' : '저장된 대화가 없습니다.\n첫 메시지를 보내면 자동 저장됩니다.'));
      return;
    }

    rows.forEach(function (s) {
      var item = el('button', 'session-item');
      item.type = 'button';
      item.dataset.id = s.id;
      item.appendChild(el('span', 's-title', s.title || '제목 없음'));
      var provider = CAI.providers.all[s.provider];
      item.appendChild(el('span', 's-meta',
        relTime(s.updatedAt) + ' · ' + (provider ? provider.short : s.provider || '?') + ' · ' + s.count + '개'));

      var del = el('button', 's-del', '✕');
      del.type = 'button';
      del.title = '삭제';
      del.addEventListener('click', async function (e) {
        e.stopPropagation();
        if (!confirm('"' + (s.title || '이 대화') + '" 을(를) 삭제할까요? 되돌릴 수 없습니다.')) return;
        await CAI.sessions.remove(s.id);
        await refreshSessionList();
        if (state.session && state.session.id === s.id) newSession();
      });
      item.appendChild(del);

      item.addEventListener('click', function () { openSession(s.id); });
      box.appendChild(item);
    });
    highlightSession();
  }

  function highlightSession() {
    var id = state.session && state.session.id;
    Array.prototype.forEach.call($('sessionList').querySelectorAll('.session-item'), function (n) {
      n.classList.toggle('is-active', n.dataset.id === id);
    });
  }

  function relTime(ts) {
    var diff = Date.now() - (ts || 0);
    var min = Math.floor(diff / 60000);
    if (min < 1) return '방금';
    if (min < 60) return min + '분 전';
    var hr = Math.floor(min / 60);
    if (hr < 24) return hr + '시간 전';
    var day = Math.floor(hr / 24);
    if (day < 7) return day + '일 전';
    return new Date(ts).toLocaleDateString('ko-KR', { month: 'numeric', day: 'numeric' });
  }

  // ───────────────────────────────────────── 미리보기

  function showArtifact(payload) {
    state.artifact = payload;
    var pane = $('previewPane');
    var body = $('previewBody');
    $('previewTitle').textContent = payload.title || '미리보기';
    body.innerHTML = '';

    if (payload.kind === 'html' || payload.kind === 'svg') {
      var frame = document.createElement('iframe');
      frame.setAttribute('sandbox', 'allow-scripts allow-modals allow-popups');
      frame.srcdoc = payload.kind === 'svg'
        ? '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;height:100%;display:grid;place-items:center;background:#fff}svg{max-width:100%;max-height:100%}</style>' + payload.content
        : payload.content;
      body.appendChild(frame);
      $('previewOpen').hidden = false;
    } else if (payload.kind === 'markdown') {
      var doc = el('div', 'preview-doc msg-content');
      doc.innerHTML = md.render(payload.content);
      body.appendChild(doc);
      $('previewOpen').hidden = true;
    } else {
      var pre = el('pre');
      pre.textContent = payload.content;
      body.appendChild(pre);
      $('previewOpen').hidden = true;
    }
    pane.hidden = false;
  }

  function togglePreview() {
    var pane = $('previewPane');
    if (!pane.hidden) { pane.hidden = true; return; }
    if (!state.artifact) {
      $('previewTitle').textContent = '미리보기';
      $('previewBody').innerHTML = '';
      $('previewBody').appendChild(el('div', 'preview-empty',
        '아직 표시할 결과물이 없습니다.\n모델이 show_artifact 도구를 쓰면 여기에 나타납니다.'));
      $('previewOpen').hidden = true;
    }
    pane.hidden = false;
  }

  // ───────────────────────────────────────── 설정

  function openSettings(tab) {
    // 설정은 모달 밖(상단바 · 세션 전환)에서도 바뀌므로 열 때마다 값을 다시 채운다.
    buildSettingsUI();
    $('settingsModal').hidden = false;
    if (tab) selectSettingsTab(tab);
    refreshWorkspacePanels();
  }
  function closeSettings() {
    $('settingsModal').hidden = true;
    // 설정 안에서 키·모델이 바뀌었을 수 있으므로 상단바와 안내 배너를 맞춘다.
    populateModels();
    syncComposerNotice();
  }

  function selectSettingsTab(tab) {
    Array.prototype.forEach.call(document.querySelectorAll('.modal-tab'), function (b) {
      b.classList.toggle('is-active', b.dataset.tab === tab);
    });
    Array.prototype.forEach.call(document.querySelectorAll('.tab-panel'), function (p) {
      p.classList.toggle('is-active', p.dataset.panel === tab);
    });
  }

  function buildSettingsUI() {
    // --- API 키 ---
    var box = $('keyFields');
    box.innerHTML = '';
    CAI.providers.list().forEach(function (provider) {
      var row = el('div', 'key-row');

      var head = el('div', 'key-head');
      head.appendChild(el('b', null, provider.label));
      var link = el('a', null, '키 발급 ↗');
      link.href = provider.keysUrl;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      head.appendChild(link);
      row.appendChild(head);

      var inputRow = el('div', 'key-input-row');
      var input = document.createElement('input');
      input.type = 'password';
      input.placeholder = provider.keyPlaceholder;
      input.autocomplete = 'off';
      input.spellcheck = false;
      input.value = state.settings.keys[provider.id] || '';
      inputRow.appendChild(input);

      var eye = el('button', 'btn', '👁');
      eye.type = 'button';
      eye.title = '표시 / 숨김';
      eye.addEventListener('click', function () {
        input.type = input.type === 'password' ? 'text' : 'password';
      });
      inputRow.appendChild(eye);

      var test = el('button', 'btn', '확인');
      test.type = 'button';
      inputRow.appendChild(test);
      row.appendChild(inputRow);

      var stateLine = el('div', 'key-state');
      row.appendChild(stateLine);

      input.addEventListener('input', function () {
        state.settings.keys[provider.id] = input.value.trim();
        saveSettingsSoon();
        syncComposerNotice();
        stateLine.className = 'key-state';
        stateLine.textContent = '';
      });

      test.addEventListener('click', async function () {
        var key = input.value.trim();
        if (!key) { stateLine.className = 'key-state bad'; stateLine.textContent = '키를 입력해 주세요.'; return; }
        stateLine.className = 'key-state busy';
        stateLine.textContent = '확인 중…';
        test.disabled = true;
        try {
          var models = await provider.listModels(key, state.settings.baseUrls[provider.id]);
          state.settings.modelCache[provider.id] = models;
          state.settings.keys[provider.id] = key;
          if (!state.settings.models[provider.id] && models.length) {
            state.settings.models[provider.id] = models[0].id;
          }
          await CAI.auth.saveSettings();
          stateLine.className = 'key-state ok';
          stateLine.textContent = '✔ 연결됨 — 모델 ' + models.length + '개를 불러왔습니다.';
          if (state.settings.provider === provider.id) populateModels();
          syncComposerNotice();
        } catch (e) {
          stateLine.className = 'key-state bad';
          stateLine.textContent = '✕ ' + errorText(e);
        } finally {
          test.disabled = false;
        }
      });

      box.appendChild(row);
    });

    // --- 생성 파라미터 ---
    $('tempInput').value = state.settings.temperature;
    $('tempValue').textContent = state.settings.temperature;
    $('maxTokensInput').value = state.settings.maxTokens;
    $('maxStepsInput').value = state.settings.maxSteps;
    $('userNameInput').value = state.settings.userName || '';

    // --- 하네스 ---
    var preset = $('harnessPreset');
    preset.innerHTML = '';
    CAI.harness.presets.forEach(function (p) {
      var o = el('option', null, p.label);
      o.value = p.id;
      preset.appendChild(o);
    });
    preset.value = state.settings.harnessId;
    syncHarnessPanel();

    // --- 도구 ---
    $('toolsEnabled').checked = state.settings.toolsEnabled !== false;
    var list = $('toolList');
    list.innerHTML = '';
    CAI.tools.defs.forEach(function (def) {
      var label = el('label', 'tool-row');
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = (state.settings.disabledTools || []).indexOf(def.name) < 0;
      cb.addEventListener('change', function () {
        var off = state.settings.disabledTools || [];
        var i = off.indexOf(def.name);
        if (cb.checked && i >= 0) off.splice(i, 1);
        if (!cb.checked && i < 0) off.push(def.name);
        state.settings.disabledTools = off;
        saveSettingsSoon();
      });
      label.appendChild(cb);
      var textWrap = el('div');
      textWrap.appendChild(el('b', null, def.name));
      textWrap.appendChild(el('span', null, def.description.split('.')[0] + '.'));
      label.appendChild(textWrap);
      list.appendChild(label);
    });

    // --- 팀 ---
    var team = state.settings.team || (state.settings.team = { mode: 'solo', goal: '', rounds: 1, members: [] });
    $('teamGoal').value = team.goal || '';
    $('teamRounds').value = team.rounds || 1;
    renderTeamRoster();
  }

  // ───────────────────────────────────────── 팀 로스터 설정

  var MEMBER_COLORS = ['#5b9dff', '#4dd0a7', '#ff9f6b', '#c98bff', '#ffd24c', '#ff7fb6', '#6be8ff', '#ff6b6b'];

  function teamMembers() {
    var team = state.settings.team || (state.settings.team = { mode: 'solo', goal: '', rounds: 1, members: [] });
    if (!Array.isArray(team.members)) team.members = [];
    return team.members;
  }

  function providerModelOptions(providerId) {
    return modelOptionsFor(providerId);
  }

  function renderTeamRoster() {
    var box = $('teamRoster');
    box.innerHTML = '';
    var members = teamMembers();

    if (!members.length) {
      box.appendChild(el('div', 'fs-empty', '조원이 없습니다. 아래에서 추가하거나 “등록된 키로 자동 구성”을 누르세요.'));
    }

    members.forEach(function (m, idx) {
      var row = el('div', 'member-row');
      var dot = el('span', 'member-dot');
      dot.style.background = m.color || MEMBER_COLORS[idx % MEMBER_COLORS.length];
      row.appendChild(dot);

      var name = document.createElement('input');
      name.className = 'member-name';
      name.value = m.name || '';
      name.placeholder = '이름';
      name.addEventListener('input', function () { m.name = name.value; saveSettingsSoon(); });
      row.appendChild(name);

      var prov = document.createElement('select');
      prov.className = 'member-select';
      CAI.providers.list().forEach(function (p) {
        var o = el('option', null, p.short); o.value = p.id; prov.appendChild(o);
      });
      prov.value = m.provider;
      row.appendChild(prov);

      var model = document.createElement('select');
      model.className = 'member-select member-model';
      function fillModels() {
        model.innerHTML = '';
        providerModelOptions(m.provider).forEach(function (mm) {
          var o = el('option', null, mm.label || mm.id); o.value = mm.id; model.appendChild(o);
        });
        if (m.model && !Array.prototype.some.call(model.options, function (o) { return o.value === m.model; })) {
          var o = el('option', null, m.model + ' (직접)'); o.value = m.model; model.appendChild(o);
        }
        model.value = m.model || (model.options[0] && model.options[0].value) || '';
        m.model = model.value;
      }
      fillModels();
      row.appendChild(model);

      prov.addEventListener('change', function () {
        m.provider = prov.value;
        m.model = (providerModelOptions(m.provider)[0] || {}).id || '';
        fillModels();
        saveSettingsSoon();
      });
      model.addEventListener('change', function () { m.model = model.value; saveSettingsSoon(); });

      var role = document.createElement('select');
      role.className = 'member-select member-role';
      CAI.harness.presets.forEach(function (p) {
        if (p.id === 'plain' || p.id === 'custom') return;
        var o = el('option', null, p.label); o.value = p.id; role.appendChild(o);
      });
      role.value = m.role || 'cai-redteam';
      role.addEventListener('change', function () { m.role = role.value; saveSettingsSoon(); });
      row.appendChild(role);

      var del = el('button', 'icon-btn member-del', '✕');
      del.type = 'button';
      del.title = '조원 삭제';
      del.addEventListener('click', function () {
        members.splice(idx, 1);
        saveSettingsSoon();
        renderTeamRoster();
      });
      row.appendChild(del);

      box.appendChild(row);
    });
  }

  function addMember(seed) {
    var members = teamMembers();
    var provider = (seed && seed.provider) || state.settings.provider;
    var color = MEMBER_COLORS[members.length % MEMBER_COLORS.length];
    var prov = CAI.providers.all[provider];
    members.push({
      id: 'mem_' + CAI.crypto.randomId(6),
      name: (seed && seed.name) || (prov ? prov.short : provider) + ' ' + (members.length + 1),
      provider: provider,
      model: (seed && seed.model) || (modelOptionsFor(provider)[0] || {}).id || '',
      role: (seed && seed.role) || 'cai-redteam',
      color: color,
      keyOverride: '',
    });
    saveSettingsSoon();
    renderTeamRoster();
  }

  // 등록된 키가 있는 제공자로 레드팀 역할을 나눠 자동 구성
  function autoBuildTeam() {
    var members = teamMembers();
    var roles = ['cai-web', 'cai-pwn', 'cai-crypto', 'cai-redteam'];
    var added = 0;
    CAI.providers.list().forEach(function (p) {
      if (!state.settings.keys[p.id]) return;
      var role = roles[members.length % roles.length];
      members.push({
        id: 'mem_' + CAI.crypto.randomId(6),
        name: p.short + ' · ' + CAI.harness.roleLabel(role),
        provider: p.id,
        model: state.settings.models[p.id] || (modelOptionsFor(p.id)[0] || {}).id || '',
        role: role,
        color: MEMBER_COLORS[members.length % MEMBER_COLORS.length],
        keyOverride: '',
      });
      added++;
    });
    if (!added) { toast('먼저 API 키를 하나 이상 등록하세요.', true); return; }
    saveSettingsSoon();
    renderTeamRoster();
    toast(added + '개 제공자로 팀을 구성했습니다.');
  }

  function syncHarnessPanel() {
    var id = $('harnessPreset').value;
    var preset = CAI.harness.byId[id];
    $('harnessDesc').textContent = preset ? preset.description : '';
    var area = $('harnessText');
    if (id === 'custom') {
      area.value = state.settings.harnessCustom || CAI.harness.core;
      area.readOnly = false;
    } else {
      area.value = preset ? preset.text : '';
      area.readOnly = true;
    }
  }

  async function refreshWorkspacePanels() {
    try {
      var files = await CAI.tools.loadFiles();
      var box = $('fsList');
      box.innerHTML = '';
      var names = Object.keys(files).sort();
      if (!names.length) {
        box.appendChild(el('div', 'fs-empty', '저장된 파일이 없습니다.'));
      } else {
        names.forEach(function (name) {
          var row = el('div', 'fs-row');
          var code = el('code', null, name + '  (' + files[name].length + '자)');
          row.appendChild(code);
          var view = el('button', 'link-btn', '보기');
          view.type = 'button';
          view.addEventListener('click', function () {
            showArtifact({ title: name, kind: /\.(md|markdown)$/i.test(name) ? 'markdown' : 'text', content: files[name] });
            closeSettings();
          });
          row.appendChild(view);
          var del = el('button', 'link-btn', '삭제');
          del.type = 'button';
          del.addEventListener('click', async function () {
            delete files[name];
            await CAI.auth.saveVault('files', files);
            refreshWorkspacePanels();
          });
          row.appendChild(del);
          box.appendChild(row);
        });
      }

      var memories = await CAI.tools.loadMemory();
      var mbox = $('memList');
      mbox.innerHTML = '';
      if (!memories.length) {
        mbox.appendChild(el('div', 'fs-empty', '저장된 기억이 없습니다.'));
      } else {
        memories.slice().reverse().forEach(function (m) {
          var row = el('div', 'fs-row');
          row.appendChild(el('code', null, m.text));
          var del = el('button', 'link-btn', '삭제');
          del.type = 'button';
          del.addEventListener('click', async function () {
            var next = (await CAI.tools.loadMemory()).filter(function (x) { return x.id !== m.id; });
            await CAI.tools.saveMemory(next);
            refreshWorkspacePanels();
          });
          row.appendChild(del);
          mbox.appendChild(row);
        });
      }
    } catch (e) {
      /* 로그인 전이면 무시 */
    }
  }

  // ───────────────────────────────────────── 내보내기 / 가져오기

  async function doExport() {
    try {
      var payload = await CAI.sessions.exportAll();
      var blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url;
      a.download = 'cai-harness-' + new Date().toISOString().slice(0, 10) + '.json';
      a.click();
      setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
      toast(payload.sessions.length + '개 대화를 내보냈습니다.');
    } catch (e) {
      toast(errorText(e), true);
    }
  }

  function doImport() { $('importFile').click(); }

  async function onImportFile(e) {
    var file = e.target.files && e.target.files[0];
    e.target.value = '';
    if (!file) return;
    try {
      var n = await CAI.sessions.importAll(JSON.parse(await file.text()));
      await refreshSessionList();
      toast(n + '개 대화를 가져왔습니다.');
    } catch (err) {
      toast(errorText(err), true);
    }
  }

  // ───────────────────────────────────────── 입력창

  function autoGrow() {
    var box = $('input');
    box.style.height = 'auto';
    box.style.height = Math.min(box.scrollHeight, 220) + 'px';
  }

  function openDrawer() { $('sidebar').classList.add('is-open'); $('scrim').hidden = false; }
  function closeDrawer() { $('sidebar').classList.remove('is-open'); $('scrim').hidden = true; }

  // ───────────────────────────────────────── 이벤트 배선

  function wireApp() {
    $('providerSelect').addEventListener('change', function (e) {
      state.settings.provider = e.target.value;
      populateModels();
      syncComposerNotice();
      saveSettingsSoon();
    });

    $('modelSelect').addEventListener('change', function (e) {
      var providerId = state.settings.provider;
      if (e.target.value === '__custom__') {
        var entered = prompt('모델 ID 를 직접 입력하세요', state.settings.models[providerId] || '');
        if (entered && entered.trim()) state.settings.models[providerId] = entered.trim();
        populateModels();
      } else {
        state.settings.models[providerId] = e.target.value;
      }
      saveSettingsSoon();
    });

    $('harnessSelect').addEventListener('change', function (e) {
      state.settings.harnessId = e.target.value;
      var preset = $('harnessPreset');
      if (preset) { preset.value = e.target.value; syncHarnessPanel(); }
      saveSettingsSoon();
    });

    $('settingsBtn').addEventListener('click', function () { openSettings(); });
    $('previewBtn').addEventListener('click', togglePreview);
    $('previewClose').addEventListener('click', function () { $('previewPane').hidden = true; });
    $('previewOpen').addEventListener('click', function () {
      if (!state.artifact) return;
      var blob = new Blob([state.artifact.content], { type: 'text/html' });
      var url = URL.createObjectURL(blob);
      global.open(url, '_blank', 'noopener');
      setTimeout(function () { URL.revokeObjectURL(url); }, 20000);
    });

    $('newChatBtn').addEventListener('click', function () { newSession(); closeDrawer(); $('input').focus(); });
    Array.prototype.forEach.call(document.querySelectorAll('#modeToggle [data-mode]'), function (b) {
      b.addEventListener('click', function () { setMode(b.dataset.mode); });
    });
    $('sessionSearch').addEventListener('input', renderSessionList);
    $('logoutBtn').addEventListener('click', leaveApp);
    $('exportBtn').addEventListener('click', doExport);
    $('exportBtn2').addEventListener('click', doExport);
    $('importBtn').addEventListener('click', doImport);
    $('importBtn2').addEventListener('click', doImport);
    $('importFile').addEventListener('change', onImportFile);

    $('menuBtn').addEventListener('click', openDrawer);
    $('scrim').addEventListener('click', closeDrawer);

    $('sendBtn').addEventListener('click', send);
    $('stopBtn').addEventListener('click', function () { if (state.abort) state.abort.abort(); });

    var input = $('input');
    input.addEventListener('input', autoGrow);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
        e.preventDefault();
        send();
      }
    });

    // 코드 블록 복사
    $('messages').addEventListener('click', function (e) {
      var btn = e.target.closest && e.target.closest('[data-copy]');
      if (!btn) return;
      var block = btn.closest('.code-block');
      var code = block && block.querySelector('code');
      if (code) copyText(code.textContent, btn);
    });

    // 설정 모달
    Array.prototype.forEach.call(document.querySelectorAll('[data-close-settings]'), function (b) {
      b.addEventListener('click', closeSettings);
    });
    Array.prototype.forEach.call(document.querySelectorAll('.modal-tab'), function (b) {
      b.addEventListener('click', function () { selectSettingsTab(b.dataset.tab); });
    });

    $('tempInput').addEventListener('input', function (e) {
      state.settings.temperature = Number(e.target.value);
      $('tempValue').textContent = e.target.value;
      saveSettingsSoon();
    });
    $('maxTokensInput').addEventListener('change', function (e) {
      state.settings.maxTokens = Math.max(256, Number(e.target.value) || 4096);
      e.target.value = state.settings.maxTokens;
      saveSettingsSoon();
    });
    $('maxStepsInput').addEventListener('change', function (e) {
      state.settings.maxSteps = Math.min(40, Math.max(1, Number(e.target.value) || 12));
      e.target.value = state.settings.maxSteps;
      saveSettingsSoon();
    });
    $('userNameInput').addEventListener('input', function (e) {
      state.settings.userName = e.target.value;
      saveSettingsSoon();
    });

    $('harnessPreset').addEventListener('change', function (e) {
      state.settings.harnessId = e.target.value;
      $('harnessSelect').value = e.target.value;
      syncHarnessPanel();
      saveSettingsSoon();
    });
    $('harnessText').addEventListener('input', function (e) {
      if ($('harnessPreset').value !== 'custom') return;
      state.settings.harnessCustom = e.target.value;
      saveSettingsSoon();
    });
    $('harnessCopyBtn').addEventListener('click', function () {
      var current = CAI.harness.byId[$('harnessPreset').value];
      state.settings.harnessCustom = (current && current.text) || CAI.harness.core;
      state.settings.harnessId = 'custom';
      $('harnessPreset').value = 'custom';
      $('harnessSelect').value = 'custom';
      syncHarnessPanel();
      saveSettingsSoon();
      toast('직접 작성 프리셋으로 복사했습니다.');
    });

    $('toolsEnabled').addEventListener('change', function (e) {
      state.settings.toolsEnabled = e.target.checked;
      saveSettingsSoon();
    });

    // --- 팀 ---
    $('teamGoal').addEventListener('input', function (e) {
      state.settings.team.goal = e.target.value;
      saveSettingsSoon();
    });
    $('teamRounds').addEventListener('change', function (e) {
      state.settings.team.rounds = Math.min(5, Math.max(1, Number(e.target.value) || 1));
      e.target.value = state.settings.team.rounds;
      saveSettingsSoon();
    });
    $('addMemberBtn').addEventListener('click', function () { addMember(); });
    $('autoTeamBtn').addEventListener('click', autoBuildTeam);

    $('memClearBtn').addEventListener('click', async function () {
      if (!confirm('장기 기억을 모두 삭제할까요?')) return;
      await CAI.tools.saveMemory([]);
      refreshWorkspacePanels();
      toast('기억을 비웠습니다.');
    });

    $('pwChangeBtn').addEventListener('click', async function () {
      var cur = $('pwCurrent').value;
      var next = $('pwNext').value;
      if (!cur || !next) { toast('현재 비밀번호와 새 비밀번호를 모두 입력해 주세요.', true); return; }
      var btn = $('pwChangeBtn');
      btn.disabled = true;
      $('settingsStatus').textContent = '재암호화 중…';
      try {
        await CAI.auth.changePassword(cur, next);
        $('pwCurrent').value = '';
        $('pwNext').value = '';
        toast('비밀번호를 변경했습니다.');
      } catch (e) {
        toast(errorText(e), true);
      } finally {
        btn.disabled = false;
        $('settingsStatus').textContent = '';
      }
    });

    $('deleteAccountBtn').addEventListener('click', async function () {
      var name = CAI.auth.username();
      if (!confirm('계정 "' + name + '" 의 모든 데이터를 삭제합니다. 계속할까요?')) return;
      if (prompt('확인을 위해 아이디를 입력하세요: ' + name) !== name) { toast('취소했습니다.'); return; }
      try {
        await CAI.auth.deleteAccount();
        closeSettings();
        leaveApp();
        toast('계정을 삭제했습니다.');
      } catch (e) {
        toast(errorText(e), true);
      }
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        if (!$('settingsModal').hidden) closeSettings();
        else closeDrawer();
      }
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        if (!$('app').hidden) { newSession(); $('input').focus(); }
      }
    });

    global.addEventListener('beforeunload', function (e) {
      if (!state.running) return;
      e.preventDefault();
      e.returnValue = '';
    });
  }

  // ───────────────────────────────────────── 시작

  function init() {
    wireAuth();
    wireApp();
    setAuthMode('login');

    if (!global.crypto || !global.crypto.subtle) {
      authError(
        '이 페이지는 보안 컨텍스트에서만 동작합니다.\n' +
        'https:// 주소 또는 http://localhost 로 접속해 주세요. (file:// 로 연 경우 동작하지 않습니다)'
      );
      $('authSubmit').disabled = true;
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  CAI.app = { state: state, toast: toast, showArtifact: showArtifact };
})(window);
