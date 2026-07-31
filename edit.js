/* ═══════════════════════════════════════════════════════════════════════
   Sunflower Café — in-place edit mode.

   Loaded ONLY when the storefront is opened with ?edit=1 by someone whose tab
   already holds the admin passphrase, so ordinary visitors never download a
   byte of it.

   Editing model, and why (carried over from Ariana Bakehouse):
   • All copy is stored as PLAIN TEXT in one `sf_content` row (section 'copy'),
     applied with textContent. Nothing here ever writes innerHTML — a stored
     string can therefore never inject markup into a public page, even if the
     database were tampered with.
   • Elements opt in with data-edit="<key>". Design that needs markup (the
     hero's italic word, the line break) is split into several keys rather
     than storing HTML.
   • Menu items are edited through the same passphrase-gated definer RPCs the
     back office uses. Edit mode adds no new privilege and no new write path.
   ═══════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var CFG = window.SF_CONFIG || {};
  var PASS = '';
  try { PASS = sessionStorage.getItem('sf_pass') || ''; } catch (e) {}
  if (!PASS || !CFG.SUPA_URL) return;

  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return [].slice.call((r || document).querySelectorAll(s)); };

  function rpc(fn, body) {
    var ctl = (typeof AbortController !== 'undefined') ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctl) ctl.abort(); }, 20000);
    return fetch(CFG.SUPA_URL + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: { apikey: CFG.SUPA_KEY, Authorization: 'Bearer ' + CFG.SUPA_KEY,
                 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
      signal: ctl ? ctl.signal : undefined
    }).then(function (r) {
      clearTimeout(timer);
      return r.text().then(function (t) {
        var d = null;
        try { d = t ? JSON.parse(t) : null; } catch (e) { d = t; }
        return { ok: r.ok, status: r.status, data: d,
                 message: (d && d.message) ? d.message : '' };
      });
    })['catch'](function (e) {
      clearTimeout(timer);
      return { ok: false, status: 0, message: String(e && e.message || e) };
    });
  }
  function api(path) {
    return fetch(CFG.SUPA_URL + '/rest/v1/' + path, {
      headers: { apikey: CFG.SUPA_KEY, Authorization: 'Bearer ' + CFG.SUPA_KEY }
    }).then(function (r) { return r.ok ? r.json() : []; })['catch'](function () { return []; });
  }

  /* ── chrome ───────────────────────────────────────────────────────── */
  var CSS_TEXT = [
    '.ed-bar{position:fixed;left:50%;transform:translateX(-50%);bottom:18px;z-index:9000;',
    '  display:flex;gap:8px;align-items:center;background:#2B2018;color:#FBF6EF;',
    '  padding:9px 12px;border-radius:999px;box-shadow:0 14px 40px -12px rgba(0,0,0,.6);',
    '  font:600 13px/1 Inter,system-ui,sans-serif}',
    '.ed-bar b{font-weight:700;letter-spacing:.06em;text-transform:uppercase;font-size:11px;color:#E0A06E}',
    '.ed-bar button{font:inherit;border:0;border-radius:999px;padding:8px 13px;cursor:pointer;',
    '  background:#41332A;color:#FBF6EF;min-height:36px}',
    '.ed-bar button:hover{background:#54432F}',
    '[data-edit]{outline:1px dashed rgba(154,91,8,.45);outline-offset:3px;cursor:pointer;border-radius:3px}',
    '[data-edit]:hover{outline:2px solid #9A5B08;background:rgba(224,160,110,.16)}',
    '.ed-pencil{position:absolute;z-index:40;background:#9A5B08;color:#FBF6EF;border:0;',
    '  border-radius:999px;padding:5px 10px;font:600 11px/1 Inter,sans-serif;cursor:pointer;',
    '  top:8px;right:8px;min-height:30px}',
    '.p-card{position:relative}',
    '.ed-wrap{position:fixed;inset:0;z-index:9100;background:rgba(43,32,24,.5);',
    '  display:grid;place-items:center;padding:20px}',
    '.ed-sheet{background:#FFFDFA;color:#2B2018;border-radius:14px;padding:22px;width:min(520px,100%);',
    '  max-height:88vh;overflow:auto;box-shadow:0 30px 70px -20px rgba(0,0,0,.5);',
    '  font:15px/1.55 Inter,system-ui,sans-serif}',
    '.ed-sheet h3{font:600 20px/1.2 Fraunces,Georgia,serif;margin:0 0 6px}',
    '.ed-sheet .hint{font-size:13px;color:#756351;margin:0 0 16px}',
    '.ed-sheet label{display:block;font-size:12px;font-weight:600;letter-spacing:.05em;',
    '  text-transform:uppercase;color:#5A4A3C;margin:12px 0 5px}',
    '.ed-sheet input,.ed-sheet textarea,.ed-sheet select{width:100%;font:inherit;font-size:16px;',
    '  padding:11px 13px;border:1px solid rgba(43,32,24,.18);border-radius:10px;background:#FBF6EF;color:#2B2018}',
    '.ed-sheet textarea{min-height:96px;resize:vertical}',
    '.ed-sheet input:focus,.ed-sheet textarea:focus,.ed-sheet select:focus{outline:none;',
    '  border-color:#9A5B08;box-shadow:0 0 0 3px rgba(154,91,8,.24)}',
    '.ed-row{display:flex;gap:9px;align-items:center;margin-top:20px}',
    '.ed-row .sp{margin-left:auto}',
    '.ed-btn{font:600 14px/1 Inter,sans-serif;border:0;border-radius:999px;padding:12px 18px;',
    '  cursor:pointer;background:#9A5B08;color:#FBF6EF;min-height:44px}',
    '.ed-btn.sec{background:transparent;color:#2B2018;border:1px solid rgba(43,32,24,.18)}',
    '.ed-btn.danger{background:transparent;color:#9A3A12;border:1px solid rgba(154,58,18,.35)}',
    '.ed-btn[disabled]{opacity:.6;cursor:default}',
    '.ed-msg{font-size:13px;color:#9A3A12;margin-top:10px;min-height:18px}',
    '.ed-toast{position:fixed;left:50%;transform:translateX(-50%);bottom:74px;z-index:9200;',
    '  background:#2B2018;color:#FBF6EF;padding:10px 16px;border-radius:999px;',
    '  font:600 13px/1 Inter,sans-serif;box-shadow:0 12px 30px -10px rgba(0,0,0,.5)}',
    '.ed-toast.bad{background:#9A3A12}'
  ].join('');

  function injectCSS() {
    var s = document.createElement('style');
    s.textContent = CSS_TEXT;
    document.head.appendChild(s);
  }

  var toastEl;
  function toast(text, bad) {
    if (!toastEl) { toastEl = document.createElement('div'); document.body.appendChild(toastEl); }
    toastEl.className = 'ed-toast' + (bad ? ' bad' : '');
    toastEl.textContent = text;
    toastEl.style.display = '';
    clearTimeout(toast._t);
    toast._t = setTimeout(function () { toastEl.style.display = 'none'; }, 2600);
  }

  function sheet(opts) {
    var wrap = document.createElement('div');
    wrap.className = 'ed-wrap';
    var box = document.createElement('div');
    box.className = 'ed-sheet';
    wrap.appendChild(box);

    var h = document.createElement('h3'); h.textContent = opts.title; box.appendChild(h);
    if (opts.hint) {
      var p = document.createElement('p'); p.className = 'hint'; p.textContent = opts.hint;
      box.appendChild(p);
    }
    var body = document.createElement('div'); box.appendChild(body);
    var msg = document.createElement('p'); msg.className = 'ed-msg'; box.appendChild(msg);

    var row = document.createElement('div'); row.className = 'ed-row';
    var save = document.createElement('button'); save.className = 'ed-btn';
    save.textContent = opts.saveLabel || 'Save';
    var cancel = document.createElement('button'); cancel.className = 'ed-btn sec';
    cancel.textContent = 'Cancel';
    row.appendChild(save); row.appendChild(cancel);
    if (opts.onDelete) {
      var sp = document.createElement('span'); sp.className = 'sp'; row.appendChild(sp);
      var del = document.createElement('button'); del.className = 'ed-btn danger';
      del.textContent = 'Delete';
      del.addEventListener('click', function () {
        opts.onDelete(close, function (t) { msg.textContent = t; });
      });
      row.appendChild(del);
    }
    box.appendChild(row);

    function close() {
      if (wrap.parentNode) wrap.parentNode.removeChild(wrap);
      document.removeEventListener('keydown', onEsc);
    }
    function onEsc(e) { if (e.key === 'Escape') close(); }
    cancel.addEventListener('click', close);
    wrap.addEventListener('click', function (e) { if (e.target === wrap) close(); });
    document.addEventListener('keydown', onEsc);
    save.addEventListener('click', function () {
      save.disabled = true; save.textContent = 'Saving…';
      opts.onSave(close, function (t) {
        msg.textContent = t; save.disabled = false; save.textContent = opts.saveLabel || 'Save';
      });
    });

    document.body.appendChild(wrap);
    opts.build(body, box);
    var first = body.querySelector('input,textarea,select');
    if (first) first.focus();
    return { close: close, msg: msg };
  }

  function field(parent, label, value, type) {
    var l = document.createElement('label'); l.textContent = label; parent.appendChild(l);
    var el = document.createElement(type === 'textarea' ? 'textarea' : 'input');
    if (type && type !== 'textarea') el.type = type;
    el.value = value == null ? '' : value;
    parent.appendChild(el);
    return el;
  }
  function select(parent, label, value, options) {
    var l = document.createElement('label'); l.textContent = label; parent.appendChild(l);
    var el = document.createElement('select');
    options.forEach(function (o) {
      var op = document.createElement('option');
      op.value = o[0]; op.textContent = o[1];
      if (String(o[0]) === String(value)) op.selected = true;
      el.appendChild(op);
    });
    parent.appendChild(el);
    return el;
  }

  /* ── copy (every plain-text string on the page) ───────────────────── */
  var COPY = {};
  function loadCopy() {
    return api('sf_content?select=section,data&section=eq.copy').then(function (rows) {
      COPY = (rows && rows[0] && rows[0].data) || {};
      return COPY;
    });
  }
  function saveCopy(next, done, fail) {
    rpc('sf_save_content', { p_pass: PASS, p_section: 'copy', p_data: next }).then(function (r) {
      if (r.ok) { COPY = next; done(); }
      else fail('Save failed — ' + (r.message || ('HTTP ' + r.status)));
    });
  }
  function editText(el) {
    var key = el.getAttribute('data-edit');
    var current = el.textContent;
    var input;
    sheet({
      title: 'Edit text',
      hint: 'Plain text only. This replaces the words in place, everywhere they appear on the site.',
      build: function (body) {
        input = field(body, key.replace(/\./g, ' › '), current, current.length > 60 ? 'textarea' : 'text');
      },
      onSave: function (close, fail) {
        var v = input.value.trim();
        if (!v) return fail('Text cannot be empty. Use Cancel to leave it unchanged.');
        var next = {};
        Object.keys(COPY).forEach(function (k) { next[k] = COPY[k]; });
        next[key] = v;
        saveCopy(next, function () { el.textContent = v; close(); toast('Saved'); }, fail);
      }
    });
  }

  /* ── menu items ───────────────────────────────────────────────────── */
  var ITEMS = [], CATS = [];
  var GLYPHS = ['pancakes','omelet','skillet','benedict','egg','sandwich','burger','wrap',
                'quesadilla','tortilla','fish','wings','curds','soup','salad','steak','bacon',
                'toast','fries','pie','coffee','tea','milk','juice','soda','kids','plate'];

  function loadItems() {
    return Promise.all([
      api('sf_categories?select=key,label,sort&order=sort.asc'),
      api('sf_menu?select=id,slug,name,category,blurb,price_cents,unit,glyph,badge,sort,featured,active&order=category.asc,sort.asc')
    ]).then(function (r) { CATS = r[0] || []; ITEMS = r[1] || []; });
  }
  function itemBySlug(slug) {
    for (var i = 0; i < ITEMS.length; i++) if (ITEMS[i].slug === slug) return ITEMS[i];
    return null;
  }

  function editItem(slug) {
    var it = itemBySlug(slug);
    if (!it) { toast('That item is not loaded yet', true); return; }
    var fName, fPrice, fBlurb, fBadge, fCat, fGlyph, fFeat, fActive;
    sheet({
      title: it.name,
      hint: 'Priced at $0.00 keeps the dish on the menu but marks it “ask” — it cannot be pre-ordered.',
      build: function (body) {
        fName  = field(body, 'Name', it.name, 'text');
        fPrice = field(body, 'Price (dollars)', (it.price_cents / 100).toFixed(2), 'number');
        fPrice.step = '0.01'; fPrice.min = '0';
        fBlurb = field(body, 'Description', it.blurb || '', 'textarea');
        fBadge = field(body, 'Badge (optional)', it.badge || '', 'text');
        fCat   = select(body, 'Section', it.category, CATS.map(function (c) { return [c.key, c.label]; }));
        fGlyph = select(body, 'Placeholder drawing', it.glyph || 'plate',
                        GLYPHS.map(function (g) { return [g, g]; }));
        fFeat  = select(body, 'Show in House favorites', String(!!it.featured), [['true','Yes'],['false','No']]);
        fActive= select(body, 'Shown on the site', String(!!it.active), [['true','Yes'],['false','Hidden']]);
      },
      onSave: function (close, fail) {
        var name = fName.value.trim();
        if (name.length < 2) return fail('Give the dish a name.');
        var dollars = parseFloat(fPrice.value);
        if (isNaN(dollars) || dollars < 0) dollars = 0;
        rpc('sf_save_item', {
          p_pass: PASS, p_id: it.id,
          p_data: {
            slug: it.slug,          /* keep the slug stable so past orders still resolve */
            name: name,
            category: fCat.value,
            blurb: fBlurb.value.trim(),
            badge: fBadge.value.trim(),
            glyph: fGlyph.value,
            price_cents: Math.round(dollars * 100),
            sort: it.sort,
            featured: fFeat.value === 'true',
            active: fActive.value === 'true'
          }
        }).then(function (r) {
          if (!r.ok) return fail('Save failed — ' + (r.message || ('HTTP ' + r.status)));
          close(); toast('Saved — reloading');
          setTimeout(function () { location.reload(); }, 700);
        });
      },
      onDelete: function (close, fail) {
        if (!confirm('Delete "' + it.name + '" from the menu? This cannot be undone.')) return;
        rpc('sf_delete_item', { p_pass: PASS, p_id: it.id }).then(function (r) {
          if (!r.ok) return fail('Delete failed — ' + (r.message || ('HTTP ' + r.status)));
          close(); toast('Deleted — reloading');
          setTimeout(function () { location.reload(); }, 700);
        });
      }
    });
  }

  /* ── hours ────────────────────────────────────────────────────────── */
  var DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  function editHours() {
    api('sf_content?select=data&section=eq.hours').then(function (rows) {
      var h = (rows && rows[0] && rows[0].data) || {};
      var days = (h.days && h.days.length === 7) ? h.days
        : DAYS.map(function (d) { return { label: d, open: '08:00', close: '15:00' }; });
      var opens = [], closes = [], shut = [], note;
      sheet({
        title: 'Hours',
        hint: 'The “Open now” chip on the page reads these, in the café’s own time zone.',
        build: function (body) {
          days.forEach(function (d, i) {
            shut[i]   = select(body, d.label, String(!!d.closed), [['false','Open'],['true','Closed']]);
            opens[i]  = field(body, d.label + ' — opens', d.open || '08:00', 'time');
            closes[i] = field(body, d.label + ' — closes', d.close || '15:00', 'time');
          });
          note = field(body, 'Note under the hours', h.note || '', 'text');
        },
        onSave: function (close, fail) {
          var next = {
            days: DAYS.map(function (d, i) {
              return { label: d, closed: shut[i].value === 'true',
                       open: opens[i].value || '08:00', close: closes[i].value || '15:00' };
            }),
            note: note.value.trim()
          };
          rpc('sf_save_content', { p_pass: PASS, p_section: 'hours', p_data: next }).then(function (r) {
            if (!r.ok) return fail('Save failed — ' + (r.message || ('HTTP ' + r.status)));
            close(); toast('Saved — reloading');
            setTimeout(function () { location.reload(); }, 700);
          });
        }
      });
    });
  }

  /* ── decorate ─────────────────────────────────────────────────────── */
  function decorate() {
    $$('.p-card').forEach(function (card) {
      if (card.querySelector('.ed-pencil')) return;
      var foot = card.querySelector('[data-foot]');
      if (!foot) return;
      var slug = foot.getAttribute('data-foot');
      var b = document.createElement('button');
      b.className = 'ed-pencil';
      b.type = 'button';
      b.textContent = 'Edit';
      b.addEventListener('click', function (e) {
        e.preventDefault(); e.stopPropagation();
        editItem(slug);
      });
      card.appendChild(b);
    });
  }

  function bar() {
    var el = document.createElement('div');
    el.className = 'ed-bar';
    var label = document.createElement('b'); label.textContent = 'Edit mode';
    el.appendChild(label);

    var hoursBtn = document.createElement('button');
    hoursBtn.type = 'button'; hoursBtn.textContent = 'Hours';
    hoursBtn.addEventListener('click', editHours);
    el.appendChild(hoursBtn);

    var adminBtn = document.createElement('button');
    adminBtn.type = 'button'; adminBtn.textContent = 'Back of house';
    adminBtn.addEventListener('click', function () { location.href = 'admin.html'; });
    el.appendChild(adminBtn);

    var doneBtn = document.createElement('button');
    doneBtn.type = 'button'; doneBtn.textContent = 'Done';
    doneBtn.addEventListener('click', function () {
      location.href = location.pathname;
    });
    el.appendChild(doneBtn);

    document.body.appendChild(el);
  }

  /* ── boot ─────────────────────────────────────────────────────────── */
  function boot() {
    injectCSS();
    bar();

    document.addEventListener('click', function (e) {
      var t = e.target.closest('[data-edit]');
      if (!t) return;
      e.preventDefault(); e.stopPropagation();
      editText(t);
    }, true);

    loadCopy();
    loadItems().then(function () {
      decorate();
      /* the catalog re-renders on filter and search — keep the pencils on */
      var host = document.getElementById('catalog');
      if (host && 'MutationObserver' in window) {
        new MutationObserver(decorate).observe(host, { childList: true, subtree: true });
      }
      var rail = document.getElementById('rail');
      if (rail && 'MutationObserver' in window) {
        new MutationObserver(decorate).observe(rail, { childList: true, subtree: true });
      }
    });
    toast('Edit mode — tap any text or dish');
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
