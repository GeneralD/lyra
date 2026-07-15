<p align="center">
  <img src="assets/banner.png" alt="lyra" width="600">
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/tag/GeneralD/lyra?label=version" alt="Version">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/github/license/GeneralD/lyra" alt="License">
  <img src="https://img.shields.io/github/actions/workflow/status/GeneralD/lyra/test.yml?label=tests" alt="Tests">
  <a href="https://codecov.io/gh/GeneralD/lyra"><img src="https://codecov.io/gh/GeneralD/lyra/graph/badge.svg" alt="Coverage"></a>
  <a href="https://coderabbit.ai"><img src="https://img.shields.io/coderabbit/prs/github/GeneralD/lyra?utm_source=oss&utm_medium=github&utm_campaign=GeneralD%2Flyra&labelColor=171717&color=FF570A&label=CodeRabbit+Reviews" alt="CodeRabbit Reviews"></a>
  <img src="https://img.shields.io/badge/open%20source-%E2%9D%A4-red" alt="Open Source">
</p>

<p align="center">
  <a href="https://codecov.io/gh/GeneralD/lyra"><img src="https://codecov.io/gh/GeneralD/lyra/graphs/sunburst.svg?token=TJ416Q2M2J" alt="Coverage Sunburst" width="200"></a>
</p>

# lyra

Desktop lyrics overlay and video wallpaper for macOS.

