import Foundation

/// Display-only DOM annotation. Text nodes retain their exact original spelling,
/// inline markup and links; the file, locator anchors and stored records are untouched.
public enum QuranQuotationScript {
    public static func source(index: QuranQuotationIndex?) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: index?.patterns ?? [])) ?? Data("[]".utf8)
        let patterns = String(decoding: data, as: UTF8.self)
        return #"""
        (() => {
          const trie = Object.create(null);
          for (const pattern of \#(patterns)) {
            let branch = trie;
            for (const word of pattern) branch = branch[word] ??= Object.create(null);
            branch['@'] = true;
          }
          const normalize = word => word.normalize('NFKD').replace(/\p{M}/gu, '').replace(/ـ/g, '').replace(/ٱ/g, 'ا').replace(/ى/g, 'ي');
          const blocks = 'p, li, blockquote, h1, h2, h3, h4, h5, h6, div, dd, dt, figcaption';
          window.madarMarkQuranQuotations = () => {
            if (!document.body) return {marked: 0, matched: 0};
            const groups = [];
            let group;
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            while (walker.nextNode()) {
              const node = walker.currentNode, parent = node.parentElement;
              if (!parent || parent.closest('script, style, textarea, code, pre, svg, .madar-ayah, [hidden]')) { group = undefined; continue; }
              const block = parent.closest(blocks) || document.body;
              if (!group || group.block !== block) { group = {block, nodes: []}; groups.push(group); }
              group.nodes.push(node);
            }
            let marked = 0, matched = 0;
            for (const group of groups) {
              const text = group.nodes.map(node => node.nodeValue).join('');
              const ranges = Array.from(text.matchAll(/﴿[^﴾]*﴾/gu), match => ({start: match.index, end: match.index + match[0].length, kind: 'marked'}));
              marked += ranges.length;
              const words = Array.from(text.matchAll(/[\p{L}\p{M}ـ]+/gu), match => ({word: normalize(match[0]), start: match.index, end: match.index + match[0].length})).filter(token => token.word);
              for (let i = 0; i < words.length;) {
                let branch = trie, last = i;
                for (let j = i; j < words.length && (branch = branch[words[j].word]); j++) if (branch['@']) last = j + 1;
                if (last > i) {
                  const start = words[i].start, end = words[last - 1].end;
                  if (!ranges.some(range => range.start < end && start < range.end)) { ranges.push({start, end, kind: 'matched'}); matched++; }
                  i = last;
                } else i++;
              }
              ranges.sort((a, b) => a.start - b.start);
              let offset = 0;
              for (const node of group.nodes) {
                const value = node.nodeValue, limit = offset + value.length;
                const intersections = ranges.filter(range => range.start < limit && offset < range.end);
                if (intersections.length) {
                  const fragment = document.createDocumentFragment();
                  let cursor = 0;
                  for (const range of intersections) {
                    const start = Math.max(0, range.start - offset), end = Math.min(value.length, range.end - offset);
                    if (start > cursor) fragment.appendChild(document.createTextNode(value.slice(cursor, start)));
                    const span = document.createElement('span');
                    span.className = 'madar-ayah'; span.dataset.madarAyahKind = range.kind;
                    span.textContent = value.slice(start, end); fragment.appendChild(span); cursor = end;
                  }
                  if (cursor < value.length) fragment.appendChild(document.createTextNode(value.slice(cursor)));
                  node.parentNode.replaceChild(fragment, node);
                }
                offset = limit;
              }
            }
            return {marked, matched};
          };
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', window.madarMarkQuranQuotations, {once: true});
          else window.madarMarkQuranQuotations();
        })();
        """#
    }
}
