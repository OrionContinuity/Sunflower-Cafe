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
| `index.html` | The whole site. CSS and JS inline — it is the critical path. |
| `admin.html` | Passphrase-gated back office. `noindex`, and disallowed in robots.txt. |
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

Palette measured, not guessed — every text pair clears WCAG AA:

| | on parchment `#FDF8EE` |
| --- | --- |
| ink `#2B2118` | 14.88:1 |
| ink-soft `#57483A` | 8.29:1 |
| ink-faint `#71604F` | 5.69:1 |
| gold-deep `#9A5B08` | 5.12:1 |
| green `#3D6B39` | 5.90:1 |

Ink on the gold button runs 6.97:1; parchment on the deep-green footer is 8.39:1. The one
pairing that fails AA for body text — deep-gold on the deepest band tint (4.16:1) — is used
for borders only, never text. The ink is espresso rather than blue-grey: one cool ink undoes
a warm page.

Other rules the build follows: no autoplaying carousel anywhere, one IntersectionObserver
reveal system with reduced-motion guards in CSS *and* JS, 16px minimum on form fields to
stop iOS zoom-on-focus, 44px touch targets, header elevation driven by a sentinel observer
rather than a scroll listener, and date handling on local calendar fields rather than
`toISOString()` (which is UTC and pre-fills tomorrow in the evening).

The "open now" chip computes against `America/Chicago` via `Intl`, so it is correct for the
café regardless of where the visitor is.

## Still to do

- **Photography.** The hero is a hand-drawn SVG and says "Photography coming" rather than
  pretending. Real photos of the room and the plates are the single biggest upgrade here.
- **A domain.** Canonical URLs currently point at the GitHub Pages address.
- **Owner review of the menu**, especially the eleven unpriced items and anything Toast
  lists differently from the printed menu.
- **In-place edit mode** (`?edit=1`), the way Ariana Bakehouse has it. Not ported yet — the
  back office covers the same edits, this would just make them clickable on the page itself.
