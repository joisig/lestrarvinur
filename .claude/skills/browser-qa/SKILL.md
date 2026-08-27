---
name: browser-qa
description: Launch the Lestrarvinur Phoenix server and drive it with a headless browser (Python Playwright) to QA features and visually validate UI — screenshots at iPad-first breakpoints, simulated touch/swipe input, console and network error checks. Use when asked to run, QA, screenshot, or visually verify the app in a real browser.
---

# Browser QA for Lestrarvinur

Verify UI changes by driving the real app in headless Chromium, not just by
running `mix test`. Always end with a screenshot and **look at it** with the
Read tool. A blank white screenshot means the step failed (bad URL, crashed
LiveView) — check `page.url()` and the console log, don't just reshoot.

Evidence lives under repo `tmp/qa/` (gitignored) when it should outlive the
session; throwaway shots can go to the session scratchpad.

## 1. Probes first

Run at the start of any QA run and report anything down before proceeding:

```bash
curl -sf -o /dev/null http://localhost:4000/ && echo phoenix-up
```

If Phoenix is down:

```bash
(lsof -ti:4000 -sTCP:LISTEN | xargs -r kill) 2>/dev/null
nohup mix phx.server > tmp/qa/phx.log 2>&1 &
timeout 60 bash -c 'until curl -sf http://localhost:4000 >/dev/null; do sleep 1; done'
```

Poll the port; never fixed sleeps. Never start a second copy. Stop it with the
`lsof -ti:4000 ... kill` line — NOT `pkill -f` with a broad pattern, which can
kill the agent session itself.

**The dev DB (`lestrarvinur_phoenix_dev.db`) is the kids' live progress data.**
Do not reset, bulk-mutate, or advance progress on real users. Create throwaway
users for QA (`Accounts.create_user/1`) or use the login-free test routes.

## 2. Drive with Python Playwright

Python Playwright is installed system-wide (`python3 -m playwright install
chromium` if the browser is missing). Plain launch works:

```python
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(args=["--disable-gpu"])
    page = browser.new_page(viewport={"width": 1180, "height": 820})
    errors = []
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("response", lambda r: errors.append(f"{r.status} {r.url}") if r.status >= 400 else None)
    page.goto("http://localhost:4000/pacman-test", wait_until="domcontentloaded")
    page.wait_for_selector(".phx-connected", timeout=10000)
    page.screenshot(path="tmp/qa/shot.png")
```

Rules that matter:

- Register the console/pageerror/response listeners on every run and report
  what they caught alongside the visual findings — a page can render its shell
  while every JS handler throws or a fetch 500s.
- `goto(..., wait_until="domcontentloaded")`, never `networkidle` — LiveView
  holds a websocket open, so networkidle waits hang.
- Settle LiveView with `wait_for_selector(".phx-connected")`, then wait for
  the element you actually need.
- The app is tablet-first: simulate swipes/drags with `page.mouse.down()` →
  stepped `page.mouse.move()` → `page.mouse.up()`.

**Sandboxed-harness fallback:** when the Claude Code Bash sandbox is ON,
`chromium.launch()` dies with `bootstrap_check_in ... Permission denied (1100)`
(macOS denies Chromium's Mach port registration). Workaround: launch the
bundled headless shell yourself with `--single-process
--remote-debugging-port=9222`, wait for `curl -sf
http://127.0.0.1:9222/json/version`, then
`p.chromium.connect_over_cdp("http://127.0.0.1:9222")` — connect via
`127.0.0.1`, not `localhost` (Playwright resolves `localhost` to `::1`;
Chromium listens on IPv4). In single-process mode new contexts fail: reuse
`browser.contexts[0]` and its existing page. Clean up with
`pkill -f chrome-headless-shell`.

## 3. Responsive validation

For screenshot-look-iterate UI work, shoot each screen at the breakpoints and
Read all of them, judging layout breaks, overlap, truncated text, dark-on-dark:

```python
for w, h, slug in [(1180, 820, "ipad-landscape"), (820, 1180, "ipad-portrait"), (375, 667, "phone")]:
    page.set_viewport_size({"width": w, "height": h})
    page.wait_for_timeout(700)
    page.screenshot(path=f"tmp/qa/SCREEN-{slug}.png")
```

iPad landscape is the primary device; the other two are sanity checks.

## 4. Key screens (extend as you QA new areas)

| Screen | Path | Notes |
|---|---|---|
| Login | `/` | username + password form, all UI in Icelandic |
| Dashboard | `/dashboard?username=<name>` | game LiveViews take username as query param — no session auth |
| Reading game | `/game?username=<name>` | tap advances flashcards; milestone minigame every 100 words |
| Math game | `/math-game?username=<name>` | tap the correct choice; milestone every 100 problems |
| Admin | `/admin` | |
| Dragon harness | `/dragon-test` | login-free minigame test pages |
| Centipede harness | `/centipede-test` | |
| Pac-Man harness | `/pacman-test` (`?mode=math` for math problems) | Phaser; canvas at `#pacman-arena canvas` |
| Invaders harness | `/invaders-test` (`?mode=math`) | Phaser; canvas at `#invaders-arena canvas`; auto-fires, so its counter climbing with zero input is a free smoke check |

Phaser pages: wait for the canvas selector, then ~2s for the scene to draw
before screenshotting. The games boot PAUSED behind a start button — click
`[data-game-start]` before simulating any gameplay, or nothing will move
(the button click is also what unlocks audio on iOS, where only a clean
tap counts as a user gesture, not a drag). Add `?sfxdebug=1` to a game URL
for an on-screen AudioContext state readout (`#sfx-debug`). `--disable-gpu` in the launch args is REQUIRED for
them: without it, headless Chromium on this Mac creates a WebGL context whose
framebuffer is unsupported (console warns "Framebuffer status: Framebuffer
Unsupported") and Phaser silently draws into a black canvas. Disabling the
GPU makes Phaser fall back to its canvas renderer, which is pixel-fine. Progress pills sit top-left
(`#<game>-game > div.absolute.top-4.left-4`) — assert on them to prove the
`pushEvent` → LiveView round-trip, not just rendering.

## 5. Milestone flows

Reaching a real milestone game takes 100 words/problems — don't grind that in
a browser. The server-side flow (game selection, forced-game consumption,
counters, trophy handoff) is covered by
`test/lestrarvinur_phoenix_web/live/minigame_milestone_test.exs` (`mix test`);
use the browser only for the client-side game itself via the harness routes.

## Gotchas

- `mix phx.server` runs esbuild/tailwind watchers, so `assets/js` edits
  rebuild automatically. If a reload shows stale JS anyway, run
  `mix assets.build` and reload again.
- A selector that matches a hidden element first makes clicks wait until
  timeout — target by text or a tighter selector.
- Run QA flows sequentially — one shared dev DB, one server instance.
