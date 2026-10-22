/// Experimental DOM adapter. Selectors must be verified against the signed-in site.
public enum ClaudeWebsiteScript {
    // Only known quota cards on the exact usage origin/path are inspected. No form inputs,
    // cookies, tokens, page HTML, or conversation text are returned to native code.
    public static let extractionScript = #"""
    (() => {
      if (location.origin !== 'https://claude.ai' ||
          !(location.pathname.replace(/\/$/, '') === '/settings/usage' ||
            (location.pathname.replace(/\/$/, '') === '/new' &&
             location.hash.replace(/^#\/?/, '') === 'settings/usage'))) return '[]';
      const definitions = [
        ['session', /^current session$/i],
        ['weekly', /^this week$/i]
      ];
      const visible = el => el.getClientRects().length > 0;
      const nodes = [...document.querySelectorAll('h1,h2,h3,h4,p,span,div')];
      const cards = [];
      for (const [id, heading] of definitions) {
        const headings = nodes.filter(el => visible(el) && heading.test((el.innerText || '').trim()));
        for (const headingNode of headings) {
          let el = headingNode;
          for (let depth = 0; el && depth < 7; depth++, el = el.parentElement) {
            const text = (el.innerText || '').trim();
            if (text.length > 1500) break;
            if (definitions.some(([otherID, otherHeading]) => otherID !== id &&
                text.split(/\n/).some(line => otherHeading.test(line.trim())))) break;
            const percentages = text.match(/[-+]?\d+(?:[.,]\d+)?\s*%/g) || [];
            if (percentages.length > 1) break;
            if (percentages.length === 1 && /\d+(?:\.\d+)?\s*%\s*(?:remaining|left|used)\b/i.test(text)) {
              const dates = [...el.querySelectorAll('time[datetime]')];
              const iso = dates.length === 1 ? dates[0].getAttribute('datetime') : null;
              const resets = [...new Set([...el.querySelectorAll('p,span,div,time')]
                .filter(visible).map(node => (node.innerText || '').trim())
                .filter(value => /^resets\s+/i.test(value) && value.length < 120 && !value.includes("%") && !value.includes("\n")))];
              cards.push({id, text, resetText: resets.length === 1 ? resets[0] : null,
                resetISO: /reset/i.test(text) && iso && /(?:Z|[+-]\d{2}:\d{2})$/.test(iso) ? iso : null});
              break;
            }
          }
          if (cards.some(card => card.id === id)) break;
        }
      }
      return JSON.stringify(cards);
    })()
    """#
}
