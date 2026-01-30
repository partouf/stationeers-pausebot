#!/bin/bash
# Wait for Stationeers server to fully start, then trigger AutoPauseServer
# by briefly connecting a fake client and disconnecting.
# This runs as ExecStartPost, so it runs after service starts.

LOG_FILE="/home/steam/stationeers/logs/server.log"
SCRIPT_DIR="/home/steam/stationeers"
MAX_WAIT=300  # Maximum seconds to wait for server to be ready

echo "Waiting for server to be ready before pausing..."

# Run in background so ExecStartPost doesn't block
(
    # Wait for log file to exist
    waited=0
    while [ ! -f "$LOG_FILE" ] && [ $waited -lt $MAX_WAIT ]; do
        sleep 5
        waited=$((waited + 5))
    done

    if [ ! -f "$LOG_FILE" ]; then
        echo "ERROR: Log file not found after ${MAX_WAIT}s"
        exit 1
    fi

    # Wait for "registered with session" which indicates server is ready
    echo "Watching for server ready signal..."
    waited=0
    while [ $waited -lt $MAX_WAIT ]; do
        if grep -q "registered with session" "$LOG_FILE" 2>/dev/null; then
            echo "Server ready, waiting 5s before triggering pause..."
            sleep 5

            # Trigger AutoPauseServer via fake client connect/disconnect
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Running fake-connect to trigger AutoPauseServer"
            python3 "$SCRIPT_DIR/fake-connect.py"
            result=$?

            if [ $result -eq 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S'): AutoPauseServer triggered successfully"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: fake-connect failed with exit code $result"
            fi
            exit $result
        fi
        sleep 5
        waited=$((waited + 5))
    done

    echo "WARNING: Server ready signal not found after ${MAX_WAIT}s"
) >> /home/steam/stationeers/logs/startup-pause.log 2>&1 &

exit 0
