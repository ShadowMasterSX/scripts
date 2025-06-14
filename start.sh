#!/bin/bash

ServerDir=home
LogDir="/$ServerDir/logs"

# Check if strace is installed
if ! command -v strace &> /dev/null; then
    echo "strace is not installed. Please install it with: sudo apt install strace"
    exit 1
fi

# Ensure log directory exists
mkdir -p "$LogDir"

# Rotate logs: keep 5 previous versions
rotate_logs() {
    local logfile="$1"
    for i in 5 4 3 2 1; do
        [ -f "$logfile.$i" ] && mv "$logfile.$i" "$logfile.$((i+1))"
    done
    [ -f "$logfile" ] && mv "$logfile" "$logfile.1"
}

# Start service with strace, logging, and error checking
start_service() {
    local name=$1
    local path=$2
    local binary=$3
    local config=$4
    local logfile="$LogDir/${name}.log"
    local strace_log="$LogDir/${name}_strace.log"

    echo -e "=== [STARTING] $name ==="
    rotate_logs "$logfile"
    rotate_logs "$strace_log"

    cd "$path" || { echo "[ERROR] Cannot enter $path"; return 1; }

    strace -ff -tt -s 256 -o "$strace_log" "./$binary" $config > "$logfile" 2>&1 &
    local pid=$!
    sleep 5

    if ! kill -0 $pid 2>/dev/null; then
        echo "[ERROR] $name failed to start. Check $logfile."
    else
        echo "=== [OK] $name started (PID $pid) ==="
    fi
    echo ""
}

start_service "logservice" "/$ServerDir/logservice" "logservice" "logservice.conf"
start_service "gauthd" "/$ServerDir/gauthd" "gauthd" "gamesys.conf"
start_service "uniquenamed" "/$ServerDir/uniquenamed" "uniquenamed" "gamesys.conf"
start_service "gamedbd" "/$ServerDir/gamedbd" "gamedbd" "gamesys.conf"
start_service "gacd" "/$ServerDir/gacd" "gacd" "gamesys.conf"
start_service "gfactiond" "/$ServerDir/gfactiond" "gfactiond" "gamesys.conf"
start_service "gdeliveryd" "/$ServerDir/gdeliveryd" "gdeliveryd" "gamesys.conf"

echo -e "=== [STARTING] glinkd (4 instances) ==="
for i in {1..4}; do
    logfile="$LogDir/glinkd${i}.log"
    strace_log="$LogDir/glinkd${i}_strace.log"
    rotate_logs "$logfile"
    rotate_logs "$strace_log"
    cd "/$ServerDir/glinkd" || continue
    strace -ff -tt -s 256 -o "$strace_log" ./glinkd gamesys.conf $i >> "$logfile" 2>&1 &
    pid=$!
    sleep 3
    if ! kill -0 $pid 2>/dev/null; then
        echo "[ERROR] glinkd instance $i failed to start. Check $logfile."
    else
        echo "=== [OK] glinkd $i started (PID $pid) ==="
    fi
done
echo ""

echo -e "=== [STARTING] gamed ==="
start_service "gamed" "/$ServerDir/gamed" "gs" "gsalias.conf gmserver.conf gs.conf"

# Drop file system caches
echo 3 > /proc/sys/vm/drop_caches
