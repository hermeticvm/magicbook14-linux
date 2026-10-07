#!/bin/bash

# dh.power battery status — feeds the dh.power panel. Same key/value contract
# as omarchy-battery-status --shell, plus:
#   * "time" while discharging is a rolling 10-minute average of the
#     instantaneous draw (upower's instant estimate swings with momentary
#     load spikes).
#   * "screen_on": accumulated screen-on time during the current discharge
#     session — resets whenever the battery is charged. The screen counts as
#     off when the omarchy screensaver runs, the session is locked, or every
#     monitor is disabled/DPMS-off. Gaps >120s (suspend, missed samples)
#     never count as screen-on.
#   * --graph: 96 five-minute buckets covering the last 8h of the discharge
#     session, each with mean draw (W) and screen-on minutes. Read-only; the
#     panel refreshes it every 5 minutes.
#
# Histories under $XDG_STATE_HOME/dh.power/:
#   rate.tsv  ts \t W                      — last 10 min, discharge only
#   long.tsv  ts \t W \t state \t screen_on — 48h, all states (sessions/graphs)
#
# A discharge session is the rows after the last non-discharging row. A charge
# that happens while the shell isn't running can't split a session; the next
# sampled charge resets it.

power_supply_path="${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dh.power"
rate_file="$state_dir/rate.tsv"
long_file="$state_dir/long.tsv"
window_s=600
min_samples=4
long_keep_s=172800
graph_buckets=96
graph_bucket_s=300

usage() {
  echo "Usage: battery-status.sh --shell | --graph" >&2
  exit 2
}

probe_screen_on() {
  if pgrep -f '[o]rg.omarchy.screensaver' >/dev/null 2>&1; then
    echo 0
    return
  fi
  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
    && ! hyprctl monitors -j 2>/dev/null | jq -e '[.[] | select(.disabled != true and .dpmsStatus == true)] | length > 0' >/dev/null 2>&1; then
    echo 0
    return
  fi
  if [[ $(omarchy-shell -q lock isLocked 2>/dev/null || echo false) == "true" ]]; then
    echo 0
    return
  fi
  echo 1
}

case "${1:-}" in
  --shell) ;;
  --graph)
    [[ -f $long_file ]] || exit 0
    awk -F'\t' -v buckets="$graph_buckets" -v bs="$graph_bucket_s" '
      NF != 4 { next }
      {
        if ($3 == "discharging") {
          n++
          ts[n] = $1 + 0
          w[n] = $2 + 0
          on[n] = ($4 == "1") ? 1 : 0
        } else {
          start = n
        }
      }
      END {
        first = start + 1
        if (n == 0 || first > n) exit
        wend = ts[n]
        wstart = wend - buckets * bs
        for (i = first; i <= n; i++) {
          if (ts[i] < wstart) continue
          b = int((ts[i] - wstart) / bs)
          if (b > buckets - 1) b = buckets - 1
          if (b < 0) continue
          ws[b] += w[i]
          wc[b]++
          if (i > first) {
            gap = ts[i] - ts[i - 1]
            if (on[i] == 1 && on[i - 1] == 1 && gap > 0 && gap <= 120) {
              mid = (ts[i] + ts[i - 1]) / 2
              bm = int((mid - wstart) / bs)
              if (bm >= 0 && bm < buckets) ss[bm] += gap
            }
          }
        }
        print wend
        for (b = 0; b < buckets; b++) {
          wv = (wc[b] > 0) ? sprintf("%.1f", ws[b] / wc[b]) : ""
          sv = (ss[b] > 0) ? sprintf("%.1f", (ss[b] > bs ? bs : ss[b]) / 60) : ""
          printf "%d\t%s\t%s\n", b, wv, sv
        }
      }
    ' "$long_file"
    exit 0
    ;;
  *)
    usage
    ;;
esac

battery=$(upower -e 2>/dev/null | grep BAT | head -n 1)
[[ -z $battery ]] && exit 0

battery_info=$(upower -i "$battery")

