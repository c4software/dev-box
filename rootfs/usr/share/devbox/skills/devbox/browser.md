# Checking a page renders: headless Chromium

The box has no display. It can still render a web page and hand you a
screenshot, so that you check what a dev server shows instead of guessing from
the HTML. This is what to do when a task says "check the page looks right",
"take a screenshot", "does the layout break on mobile", or when a change to a
front end deserves a look before you call it done.

## Install it once

Chromium is not in the image, on purpose: it weighs about half a gigabyte and
most boxes never need it. It is installed on demand, and comes back after a
rebuild because `devbox pkg` remembers it:

```bash
devbox pkg add chromium noto-fonts
```

`noto-fonts` matters: without it the only font in the box is Liberation, and
pages with emojis, symbols or non Latin scripts render squares. Both packages
exist on amd64 and on Arch Linux ARM, so the same command works on a Raspberry
Pi.

`command -v chromium` tells you whether this box already has it. Never
`sudo pacman -S chromium`: pacman alone is forgotten at the next rebuild.

## Screenshot a page

```bash
chromium --headless --no-sandbox --disable-gpu --hide-scrollbars \
  --window-size=1280,800 --screenshot=/tmp/page.png http://localhost:3000
```

Then open `/tmp/page.png` the way you open any image file and look at it.

- `--no-sandbox` is required: the Chromium sandbox needs user namespaces the
  container does not hand out, and without the flag Chromium exits at once.
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

When a project already uses Playwright or Puppeteer, or when the check needs
clicks, form input or a full page capture, drive the system Chromium rather
than the browser those libraries download. The bundled builds target Debian
and Ubuntu, complain about the distribution on Arch, and miss libraries on
arm64. The system one works on both architectures.

Playwright, without `npx playwright install`:

```bash
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium node shot.mjs
```

```js
// shot.mjs
import { chromium } from "playwright";
const browser = await chromium.launch({ args: ["--no-sandbox"] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await page.goto("http://localhost:3000", { waitUntil: "networkidle" });
await page.screenshot({ path: "/tmp/page.png", fullPage: true });
await browser.close();
```

The same with Puppeteer, `executablePath: "/usr/bin/chromium"` in the
`launch` options and `PUPPETEER_SKIP_DOWNLOAD=1` at `npm install` time.

Install the library in the project, not globally, and only if the project
does not have it already. Do not add it to a project only to take one
screenshot: the bare `chromium --screenshot` above does that.

## Where the page comes from

The page has to be reachable from inside the box. `http://localhost:<port>`
works for a server started in the box. A server running in a podman container
started from the box is reachable on the port it publishes, `-p 3000:3000`.
A page on the tailnet is reachable by the machine's tailnet name when Tailscale
is on.

## When it does not work

- `chromium: command not found`: run `devbox pkg add chromium noto-fonts`.
- exits at once with a message about the sandbox or namespaces: `--no-sandbox`
  is missing.
- a blank or half drawn screenshot: add `--virtual-time-budget=5000`, or wait
  for the server before capturing.
- squares in place of characters: `noto-fonts` is missing, `fc-list | wc -l`
  should be well above 20.
- `ERR_CONNECTION_REFUSED` in the screenshot: nothing listens on that port
  inside the box; check the server is up and which port it took.
