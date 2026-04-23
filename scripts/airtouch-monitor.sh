#!/bin/bash
# AirTouch.htb Monitor - Checks if target is back online
# Runs every 5 minutes, sends notification when target is up

TARGET="10.129.244.98"
LOGFILE="/home/raquel/.openclaw/workspace/reports/10.129.244.98-AirTouch/monitor.log"
STATEFILE="/home/raquel/.openclaw/workspace/reports/10.129.244.98-AirTouch/.target-state"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking $TARGET..." >> $LOGFILE

# Check if SSH is up
if nc -zv $TARGET 22 2>&1 | grep -q "succeeded"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ TARGET IS BACK ONLINE!" >> $LOGFILE
    
    # Check if we already notified
    if [ ! -f "$STATEFILE" ] || [ "$(cat $STATEFILE 2>/dev/null)" != "up" ]; then
        echo "up" > $STATEFILE
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚨 Sending notification..." >> $LOGFILE
        
        # Send notification to user
        cat << 'EOF'
        
╔══════════════════════════════════════════════════════════╗
║  🎯 AIRTOUCH.HTB IS BACK ONLINE!                         ║
║  Target: 10.129.244.98:22                                ║
║  Status: SSH accessible                                  ║
║                                                          ║
║  Run: bash scripts/airtouch-fast-attack.sh               ║
╚══════════════════════════════════════════════════════════╝

EOF
        
        # Could also send via email, discord webhook, etc.
        # curl -X POST "webhook_url" -d "AirTouch.htb is back!"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Target still down" >> $LOGFILE
    echo "down" > $STATEFILE
fi