percentage=$(awk '/percentage/ { print int($2); exit }' <<<"$battery_info")
capacity=$(awk '/energy-full:/ { printf "%d", $2; exit }' <<<"$battery_info")
time_remaining=$(awk '/time to (empty|full)/ {
  value = $4
  unit = $5
  if (unit ~ /^minute/) {
    printf "%dm", int(value)
  } else {
    hours = int(value)
    minutes = int((value - hours) * 60)
    if (minutes > 0) {
      printf "%dh %dm", hours, minutes
    } else {
      printf "%dh", hours
    }
  }
  exit
}' <<<"$battery_info")
power_rate_raw=$(awk '/energy-rate/ { print $2; exit }' <<<"$battery_info")
native_path=$(awk '/native-path/ { print $2; exit }' <<<"$battery_info")
battery_path="$power_supply_path/$native_path"

# UPower's energy-rate can lag the kernel telemetry by tens of seconds. Use
# the instantaneous sysfs reading when available so the draw sample — and the
# live "rate" field — track reality.
if [[ -r $battery_path/power_now ]]; then
  power_rate_raw=$(awk -v microwatts="$(<"$battery_path/power_now")" 'BEGIN { print microwatts / 1000000 }')
elif [[ -r $battery_path/current_now && -r $battery_path/voltage_now ]]; then
  power_rate_raw=$(awk \
    -v microamps="$(<"$battery_path/current_now")" \
    -v microvolts="$(<"$battery_path/voltage_now")" \
    'BEGIN { print microamps * microvolts / 1000000000000 }')
fi

state=$(awk '/state/ { print $2; exit }' <<<"$battery_info")
screen_on_flag=$(probe_screen_on)

