# backdrop

Desktop lyrics overlay and video wallpaper for macOS.

Displays synced lyrics from [LRCLIB](https://lrclib.net) over your desktop, with optional video wallpaper and mouse-reactive ripple effects. Text appears with a matrix-style decode animation.

## Install

```sh
# via Mint
mint install GeneralD/backdrop

# or build from source
make install
```

## Usage

```sh
backdrop start       # start as background daemon
backdrop stop        # stop the daemon
backdrop restart     # restart
backdrop daemon      # run in foreground (debug)
backdrop version     # show version
```

### Login item

```sh
backdrop service install    # auto-start on login
backdrop service uninstall
```

### Shell completion

```sh
# zsh / bash / fish
eval "$(backdrop completion zsh)"
```

## Configuration

`~/.config/backdrop/config.toml`

```toml
screen = "match"           # main, primary, smallest, largest, match, or index
wallpaper = "koko.mp4"     # relative to config dir, or absolute path

[text.default]
font = "Zen Maru Gothic"
size = 12
color = "#FFFFFFD9"        # solid color or gradient array
shadow = "#000000E6"
spacing = 6

[text.title]
size = 18

[text.artist]
size = 12

[text.highlight]
color = ["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]
# size, spacing, font, weight, shadow also supported

[text.decode_effect]
duration = 0.8                       # seconds for decode animation
charset = ["latin", "cyrillic"]      # latin, cyrillic, greek, symbols

[artwork]
size = 96
opacity = 0.8              # 0 = hidden (left-align text), 1 = fully visible

[ripple]
color = "#AAAAFFFF"
radius = 60
duration = 0.4
idle = 1.3
```

All fields are optional. Missing values use sensible defaults.

## Requirements

- macOS 14+
- Swift 6.0+

## License

MIT
