/*!
 * cai/js/agent.js — 에이전트 루프
 *
 *   사용자 메시지 → 모델 스트리밍 → 도구 호출이 있으면 실행 → 결과를 다시 모델에 →
 *   도구 호출이 없어질 때까지 반복 (maxSteps 로 제한)
 *
 * 이 루프가 제공자와 무관하게 동일하게 돌아가는 것이 CAI 하네스의 핵심이다.
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});

  function textPart(text) {
    return { type: 'text', text: text };
  }

  /** 대화가 길어지면 앞쪽을 잘라 컨텍스트를 아낀다(도구 쌍은 깨지지 않게 유지). */
  function windowMessages(messages, keep) {
    if (messages.length <= keep) return messages;
    var start = messages.length - keep;
    // tool_result 로 시작하면 짝이 되는 assistant tool_use 를 잃으므로 한 칸 앞으로 민다.
    while (start > 0) {
      var m = messages[start];
      var hasResult =
        Array.isArray(m.content) &&
        m.content.some(function (p) {
          return p.type === 'tool_result';
        });
      if (!hasResult) break;
      start--;
    }
    return messages.slice(start);
  }

  /**
   * @param {object} o
   * @param {object} o.session  현재 세션(메시지가 이 객체에 직접 추가된다)
   * @param {object} o.settings 사용자 설정
   * @param {string} o.text     사용자가 입력한 새 메시지 (없으면 재생성)
   * @param {function} o.onEvent UI 갱신 콜백
   * @param {AbortSignal} o.signal
   */
  async function run(o) {
    var session = o.session;
    var settings = o.settings;
    var emit = o.onEvent || function () {};
    var provider = CAI.providers.get(settings.provider);
    var apiKey = (settings.keys && settings.keys[settings.provider]) || '';
    var model = (settings.models && settings.models[settings.provider]) || '';

    if (!apiKey) {
      throw new Error(provider.label + ' API 키가 없습니다. ⚙️ 설정에서 키를 입력해 주세요.');
    }
    if (!model) {
      throw new Error(provider.label + ' 모델이 선택되지 않았습니다. ⚙️ 설정에서 모델을 골라 주세요.');
    }

    if (o.text) {
      session.messages.push({ role: 'user', content: [textPart(o.text)] });
      emit({ type: 'user_message', text: o.text });
    }

    session.provider = settings.provider;
    session.model = model;
    session.harnessId = settings.harnessId;

    var toolSchemas = CAI.tools.schemasFor(settings);
    var memories = [];
    try {
      memories = await CAI.tools.loadMemory();
    } catch (e) {}

    var system = CAI.harness.build({
      settings: settings,
      tools: toolSchemas,
      memories: memories,
    });

    var maxSteps = Math.max(1, Number(settings.maxSteps) || 12);
    var artifactSink = o.onArtifact || function () {};

    for (var step = 0; step < maxSteps; step++) {
      emit({ type: 'step_start', step: step });

      var parts = [];
      var buffered = '';
      var thinking = '';
      var toolUses = [];

      var streamOpts = {
        apiKey: apiKey,
        model: model,
        system: system,
        messages: windowMessages(session.messages, 60),
        tools: toolSchemas,
        temperature: typeof settings.temperature === 'number' ? settings.temperature : undefined,
        maxTokens: Number(settings.maxTokens) || 4096,
        baseUrl: (settings.baseUrls && settings.baseUrls[settings.provider]) || '',
        signal: o.signal,
      };

      for await (var ev of provider.stream(streamOpts)) {
        if (o.signal && o.signal.aborted) throw new DOMException('중단됨', 'AbortError');

        if (ev.type === 'text') {
          buffered += ev.delta;
          emit({ type: 'text', delta: ev.delta, text: buffered });
        } else if (ev.type === 'thinking') {
          thinking += ev.delta;
          emit({ type: 'thinking', delta: ev.delta, text: thinking });
        } else if (ev.type === 'tool_use') {
          toolUses.push(ev);
          emit({ type: 'tool_use', id: ev.id, name: ev.name, input: ev.input });
        } else if (ev.type === 'usage') {
          session.usage = session.usage || { input: 0, output: 0 };
          session.usage.input += ev.input || 0;
          session.usage.output += ev.output || 0;
          emit({ type: 'usage', input: ev.input, output: ev.output, total: session.usage });
        }
      }

      if (buffered) parts.push(textPart(buffered));
      toolUses.forEach(function (t) {
        parts.push({ type: 'tool_use', id: t.id, name: t.name, input: t.input });
      });

      if (!parts.length) parts.push(textPart(''));
      // 추론 내용은 화면 표시용으로만 남긴다. content 에 넣으면 다음 요청에
      // 일반 텍스트로 되돌아가 모델을 혼란스럽게 만든다.
      var assistantMessage = { role: 'assistant', content: parts };
      if (thinking) assistantMessage.thinking = thinking;
      session.messages.push(assistantMessage);
      emit({ type: 'assistant_chunk_done', text: buffered, toolUses: toolUses.length });

      if (!toolUses.length) {
        emit({ type: 'done', reason: 'stop' });
        return session;
      }

      var results = [];
      for (var i = 0; i < toolUses.length; i++) {
        var call = toolUses[i];
        emit({ type: 'tool_start', id: call.id, name: call.name, input: call.input });
        var out = await CAI.tools.execute(call.name, call.input, {
          onArtifact: artifactSink,
          signal: o.signal,
        });
        emit({
          type: 'tool_end',
          id: call.id,
          name: call.name,
          content: out.content,
          is_error: out.is_error,
        });
        results.push({
          type: 'tool_result',
          tool_use_id: call.id,
          name: call.name,
          content: out.content,
          is_error: out.is_error,
        });
      }
      session.messages.push({ role: 'user', content: results });
    }

    emit({ type: 'done', reason: 'max_steps' });
    session.messages.push({
      role: 'assistant',
      content: [
        textPart(
          '_도구 호출이 ' +
            maxSteps +
            '단계 제한에 도달해 멈췄습니다. 계속하려면 "계속" 이라고 보내 주세요._'
        ),
      ],
    });
    return session;
  }

  // ─────────────────────────────────────────── 팀(레드팀 조별과제) 러너
  //
  // 등록된 조원들이 순서대로 한 번씩 발언한다(라운드). 각 조원은 지금까지의
  // 전체 대화(사용자 + 다른 조원의 발언)를 보고 이어서 반응한다. 도구는 쓰지
  // 않고 토론·산출물 작성에 집중한다(멀티에이전트 + 도구루프는 과도하게 복잡).

  function collectText(message) {
    return (Array.isArray(message.content) ? message.content : [])
      .filter(function (p) { return p.type === 'text'; })
      .map(function (p) { return p.text; })
      .join('\n')
      .trim();
  }

  /** 특정 조원의 시점에서 대화 기록을 provider 메시지로 변환한다.
   *  자기 발언 = assistant, 그 외(사용자·다른 조원) = user + "이름: " 접두. */
  function teamViewMessages(messages, selfId) {
    var out = [];
    for (var i = 0; i < messages.length; i++) {
      var m = messages[i];
      var text = collectText(m);
      if (!text) continue;
      if (m.role === 'assistant' && m.agent && m.agent.id === selfId) {
        out.push({ role: 'assistant', content: [textPart(text)] });
      } else {
        var speaker = m.role === 'assistant' && m.agent ? m.agent.name : '사용자';
        out.push({ role: 'user', content: [textPart(speaker + ': ' + text)] });
      }
    }
    // 연속된 user 메시지는 합쳐 준다(일부 provider 가 교대 역할을 선호).
    var merged = [];
    out.forEach(function (msg) {
      var last = merged[merged.length - 1];
      if (last && last.role === msg.role) {
        last.content[0].text += '\n\n' + msg.content[0].text;
      } else {
        merged.push({ role: msg.role, content: [textPart(msg.content[0].text)] });
      }
    });
    // 첫 메시지가 assistant 이면(첫 발언자) 앞에 맥락 한 줄을 넣어 user 로 시작하게 한다.
    if (merged.length && merged[0].role === 'assistant') {
      merged.unshift({ role: 'user', content: [textPart('(팀 토론을 이어가세요.)')] });
    }
    return merged;
  }

  /**
   * @param o.session, o.settings, o.text
   * @param o.onEvent(ev)  ev.member 로 현재 발언 조원을 전달
   * @param o.signal
   */
  async function runTeam(o) {
    var session = o.session;
    var settings = o.settings;
    var emit = o.onEvent || function () {};
    var team = settings.team || {};
    var members = (team.members || []).filter(function (m) {
      return m && m.provider && m.model;
    });

    if (!members.length) {
      throw new Error('팀에 조원이 없습니다. ⚙️ 설정 → 팀 에서 조원을 추가하세요.');
    }

    // 키 확인
    for (var k = 0; k < members.length; k++) {
      var mk = members[k].keyOverride || (settings.keys && settings.keys[members[k].provider]);
      if (!mk) {
        var pv = CAI.providers.all[members[k].provider];
        throw new Error(
          members[k].name + ' 조원의 ' + (pv ? pv.label : members[k].provider) +
          ' API 키가 없습니다. ⚙️ 설정에서 키를 등록하세요.'
        );
      }
    }

    if (o.text) {
      session.messages.push({ role: 'user', content: [textPart(o.text)] });
      emit({ type: 'user_message', text: o.text });
    }
    session.isTeam = true;

    var memories = [];
    try { memories = await CAI.tools.loadMemory(); } catch (e) {}

    var rounds = Math.max(1, Math.min(5, Number(o.rounds || team.rounds) || 1));
    session.usage = session.usage || { input: 0, output: 0 };

    for (var r = 0; r < rounds; r++) {
      for (var i = 0; i < members.length; i++) {
        if (o.signal && o.signal.aborted) throw new DOMException('중단됨', 'AbortError');
        var member = members[i];
        var provider = CAI.providers.get(member.provider);
        var apiKey = member.keyOverride || settings.keys[member.provider];

        var system = CAI.harness.build({
          settings: settings,
          roleOverride: member.role,
          provider: member.provider,
          model: member.model,
          tools: [],
          memories: memories,
          team: { self: member, members: members, goal: team.goal },
        });

        emit({ type: 'member_start', member: member, round: r });

        var buffered = '';
        var streamOpts = {
          apiKey: apiKey,
          model: member.model,
          system: system,
          messages: windowMessages(teamViewMessages(session.messages, member.id), 80),
          tools: [],
          temperature: typeof settings.temperature === 'number' ? settings.temperature : undefined,
          maxTokens: Number(settings.maxTokens) || 4096,
          baseUrl: (settings.baseUrls && settings.baseUrls[member.provider]) || '',
          signal: o.signal,
        };

        for await (var ev of provider.stream(streamOpts)) {
          if (o.signal && o.signal.aborted) throw new DOMException('중단됨', 'AbortError');
          if (ev.type === 'text') {
            buffered += ev.delta;
            emit({ type: 'text', delta: ev.delta, text: buffered, member: member });
          } else if (ev.type === 'thinking') {
            emit({ type: 'thinking', delta: ev.delta, member: member });
          } else if (ev.type === 'usage') {
            session.usage.input += ev.input || 0;
            session.usage.output += ev.output || 0;
            emit({ type: 'usage', total: session.usage });
          }
        }

        session.messages.push({
          role: 'assistant',
          content: [textPart(buffered)],
          agent: {
            id: member.id, name: member.name, provider: member.provider,
            model: member.model, color: member.color,
          },
        });
        emit({ type: 'member_done', member: member, text: buffered });
      }
    }

    emit({ type: 'done', reason: 'team_round' });
    return session;
  }

  CAI.agent = { run: run, runTeam: runTeam, windowMessages: windowMessages, teamViewMessages: teamViewMessages };
})(window);