# --- Histories -----------------------------------------------------------
# Every run appends the current state to the long history (48h retention) so
# charging periods mark session boundaries even while the panel is closed.
# The discharge rate feeds the rolling-average file for the time estimate.
# Best-effort: on failure the estimates fall back to upower's instant values.
sample_count=0
avg_watts=0
session_screen_s=0
now=$(date +%s)
if mkdir -p "$state_dir" 2>/dev/null && touch "$long_file" "$rate_file" 2>/dev/null; then
  printf '%s\t%s\t%s\t%s\n' "$now" "${power_rate_raw:-0}" "$state" "$screen_on_flag" >>"$long_file"
  if [[ $state == "discharging" ]]; then
    if awk -v r="${power_rate_raw:-0}" 'BEGIN { exit !(r > 0.2) }'; then
      printf '%s\t%s\n' "$now" "$power_rate_raw" >>"$rate_file"
    fi
  fi

  ltmp="$long_file.tmp"
  : >"$ltmp"
  awk -F'\t' -v now="$now" -v keep="$long_keep_s" -v out="$ltmp" '
    NF == 4 && $1 ~ /^[0-9]+$/ && ($1 + 0) >= now - keep { print > out }
  ' "$long_file"
  mv "$ltmp" "$long_file"

  rtmp="$rate_file.tmp"
  : >"$rtmp"
  read -r avg_watts sample_count <<<"$(awk -F'\t' -v now="$now" -v win="$window_s" -v out="$rtmp" '
    NF == 2 && $1 ~ /^[0-9]+$/ && ($2 + 0) > 0.2 && ($1 + 0) >= now - win {
      print > out
      n++
      total += $2
    }
    END { printf "%.4f %d\n", (n ? total / n : 0), n }
  ' "$rate_file")"
  mv "$rtmp" "$rate_file"

  session_screen_s=$(awk -F'\t' '
    NF != 4 { next }
    {
      if ($3 == "discharging") {
        if (in_session && $4 == "1" && prev_on == 1) {
          gap = $1 - prev_ts
          if (gap > 0 && gap <= 120) total += gap
        }
        in_session = 1
        prev_ts = $1
        prev_on = ($4 == "1") ? 1 : 0
      } else {
        in_session = 0
        prev_ts = 0
        prev_on = 0
        total = 0
      }
    }
    END { print total + 0 }
  ' "$long_file")
fi

# Remaining energy straight from the daemon; fall back to percentage of the
# last full charge when the battery does not report energy.
energy_wh=$(awk '/energy:/ { print $2; exit }' <<<"$battery_info")
if [[ -z $energy_wh ]]; then
  energy_wh=$(awk -v p="${percentage:-0}" -v f="${capacity:-0}" 'BEGIN { if (p > 0 && f > 0) printf "%.4f", p * f / 100 }')
fi

# Replace the instant estimate with the rolling average once the window holds
# enough discharging samples.
if [[ $state == "discharging" && -n $energy_wh ]] && (( sample_count >= min_samples )) \
  && awk -v a="$avg_watts" 'BEGIN { exit !(a > 0.2) }'; then
  time_remaining=$(awk -v e="$energy_wh" -v a="$avg_watts" 'BEGIN {
    h = e / a
    hours = int(h)
    minutes = int((h - hours) * 60)
    if (minutes > 0) {
      printf "%dh %dm", hours, minutes
    } else {
      printf "%dh", hours
    }
  }')
fi

power_rate=$(awk -v rate="${power_rate_raw:-0}" 'BEGIN {
  rounded = sprintf("%.1f", rate)
  sub(/\.0$/, "", rounded)
  print rounded
}')
threshold_start=$(awk '/charge-start-threshold:/ { gsub(/%/, "", $2); print int($2); exit }' <<<"$battery_info")
threshold_end=$(awk '/charge-end-threshold:/ { gsub(/%/, "", $2); print int($2); exit }' <<<"$battery_info")

[[ -z $threshold_end ]] && threshold_end=$(cat "$power_supply_path"/BAT*/charge_control_end_threshold 2>/dev/null | head -1)
[[ -z $threshold_start ]] && threshold_start=$(cat "$power_supply_path"/BAT*/charge_control_start_threshold 2>/dev/null | head -1)

ac_online=false
for supply in "$power_supply_path"/*; do
  [[ -r $supply/type ]] || continue
  [[ $(<"$supply/type") == "Mains" ]] || continue
  [[ -r $supply/online ]] || continue

  if [[ $(<"$supply/online") == "1" ]]; then
    ac_online=true
    break
  fi
done

charge_idle=false
if awk -v rate="${power_rate_raw:-0}" 'BEGIN { exit !(rate <= 0.2) }'; then
  charge_idle=true
fi

charge_holding=false
if [[ $ac_online == "true" && -n $threshold_end ]]; then
  if [[ $state == "pending-charge" ]]; then
    charge_holding=true
  elif [[ $state == "fully-charged" ]] && (( percentage < 99 )); then
    charge_holding=true
  elif [[ $state == "charging" && $charge_idle == "true" ]] && (( threshold_end < 99 && percentage >= threshold_end )); then
    charge_holding=true
  fi
fi

# Screen-on total of the current discharge session; "-" once charged.
if [[ $state == "discharging" ]]; then
  screen_on=$(awk -v s="$session_screen_s" 'BEGIN {
    h = int(s / 3600)
    m = int((s - h * 3600) / 60)
    if (h > 0) {
      if (m > 0) printf "%dh %dm", h, m
      else printf "%dh", h
    } else {
      printf "%dm", m
    }
  }')
else
  screen_on="-"
fi

printf 'percentage\t%s\n' "${percentage}%"
if [[ $charge_holding == "true" ]]; then
  printf 'state\tholding\n'
else
  printf 'state\t%s\n' "$state"
fi
printf 'rate\t%s\n' "${power_rate}W"
printf 'size\t%s\n' "${capacity}Wh"
printf 'time\t%s\n' "$time_remaining"

cycles=$(cat "$power_supply_path"/BAT*/cycle_count 2>/dev/null | head -1)

[[ -n $cycles ]] && printf 'cycles\t%s\n' "$cycles"

if [[ -n $threshold_end ]]; then
  if [[ -n $threshold_start && $threshold_start != $threshold_end ]]; then
    printf 'threshold\t%s-%s%%\n' "$threshold_start" "$threshold_end"
  else
    printf 'threshold\t%s%%\n' "$threshold_end"
  fi
fi

printf 'screen_on\t%s\n' "$screen_on"
