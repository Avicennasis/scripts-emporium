#!/usr/bin/env bash
set -Eeuo pipefail

# PIT.sh — NWS PBZ current conditions + (optional) forecast + alerts, TTS-friendly
#
# Behavior:
#   - Always prints: Current conditions + Alerts
#   - Prints Forecast ONLY if DETAILED=1 (default is 0)
#
# This script intentionally does NOT support hyphen args anymore (per your request).
# Use environment variables (uppercase OR lowercase), e.g.:
#   detailed=1 periods=6 debug=1 verbose=1 ./PIT.sh
#   DETAILED=1 PERIODS=6 DEBUG=1 VERBOSE=1 ./PIT.sh
#
# If SPEAK=1, the script calls espeak directly (don't pipe into espeak again).

# ------------------------ env picking helper ------------------------
pick_env() {
  # Usage: pick_env TARGET_VAR DEFAULT ALT1 ALT2 ALT3...
  local target="$1"; shift
  local def="$1"; shift

  local val=""
  # 1) exact target name
  val="${!target-}"

  # 2) fallbacks / aliases
  if [[ -z "$val" ]]; then
    local k
    for k in "$@"; do
      val="${!k-}"
      [[ -n "$val" ]] && break
    done
  fi

  # 3) default
  [[ -z "$val" ]] && val="$def"

  printf -v "$target" '%s' "$val"
  export "$target"
}
# -------------------------------------------------------------------

# ---- Core config (accepts UPPERCASE or lowercase aliases) ----
pick_env WFO           "PBZ"          wfo
pick_env GRID_X        "72"           grid_x gridx x
pick_env GRID_Y        "62"           grid_y gridy y
pick_env LAT           "40.4406"      lat
pick_env LON           "-79.9959"     lon lng

pick_env FORECAST_PATH "forecast/hourly" forecast_path forecastpath
pick_env PERIODS       "6"            periods period

# DETAILED=0 => skip forecast; DETAILED=1 => include forecast (and extra bits)
pick_env DETAILED      "0"            detailed details detalled DETALLED

pick_env FULL_ALERT_TEXT "0"          full_alert_text fullalert fullalerts alerts_full

pick_env DEBUG         "0"            debug
pick_env VERBOSE       "0"            verbose
pick_env SPEAK         "0"            speak

pick_env NWS_UA        "pit-tts/3.6 (contact: you@example.com)" user_agent ua

# Espeak settings (only used if SPEAK=1)
pick_env ESPEAK_BIN    "espeak"       espeak_bin
pick_env ESPEAK_VOICE  "en-us"        espeak_voice voice
pick_env ESPEAK_SPEED  "155"          espeak_speed speed
pick_env ESPEAK_ARGS   ""             espeak_args args
pick_env ESPEAK_WAV    ""             espeak_wav wav
# ------------------------------------------------------------

run_python() {
python3 - <<'PY'
import os, sys, json, re
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from datetime import datetime

WFO=os.getenv("WFO","PBZ")
GRID_X=os.getenv("GRID_X","72")
GRID_Y=os.getenv("GRID_Y","62")
LAT=os.getenv("LAT","40.4406")
LON=os.getenv("LON","-79.9959")
FORECAST_PATH=os.getenv("FORECAST_PATH","forecast/hourly")
PERIODS=int(os.getenv("PERIODS","6"))
DETAILED=int(os.getenv("DETAILED","0"))          # 0 = skip forecast; 1 = include forecast
FULL_ALERT_TEXT=int(os.getenv("FULL_ALERT_TEXT","0"))
UA=os.getenv("NWS_UA","pit-tts/3.6 (contact: you@example.com)")
DEBUG=os.getenv("DEBUG","0") == "1"
VERBOSE=int(os.getenv("VERBOSE","0"))
SPEAK=int(os.getenv("SPEAK","0"))

DIR_WORDS = {
  "N":"North","NNE":"North-northeast","NE":"Northeast","ENE":"East-northeast",
  "E":"East","ESE":"East-southeast","SE":"Southeast","SSE":"South-southeast",
  "S":"South","SSW":"South-southwest","SW":"Southwest","WSW":"West-southwest",
  "W":"West","WNW":"West-northwest","NW":"Northwest","NNW":"North-northwest",
  "VRB":"Variable"
}
DIRS_16 = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]

def log(msg: str):
    if DEBUG:
        print(f"[debug] {msg}", file=sys.stderr)

