# Weather.sh TTS (NWS API + espeak)
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A small Bash and Python script that generates a spoken (or speakable) local weather report for a given location (defaults to Pittsburgh, PA) using the National Weather Service API (`api.weather.gov`), pulling current conditions, optional forecast, and active alerts, then outputting TTS-friendly text that you can pipe into a speech engine or have it call `espeak` directly.

NOAA/NWS Weather Radio MP3 links that used to work (old `srh.noaa.gov/images/rtimages/.../nwr/audio/*.mp3` paths) are no longer reliable and often 404. Instead of scraping or chasing moving audio URLs, this project fetches live structured data from the official NWS API and produces speech output locally.

## Features

- Current conditions near location (temperature, humidity, wind)
- Active alerts for the configured point (if any)
- Optional hourly forecast (opt-in)
- Wind direction expansion (S to South, SW to Southwest, etc.)
- Unit expansion for speech (Fahrenheit / miles per hour)
- Two modes: text output (default) for piping/logging, and direct speech (`SPEAK=1`) with `espeak`
- Configurable via environment variables (uppercase or lowercase)

## Requirements

### Required

- `bash`
- `python3` (uses only the Python standard library)

### Optional (for audio playback)

- `espeak` (only needed if `SPEAK=1`)

```bash
sudo apt-get update
sudo apt-get install -y python3 espeak
```

## Installation

Make the script executable:

```bash
chmod +x PIT.sh
```

## Usage

```bash
# Default: current conditions + alerts (no forecast)
./PIT.sh
```

### Options

The script is configured entirely through environment variables. Both uppercase and lowercase variable names are supported.

**Location / Office / Forecast source:**

| Option | Description | Default |
|--------|-------------|---------|
| `WFO` | NWS office ID | `PBZ` |
| `GRID_X` | Grid X coordinate | `72` |
| `GRID_Y` | Grid Y coordinate | `62` |
| `LAT` | Point latitude (used for current conditions + alerts) | `40.4406` |
| `LON` | Point longitude | `-79.9959` |
| `FORECAST_PATH` | Can be `forecast` or `forecast/hourly` | `forecast/hourly` |

**Output controls:**

| Option | Description | Default |
|--------|-------------|---------|
| `DETAILED` | `0`: skip forecast; `1`: include forecast (and precip/humidity if available) | `0` |
| `PERIODS` | Number of forecast periods to read | `6` |
| `FULL_ALERT_TEXT` | `0`: alert headline only; `1`: include full description + instructions | `0` |
| `DEBUG` | Prints request debug logs to stderr | `0` |
| `VERBOSE` | When `SPEAK=1`, prints spoken text while speaking (via `tee`) | `0` |

**TTS controls (only if `SPEAK=1`):**

| Option | Description | Default |
|--------|-------------|---------|
| `SPEAK` | Call `espeak` directly | `0` |
| `ESPEAK_BIN` | Path to espeak binary | `espeak` |
| `ESPEAK_VOICE` | Voice to use | `en-us` |
| `ESPEAK_SPEED` | Speech rate | `155` |
| `ESPEAK_ARGS` | Extra `espeak` arguments | (empty) |
| `ESPEAK_WAV` | If set, write a WAV file to this path | (empty) |

### Examples

**Include forecast (hourly) + extra details:**

```bash
DETAILED=1 PERIODS=6 ./PIT.sh
```

**Speak out loud (no piping needed):**

```bash
SPEAK=1 VERBOSE=1 DETAILED=1 PERIODS=6 ./PIT.sh
```

**Pipe into your own TTS pipeline:**

```bash
DETAILED=1 PERIODS=6 ./PIT.sh | espeak -v en-us -s 155
```

**Use a custom location:**

```bash
LAT=40.4406 LON=-79.9959 FORECAST_PATH="forecast" DETAILED=1 ./PIT.sh
```

**Adjust speech speed and write a WAV file:**

```bash
SPEAK=1 VERBOSE=1 ESPEAK_SPEED=140 ESPEAK_VOICE=en-us ./PIT.sh
```

```bash
SPEAK=1 VERBOSE=1 ESPEAK_WAV="pittsburgh-weather.wav" DETAILED=1 ./PIT.sh
```

## Configuration

### NWS API User-Agent

NWS requests a descriptive `User-Agent` identifying your application. Set:

```bash
NWS_UA="your-app-name (contact: email@example.com)"
```

Example:

```bash
NWS_UA="pit-weather-tts (contact: me@domain.com)" ./PIT.sh
```

## Troubleshooting

### No forecast appears

Forecast is intentionally opt-in. Set:

```bash
DETAILED=1 ./PIT.sh
```

### Debug API requests

```bash
DEBUG=1 ./PIT.sh
```

### No audio plays

Only `SPEAK=1` triggers audio playback:

```bash
SPEAK=1 ./PIT.sh
```

Or pipe into your own TTS:

```bash
./PIT.sh | espeak -v en-us -s 155
```

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
