# Checking a page renders: headless Chromium

The box has no display. It can still render a web page and hand you a
screenshot, so that you check what a dev server shows instead of guessing from
the HTML. This is what to do when a task says "check the page looks right",
"take a screenshot", "does the layout break on mobile", or when a change to a
front end deserves a look before you call it done.

## Install it once

Chromium is not in the image, on purpose: it weighs about half a gigabyte and
most boxes never need it. It is a `devbox dev-env` environment, installed on
demand:

```bash
devbox dev-env browser
```

Behind it, `devbox pkg add chromium noto-fonts`: pacman packages that
`devbox pkg` reinstalls after a rebuild, so the browser is there for good.
`noto-fonts` matters: without it the only font in the box is Liberation, and
pages with emojis, symbols or non Latin scripts render squares. Both packages
exist on amd64 and on Arch Linux ARM, so the same command works on a Raspberry
Pi. The same environment adds `agent-browser` through mise, a single binary,
and points it at that Chromium in `~/.agent-browser/config.json`.

`devbox dev-env --list` marks it when this box already has it, and
`command -v chromium agent-browser` says the same. Never `sudo pacman -S
chromium`: pacman alone is forgotten at the next rebuild. Never
`npx playwright install` nor a Puppeteer download either: those browsers are
built for Debian and Ubuntu, weigh hundreds of megabytes in `~/.cache`, and
the system Chromium does the same job. `devbox dev-env --remove browser`
takes it out.

## Drive a page: agent-browser first

`agent-browser` is the tool to reach for as soon as the check goes beyond one
screenshot: clicks, form input, several steps, reading what changed. No script
to write, no `npm install`, every step is one command and the browser stays
open between them:

```bash
agent-browser open http://localhost:3000
agent-browser snapshot                  # accessibility tree, each element with a ref (@e2)
agent-browser click @e2                 # or a CSS selector: agent-browser click "button.save"
agent-browser fill "#email" "a@b.c"
agent-browser get text "#result"
agent-browser eval "document.title"
agent-browser screenshot /tmp/page.png  # --full for the whole page
agent-browser close
```

`snapshot` is usually worth more than a screenshot: it lists what is on the
page with a ref per element, to click or fill next. `agent-browser --help`
has the rest: `wait`, `press`, `mouse`, `scroll`, `set viewport`, `record`,
`batch` for several commands in one call, `--session` to keep two pages apart.
It runs the system Chromium headless, sandbox included, with nothing to add.

## Screenshot a page

```bash
chromium --headless --no-sandbox --disable-gpu --hide-scrollbars \
  --window-size=1280,800 --screenshot=/tmp/page.png http://localhost:3000
```

Then open `/tmp/page.png` the way you open any image file and look at it.

- `--no-sandbox` is required: the Chromium sandbox needs user namespaces the
  container does not hand out, and without the flag Chromium exits at once.
- `--disable-gpu` costs nothing: headless Chromium renders in software
  (SwiftShader) in the box, even when the host GPU is passed through
  `/dev/dri` and `devbox gpu install` has run. Checked on an Intel iGPU:
  no flag (`--use-angle=vulkan`, `gl-egl`, `--ignore-gpu-blocklist`, the
  Vaapi features) makes it pick the GPU up, some even turn WebGL off. Do not
  spend time on it; ffmpeg and native Vulkan are what the GPU serves here.
- `--window-size=390,844` gives a phone viewport, `1920,1080` a desktop one.
  Run both when the question is about responsive layout.
- `--virtual-time-budget=5000` lets a page that renders client side (React,
  Vue, Svelte) finish before the capture. Without it a single page app is
  often captured blank.
- `--screenshot` captures the viewport only. For the whole page, use
  Playwright or Puppeteer below with `fullPage: true`.
- Chromium writes a few warnings on stderr about dbus and the GPU. They are
  noise: the screenshot is fine.

Wait for the dev server to answer before capturing. Playwright and Puppeteer
retry on their own, a bare Chromium does not:

```bash
until curl -fsS -o /dev/null http://localhost:3000; do sleep 1; done
```

## Read what the page became

`--dump-dom` prints the DOM after scripts ran, which is what a user's browser
would show, unlike `curl`, which returns the HTML before any JavaScript:

```bash
chromium --headless --no-sandbox --disable-gpu --virtual-time-budget=5000 \
  --dump-dom http://localhost:3000 > /tmp/page.html
```

Handy to check that a component mounted, a fetch filled a list, or a text is
present, without a screenshot.

## Playwright or Puppeteer

When a project already uses Playwright or Puppeteer, or when a long scenario
really needs a script (a game loop, timings, many screenshots in a row), drive
the system Chromium rather than the browser those libraries download. The
bundled builds target Debian and Ubuntu, complain about the distribution on
Arch, and miss libraries on arm64. The system one works on both
architectures.

Playwright: install it with `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i playwright`
and give `executablePath` to `launch`. There is no environment variable for
it: without `executablePath`, Playwright looks for its own browser and tells
you to run `npx playwright install`, which is the wrong fix here.

```js
// shot.mjs
import { chromium } from "playwright";
const browser = await chromium.launch({ executablePath: "/usr/bin/chromium", args: ["--no-sandbox"] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await page.goto("http://localhost:3000", { waitUntil: "networkidle" });
await page.screenshot({ path: "/tmp/page.png", fullPage: true });
await browser.close();
```

The same with Puppeteer, `executablePath: "/usr/bin/chromium"` in the
`launch` options and `PUPPETEER_SKIP_DOWNLOAD=1` at `npm install` time.

Install the library in the project, not globally, and only if the project
does not have it already. Do not add it to a project only to take one
screenshot or click through a page: `chromium --screenshot` and
`agent-browser` above do that with nothing to install.

## Where the page comes from

The page has to be reachable from inside the box. `http://localhost:<port>`
works for a server started in the box. A server running in a podman container
started from the box is reachable on the port it publishes, `-p 3000:3000`.
A page on the tailnet is reachable by the machine's tailnet name when Tailscale
is on.

## When it does not work

- `chromium: command not found` or `agent-browser: command not found`: run
  `devbox dev-env browser`.
- Playwright says `Executable doesn't exist at ~/.cache/ms-playwright/...`:
  `executablePath: "/usr/bin/chromium"` is missing from `launch`; do not run
  `npx playwright install`.
- exits at once with a message about the sandbox or namespaces: `--no-sandbox`
  is missing.
- a blank or half drawn screenshot: add `--virtual-time-budget=5000`, or wait
  for the server before capturing.
- squares in place of characters: `noto-fonts` is missing, `fc-list | wc -l`
  should be well above 20.
- `ERR_CONNECTION_REFUSED` in the screenshot: nothing listens on that port
  inside the box; check the server is up and which port it took.
