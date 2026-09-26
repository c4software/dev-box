# Coding agents

The image ships wrappers for `claude` (Claude Code), `pi`, `omp`, `opencode`
and `codex`, installed through mise on their first call (see
[tools.md](tools.md#dev-tools-mise)). This page covers picking which one runs,
reading its account limits, the skill that teaches them how the box works, and
where their config files come from.

## The default coding agent

`devbox agent` remembers one agent for the box, in `~/.config/dev-box/agent`,
and launches it in the current directory.

```bash
devbox agent                 # menu: run the default, pick one, see the usage
devbox agent set             # gum menu, then remember the choice
devbox agent set codex       # or name it outright
devbox agent which           # print the current default
devbox agent prompt "review this project"
devbox agent usage claude    # what is left of the account limits, and the tokens
devbox agent usage proxy     # what went through the LLM proxy
devbox agent usage           # the three of them, Claude Code, Codex, LLM proxy
```

In a terminal, a bare `devbox agent` opens a small menu: run the default agent
here, pick the default, or show the usage of Claude Code, of Codex, of the LLM
proxy, or of all three. Without a terminal it runs the default agent directly.
The list of agents is what the image ships, `claude`, `pi`, `omp`, `opencode`
and `codex`, plus any wrapper `devbox mise-install` has written.

`devbox diagnostic` also goes through the default agent, see
[troubleshooting.md](troubleshooting.md).

## Account limits and tokens: `devbox agent usage`

`devbox agent usage` prints one line per limit window, with a twenty cell bar,
the percentage used and a countdown to the reset in the box's timezone
(`resets in 2 h 13 min (16:45)`). It keeps everything local: nothing is cached
on disk and nothing is sent anywhere. For Claude Code it reads the OAuth token
out of `~/.claude/.credentials.json` and asks Anthropic's usage endpoint, so the
token only ever travels in that one Authorization header. Without credentials
it says to run `claude` and `/login`. For Codex it talks to `codex app-server`
over stdin, which is where Codex keeps its rate limits; when that answers
nothing it says so and points at `/status` inside Codex.

Under the limits comes a `Tokens` block, the same one for the three accounts:
one line per model, with its share of the window as a twenty cell bar, that
share, the tokens, the number of requests and a sparkline of the seven days,
today on the right. The models are sorted by share and everything past the
eighth is folded into one `others` line. Two lines close the block, the input
and output totals and what today weighs:

```
Tokens, last 7 days                                11 884 requests   1.5G tokens
  claude-opus-5    ███████████░░░░░░░░░  57%  874.2M 8.5k req ▂▅▆▆█▂▆
  claude-fable-5-1 ████████░░░░░░░░░░░░  41%  643.0M 3.0k req ▂▄▆▆█▂▄
  claude-sonnet-5  ░░░░░░░░░░░░░░░░░░░░  <1%   15.1M  292 req ▁▅█▃▃▁▁
  in 1.5G, of which 1.5G from the cache, out 7.0M
  today: 1 828 requests, 232.4M tokens
```

Those counts are read from the transcripts the agents themselves write in the
home, `~/.claude/projects` for Claude Code and `~/.codex/sessions` for Codex.
Nothing is fetched for them and nothing is written: the files are read as they
are. A request is one assistant message for Claude Code and one token count
event for Codex. The days are cut at local midnight in the box's timezone, and
counts are printed short, `12.3k` or `4.5M`, exact below a thousand.

`devbox agent usage proxy` is the same block for the LLM proxy, under its own
heading, with one difference: the bar is still the share of the window, but the
percentage next to it is the cache hit rate of the model, the part of its input
served from the cache. Red below 50, yellow below 80, green above, and a bare
`?` for a model that read no input at all. A header line names the columns:

```
LLM proxy, last 7 days                            3 300 requests   734.9M tokens
  model         share                cache  tokens      req 7 days
  claude-opus-5 ██████████████░░░░░░  88%  513.1M 2.2k req ▃▁▁▇▁▁█
  gpt-5-codex   ██████░░░░░░░░░░░░░░  66%  211.6M  920 req ▁▁▇▁▁▁█
  mistral-large ░░░░░░░░░░░░░░░░░░░░  15%   10.2M  100 req ▁▁▁▁█▁▆
  in 730.0M, of which 594.5M from the cache, out 4.9M
  today: 1 760 requests, 386.5M tokens
```

The models are still sorted by tokens, largest first. Those figures do not come
from a transcript but from the proxy's own usage route,
`/v1/organization/usage/completions` on `LLM_PROXY_URL`, called with
`LLM_PROXY_API_KEY`, in hourly buckets so the days line up with the box's. The
cached tokens are the part of the input that was served from a cache, in every
account, so they are counted inside the input and never twice. When the proxy
does not answer, the section says so in one line and nothing else.

## Agent configuration files

The files the agents read (`~/.claude/settings.json`, the `pi` and `omp`
sub-agents of Claude Code, the `llm-proxy.ts` extension of pi and omp) are
shipped by the image and laid down by the seed, which never overwrites a file
you changed. The table and what each file holds are in
[customization.md](customization.md#seeded-files-and-devbox-seed).

## Agent skill

The image also ships a skill that teaches a coding agent how this box works,
the same way Omarchy ships one for the desktop. It lives in
`/usr/share/devbox/skills/devbox/`, a `SKILL.md` plus its guides:

| File | Covers |
| --- | --- |
| `SKILL.md` | when the skill applies, the safety rules, command discovery, a decision framework |
| `architecture.md` | what belongs to the image, what belongs to the home, what a start does, the seed, overrides, podman |
| `commands.md` | `devbox` and every command it dispatches to |
| `extending.md` | how to change the box for good, through the repository |
| `updates.md` | what updates, when, and on whose command |
| `browser.md` | rendering a page in the box with headless Chromium, installed on demand through `devbox pkg`, screenshots, Playwright and Puppeteer |
| `diagnostic.md` | something in the box is broken: facts first, then a diagnosis, then a fix the user agreed to |

The sources are in
[`rootfs/usr/share/devbox/skills/devbox/`](../rootfs/usr/share/devbox/skills/devbox/).
The entrypoint links the skill into the home at every start, so it follows the
image without going through the seed:

| Link | Target |
| --- | --- |
| `~/.claude/skills/devbox` | `/usr/share/devbox/skills/devbox` |
| `~/.pi/agent/skills/devbox` | same |
| `~/.omp/agent/skills/devbox` | same |

Claude Code reads `~/.claude/skills`, and pi and omp read the `skills`
directory of their own agent folder. All three pick the skill up on their own.
`codex` has no equivalent skill directory, so it is not linked anywhere.

The point is the rule it carries: never edit `/usr/local/bin`, `/etc/devbox` or
`/usr/share/devbox` inside the box, because those come from the image and a
change there disappears silently on the next rebuild. Reading them is
encouraged. Changes go to `~/.config/dev-box/overrides/`, to
`~/.config/mise/config.toml`, or to the repository followed by `just rebuild`.

Adding a guide means dropping an `.md` file in
`rootfs/usr/share/devbox/skills/devbox/` and listing it in the Topic Guides
section of `SKILL.md`. There is nothing else to register.
