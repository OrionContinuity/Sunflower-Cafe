# Sunflower Café

The website for Sunflower Café — 2301 Church Street, Stevens Point, Wisconsin.
Built the way GBC and Ariana Bakehouse are built: hand-written static HTML, zero
dependencies, Supabase behind it for anything that changes.

Live at **https://orioncontinuity.github.io/Sunflower-Cafe/** (GitHub Pages, `main`, root).

---

## Run it

It is static. Open `index.html`, or serve the folder:

```sh
python3 -m http.server 8080
```

With `config.js` blank the site runs in **static mode**: a small baked-in menu renders
and the pre-order form falls back to a pre-filled email. Nothing breaks without a backend.

## The backend

Lives in the shared **WebApps** Supabase project (`unfjnmrjmidrfmmtyhpe`), alongside
`gbc_*` and `ar_*`. Every table and function here is prefixed `sf_` so the three sites
never collide. `supabase-setup.sql` has already been applied.

To stand it up somewhere else: change `CHANGE-ME-NOW` in `supabase-setup.sql` to a real
passphrase, run the whole file in that project's SQL editor, and put the project URL and
publishable key into `config.js`.

## Where the menu came from

The 190 items — names, descriptions and prices — were imported on **2026-07-31** from the
café's own live Toast ordering menu, and the hours and phone number from the same source.
Categories follow Toast's own sections and order.

**The menu is data, not code.** It is not seeded in `supabase-setup.sql`, so re-running that
file can never clobber a price the owner has since corrected. From here on the menu is
maintained in the back office.

Eleven items came across without a price (they are priced at the counter on Toast). An item
priced at $0.00 still appears on the menu, reads *"ask"* instead of a price, and **cannot be
added to a pre-order** — `sf_submit_order` drops unpriced lines server-side, so nothing can
be ordered for free.

## Files

| Path | What it is |
| --- | --- |
| `index.html` | The whole site. CSS, JS and the illustration sprite inline — it is the critical path. |
| `admin.html` | Passphrase-gated back office. `noindex`, and disallowed in robots.txt. |
| `edit.js` | In-place edit mode. Loaded **only** at `?edit=1` and only when the tab already holds the passphrase, so ordinary visitors never download it. |
| `supabase-setup.sql` | Schema, RLS, and every RPC. Run once. |
| `config.js` | The only file with credentials in it. |
| `favicon.svg`, `404.html`, `robots.txt`, `sitemap.xml` | The usual furniture. |

## How the security model works

Same shape as GBC and Ariana, which came out of the NEXUS hardening:

- Public tables are **read-only to anon**. There is not a single write policy.
- Every write goes through a `security definer` RPC that checks a bcrypt passphrase
  first, with `search_path` pinned.
- Supabase auto-grants `EXECUTE` on new functions, so the setup script **revokes**
  `PUBLIC` and `authenticated` explicitly, then re-grants only `anon` and `service_role`.
- `sf_orders`, `sf_events` and `sf_auth_attempts` hold customer data and have **no select
  policy at all** — the anon key can write an order through the RPC but cannot read one back.
- Sign-in goes through `sf_admin_login`, which **rate-limits to 8 failures per IP per 15
  minutes**. `sf_check_admin` is revoked from `anon` entirely, so it cannot be used as an
  unthrottled passphrase oracle.
- The order funnel has a honeypot field, a per-IP hourly limit and a global daily ceiling,
  and derives the client IP from `cf-connecting-ip` rather than the spoofable left-most
  `x-forwarded-for` hop.
- **Prices are never trusted from the browser.** `sf_submit_order` re-prices every line
  against `sf_menu` and computes the total itself, so a tampered cart cannot change what an
  order is worth.

## Design notes

The design system is Ariana Bakehouse's, carried over deliberately rather than
reinvented: the same warm parchment and paper grain, the same numbered section
kickers, pill buttons that press on `:active`, scroll-snap rail, dish cards,
stepper, sticky tray, mobile dock and one-shot reveals. Only the accent moved —
copper became the café's deeper sunflower gold.

Palette measured, not guessed. Every text pair clears WCAG AA on every surface
it is actually used on:

| | on parchment `#FBF6EF` | on card `#FFFDFA` | on band `#F3EADD` |
| --- | --- | --- | --- |
| ink `#2B2018` | 14.77:1 | 15.64:1 | 13.33:1 |
| ink-soft `#5A4A3C` | 7.88:1 | 8.34:1 | 7.11:1 |
| ink-faint `#756351` | 5.34:1 | 5.65:1 | 4.82:1 |
| gold `#9A5B08` | 5.04:1 | 5.34:1 | 4.55:1 |
| pistachio `#4F6B3C` | 5.58:1 | — | — |

Parchment on gold runs 5.04:1 and on gold-deep 6.86:1, so the filled buttons
carry light text safely. `#EADCC9` is the dark end of the card-art gradient and
never a text background — gold on it is 4.02:1, which is why nothing reads there.
The ink is espresso rather than a blue-grey: one cool ink undoes a warm page.

**Food placeholders.** There is no photography yet, so every dish gets a drawn
one. `index.html` carries an inline SVG sprite of 27 line illustrations —
pancakes, omelet, skillet, benedict, egg, sandwich, burger, wrap, quesadilla,
tortilla, fish, wings, curds, soup, salad, steak, bacon, toast, fries, pie,
coffee, tea, milk, juice, soda, kids and a generic plate — and each item's
`glyph` column picks one. They were assigned in bulk by keyword against the
real dish names, and the back office (or edit mode) can change any of them.
The moment a real photo goes in an item's `image` field, the drawing steps aside.

Other rules the build follows: `[hidden]{display:none !important}` at the reset
(an author `display` rule outranks the UA rule, which once left a login gate
covering a working dashboard on Ariana), no autoplaying carousel anywhere, one
IntersectionObserver reveal system with reduced-motion guards in CSS *and* JS,
16px minimum on form fields to stop iOS zoom-on-focus, 44px touch targets,
header elevation and dock visibility from a sentinel observer rather than a
scroll listener, extra footer padding under the mobile dock so the last row
stays reachable, and date handling on local calendar fields rather than
`toISOString()` (which is UTC and pre-fills tomorrow in the evening).

The "open now" chip computes against `America/Chicago` via `Intl`, so it is
correct for the café regardless of where the visitor is.

## Editing the site

Two ways in, both gated by the same passphrase and the same RPCs:

- **`admin.html`** — orders inbox, the full menu, page text, hours and contact
  details, plus a small analytics tile.
- **`?edit=1`** — open the site itself in edit mode from the back office's
  *Edit on the page* button. Every string with a `data-edit` key becomes
  clickable, every dish card grows an Edit button, and the toolbar has the
  hours editor. Copy is stored and applied as plain text with `textContent`,
  so a stored string can never inject markup into a public page.

## Still to do

- **Photography.** The hero is a hand-drawn SVG and says "Photography coming" rather than
  pretending. Real photos of the room and the plates are the single biggest upgrade here.
- **A domain.** Canonical URLs currently point at the GitHub Pages address.
- **Owner review of the menu**, especially the eleven unpriced items and anything Toast
  lists differently from the printed menu.
- **A journal**, the way Ariana Bakehouse has one. Deliberately not built: there is
  nothing true to put in it yet, and inventing café news would be worse than an
  empty section.