def fetch_json(url: str):
    req = Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/geo+json, application/json;q=0.9,*/*;q=0.1",
    })
    try:
        with urlopen(req, timeout=20) as r:
            raw = r.read()
            log(f"GET {url} -> HTTP {getattr(r,'status',200)}, bytes={len(raw)}")
    except HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if hasattr(e, "read") else ""
        print(f"ERROR: HTTP {e.code} fetching {url}", file=sys.stderr)
        if body:
            print("Response preview:", file=sys.stderr)
            print(body[:800], file=sys.stderr)
        raise
    except URLError as e:
        print(f"ERROR: Network fetching {url}: {e}", file=sys.stderr)
        raise

    text = raw.decode("utf-8", errors="replace")
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON from {url}: {e}", file=sys.stderr)
        print("Response preview:", file=sys.stderr)
        print(text[:800], file=sys.stderr)
        raise

def sanitize(s: str) -> str:
    s = s.replace("°", " degrees ")
    s = re.sub(r"\s+", " ", s).strip()
    return s

def say(line=""):
    out = sanitize(line)
    print(out)
    # If stdout is being piped (e.g. to espeak) and VERBOSE=1, mirror to stderr.
    # When SPEAK=1, bash wrapper handles verbose printing via tee.
    if VERBOSE and (not sys.stdout.isatty()) and (not SPEAK):
        print(out, file=sys.stderr)

def c_to_f(c):
    return int(round(c*9/5+32))

def mps_to_mph(mps):
    return int(round(mps*2.2369362920544))

def deg_to_dir16(deg):
    try:
        d = float(deg) % 360.0
    except Exception:
        return ""
    idx = int((d / 22.5) + 0.5) % 16
    return DIRS_16[idx]

def expand_wind_dir(wind_dir: str) -> str:
    d = (wind_dir or "").strip()
    if not d:
        return ""
    u = d.upper()
    if u in DIR_WORDS:
        return DIR_WORDS[u]
    if len(u) <= 3 and u.isalpha():
        return d
    return d[:1].upper() + d[1:]

def fmt_temp(temp, unit):
    if temp is None:
        return None
    u = (unit or "").upper()
    if u == "F":
        return f"{temp} degrees Fahrenheit"
    if u == "C":
        return f"{temp} degrees Celsius"
    return f"{temp} {unit}".strip()

def fmt_wind(wind_dir, wind_speed_str):
    ws = (wind_speed_str or "").strip()
    if not ws:
        return None
    ws = ws.replace("mph", "miles per hour").replace("MPH", "miles per hour")
    d_words = expand_wind_dir(wind_dir)
    if d_words:
        return f"Wind from the {d_words} at {ws}."
    return f"Wind at {ws}."

def label_for_period(p):
    start = (p.get("startTime") or "").strip()
    if start:
        try:
            dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
            return dt.strftime("%A %I %p").replace(" 0", " ").lstrip("0")
        except Exception:
            pass
    name = (p.get("name") or "").strip()
    return name if name else "Period"

def current_conditions():
    points = fetch_json(f"https://api.weather.gov/points/{LAT},{LON}")
    props = points.get("properties") or {}
    stations_url = props.get("observationStations","")
    if not stations_url:
        say("Current conditions: unavailable.")
        return

    stations = fetch_json(stations_url)
    feats = stations.get("features") or []
    if not feats:
        say("Current conditions: unavailable.")
        return

    p0 = feats[0]
    p = (p0.get("properties") or {})
    station_id = p.get("stationIdentifier","")
    if not station_id:
        fid = p0.get("id","")
        if "/stations/" in fid:
            station_id = fid.split("/stations/")[-1].strip()
    if not station_id:
        say("Current conditions: unavailable.")
        return

    obs = fetch_json(f"https://api.weather.gov/stations/{station_id}/observations/latest")
    op = obs.get("properties") or {}

    desc = (op.get("textDescription") or "").strip()
    temp_c = (op.get("temperature") or {}).get("value", None)
    wind_mps = (op.get("windSpeed") or {}).get("value", None)
    wind_deg = (op.get("windDirection") or {}).get("value", None)
    rh = (op.get("relativeHumidity") or {}).get("value", None)

    say("Current conditions near Pittsburgh.")
    if desc:
        say(f"{desc}.")
    if isinstance(temp_c, (int,float)):
        say(f"Temperature {c_to_f(temp_c)} degrees Fahrenheit.")
    if isinstance(wind_mps, (int,float)):
        mph = mps_to_mph(wind_mps)
        d_abbr = deg_to_dir16(wind_deg) if isinstance(wind_deg,(int,float)) else ""
        d_words = expand_wind_dir(d_abbr) if d_abbr else ""
        if d_words:
            say(f"Wind from the {d_words} about {mph} miles per hour.")
        else:
            say(f"Wind about {mph} miles per hour.")
    if isinstance(rh, (int,float)):
        say(f"Humidity about {int(round(rh))} percent.")

def forecast():
    url = f"https://api.weather.gov/gridpoints/{WFO}/{GRID_X},{GRID_Y}/{FORECAST_PATH}"
    data = fetch_json(url)
    periods = ((data.get("properties") or {}).get("periods") or [])[:PERIODS]

    say("")
    say("Forecast.")
    if not periods:
        say("Forecast data unavailable.")
        return

    for p in periods:
        label = label_for_period(p)
        temp = p.get("temperature", None)
        unit = p.get("temperatureUnit","")
        short = (p.get("shortForecast") or "").strip()
        wind_dir = (p.get("windDirection") or "").strip()
        wind_spd = (p.get("windSpeed") or "").strip()
        detail = (p.get("detailedForecast") or "").strip()
        pop = ((p.get("probabilityOfPrecipitation") or {}).get("value", None))
        rh = ((p.get("relativeHumidity") or {}).get("value", None))

        parts = [f"{label}."]
        if short:
            parts.append(f"{short}.")
        t = fmt_temp(temp, unit)
        if t:
            parts.append(f"Temperature {t}.")
        w = fmt_wind(wind_dir, wind_spd)
        if w:
            parts.append(w)

        # Since forecast only shows when DETAILED=1, include the good stuff by default:
        if isinstance(pop, (int,float)):
            parts.append(f"Chance of precipitation {int(round(pop))} percent.")
        if isinstance(rh, (int,float)):
            parts.append(f"Humidity {int(round(rh))} percent.")
        if detail:
            parts.append(detail)

        say(" ".join(parts))

def alerts():
    data = fetch_json(f"https://api.weather.gov/alerts/active?point={LAT},{LON}")
    feats = data.get("features") or []

    say("")
    if not feats:
        say("Alerts: none active.")
        return

    say(f"Alerts: {len(feats)} active.")
    for f in feats:
        ap = (f.get("properties") or {})
        event = ap.get("event","Alert")
        headline = (ap.get("headline") or "").strip()
        desc = (ap.get("description") or "").strip()
        instr = (ap.get("instruction") or "").strip()

        if FULL_ALERT_TEXT:
            chunk = f"{event}. {headline}"
            if desc:
                chunk += f" Details: {desc}"
            if instr:
                chunk += f" Instructions: {instr}"
            say(chunk)
        else:
            say(f"{event}. {headline}")

def main():
    say(f"Pittsburgh, Pennsylvania weather. NWS {WFO} gridpoint {GRID_X},{GRID_Y}.")
    current_conditions()

    # The key behavior you wanted:
    # DETAILED=0 => skip forecast but KEEP alerts
    if DETAILED:
        forecast()

    alerts()

main()
PY
}

# If SPEAK=1, speak directly; otherwise just print text.
if [[ "$SPEAK" == "1" ]]; then
  command -v "$ESPEAK_BIN" >/dev/null 2>&1 || { echo "ERROR: espeak not found." >&2; exit 1; }

  if [[ -n "$ESPEAK_WAV" ]]; then
    if [[ "$VERBOSE" == "1" ]]; then
      run_python | tee /dev/stderr | "$ESPEAK_BIN" -v "$ESPEAK_VOICE" -s "$ESPEAK_SPEED" $ESPEAK_ARGS -w "$ESPEAK_WAV"
    else
      run_python | "$ESPEAK_BIN" -v "$ESPEAK_VOICE" -s "$ESPEAK_SPEED" $ESPEAK_ARGS -w "$ESPEAK_WAV"
    fi
  else
    if [[ "$VERBOSE" == "1" ]]; then
      run_python | tee /dev/stderr | "$ESPEAK_BIN" -v "$ESPEAK_VOICE" -s "$ESPEAK_SPEED" $ESPEAK_ARGS
    else
      run_python | "$ESPEAK_BIN" -v "$ESPEAK_VOICE" -s "$ESPEAK_SPEED" $ESPEAK_ARGS
    fi
  fi
else
  run_python
fi
