#!/bin/bash

ServerDir=/home
LogDir=$ServerDir/logs
strace=$ServerDir/logs/strace
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MapConfig="$SCRIPT_DIR/maps.conf"
cd /$ServerDir/licenseservice/ && ./start.sh && cd /$ServerDir/iwebserver/ && ./iweb.sh start && cd /$ServerDir/

# Check for strace
if ! command -v strace &> /dev/null; then
    echo "strace is not installed. Please install it with: sudo apt install strace"
    exit 1
fi

mkdir -p "$LogDir"

# Generate default maps.conf if missing
if [ ! -f "$MapConfig" ]; then
    echo "maps.conf not found, generating default configuration..."
    for i in $(seq -w 1 115); do
        echo "is$i=no"
    done > "$MapConfig"
    echo "maps.conf created with all maps set to 'no'. Edit the file to enable specific maps."
    chmod 777 $SCRIPT_DIR/maps.conf
fi

# Log rotation
rotate_logs() {
    local logfile="$1"
    for i in 5 4 3 2 1; do
        [ -f "$logfile.$i" ] && mv "$logfile.$i" "$logfile.$((i+1))"
    done
    [ -f "$logfile" ] && mv "$logfile" "$logfile.1"
}

# Generic service starter
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

# Standard services
start_service "logservice" "/$ServerDir/logservice" "logservice" "logservice.conf"
start_service "gauthd" "/$ServerDir/gauthd" "gauthd" "gamesys.conf"
start_service "uniquenamed" "/$ServerDir/uniquenamed" "uniquenamed" "gamesys.conf"
start_service "gamedbd" "/$ServerDir/gamedbd" "gamedbd" "gamesys.conf"
start_service "gacd" "/$ServerDir/gacd" "gacd" "gamesys.conf"
start_service "gfactiond" "/$ServerDir/gfactiond" "gfactiond" "gamesys.conf"
start_service "gdeliveryd" "/$ServerDir/gdeliveryd" "gdeliveryd" "gamesys.conf"

# Start glinkd
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

# Start enabled maps
start_gs_maps() {
    local path="/$ServerDir/gamed"
    local binary="gs"

    cd "$path" || { echo "[ERROR] Cannot enter $path"; return 1; }

    while IFS='=' read -r map state; do
        map=$(echo "$map" | tr -d ' ')
        state=$(echo "$state" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
        [[ "$map" =~ ^#.*$ || -z "$map" ]] && continue
        if [[ "$state" == "yes" ]]; then
            local logfile="$LogDir/${map}.log"
            local strace_log="$LogDir/${map}_strace.log"
            rotate_logs "$logfile"
            rotate_logs "$strace_log"

            echo -e "=== [STARTING] $binary $map ==="
            strace -ff -tt -s 256 -o "$strace_log" "./$binary" "$map" > "$logfile" 2>&1 &
            local pid=$!
            sleep 3

            if ! kill -0 $pid 2>/dev/null; then
                echo "[ERROR] Map $map failed to start. Check $logfile."
            else
                echo "=== [OK] Map $map started (PID $pid) ==="
            fi
        fi
    done < "$MapConfig"
}

start_gs_maps

# Clear file system cache
echo 3 > /proc/sys/vm/drop_caches
