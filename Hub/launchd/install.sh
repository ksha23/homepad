#!/bin/zsh
# Installs homepad-hub as a LaunchAgent for the current macOS user, so it starts at
# login and restarts if it stops. Run it yourself in Terminal, in each person's macOS user:
#   Hub/launchd/install.sh            # port 8787 for the Mac's first user, 8788 for the second, ...
#   HUB_PORT=9000 Hub/launchd/install.sh
# Each user gets their own port, so one Mac can serve the whole household.
# Then give ~/.homepad-hub/homepad-hub Full Disk Access in System Settings >
# Privacy & Security, so launchd can read ~/Library/Messages/chat.db.
set -euo pipefail

root=${0:A:h:h}
dir="$HOME/.homepad-hub"
old="$HOME/.homepad-hub"
plist="$HOME/Library/LaunchAgents/com.homepad.hub.plist"
# macOS numbers its users from 501, so each user lands on a port of their own.
port=${HUB_PORT:-$((8787 + $(id -u) - 501))}

mkdir -p "$dir"
chmod 700 "$dir"
if [ ! -f "$dir/token" ]; then
  if [ -f "$old/token" ]; then cp "$old/token" "$dir/token"; else openssl rand -hex 24 > "$dir/token"; fi
  chmod 600 "$dir/token"
fi
# Swap in a new signed file. Overwriting a running binary breaks its signature and launchd kills it.
launchctl bootout "gui/$(id -u)/com.homepad.hub" 2>/dev/null || true
cp "$root/.build/release/homepad-hub" "$dir/homepad-hub.new"
codesign --force -s - "$dir/homepad-hub.new"
mv -f "$dir/homepad-hub.new" "$dir/homepad-hub"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.homepad.hub</string>
    <key>ProgramArguments</key>
    <array>
        <string>$dir/homepad-hub</string>
        <string>--token-file</string><string>$dir/token</string>
        <string>--bind</string><string>0.0.0.0</string>
        <string>--port</string><string>$port</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>$dir/hub.log</string>
    <key>StandardErrorPath</key><string>$dir/hub.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/com.homepad.hub" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed on port $port. On the iPad, this person's hub address is http://$(scutil --get LocalHostName).local:$port"
echo "Now add $dir/homepad-hub to Full Disk Access, then:"
echo "  launchctl kickstart -k gui/$(id -u)/com.homepad.hub"
