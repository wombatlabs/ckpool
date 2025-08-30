#!/bin/bash
#
# EloPool/CKPool Installation Script with Lean Blocks Support
# For Ubuntu Server deployment
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/ckpool"
CONFIG_FILE="ckpool.conf"
LEAN_CONFIG_FILE="ckpool-lean.conf"

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}EloPool Installation with Lean Blocks${NC}"
echo -e "${GREEN}============================================${NC}"

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${YELLOW}Warning: This script is designed for Ubuntu. Proceed with caution.${NC}"
fi

# Install dependencies
echo -e "${YELLOW}Installing build dependencies...${NC}"
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    yasm \
    libzmq3-dev \
    pkg-config \
    git

# Build from source
echo -e "${YELLOW}Building EloPool with lean blocks...${NC}"
if [ ! -f "autogen.sh" ]; then
    echo -e "${RED}Error: autogen.sh not found. Run this from the ckpool directory.${NC}"
    exit 1
fi

# Clean any previous build
make distclean 2>/dev/null || true

# Generate configure script
./autogen.sh

# Configure with optimizations
CFLAGS="-O2 -march=native" ./configure

# Build
make -j$(nproc)

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed! Check errors above.${NC}"
    exit 1
fi

# Create installation directory
echo -e "${YELLOW}Installing to ${INSTALL_DIR}...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/logs"

# Copy binaries
cp -f ckpool "$INSTALL_DIR/"
cp -f ckpmsg "$INSTALL_DIR/"
cp -f notifier "$INSTALL_DIR/"

