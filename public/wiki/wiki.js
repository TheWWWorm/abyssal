// Reader for an exported DEEP reference. Pages are the exporter's escaped
// HTML; wiki:// links become in-page addresses, so Back and Forward work.
// Each language is its own content file, loaded when it is chosen.
(() => {
  const langs = window.DEEP_WIKI_LANGUAGES;
  const loaded = window.DEEP_WIKI_LANGS = window.DEEP_WIKI_LANGS || {};
  const page = document.getElementById('page');
  const media = document.getElementById('media');
  const results = document.getElementById('results');
  const search = document.getElementById('search');
  const categories = document.getElementById('categories');
  const language = document.getElementById('language');
  const count = document.getElementById('count');
  let data, byKey, label, order, category = 'all';
  const norm = s => s.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/ё/g, 'е');
  const score = (q, e) => {
    const t = norm(e.title), x = ' ' + norm(e.title + ' ' + e.subtitle).replace(/[^\p{L}\p{N}]+/gu, ' ');
    if (t === q) return 1000; if (t.startsWith(q)) return 800; if (t.includes(q)) return 600;
    return q.split(/\s+/).every(w => x.includes(' ' + w)) ? 300 : -1;
  };
  const byTitle = (a, b) => a.title.localeCompare(b.title, data.language, {numeric: true});
  const current = () => decodeURIComponent(location.hash.slice(1)) || 'home';
  function row(e, q) {
    const li = document.createElement('li'), a = document.createElement('a'), icon = document.createElement('span'), text = document.createElement('span');
    a.href = '#' + e.key; icon.className = 'icon';
    if (e.icon) { const img = document.createElement('img'); img.src = e.icon; img.alt = ''; icon.append(img); } else icon.append(document.createElement('i'));
    text.textContent = e.title;
    const note = e.subtitle || (q || category === 'all' ? label.get(e.category) : '');
    if (note) { const s = document.createElement('small'); s.textContent = note; text.append(s); }
    if (e.key === current()) a.className = 'current';
    a.append(icon, text); li.append(a); return li;
  }
  function list() {
    const q = norm(search.value.trim());
    let rows = data.index.filter(e => e.category);
    if (q) rows = rows.map(e => [score(q, e), e]).filter(r => r[0] >= 0).sort((a, b) => b[0] - a[0] || byTitle(a[1], b[1])).map(r => r[1]);
    else {
      if (category !== 'all') rows = rows.filter(e => e.category === category);
      rows = [...rows].sort((a, b) => order.indexOf(a.category) - order.indexOf(b.category) || (a.category === 'story' ? 0 : byTitle(a, b)));
    }
    const items = []; let section = '';
    for (const e of rows) {
      if (!q && category === 'all' && e.category !== section) {
        section = e.category; const h = document.createElement('li'); h.className = 'section'; h.textContent = label.get(section); items.push(h);
      }
      items.push(row(e, q));
    }
    results.replaceChildren(...items);
    count.textContent = rows.length + ' / ' + data.index.filter(e => e.category).length;
    const here = results.querySelector('a.current'); if (here) here.scrollIntoView({block: 'nearest'});
  }
  // Every station at its chart position, coloured by who holds it at the
  // figure's chapter; stations joining then are ringed, the page's own named.
  function chart(figure) {
    const ns = 'http://www.w3.org/2000/svg', svg = document.createElementNS(ns, 'svg');
    const here = Number(figure.dataset.highlight), asOf = Number(figure.dataset.asOf);
    const joining = (figure.dataset.joining || '').split(',').filter(Boolean).map(Number);
    svg.setAttribute('viewBox', '0 0 100 100');
    data.stations.forEach(([x, y, since], id) => {
      const a = document.createElementNS(ns, 'a'), dot = document.createElementNS(ns, 'circle'), name = document.createElementNS(ns, 'title');
      a.setAttribute('href', '#station/' + id);
      dot.setAttribute('class', (since >= 0 && since <= asOf ? 'rebel' : 'colonist') + (joining.includes(id) ? ' joining' : '') + (id === here ? ' here' : ''));
      dot.setAttribute('cx', x); dot.setAttribute('cy', y); dot.setAttribute('r', id === here ? 2.2 : joining.includes(id) ? 1.5 : 0.9);
      name.textContent = (byKey.get('station/' + id) || {}).title || ''; dot.append(name); a.append(dot); svg.append(a);
    });
    if (here >= 0 && data.stations[here]) {
      const [x, y] = data.stations[here], text = document.createElementNS(ns, 'text');
      text.setAttribute('x', Math.min(Math.max(x + 3, 0), 80)); text.setAttribute('y', Math.min(Math.max(y - 3, 4), 98));
      text.textContent = (byKey.get('station/' + here) || {}).title || ''; svg.append(text);
    }
    const caption = document.createElement('figcaption'); caption.textContent = data.stations.every(([x, y, since]) => since >= 0 && since <= asOf) ? data.chart_all : data.chart;
    figure.replaceChildren(svg, caption);
  }
  function show() {
    const key = current(), entry = byKey.get(key);
    page.innerHTML = (data.pages[key] || data.pages.home).replace(/wiki:\/\//g, '#');
    page.querySelectorAll('figure.chart').forEach(chart);
    media.replaceChildren();
    const figure = page.querySelector('figure.chart'), src = data.media[key];
    if (src || figure) {
      const frame = document.createElement('div'); frame.className = 'frame';
      if (src) { const img = document.createElement('img'); img.src = src; img.alt = entry ? entry.title : ''; if (src.includes('/render-')) img.className = 'render'; frame.append(img); }
      else frame.append(figure.cloneNode(true));
      media.append(frame);
      if (data.sprites && data.sprites[key]) { const sprite = document.createElement('img'); sprite.src = data.sprites[key]; sprite.alt = ''; sprite.className = 'sprite'; media.append(sprite); }
      if (src && figure) { const second = document.createElement('div'); second.className = 'frame'; second.append(figure.cloneNode(true)); media.append(second); }
    }
    media.hidden = !media.childElementCount;
    document.title = (entry ? entry.title + ' · ' : '') + 'DEEP ' + data.title;
    document.body.classList.remove('browsing');
    list(); document.getElementById('sheet').scrollTop = 0; page.focus({preventScroll: true});
  }
  function load(code, then) {
    if (loaded[code]) return then(code);
    const script = document.createElement('script');
    script.src = 'content-' + code + '.js';
    script.onload = () => then(loaded[code] ? code : langs.first);
    script.onerror = () => code === langs.first ? null : load(langs.first, then);
    document.head.append(script);
  }
  function use(code) {
    load(code, found => {
      data = loaded[found]; language.value = found;
      try { localStorage.setItem('deep-reference-language', found); } catch (e) {}
      byKey = new Map(data.index.map(e => [e.key, e]));
      label = new Map(data.categories); order = data.categories.map(c => c[0]);
      document.documentElement.lang = found;
      document.getElementById('title').textContent = data.title;
      search.placeholder = data.search; search.setAttribute('aria-label', data.search);
      document.getElementById('browse').textContent = data.browse;
      document.getElementById('play').textContent = data.play;
      const options = [];
      for (const [name, title] of [['all', data.all], ...data.categories]) {
        if (name !== 'all' && !data.index.some(e => e.category === name)) continue;
        const o = document.createElement('option'); o.value = name; o.textContent = title; options.push(o);
      }
      categories.replaceChildren(...options);
      if (!options.some(o => o.value === category)) category = 'all';
      categories.value = category;
      show();
    });
  }
  for (const [code, name] of langs.list) {
    const o = document.createElement('option'); o.value = code; o.textContent = name; language.append(o);
  }
  language.setAttribute('aria-label', langs.label); language.title = langs.label;
  language.hidden = langs.list.length < 2;
  language.onchange = () => use(language.value);
  categories.onchange = () => { category = categories.value; search.value = ''; list(); };
  search.addEventListener('input', () => { document.body.classList.add('browsing'); list(); });
  document.getElementById('browse').onclick = () => document.body.classList.toggle('browsing');
  window.addEventListener('hashchange', show);
  let stored = null;
  try { stored = localStorage.getItem('deep-reference-language'); } catch (e) {}
  use(langs.list.some(l => l[0] === stored) ? stored : langs.first);
})();
