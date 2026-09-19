/*!
 * cai/js/markdown.js — 의존성 없는 소형 마크다운 렌더러
 *
 * 스트리밍 중에도 매 프레임 다시 그려야 하므로 가볍게 유지한다.
 * 모든 입력은 먼저 HTML 이스케이프한 뒤 서식을 입히므로 XSS 로부터 안전하다.
 */
(function (global) {
  'use strict';

  var CAI = (global.CAI = global.CAI || {});

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function safeUrl(url) {
    var u = String(url || '').trim();
    if (/^(https?:|mailto:|#|\/)/i.test(u)) return u;
    return '#';
  }

  /** 인라인 서식: 코드 → 링크 → 굵게 → 기울임 → 취소선 */
  function inline(text) {
    var codes = [];
    var out = escapeHtml(text);

    // 인라인 코드는 먼저 뽑아 두고 마지막에 되돌린다(내부 서식 무시).
    out = out.replace(/`([^`\n]+)`/g, function (m, code) {
      codes.push(code);
      return '\u0000CODE' + (codes.length - 1) + '\u0000';
    });

    out = out.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, function (m, alt, url) {
      return '<img src="' + safeUrl(url) + '" alt="' + alt + '" loading="lazy" />';
    });
    out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function (m, label, url) {
      return '<a href="' + safeUrl(url) + '" target="_blank" rel="noopener noreferrer">' + label + '</a>';
    });
    out = out.replace(/(^|[\s(])((?:https?:\/\/)[^\s<)]+)/g, function (m, pre, url) {
      return pre + '<a href="' + safeUrl(url) + '" target="_blank" rel="noopener noreferrer">' + url + '</a>';
    });

    out = out.replace(/\*\*\*([^*\n]+)\*\*\*/g, '<strong><em>$1</em></strong>');
    out = out.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
    out = out.replace(/(^|[^*\w])\*([^*\n]+)\*/g, '$1<em>$2</em>');
    out = out.replace(/(^|[^_\w])_([^_\n]+)_/g, '$1<em>$2</em>');
    out = out.replace(/~~([^~\n]+)~~/g, '<del>$1</del>');

    out = out.replace(/\u0000CODE(\d+)\u0000/g, function (m, i) {
      return '<code>' + codes[Number(i)] + '</code>';
    });
    return out;
  }

  function codeBlock(lang, lines) {
    var cls = lang ? ' class="lang-' + escapeHtml(lang.replace(/[^\w+#.-]/g, '')) + '"' : '';
    return (
      '<div class="code-block"><div class="code-head"><span>' +
      escapeHtml(lang || 'text') +
      '</span><button type="button" class="code-copy" data-copy>복사</button></div>' +
      '<pre><code' + cls + '>' + escapeHtml(lines.join('\n')) + '</code></pre></div>'
    );
  }

  function tableBlock(rows) {
    // rows[0] = 헤더, rows[1] = 구분선, 나머지 = 본문
    function cells(line) {
      return line
        .replace(/^\s*\|/, '')
        .replace(/\|\s*$/, '')
        .split('|')
        .map(function (c) {
          return c.trim();
        });
    }
    var head = cells(rows[0]);
    var body = rows.slice(2).map(cells);
    var html = '<div class="table-wrap"><table><thead><tr>';
    head.forEach(function (h) {
      html += '<th>' + inline(h) + '</th>';
    });
    html += '</tr></thead><tbody>';
    body.forEach(function (r) {
      html += '<tr>';
      for (var i = 0; i < head.length; i++) html += '<td>' + inline(r[i] || '') + '</td>';
      html += '</tr>';
    });
    return html + '</tbody></table></div>';
  }

  function render(src) {
    var lines = String(src == null ? '' : src).replace(/\r\n?/g, '\n').split('\n');
    var html = [];
    var i = 0;

    function isTableSep(line) {
      return /^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$/.test(line) && line.indexOf('-') >= 0 && line.indexOf('|') >= 0;
    }

    while (i < lines.length) {
      var line = lines[i];

      // 코드 블록
      var fence = /^\s*(`{3,}|~{3,})\s*(\S*)/.exec(line);
      if (fence) {
        var marker = fence[1].charAt(0);
        var lang = fence[2];
        var buf = [];
        i++;
        while (i < lines.length && !new RegExp('^\\s*' + marker + '{3,}\\s*$').test(lines[i])) {
          buf.push(lines[i]);
          i++;
        }
        i++; // 닫는 펜스 (스트리밍 중이라 없을 수도 있다)
        html.push(codeBlock(lang, buf));
        continue;
      }

      if (!line.trim()) {
        i++;
        continue;
      }

      // 가로줄
      if (/^\s*([-*_])\s*(\1\s*){2,}$/.test(line)) {
        html.push('<hr />');
        i++;
        continue;
      }

      // 제목
      var heading = /^\s*(#{1,6})\s+(.*)$/.exec(line);
      if (heading) {
        var level = heading[1].length;
        html.push('<h' + level + '>' + inline(heading[2]) + '</h' + level + '>');
        i++;
        continue;
      }

      // 표
      if (line.indexOf('|') >= 0 && i + 1 < lines.length && isTableSep(lines[i + 1])) {
        var rows = [line, lines[i + 1]];
        i += 2;
        while (i < lines.length && lines[i].indexOf('|') >= 0 && lines[i].trim()) {
          rows.push(lines[i]);
          i++;
        }
        html.push(tableBlock(rows));
        continue;
      }

      // 인용
      if (/^\s*>/.test(line)) {
        var quote = [];
        while (i < lines.length && /^\s*>/.test(lines[i])) {
          quote.push(lines[i].replace(/^\s*>\s?/, ''));
          i++;
        }
        html.push('<blockquote>' + render(quote.join('\n')) + '</blockquote>');
        continue;
      }

      // 목록 (중첩 1단계까지)
      if (/^\s*([-*+]|\d+[.)])\s+/.test(line)) {
        var ordered = /^\s*\d+[.)]\s+/.test(line);
        var items = [];
        while (i < lines.length && /^\s*([-*+]|\d+[.)])\s+/.test(lines[i])) {
          var body = lines[i].replace(/^\s*([-*+]|\d+[.)])\s+/, '');
          var indent = /^(\s*)/.exec(lines[i])[1].length;
          i++;
          // 이어지는 들여쓰기 줄은 같은 항목에 붙인다.
          while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*+]|\d+[.)])\s+/.test(lines[i])) {
            body += '\n' + lines[i].trim();
            i++;
          }
          var checkbox = /^\[([ xX])\]\s+/.exec(body);
          if (checkbox) {
            body =
              '<input type="checkbox" disabled ' +
              (checkbox[1] === ' ' ? '' : 'checked') +
              ' /> ' +
              inline(body.slice(checkbox[0].length));
          } else {
            body = inline(body);
          }
          items.push('<li data-indent="' + indent + '">' + body + '</li>');
        }
        html.push((ordered ? '<ol>' : '<ul>') + items.join('') + (ordered ? '</ol>' : '</ul>'));
        continue;
      }

      // 문단
      var para = [];
      while (i < lines.length && lines[i].trim() && !/^\s*(#{1,6}\s|>|([-*+]|\d+[.)])\s|`{3,}|~{3,})/.test(lines[i])) {
        para.push(lines[i]);
        i++;
      }
      if (para.length) html.push('<p>' + inline(para.join('\n')).replace(/\n/g, '<br />') + '</p>');
      else i++;
    }

    return html.join('\n');
  }

  CAI.markdown = { render: render, escapeHtml: escapeHtml, inline: inline };
})(window);
