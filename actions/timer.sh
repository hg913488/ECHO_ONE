#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Timer
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Rings and says so when the time is up: "timer 5 minutes", "timer 1 hour 30 minutes".
# @raycast.argument1 { "type": "text", "placeholder": "5 minutes" }
# @echo.phrases set a timer for, set timer for, start a timer for, timer for, set a timer

seconds=0; number=""; label=""
for word in $(echo "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9.\n' ' '); do
  case "$word" in
    [0-9]*) number=$word ;;
    a|an) [ -z "$number" ] && number=1 ;; one) number=1 ;; two) number=2 ;; three) number=3 ;; four) number=4 ;; five) number=5 ;;
    six) number=6 ;; seven) number=7 ;; eight) number=8 ;; nine) number=9 ;; ten) number=10 ;;
    fifteen) number=15 ;; twenty) number=20 ;; thirty) number=30 ;; forty) number=40 ;;
    fifty) number=50 ;; sixty) number=60 ;; half) number=0.5 ;;
    h|hr|hrs|hour|hours) seconds=$(awk -v s=$seconds -v n=${number:-1} 'BEGIN{print s+n*3600}'); number="" ;;
    m|min|mins|minute|minutes) seconds=$(awk -v s=$seconds -v n=${number:-1} 'BEGIN{print s+n*60}'); number="" ;;
    s|sec|secs|second|seconds) seconds=$(awk -v s=$seconds -v n=${number:-1} 'BEGIN{print s+n}'); number="" ;;
  esac
done
# A number with no unit means minutes.
[ -n "$number" ] && seconds=$(awk -v s=$seconds -v n=$number 'BEGIN{print s+n*60}')
seconds=$(printf '%.0f' "$seconds")
if [ "$seconds" -le 0 ]; then echo "Say how long, like timer 5 minutes."; exit 1; fi

minutes=$((seconds / 60)); rest=$((seconds % 60))
if [ $minutes -ge 60 ]; then label="$((minutes / 60)) hour"; [ $((minutes / 60)) -gt 1 ] && label="${label}s"; [ $((minutes % 60)) -gt 0 ] && label="$label $((minutes % 60)) minutes"
elif [ $minutes -gt 0 ]; then label="$minutes minute"; [ $minutes -gt 1 ] && label="${label}s"; [ $rest -gt 0 ] && label="$label $rest seconds"
else label="$seconds seconds"; fi

pidfile="${TMPDIR:-/tmp}/echo-one-timer.pid"
nohup bash -c "sleep $seconds
osascript -e 'display notification \"Your $label timer is done.\" with title \"Echo One\"'
afplay /System/Library/Sounds/Glass.aiff; afplay /System/Library/Sounds/Glass.aiff
say \"Your $label timer is done.\"" >/dev/null 2>&1 &
echo $! > "$pidfile"
echo "Timer set for $label."