Displays synced lyrics from [LRCLIB](https://lrclib.net) over your desktop, with optional video wallpaper and mouse-reactive ripple effects. Text appears with a matrix-style decode animation.

<p align="center">
  <img src="assets/demo.gif" alt="lyra demo" width="600">
</p>

<p align="center">
  If lyra is useful to you, please consider starring the repo.
  It helps other macOS users find the project and supports future official Homebrew submission.
</p>

## Install

```sh
# via Homebrew
brew tap generald/tap
brew install lyra

# via Mint
mint install GeneralD/lyra

# or build from source
make install
```

## Usage

```sh
lyra start            # start as background daemon
lyra stop             # stop the daemon
lyra restart          # restart
lyra daemon           # run in foreground (debug)
lyra version          # show version
lyra healthcheck      # check API connectivity

lyra config template  # print default config to stdout
lyra config init      # create config file with defaults
lyra config edit      # open config in $EDITOR
lyra config open      # open config in GUI app

lyra track            # show now-playing info as JSON
lyra track -r         # resolve metadata (MusicBrainz/regex)
lyra track -l         # include lyrics (LRCLIB)
lyra track -rl        # resolve + lyrics

lyra benchmark        # measure CPU/memory baselines
lyra benchmark -d 30  # 30s per scenario
lyra benchmark --json # JSON output for CI
```

### Auto-start

```sh
# via Homebrew (recommended for Homebrew installs)
brew services start lyra
brew services stop lyra

# or manually (Mint / source-build users)
lyra service install    # register LaunchAgent directly
lyra service uninstall
```

> **Note:** Both methods use LaunchAgent but with different labels (`homebrew.mxcl.lyra` vs `com.generald.lyra`). Use one approach — do not mix them, or the daemon will run twice.

### Shell completion

```sh
# zsh / bash / fish
eval "$(lyra completion zsh)"
```

Homebrew installs completions automatically.

## Configuration

```sh
# Generate a starter config with all defaults
lyra config init                    # creates ~/.config/lyra/config.toml
lyra config init --format json      # JSON variant
lyra config template > custom.toml  # pipe to any path
```

Or create `~/.config/lyra/config.toml` (or `config.json`) manually. All fields are optional — missing values use sensible defaults.

Alternative paths: `~/.lyra/config.toml`, `$XDG_CONFIG_HOME/lyra/config.toml`

### Live reload

The daemon watches `config.toml` for edits and re-validates on every save — no `lyra restart` needed to pick up a config file change. Saves are debounced briefly to coalesce rapid writes, then applied automatically.

Today this covers config validation, the header and lyrics styling (fonts, colors, sizes, decode effect, and artwork all re-render live), and the lyrics `[lyrics] fallback_command`/`timeout_ms` settings (re-read on every fallback invocation). Wallpaper source replacement and screen re-selection are not wired up yet — those changes still require a `lyra restart` to take effect.

If an edit fails to parse (invalid TOML/JSON, bad values), lyra keeps the last valid style in effect rather than falling back to defaults or crashing. Since a background daemon has no visible terminal to log an error to, a small amber "shattered" sphere appears in the corner of the overlay to flag that the last edit wasn't applied — fix the file and save again to clear it.

### Top-level

| Key | Type | Default | Description |
|---|---|---|---|
| `screen` | string / int | `"main"` | Which display to use (see [Screen selection](#screen-selection)) |
| `screen_debounce` | number | `5` | Seconds between re-evaluations in `"vacant"` mode |
| `wallpaper` | string | — | Video wallpaper. Local path, HTTP(S) URL, or YouTube URL (see [Wallpaper](#wallpaper)) |
| `includes` | array | — | TOML-only: list of additional TOML files to merge (ignored for `config.json`; paths relative to config dir or absolute) |

### `[text.default]` — base text style

All text sections inherit from `[text.default]`. Section-specific values override the base.

| Key | Type | Default | Description |
|---|---|---|---|
| `font` | string | system font | Font family name (e.g. `"Helvetica Neue"`) |
| `size` | number | `12` | Font size in points |
| `weight` | string | `"regular"` | Font weight: `"regular"`, `"medium"`, `"bold"`, etc. |
| `color` | string / array | `"#FFFFFFD9"` | Solid hex `"#RRGGBBAA"` or gradient `["#AAA", "#BBB"]` |
| `shadow` | string | `"#000000E6"` | Shadow color in hex |
| `spacing` | number | `6` | Vertical padding around each line |

### `[text.title]`, `[text.artist]`, `[text.lyric]`, `[text.highlight]`

Each overrides specific properties from `[text.default]`. Unset properties fall back to the base.

| Section | Built-in overrides |
|---|---|
| `title` | `size = 18`, `weight = "bold"` |
| `artist` | `weight = "medium"` |
| `lyric` | inherits default as-is |
| `highlight` | `color = ["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]` (gold gradient). Inherits from `lyric`, then `default` |

### `[text.decode_effect]`

Controls the matrix-style text reveal animation.

| Key | Type | Default | Description |
|---|---|---|---|
| `duration` | number | `0.8` | Animation duration in seconds |
| `charset` | string / array | all | Character sets for scramble: `"latin"`, `"cyrillic"`, `"greek"`, `"symbols"`, `"cjk"`. Single string or array |
| `processing_color` | string / array | `"#4ADE80FF"` (green) | Title/artist color while the AI extractor is resolving (LLM cache miss). The header scrambles in this color until the API responds, then settles to the resolved text in its normal color. Solid hex or gradient array. Only applies when an `[ai]` endpoint is configured |

### `[artwork]`

| Key | Type | Default | Description |
|---|---|---|---|
| `size` | number | `96` | Album artwork size in points |
| `opacity` | number | `1.0` | `0` hides artwork (text aligns left), `1` fully visible |

### `[ripple]`

Mouse-reactive ripple effect on the overlay.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | Set to `false` to disable ripple effects entirely |
| `color` | string | `"#AAAAFFFF"` | Ripple color in hex |
| `radius` | number | `60` | Ripple radius in points |
| `duration` | number | `0.6` | Ripple animation duration in seconds |
| `idle` | number | `1` | Seconds before ripple fades after mouse stops |
| `shape` | string / table | `"circle"` | Ripple outline shape. See below |

#### `[ripple.shape]`

Polymorphic shape spec. Three accepted forms:

```toml
# 1. Omit entirely → defaults to circle
[ripple]
radius = 60

# 2. Bare string for parameterless shapes
[ripple]
shape = "circle"

# 3. Table form for shapes that take parameters
[ripple.shape]
type = "polygon"
sides = 6
angle = 15
```

| Shape | Required keys | Optional keys | Notes |
|---|---|---|---|
| `circle` | — | — | Same as omitting `shape` |
| `polygon` | `sides` (int `3...256`) | `angle` (degrees, default `0`) | Out-of-range `sides` values fail config decoding. `angle = 0` orients one vertex straight up |

### `[spectrum]`

Real-time spectrum analyzer bars driven by the now-playing app's audio, rendered on the overlay. Disabled by default. Requires **macOS 14.4+** (CoreAudio process tap); on the first run macOS asks for the *System Audio Recording* permission.

The defaults are tuned to look good out of the box (cava-inspired), so `enabled = true` alone gives a usable analyzer; every knob below is optional.

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `false` | Set to `true` to show the analyzer |
| `stereo` | boolean | `true` | Split into two channels (left mirrored on the left half, right on the right, bass meeting in the center); `false` shows one mono row |
| `bar_color` | string / array | `["#060912B3", "#20407FB3", "#3E86F0B3", "#9C6CEEB3", "#F4F1FFB3"]` | Solid hex or gradient array (default: deep-navy → blue → violet → white, at ~70% alpha) |
| `gradient_direction` | string | `"level"` | Axis a gradient `bar_color` runs along: `"frequency"` (across bands), `"amplitude"` (base→tip, VU-style), or `"level"` (each bar flat-colored by its height). Ignored for a solid color |
| `background_color` | string | — | Optional backdrop behind the bars |
| `bar_opacity` | number | `1` | One-knob master dimmer for the bar layer (0–1). Scales every gradient stop's opacity proportionally — fade the spectrum in or out without recalculating per-stop alpha by hand. Multiplied on top of each stop's own alpha; independent of `background_color` |
| `bar_width` | number | `6` | Bar thickness in points (fixed; the bar count is derived from the overlay size, cava-style) |
| `bar_spacing` | number | `4` | Gap between bars in points |
| `bar_corner_radius` | number | — | Bar corner radius in points; omit to derive it from `bar_width` (`min(bar_width / 4, 3)`), `0` for square corners (capped per-bar at half the thickness) |
| `min_freq` | number | `40` | Lowest frequency shown, in Hz |
| `max_freq` | number | `14000` | Highest frequency shown, in Hz |
| `min_db` | number | `-60` | Loudness floor mapped to bar height 0 |
| `max_db` | number | `0` | Loudness ceiling mapped to bar height 1 |
| `scale` | string | `"linear"` | `"linear"` (cava's amplitude look) or `"db"` (flatter, decibel-mapped) |
| `noise_reduction` | number | `77` | Motion smoothing, 0–100 (cava's leaky-integral memory + gravity release); higher is smoother/slower |
| `fft_size` | number | `1024` | FFT window size (rounded down to a power of two) |
| `placement` | string | `"bottom"` | `"bottom"`, `"top"`, `"left"`, `"right"`, or `"underlay"` (bars span the whole overlay behind the lyrics). `left`/`right` rotate the bars into horizontal columns growing inward from that edge |
| `height_ratio` | number | `0.25` | Fraction of the overlay the bars may occupy along their growth axis — the height for `bottom`/`top`, the width for `left`/`right` (ignored for `underlay`) |
| `min_height` | number | — | Optional absolute floor (points) on the growth-axis extent, applied on top of `height_ratio` (like CSS `min-height`) |
| `max_height` | number | — | Optional absolute ceiling (points) on the growth-axis extent (like CSS `max-height`). Handy on an ultrawide display, where a `left`/`right` placement would otherwise stretch far across the screen — cap it here |

> **Known limitation:** the audio is tapped per *process tree* (browsers emit audio from helper subprocesses, so the whole tree must be covered). When the now-playing app is a browser, the tap captures the browser's entire audio output — every tab, not just the one playing music.

### `[ai]`

Optional LLM-based song title and artist extraction via any OpenAI-compatible API. When omitted, lyra uses regex-based parsing only. All three fields are required to enable this feature.

| Key | Type | Default | Description |
|---|---|---|---|
| `endpoint` | string | — | OpenAI-compatible API base URL (e.g. `"https://api.openai.com/v1"`) |
| `model` | string | — | Model name (e.g. `"gpt-4o-mini"`) |
| `api_key` | string | — | API key for authentication |

> **Tip:** Keep your API key out of version control by splitting `[ai]` into a separate file and using `includes`:
>
> ```toml
> # config.toml
> includes = ["ai.toml"]
> ```
>
> ```toml
> # ai.toml (add to .gitignore)
> [ai]
> endpoint = "https://api.openai.com/v1"
> model = "gpt-4o-mini"
> api_key = "sk-..."
> ```
>
> Included files are merged into the main config. Values in the main file take precedence over included ones.

### `[lyrics]` — Tier C custom lyrics fallback (optional)

When LRCLIB has no exact or fuzzy match for a track, lyra can shell out to a
user-defined script as a last resort before giving up and showing the raw
(unprocessed) title/artist:

```toml
[lyrics]
fallback_command = ["/usr/bin/python3", "$LYRA_CONFIG_DIR/scripts/lyrics-fallback.py"]
timeout_ms = 5000
```

- `fallback_command` — an argv array (not a shell string). The first element
  must be an absolute path to the executable; lyra does not search `$PATH` for
  it (a `launchd`-run daemon has a minimal `PATH`, so relying on `$PATH`
  resolution would silently fail in production). A non-absolute path is
  rejected up front and Tier C is skipped for that lookup, so the failure is
  deterministic rather than dependent on the daemon's working directory. If
  omitted, Tier C is skipped entirely. The placeholders `$LYRA_CONFIG_DIR`
  and `$LYRA_CACHE_DIR` (or `${…}` forms) are expanded in every element
  before this check, so a command can locate its script relative to lyra's
  config directory — as in the example above — without hardcoding a
  machine-specific path. No other variables are expanded; this is a literal
  placeholder substitution, not shell interpolation.
- `timeout_ms` — how long lyra waits for the script before killing it and
  treating that candidate as a miss. Defaults to `5000`.

lyra invokes the script once per metadata candidate that has a known artist
(raw title/artist, plus any AI/MusicBrainz/regex-resolved guesses whose
artist could be resolved), appending `<title> <artist>` as the final two
arguments, and sets two read-only environment variables:

| Variable | Meaning |
|---|---|
| `LYRA_CONFIG_DIR` | The directory lyra actually loaded its config from. Setting this variable yourself has no effect on where lyra looks for its config — it is informational only. |
| `LYRA_CACHE_DIR` | The directory lyra uses for its own cache (`~/.cache/lyra` by default). Also informational only. |

The same two names double as placeholders inside `fallback_command` itself
(see above) — the values are identical in both roles.

> **Security & execution boundary.** The script runs with the full
> privileges of the lyra process (the daemon user) and **inherits lyra's
> entire parent environment** — the two `LYRA_*` variables above are merged
> *on top of* everything lyra was launched with, so the script can also see
> any secrets or tokens present in that environment (e.g. an `[ai]` API key
> exported into the daemon). Point `fallback_command` only at scripts you
> wrote or fully trust; treat it as running your own code, not a sandbox.

The script must print a single line of JSON to stdout:

```json
{"track_name": "...", "artist_name": "...", "plain_lyrics": "..."}
```

lyra treats any of the following as "no match for this candidate" and moves
on to the next one: a non-zero exit code, unparseable JSON on stdout, a
missing/empty `track_name` field, or a missing/empty `plain_lyrics` field.
Whether your script signals "not found" via a non-zero exit or an empty
`plain_lyrics` is up to you — lyra handles both identically. (`track_name` is
required because it is what the match validator below checks; a response with
lyrics but no `track_name` would bypass validation entirely, so lyra rejects
it.) `artist_name` is optional — when omitted or empty, the matched
candidate's artist is used for display and caching.

A structurally wrong `[lyrics]` section (e.g. `fallback_command` as a plain
string instead of an argv array) does not take down the rest of your config —
lyra loads everything else and disables Tier C — but `lyra healthcheck`
reports it as a validation error so the misconfiguration doesn't go
unnoticed.

Even a syntactically valid response isn't accepted automatically: the
returned `track_name` is run through the same match validator used for Tier
B fuzzy search results, and must be at least 60% similar (Levenshtein-based)
to the candidate title — otherwise the result is rejected as "no match" even
though the script exited cleanly with non-empty lyrics. (The same validator
also enforces a 5-second duration tolerance when both sides have a duration,
but the script's JSON response has no `duration` field, so that half of the
check never has grounds to reject a Tier C result today.) An accurate
`track_name` therefore matters for more than display purposes.

#### Example: KuGou lyrics fetcher

This is a working example that fetches lyrics through KuGou's keyless lyric
API (search the song hash, list lyric candidates, download the pick as LRC,
strip the timestamps, and wash out KuGou's non-lyric header lines). It is not
shipped with lyra — save it yourself and point `fallback_command` at it:

```python
#!/usr/bin/env python3
import base64
import json
import re
import sys
import urllib.parse
import urllib.request

SEARCH_URL = "http://mobilecdn.kugou.com/api/v3/search/song?keyword={}&page=1&pagesize=5"
CANDIDATES_URL = "http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&hash={}"
DOWNLOAD_URL = "http://lyrics.kugou.com/download?ver=1&client=pc&id={}&accesskey={}&fmt=lrc&charset=utf8"
TIMEOUT = 5

CREDIT_PATTERN = re.compile(
    r"^\s*[（(【\[]?\s*(作?[词詞]|作?曲|[编編]曲|歌手?|演唱|翻[译譯]|监制|製作|制作|提供|出品|[发發]行)\s*[:：]"
)
PROMO_PATTERN = re.compile(r"https?://|www\.|酷狗|QQ音乐", re.IGNORECASE)
HEADER_SCAN_LINES = 6


def fetched_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset, errors="replace"))


def normalized(text):
    return re.sub(r"\s+", "", text).casefold()


def matched_hash(title, artist):
    query = urllib.parse.quote(f"{title} {artist}")
    songs = fetched_json(SEARCH_URL.format(query)).get("data", {}).get("info", [])
    titled = [s for s in songs if normalized(title) in normalized(s.get("songname", ""))]
    # KuGou may list artists in simplified Chinese, so an artist match is
    # preferred but not required once the title matches.
    by_artist = [s for s in titled if normalized(artist) in normalized(s.get("singername", ""))]
    return next(iter(by_artist or titled), {}).get("hash")


def plain_lyrics(song_hash):
    candidates = fetched_json(CANDIDATES_URL.format(song_hash)).get("candidates", [])
    if not candidates:
        return None
    picked = candidates[0]
    payload = fetched_json(DOWNLOAD_URL.format(picked["id"], picked["accesskey"]))
    lrc = base64.b64decode(payload["content"]).decode("utf-8", errors="replace").lstrip("\ufeff")
    lines = (re.sub(r"^(\[[^\]]*\])+", "", line).strip() for line in lrc.splitlines())
    return "\n".join(line for line in lines if line) or None


def washed(lyrics, title, artist):
    """Drop KuGou's non-lyric header and promo lines.

    KuGou LRC bodies open with a few metadata lines — a "title - artist" line,
    词/曲 credits, sometimes a free-form comment — recognizable only by content.
    Scan the first few lines and cut through the LAST one that looks like
    metadata, so comment lines sitting above a title/credit line fall with it.
    """
    kept = [line for line in lyrics.splitlines() if not PROMO_PATTERN.search(line)]
    t, a = normalized(title), normalized(artist)

    def is_header(line):
        if CREDIT_PATTERN.match(line):
            return True
        n = normalized(line)
        if n in (t, a):
            return True
        if len(t) >= 6 and t in n:
            return True
        return len(a) >= 4 and a in n

    header = [i for i, line in enumerate(kept[:HEADER_SCAN_LINES]) if is_header(line)]
    return "\n".join(kept[header[-1] + 1:] if header else kept) or None


def main():
    if len(sys.argv) < 3:
        sys.exit(1)
    title, artist = sys.argv[-2], sys.argv[-1]

    try:
        song_hash = matched_hash(title, artist)
        raw = plain_lyrics(song_hash) if song_hash else None
        lyrics = washed(raw, title, artist) if raw else None
    except Exception:
        sys.exit(1)

    if not lyrics:
        sys.exit(1)
    print(json.dumps({
        "track_name": title,
        "artist_name": artist,
        "plain_lyrics": lyrics,
    }))


if __name__ == "__main__":
    main()
```

An earlier revision of this example scraped utamap.com instead; that site no
longer responds on either port 80 or 443, so the scraper cannot work and was
replaced. Third-party lyric endpoints come and go — treat any script here as
a starting point you maintain yourself. lyra ships no fetching or parsing
code of its own for this or any other lyrics site.

#### Composing multiple sources

Because the contract is plain argv-in / JSON-on-stdout, sources compose
naturally: point `fallback_command` at a small dispatcher script that runs
several single-source scripts (each itself a valid `fallback_command`
target) and prints the first hit — a Japanese-catalog site first, KuGou as
the wide-catalog fallback, and so on. Launching all sources concurrently
and then resolving results in priority order keeps both properties at once:
the preferred source still wins whenever it hits, while fall-through
latency is bounded by the slowest source actually needed instead of the sum
of every source before it. Two things to keep in mind: give each source its
own subprocess timeout so one dead endpoint cannot eat the whole budget,
and remember that `timeout_ms` covers the entire `fallback_command` run —
budget it above your per-source timeout with headroom.

### Screen selection

| Value | Behavior |
|---|---|
| `"main"` | Current main display (with focused window) |
| `"primary"` | Primary display (menu bar screen) |
| `"smallest"` | Smallest display by area |
| `"largest"` | Largest display by area |
| `"vacant"` | Least-occupied display (auto-migrates every `screen_debounce` seconds) |
| `0`, `1`, … | Display by index |

### Wallpaper

The `wallpaper` field accepts three types of values:

```toml
# Local file (relative to config dir or absolute)
wallpaper = "loop.mp4"
wallpaper = "/Users/me/Videos/bg.mp4"

# Direct HTTP(S) URL
wallpaper = "https://example.com/background.mp4"

# YouTube URL
wallpaper = "https://www.youtube.com/watch?v=XXXXX"
wallpaper = "https://youtu.be/XXXXX"
```

Remote and YouTube videos are downloaded once and cached in `~/.cache/lyra/wallpapers/`. Subsequent launches use the cached file instantly.

**YouTube requirements:**

| Tool | Install | Notes |
|---|---|---|
| `yt-dlp` | `brew install yt-dlp` | Preferred. Downloads the highest-quality video-only stream, up to 4K |
| `uvx` | `brew install uv` | Zero-install alternative — runs `uvx yt-dlp` without global install |
| `ffmpeg` | `brew install ffmpeg` | Remuxes DASH to MP4 and adds `+faststart` for seamless looping (1080p H.264 ceiling) |
| `ffprobe` | included with `brew install ffmpeg` | Unlocks 4K: detects codec and transcodes AV1/VP9 → HEVC for pre-M3 Apple Silicon and Intel |

If neither `yt-dlp` nor `uvx` is found, lyra will show an error. `ffmpeg` alone
enables DASH-to-MP4 remuxing for seamless looping at the H.264 1080p ceiling.
Pair it with `ffprobe` (included in `brew install ffmpeg`) to unlock 4K: lyra
then downloads the best VP9/AV1 stream and hardware-transcodes non-natively-playable
codecs to HEVC so every Mac — including pre-M3 Apple Silicon and Intel — can play
it. Without `ffmpeg`, lyra downloads a direct H.264 stream that may not loop automatically.

**Trim playback range** (optional):

```toml
[wallpaper]
location = "https://www.youtube.com/watch?v=XXXXX"
start = "0:30"     # skip intro
end = "3:45"       # stop before outro
scale = 1.15       # enlarge this video to hide letterboxing
```

Time format: `M:SS`, `H:MM:SS`, or fractional seconds (`1:23.5`). Both `start` and `end` are optional. `scale` defaults to `1.0`; values above `1.0` zoom the current video only. The bare string format (`wallpaper = "file.mp4"`) still works for simple cases.

**Multiple wallpapers** (optional):

Provide multiple videos with `[[wallpaper.items]]` and choose between sequential (`cycle`) and random (`shuffle`) playback:

```toml
[wallpaper]
mode = "cycle"   # or "shuffle" — default is "cycle"

[[wallpaper.items]]
location = "loop.mp4"

[[wallpaper.items]]
location = "https://www.youtube.com/watch?v=XXXXX"
start = "0:30"
end = "3:45"
scale = 1.2

[[wallpaper.items]]
location = "https://example.com/bg.mp4"
scale = 1.05
```

- `cycle` plays items in the order written, advancing when each item finishes (wraps around at the end).
- `shuffle` advances to a random item each time playback completes, never repeating the current one twice in a row.
- `scale` is configured per item, so videos with different letterboxing can use different zoom values.
- All items are resolved in parallel. In `cycle`, playback starts as soon as the first configured item is ready — later items play in configured order regardless of download speed. In `shuffle`, playback starts with whichever item resolves first.

### Full example

#### **config.toml**

```toml
includes = ["ai.toml"]

screen = "vacant"
screen_debounce = 5

[wallpaper]
mode = "cycle"

[[wallpaper.items]]
location = "https://www.youtube.com/watch?v=Sn1ieBOLGB0"
start = "0:17"
end = "3:37"

[[wallpaper.items]]
location = "https://www.youtube.com/watch?v=P0az9IS2XQQ"
start = "0:24"
end = "3:15"
scale = 1.325

[text.default]
font = "Zen Maru Gothic"
size = 12
color = "#FFFFFFD9"
shadow = "#000000E6"
spacing = 6

[text.title]
font = "Zen Kaku Gothic New"
size = 18
weight = "bold"

[text.artist]
font = "Zen Kaku Gothic New"
size = 12
weight = "medium"

[text.lyric]
color = "#FFFFFFE6"

[text.highlight]
color = ["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]

[artwork]
size = 96
opacity = 0.8

[ripple]
color = "#AAAAFFFF"
radius = 60
duration = 0.4
idle = 1.3

[spectrum]
enabled = true
bar_color = ["#1E3A5F", "#4A9EFF"]
placement = "bottom"
```

This example uses `Zen Maru Gothic` and `Zen Kaku Gothic New`. If those fonts are not installed, install them with Homebrew Cask:

```sh
brew install --cask font-zen-maru-gothic font-zen-kaku-gothic-new
```

#### **ai.toml**

```toml
[ai]
endpoint = "https://api.openai.com/v1"
model = "gpt-4o-mini"
api_key = "sk-..."
```

## Architecture

lyra is built with VIPER + Clean Architecture, with Swift Package targets
enforcing layer boundaries at compile time:

```text
View → Presenter → Interactor → UseCase → Repository → DataSource
```

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for the full module
dependency graphs, the layer/module breakdown, and the per-decision rationale
(Key Design Decisions).

## Use as a library (LyraKit)

<p align="center">
  <a href="docs/LyraKit.md"><img src="assets/lyrakit-wordmark.png" alt="LyraKit" width="360"></a>
</p>

lyra's building blocks are also published as a Swift library, **LyraKit**, so
you can embed lyra's video-wallpaper pipeline in your own macOS app or
screensaver instead of re-implementing it. A single `import LyraKit` gives you
the wallpaper resolver, the ready-made `AVPlayer` engine (`WallpaperPresenter`),
and the dependency wiring — it reads the same `~/.config/lyra/config.toml`
`[wallpaper]` set and `~/.cache/lyra/wallpapers/` cache the daemon uses.

```swift
// Package.swift
.package(url: "https://github.com/GeneralD/lyra.git", from: "2.22.0"),
// target dependency:
.product(name: "LyraKit", package: "lyra"),
```

```swift
import LyraKit

let presenter = WallpaperPresenter()   // reads ~/.config/lyra [wallpaper]
presenter.start()                      // resolves + plays; observe presenter.player
```

See **[docs/LyraKit.md](docs/LyraKit.md)** for the full integration guide.

## Requirements

- macOS 14+ (spectrum analyzer requires macOS 14.4+)
- Swift 6.0+

## License

GPL-3.0