# Create standard config if it doesn't exist
if [ ! -f "$INSTALL_DIR/$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Creating standard configuration...${NC}"
    cat > "$INSTALL_DIR/$CONFIG_FILE" << 'EOF'
{
"btcd" :  [
	{
		"url" : "localhost:8332",
		"auth" : "bchadmin",
		"pass" : "CHANGE_THIS_PASSWORD",
		"notify" : true
	}
],
"btcaddress" : "CHANGE_THIS_TO_YOUR_BCH_ADDRESS",
"btcsig" : "EloPool.cloud",
"blockpoll" : 100,
"nonce1length" : 4,
"nonce2length" : 8,
"update_interval" : 30,
"serverurl" : [
	"0.0.0.0:3333"
],
"mindiff" : 500000,
"startdiff" : 500000,
"maxdiff" : 0,
"logdir" : "logs",
"lean_blocks" : false,
"lean_mode" : "coinbase_only",
"lean_maxtx" : 0,
"lean_maxsize_kb" : 50,
"dual_submit" : false,
"aggressive_preflight" : false
}
EOF
    echo -e "${GREEN}Created standard config at $INSTALL_DIR/$CONFIG_FILE${NC}"
    echo -e "${YELLOW}IMPORTANT: Edit the config file and set your BCH address and RPC credentials${NC}"
fi

# Create lean mining config
echo -e "${YELLOW}Creating lean mining configuration...${NC}"
cat > "$INSTALL_DIR/$LEAN_CONFIG_FILE" << 'EOF'
{
"btcd" :  [
	{
		"url" : "localhost:8332",
		"auth" : "bchadmin",
		"pass" : "CHANGE_THIS_PASSWORD",
		"notify" : true
	},
	{
		"url" : "localhost:8333",
		"auth" : "bchadmin",
		"pass" : "CHANGE_THIS_PASSWORD",
		"notify" : false
	}
],
"btcaddress" : "CHANGE_THIS_TO_YOUR_BCH_ADDRESS",
"btcsig" : "EloPool.cloud/LEAN",
"blockpoll" : 100,
"nonce1length" : 4,
"nonce2length" : 8,
"update_interval" : 30,
"serverurl" : [
	"0.0.0.0:3333"
],
"mindiff" : 500000,
"startdiff" : 500000,
"maxdiff" : 0,
"logdir" : "logs",
"lean_blocks" : true,
"lean_mode" : "coinbase_only",
"lean_maxtx" : 0,
"lean_maxsize_kb" : 50,
"dual_submit" : true,
"aggressive_preflight" : true
}
EOF

# Create systemd service file
echo -e "${YELLOW}Creating systemd service...${NC}"
sudo tee /etc/systemd/system/ckpool.service > /dev/null << EOF
[Unit]
Description=EloPool Mining Pool
After=network.target bitcoind.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ckpool -c $INSTALL_DIR/$CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create lean mode service
sudo tee /etc/systemd/system/ckpool-lean.service > /dev/null << EOF
[Unit]
Description=EloPool Mining Pool (Lean Mode)
After=network.target bitcoind.service
Conflicts=ckpool.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/ckpool -c $INSTALL_DIR/$LEAN_CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create helper scripts
echo -e "${YELLOW}Creating helper scripts...${NC}"

# Start script
cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash
cd $(dirname $0)
./ckpool -c ckpool.conf
EOF
chmod +x "$INSTALL_DIR/start.sh"

# Start lean mode script
cat > "$INSTALL_DIR/start-lean.sh" << 'EOF'
#!/bin/bash
cd $(dirname $0)
echo "Starting EloPool in LEAN MODE (empty blocks for maximum speed)"
./ckpool -c ckpool-lean.conf
EOF
chmod +x "$INSTALL_DIR/start-lean.sh"

# Switch to lean mode script
cat > "$INSTALL_DIR/switch-to-lean.sh" << 'EOF'
#!/bin/bash
echo "Switching to LEAN MODE..."
sudo systemctl stop ckpool 2>/dev/null
sudo systemctl start ckpool-lean
echo "Switched to LEAN MODE - mining empty blocks for maximum speed"
sudo systemctl status ckpool-lean --no-pager
EOF
chmod +x "$INSTALL_DIR/switch-to-lean.sh"

# Switch to normal mode script
cat > "$INSTALL_DIR/switch-to-normal.sh" << 'EOF'
#!/bin/bash
echo "Switching to NORMAL MODE..."
sudo systemctl stop ckpool-lean 2>/dev/null
sudo systemctl start ckpool
echo "Switched to NORMAL MODE - mining full blocks with transactions"
sudo systemctl status ckpool --no-pager
EOF
chmod +x "$INSTALL_DIR/switch-to-normal.sh"

# Monitor script
cat > "$INSTALL_DIR/monitor.sh" << 'EOF'
#!/bin/bash
echo "=== EloPool Monitor ==="
echo ""
echo "Lean Block Stats:"
grep "LEAN_BLOCK" logs/ckpool.log 2>/dev/null | tail -5
echo ""
echo "Dual Submit Stats:"
grep "DUAL_SUBMIT" logs/ckpool.log 2>/dev/null | tail -5
echo ""
echo "Recent Blocks:"
grep "BLOCK ACCEPTED\|block solve" logs/ckpool.log 2>/dev/null | tail -5
echo ""
echo "Current Workers:"
./ckpmsg -s /tmp/ckpool/stratifier workers 2>/dev/null | head -20
EOF
chmod +x "$INSTALL_DIR/monitor.sh"

# Reload systemd
sudo systemctl daemon-reload

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}Installation directory: ${INSTALL_DIR}${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT - Next Steps:${NC}"
echo -e "1. Edit configuration files:"
echo -e "   ${GREEN}nano $INSTALL_DIR/ckpool.conf${NC} (normal mode)"
echo -e "   ${GREEN}nano $INSTALL_DIR/ckpool-lean.conf${NC} (lean mode)"
echo ""
echo -e "2. Set your BCH address and RPC credentials in both configs"
echo ""
echo -e "3. Start the pool:"
echo -e "   ${GREEN}sudo systemctl start ckpool${NC} (normal mode)"
echo -e "   ${GREEN}sudo systemctl start ckpool-lean${NC} (lean mode)"
echo ""
echo -e "${YELLOW}Quick Commands:${NC}"
echo -e "   Switch to lean:   ${GREEN}$INSTALL_DIR/switch-to-lean.sh${NC}"
echo -e "   Switch to normal: ${GREEN}$INSTALL_DIR/switch-to-normal.sh${NC}"
echo -e "   Monitor pool:     ${GREEN}$INSTALL_DIR/monitor.sh${NC}"
echo -e "   Check logs:       ${GREEN}tail -f $INSTALL_DIR/logs/ckpool.log${NC}"
echo ""
echo -e "${YELLOW}Lean Blocks Mode:${NC}"
echo -e "   When enabled, mines empty blocks for maximum speed"
echo -e "   Best for high hashrate bursts (400+ PH)"
echo -e "   Matches strategy of successful BCH miners"
echo ""