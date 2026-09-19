/*!
 * cai/js/providers.js — Anthropic(Claude) / OpenAI(GPT) / Google(Gemini) 통합 어댑터
 *
 * 내부 공통 메시지 형식 (Anthropic 스타일을 정본으로 사용):
 *   { role: 'user' | 'assistant', content: Part[] }
 *   Part =
 *     | { type:'text', text }
 *     | { type:'tool_use', id, name, input }
 *     | { type:'tool_result', tool_use_id, name, content, is_error }
 *
 * 각 어댑터의 stream() 은 아래 이벤트를 순서대로 yield 한다.
 *   { type:'text',     delta }
 *   { type:'thinking', delta }
 *   { type:'tool_use', id, name, input }
 *   { type:'usage',    input, output }
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});

  // ------------------------------------------------------------------ 공통 유틸

  function trimSlash(u) {
    return String(u || '').replace(/\/+$/, '');
  }

  async function httpError(res, providerLabel) {
    var detail = '';
    try {
      var text = await res.text();
      try {
        var json = JSON.parse(text);
        detail =
          (json.error && (json.error.message || json.error.status)) ||
          (json[0] && json[0].error && json[0].error.message) ||
          json.message ||
          text;
      } catch (e) {
        detail = text;
      }
    } catch (e) {
      /* 본문을 읽지 못하면 상태 코드만 */
    }
    detail = String(detail || '').slice(0, 800);

    var hint = '';
    if (res.status === 401 || res.status === 403) hint = ' — API 키를 확인해 주세요.';
    else if (res.status === 404) hint = ' — 모델 이름을 확인해 주세요.';
    else if (res.status === 429) hint = ' — 요청 한도(rate limit)에 걸렸습니다. 잠시 후 다시 시도하세요.';
    else if (res.status >= 500) hint = ' — 제공자 서버 오류입니다. 잠시 후 다시 시도하세요.';

    var err = new Error(providerLabel + ' ' + res.status + hint + (detail ? '\n' + detail : ''));
    err.status = res.status;
    err.detail = detail;
    return err;
  }

  /** fetch 실패를 사람이 읽을 수 있는 메시지로 바꾼다. */
  function networkError(e, providerLabel) {
    if (e && e.name === 'AbortError') return e;
    if (e instanceof TypeError) {
      return new Error(
        providerLabel +
          ' 에 연결하지 못했습니다. 네트워크 상태 또는 브라우저 확장/CORS 차단을 확인해 주세요.\n' +
          String(e.message || e)
      );
    }
    return e;
  }

  /** ReadableStream 을 한 줄씩 읽어 주는 비동기 이터레이터 */
  async function* readLines(res) {
    if (!res.body || !res.body.getReader) {
      var whole = await res.text();
      var all = whole.split('\n');
      for (var i = 0; i < all.length; i++) yield all[i].replace(/\r$/, '');
      return;
    }
    var reader = res.body.getReader();
    var decoder = new TextDecoder();
    var buf = '';
    for (;;) {
      var chunk = await reader.read();
      if (chunk.done) break;
      buf += decoder.decode(chunk.value, { stream: true });
      var idx;
      while ((idx = buf.indexOf('\n')) >= 0) {
        yield buf.slice(0, idx).replace(/\r$/, '');
        buf = buf.slice(idx + 1);
      }
    }
    buf += decoder.decode();
    if (buf) yield buf.replace(/\r$/, '');
  }

  /** SSE 의 `data:` 페이로드만 뽑아 준다. */
  async function* readSSE(res) {
    for await (var line of readLines(res)) {
      if (!line || line.charAt(0) === ':') continue;
      if (line.indexOf('data:') !== 0) continue;
      var payload = line.slice(5).trim();
      if (!payload) continue;
      yield payload;
    }
  }

  function safeJSONParse(text, fallback) {
    try {
      return JSON.parse(text);
    } catch (e) {
      return fallback;
    }
  }

  function partsOf(message) {
    if (!message) return [];
    if (Array.isArray(message.content)) return message.content;
    if (typeof message.content === 'string') return [{ type: 'text', text: message.content }];
    return [];
  }

  function textOf(parts) {
    return parts
      .filter(function (p) {
        return p.type === 'text';
      })
      .map(function (p) {
        return p.text;
      })
      .join('\n');
  }

  function toolResultText(part) {
    if (typeof part.content === 'string') return part.content;
    try {
      return JSON.stringify(part.content);
    } catch (e) {
      return String(part.content);
    }
  }

  // ------------------------------------------------------------------ Anthropic

  var anthropic = {
    id: 'anthropic',
    label: 'Claude (Anthropic)',
    short: 'Claude',
    keyPlaceholder: 'sk-ant-...',
    keysUrl: 'https://console.anthropic.com/settings/keys',
    defaultBase: 'https://api.anthropic.com',
    fallbackModels: [
      'claude-opus-5',
      'claude-sonnet-5',
      'claude-fable-5-1',
      'claude-haiku-4-5-20251001',
    ],

    headers: function (apiKey) {
      return {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      };
    },

    async listModels(apiKey, baseUrl) {
      var base = trimSlash(baseUrl) || anthropic.defaultBase;
      var res;
      try {
        res = await fetch(base + '/v1/models?limit=100', { headers: anthropic.headers(apiKey) });
      } catch (e) {
        throw networkError(e, anthropic.label);
      }
      if (!res.ok) throw await httpError(res, anthropic.label);
      var json = await res.json();
      return (json.data || []).map(function (m) {
        return { id: m.id, label: m.display_name || m.id };
      });
    },

    body: function (opts) {
      var body = {
        model: opts.model,
        max_tokens: opts.maxTokens || 4096,
        messages: opts.messages.map(function (m) {
          return {
            role: m.role,
            content: partsOf(m)
              .map(function (p) {
                if (p.type === 'tool_result') {
                  return {
                    type: 'tool_result',
                    tool_use_id: p.tool_use_id,
                    content: toolResultText(p),
                    is_error: !!p.is_error,
                  };
                }
                if (p.type === 'tool_use') {
                  return { type: 'tool_use', id: p.id, name: p.name, input: p.input || {} };
                }
                if (p.type === 'text') return { type: 'text', text: p.text || '' };
                return null;
              })
              .filter(Boolean),
          };
        }),
      };
      if (typeof opts.temperature === 'number') body.temperature = opts.temperature;
      if (opts.system) body.system = opts.system;
      if (opts.tools && opts.tools.length) {
        body.tools = opts.tools.map(function (t) {
          return { name: t.name, description: t.description, input_schema: t.input_schema };
        });
      }
      return body;
    },

    async *stream(opts) {
      var base = trimSlash(opts.baseUrl) || anthropic.defaultBase;
      var body = anthropic.body(opts);
      body.stream = true;

      var res;
      try {
        res = await fetch(base + '/v1/messages', {
          method: 'POST',
          headers: anthropic.headers(opts.apiKey),
          body: JSON.stringify(body),
          signal: opts.signal,
        });
      } catch (e) {
        throw networkError(e, anthropic.label);
      }
      if (!res.ok) throw await httpError(res, anthropic.label);

      var blocks = {};
      var usageIn = 0;

      for await (var payload of readSSE(res)) {
        var ev = safeJSONParse(payload, null);
        if (!ev) continue;

        if (ev.type === 'message_start') {
          if (ev.message && ev.message.usage) usageIn = ev.message.usage.input_tokens || 0;
        } else if (ev.type === 'content_block_start') {
          var cb = ev.content_block || {};
          blocks[ev.index] =
            cb.type === 'tool_use'
              ? { type: 'tool_use', id: cb.id, name: cb.name, json: '' }
              : { type: cb.type };
        } else if (ev.type === 'content_block_delta') {
          var d = ev.delta || {};
          if (d.type === 'text_delta') yield { type: 'text', delta: d.text || '' };
          else if (d.type === 'thinking_delta') yield { type: 'thinking', delta: d.thinking || '' };
          else if (d.type === 'input_json_delta') {
            var b = blocks[ev.index];
            if (b) b.json += d.partial_json || '';
          }
        } else if (ev.type === 'content_block_stop') {
          var done = blocks[ev.index];
          if (done && done.type === 'tool_use') {
            yield {
              type: 'tool_use',
              id: done.id,
              name: done.name,
              input: done.json ? safeJSONParse(done.json, {}) : {},
            };
          }
        } else if (ev.type === 'message_delta') {
          if (ev.usage) {
            yield { type: 'usage', input: usageIn, output: ev.usage.output_tokens || 0 };
          }
        } else if (ev.type === 'error') {
          throw new Error(
            anthropic.label + ' 스트림 오류: ' + ((ev.error && ev.error.message) || 'unknown')
          );
        }
      }
    },
  };

  // ------------------------------------------------------------------ OpenAI

  /** o-시리즈·gpt-5 계열은 max_tokens / temperature 를 받지 않는다. */
  function openaiIsReasoning(model) {
    return /^(o\d|gpt-5)/i.test(String(model || ''));
  }

  var openai = {
    id: 'openai',
    label: 'GPT (OpenAI)',
    short: 'GPT',
    keyPlaceholder: 'sk-...',
    keysUrl: 'https://platform.openai.com/api-keys',
    defaultBase: 'https://api.openai.com',
    fallbackModels: ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4o', 'gpt-4o-mini', 'o4-mini'],

    headers: function (apiKey) {
      return {
        'content-type': 'application/json',
        authorization: 'Bearer ' + apiKey,
      };
    },

    async listModels(apiKey, baseUrl) {
      var base = trimSlash(baseUrl) || openai.defaultBase;
      var res;
      try {
        res = await fetch(base + '/v1/models', { headers: openai.headers(apiKey) });
      } catch (e) {
        throw networkError(e, openai.label);
      }
      if (!res.ok) throw await httpError(res, openai.label);
      var json = await res.json();
      return (json.data || [])
        .map(function (m) {
          return { id: m.id, label: m.id };
        })
        .filter(function (m) {
          // 채팅에 쓸 수 없는 모델(임베딩·음성·이미지 등)은 목록에서 뺀다.
          return !/(embedding|whisper|tts|dall-e|moderation|audio|realtime|image|transcribe|search|codex)/i.test(
            m.id
          );
        })
        .sort(function (a, b) {
          return a.id.localeCompare(b.id);
        });
    },

    body: function (opts) {
      var messages = [];
      if (opts.system) messages.push({ role: 'system', content: opts.system });

      opts.messages.forEach(function (m) {
        var parts = partsOf(m);
        if (m.role === 'assistant') {
          var toolCalls = parts
            .filter(function (p) {
              return p.type === 'tool_use';
            })
            .map(function (p) {
              return {
                id: p.id,
                type: 'function',
                function: { name: p.name, arguments: JSON.stringify(p.input || {}) },
              };
            });
          var text = textOf(parts);
          var msg = { role: 'assistant', content: text || null };
          if (toolCalls.length) msg.tool_calls = toolCalls;
          messages.push(msg);
          return;
        }

        // user 역할: 도구 결과는 별도의 tool 메시지로 분리한다.
        var results = parts.filter(function (p) {
          return p.type === 'tool_result';
        });
        results.forEach(function (p) {
          messages.push({
            role: 'tool',
            tool_call_id: p.tool_use_id,
            content: toolResultText(p),
          });
        });
        var userText = textOf(parts);
        if (userText) messages.push({ role: 'user', content: userText });
      });

      var body = { model: opts.model, messages: messages };
      if (openaiIsReasoning(opts.model)) {
        body.max_completion_tokens = opts.maxTokens || 4096;
      } else {
        body.max_tokens = opts.maxTokens || 4096;
        if (typeof opts.temperature === 'number') body.temperature = opts.temperature;
      }
      if (opts.tools && opts.tools.length) {
        body.tools = opts.tools.map(function (t) {
          return {
            type: 'function',
            function: {
              name: t.name,
              description: t.description,
              parameters: t.input_schema,
            },
          };
        });
        body.tool_choice = 'auto';
      }
      return body;
    },

    /** 파라미터 거부(400)를 한 번 자동 보정해서 재시도한다. */
    async request(opts, body) {
      var base = trimSlash(opts.baseUrl) || openai.defaultBase;
      var res;
      try {
        res = await fetch(base + '/v1/chat/completions', {
          method: 'POST',
          headers: openai.headers(opts.apiKey),
          body: JSON.stringify(body),
          signal: opts.signal,
        });
      } catch (e) {
        throw networkError(e, openai.label);
      }
      if (res.ok) return res;
      if (res.status !== 400) throw await httpError(res, openai.label);

      var err = await httpError(res, openai.label);
      var detail = String(err.detail || '');
      var patched = Object.assign({}, body);
      var changed = false;

      if (/max_tokens/.test(detail) && patched.max_tokens !== undefined) {
        patched.max_completion_tokens = patched.max_tokens;
        delete patched.max_tokens;
        changed = true;
      }
      if (/temperature/.test(detail) && patched.temperature !== undefined) {
        delete patched.temperature;
        changed = true;
      }
      if (!changed) throw err;

      try {
        res = await fetch(base + '/v1/chat/completions', {
          method: 'POST',
          headers: openai.headers(opts.apiKey),
          body: JSON.stringify(patched),
          signal: opts.signal,
        });
      } catch (e) {
        throw networkError(e, openai.label);
      }
      if (!res.ok) throw await httpError(res, openai.label);
      return res;
    },

    async *stream(opts) {
      var body = openai.body(opts);
      body.stream = true;
      body.stream_options = { include_usage: true };

      var res = await openai.request(opts, body);
      var calls = {};

      for await (var payload of readSSE(res)) {
        if (payload === '[DONE]') break;
        var ev = safeJSONParse(payload, null);
        if (!ev) continue;

        if (ev.error) {
          throw new Error(openai.label + ' 스트림 오류: ' + (ev.error.message || 'unknown'));
        }

        var choice = ev.choices && ev.choices[0];
        if (choice && choice.delta) {
          var delta = choice.delta;
          if (delta.content) yield { type: 'text', delta: delta.content };
          if (delta.reasoning_content) yield { type: 'thinking', delta: delta.reasoning_content };
          if (delta.tool_calls) {
            for (var i = 0; i < delta.tool_calls.length; i++) {
              var tc = delta.tool_calls[i];
              var slot = tc.index === undefined ? 0 : tc.index;
              if (!calls[slot]) calls[slot] = { id: '', name: '', args: '' };
              if (tc.id) calls[slot].id = tc.id;
              if (tc.function && tc.function.name) calls[slot].name += tc.function.name;
              if (tc.function && tc.function.arguments) calls[slot].args += tc.function.arguments;
            }
          }
        }

        if (ev.usage) {
          yield {
            type: 'usage',
            input: ev.usage.prompt_tokens || 0,
            output: ev.usage.completion_tokens || 0,
          };
        }
      }

      var slots = Object.keys(calls).sort(function (a, b) {
        return Number(a) - Number(b);
      });
      for (var s = 0; s < slots.length; s++) {
        var call = calls[slots[s]];
        if (!call.name) continue;
        yield {
          type: 'tool_use',
          id: call.id || 'call_' + CAI.crypto.randomId(8),
          name: call.name,
          input: call.args ? safeJSONParse(call.args, {}) : {},
        };
      }
    },
  };

  // ------------------------------------------------------------------ Google Gemini

  /** Gemini 는 OpenAPI 서브셋만 받는다. JSON Schema 를 안전하게 깎아 준다. */
  function geminiSchema(schema) {
    if (!schema || typeof schema !== 'object') return undefined;
    var out = {};
    if (schema.type) out.type = String(schema.type).toUpperCase();
    if (schema.description) out.description = schema.description;
    if (schema.enum) out.enum = schema.enum.map(String);
    if (schema.items) out.items = geminiSchema(schema.items);
    if (schema.properties) {
      out.properties = {};
      Object.keys(schema.properties).forEach(function (k) {
        var sub = geminiSchema(schema.properties[k]);
        if (sub) out.properties[k] = sub;
      });
    }
    if (Array.isArray(schema.required) && schema.required.length) out.required = schema.required;
    if (out.type === 'OBJECT' && !out.properties) out.properties = {};
    return out;
  }

  var google = {
    id: 'google',
    label: 'Gemini (Google)',
    short: 'Gemini',
    keyPlaceholder: 'AIza...',
    keysUrl: 'https://aistudio.google.com/app/apikey',
    defaultBase: 'https://generativelanguage.googleapis.com',
    fallbackModels: ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.0-flash'],

    async listModels(apiKey, baseUrl) {
      var base = trimSlash(baseUrl) || google.defaultBase;
      var res;
      try {
        res = await fetch(base + '/v1beta/models?pageSize=200', {
          headers: { 'x-goog-api-key': apiKey },
        });
      } catch (e) {
        throw networkError(e, google.label);
      }
      if (!res.ok) throw await httpError(res, google.label);
      var json = await res.json();
      return (json.models || [])
        .filter(function (m) {
          return (m.supportedGenerationMethods || []).indexOf('generateContent') >= 0;
        })
        .map(function (m) {
          return {
            id: String(m.name || '').replace(/^models\//, ''),
            label: m.displayName || m.name,
          };
        });
    },

    body: function (opts) {
      var contents = [];

      opts.messages.forEach(function (m) {
        var parts = partsOf(m);
        var mapped = [];
        parts.forEach(function (p) {
          if (p.type === 'text') {
            if (p.text) mapped.push({ text: p.text });
          } else if (p.type === 'tool_use') {
            mapped.push({ functionCall: { name: p.name, args: p.input || {} } });
          } else if (p.type === 'tool_result') {
            mapped.push({
              functionResponse: {
                name: p.name || 'tool',
                response: p.is_error
                  ? { error: toolResultText(p) }
                  : { result: toolResultText(p) },
              },
            });
          }
        });
        if (!mapped.length) return;
        contents.push({ role: m.role === 'assistant' ? 'model' : 'user', parts: mapped });
      });

      var body = {
        contents: contents,
        generationConfig: {
          maxOutputTokens: opts.maxTokens || 4096,
        },
      };
      if (typeof opts.temperature === 'number') body.generationConfig.temperature = opts.temperature;
      if (opts.system) body.systemInstruction = { parts: [{ text: opts.system }] };
      if (opts.tools && opts.tools.length) {
        body.tools = [
          {
            functionDeclarations: opts.tools.map(function (t) {
              return {
                name: t.name,
                description: t.description,
                parameters: geminiSchema(t.input_schema),
              };
            }),
          },
        ];
      }
      return body;
    },

    async *stream(opts) {
      var base = trimSlash(opts.baseUrl) || google.defaultBase;
      var url =
        base +
        '/v1beta/models/' +
        encodeURIComponent(opts.model) +
        ':streamGenerateContent?alt=sse';

      var res;
      try {
        res = await fetch(url, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'x-goog-api-key': opts.apiKey },
          body: JSON.stringify(google.body(opts)),
          signal: opts.signal,
        });
      } catch (e) {
        throw networkError(e, google.label);
      }
      if (!res.ok) throw await httpError(res, google.label);

      var usage = null;

      for await (var payload of readSSE(res)) {
        var ev = safeJSONParse(payload, null);
        if (!ev) continue;
        if (ev.error) {
          throw new Error(google.label + ' 스트림 오류: ' + (ev.error.message || 'unknown'));
        }

        if (ev.usageMetadata) {
          usage = {
            type: 'usage',
            input: ev.usageMetadata.promptTokenCount || 0,
            output: ev.usageMetadata.candidatesTokenCount || 0,
          };
        }

        var cand = ev.candidates && ev.candidates[0];
        var parts = (cand && cand.content && cand.content.parts) || [];
        for (var i = 0; i < parts.length; i++) {
          var p = parts[i];
          if (p.functionCall) {
            yield {
              type: 'tool_use',
              id: 'call_' + CAI.crypto.randomId(8),
              name: p.functionCall.name,
              input: p.functionCall.args || {},
            };
          } else if (typeof p.text === 'string' && p.text) {
            if (p.thought) yield { type: 'thinking', delta: p.text };
            else yield { type: 'text', delta: p.text };
          }
        }

        if (cand && cand.finishReason && cand.finishReason !== 'STOP' && cand.finishReason !== 'MAX_TOKENS') {
          yield { type: 'text', delta: '\n\n_(중단 사유: ' + cand.finishReason + ')_' };
        }
      }

      if (usage) yield usage;
    },
  };

  // ------------------------------------------------------------------ 레지스트리

  var registry = {
    anthropic: anthropic,
    openai: openai,
    google: google,
  };

  CAI.providers = {
    all: registry,
    order: ['anthropic', 'openai', 'google'],
    get: function (id) {
      var p = registry[id];
      if (!p) throw new Error('알 수 없는 제공자: ' + id);
      return p;
    },
    list: function () {
      return ['anthropic', 'openai', 'google'].map(function (id) {
        return registry[id];
      });
    },
  };
})(window);
