#!/bin/bash
#
# EloPool/CKPool Installation Script for Local Test Server (10.0.0.144)
# Builds in current directory, installs to ~/ckpool
# Configured for test nodes: bchnode1 (10.0.0.61) and bchnode2 (10.0.1.238)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/ckpool"
BUILD_DIR=$(pwd)
TEST_SERVER="10.0.0.144"
BCHNODE1="10.0.0.61"
BCHNODE2="10.0.1.238"
RPC_USER="skaisser"
RPC_PASS="Leprechal22"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   EloPool Local Test Installation${NC}"
echo -e "${BLUE}   Server: ${TEST_SERVER}${NC}"
echo -e "${BLUE}   Nodes: ${BCHNODE1}, ${BCHNODE2}${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check we're in the right directory
if [ ! -f "autogen.sh" ] || [ ! -f "src/ckpool.c" ]; then
    echo -e "${RED}Error: This script must be run from the ckpool source directory${NC}"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Install dependencies if needed
echo -e "${YELLOW}[1/6] Checking build dependencies...${NC}"
DEPS_NEEDED=""
for pkg in build-essential autoconf automake libtool yasm pkg-config; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        DEPS_NEEDED="$DEPS_NEEDED $pkg"
    fi
done

if [ -n "$DEPS_NEEDED" ]; then
    echo "Installing: $DEPS_NEEDED"
    sudo apt-get update
    sudo apt-get install -y $DEPS_NEEDED
else
    echo -e "${GREEN}✓ All dependencies installed${NC}"
fi

# Clean any previous build
echo -e "${YELLOW}[2/6] Cleaning previous build...${NC}"
if [ -f "Makefile" ]; then
    make clean 2>/dev/null || true
fi

# Build from source
echo -e "${YELLOW}[3/6] Building EloPool with lean blocks (FIXED coinbase calculation)...${NC}"

# Only run autogen.sh and configure if Makefile doesn't exist
if [ ! -f "Makefile" ]; then
    echo "Running autogen.sh and configure..."
    ./autogen.sh
    CFLAGS="-O2 -march=native" ./configure
else
    echo "Makefile exists, skipping autogen/configure"
fi

echo "Building with $(nproc) cores..."
make -j$(nproc)

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed! Check errors above.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful${NC}"

# Create installation directory
echo -e "${YELLOW}[4/6] Installing to ${INSTALL_DIR}...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/configs"

# Stop any running ckpool before updating binaries
if pgrep -f ckpool > /dev/null; then
    echo -e "${YELLOW}Stopping running ckpool...${NC}"
    pkill -f ckpool
    sleep 2
fi

# Copy binaries (they're built in src/ directory)
cp -f src/ckpool "$INSTALL_DIR/" 2>/dev/null || cp -f ckpool "$INSTALL_DIR/"
cp -f src/ckpmsg "$INSTALL_DIR/" 2>/dev/null || cp -f ckpmsg "$INSTALL_DIR/"
cp -f src/notifier "$INSTALL_DIR/" 2>/dev/null || cp -f notifier "$INSTALL_DIR/"
echo -e "${GREEN}✓ Binaries updated with coinbase fix${NC}"

# Create test configurations
echo -e "${YELLOW}[5/6] Creating configurations...${NC}"

# Normal mode config
cat > "$INSTALL_DIR/configs/ckpool-normal.conf" << EOF
{
    "btcd": [
        {
            "url": "${BCHNODE1}:8332",
            "auth": "${RPC_USER}",
            "pass": "${RPC_PASS}",
            "zmqnotify": "tcp://${BCHNODE1}:28333"
        },
        {
            "url": "${BCHNODE2}:8332",
            "auth": "${RPC_USER}",
            "pass": "${RPC_PASS}",
            "zmqnotify": "tcp://${BCHNODE2}:28333"
        }
    ],
    "btcaddress": "1AGQcP3KNqTAQkZQA2LBCKqvYn1C4V7cS",
    "btcsig": "/[Solo]",
    "pooladdress": "1AGQcP3KNqTAQkZQA2LBCKqvYn1C4V7cS",
    "poolfee": 1,
    "blockpoll": 1,
    "update_interval": 1,
    "serverurl": [
        "0.0.0.0:3333"
    ],
    "logdir": "logs",
    "node_warning": false,
    "log_shares": true,
    "asicboost": true,
    "version_mask": "1fffe000",
    "maxclients": 100000,
    "mindiff": 1000000,
    "startdiff": 2000000,
    "maxdiff": 20000000,
    "lean_blocks": false,
    "lean_mode": "coinbase_only",
    "lean_maxtx": 0,
    "lean_maxsize_kb": 50,
    "dual_submit": false,
    "aggressive_preflight": false
}
EOF

# Lean mode config (empty blocks)
cat > "$INSTALL_DIR/configs/ckpool-lean.conf" << EOF
{
    "btcd": [
        {
            "url": "${BCHNODE1}:8332",
            "auth": "${RPC_USER}",
            "pass": "${RPC_PASS}",
            "zmqnotify": "tcp://${BCHNODE1}:28333"
        },
        {
            "url": "${BCHNODE2}:8332",
            "auth": "${RPC_USER}",
            "pass": "${RPC_PASS}",
            "zmqnotify": "tcp://${BCHNODE2}:28333"
        }
    ],
    "btcaddress": "1AGQcP3KNqTAQkZQA2LBCKqvYn1C4V7cS",
    "btcsig": "/[Solo]",
    "pooladdress": "1AGQcP3KNqTAQkZQA2LBCKqvYn1C4V7cS",
    "poolfee": 1,
    "blockpoll": 1,
    "update_interval": 1,
    "serverurl": [
        "0.0.0.0:3333"
    ],
    "logdir": "logs",
    "node_warning": false,
    "log_shares": true,
    "asicboost": true,
    "version_mask": "1fffe000",
    "maxclients": 100000,
    "mindiff": 1000000,
    "startdiff": 2000000,
    "maxdiff": 20000000,
    "lean_blocks": true,
    "lean_mode": "coinbase_only",
    "lean_maxtx": 0,
    "lean_maxsize_kb": 50,
    "dual_submit": true,
    "aggressive_preflight": true
}
EOF

# Create convenience symlinks
ln -sf configs/ckpool-normal.conf "$INSTALL_DIR/ckpool.conf"

echo -e "${GREEN}✓ Configurations created${NC}"

# Create helper scripts
echo -e "${YELLOW}[6/6] Creating helper scripts...${NC}"

# Start normal mode
cat > "$INSTALL_DIR/start-normal.sh" << 'EOF'
#!/bin/bash
cd $(dirname $0)
echo "Starting EloPool in NORMAL mode (full blocks with transactions)"
./ckpool -c configs/ckpool-normal.conf
EOF
chmod +x "$INSTALL_DIR/start-normal.sh"

# Start lean mode  
cat > "$INSTALL_DIR/start-lean.sh" << 'EOF'
#!/bin/bash
cd $(dirname $0)
echo "Starting EloPool in LEAN mode (empty blocks for maximum speed)"
./ckpool -c configs/ckpool-lean.conf
EOF
chmod +x "$INSTALL_DIR/start-lean.sh"

# Test nodes connectivity
cat > "$INSTALL_DIR/test-nodes.sh" << EOF
#!/bin/bash
echo "Testing BCH node connectivity..."
echo ""
echo -n "Node 1 (${BCHNODE1}): "
if bitcoin-cli -rpcconnect=${BCHNODE1} -rpcuser=${RPC_USER} -rpcpassword=${RPC_PASS} getblockcount 2>/dev/null; then
    echo " ✓ Connected"
else
    echo " ✗ Failed"
fi

echo -n "Node 2 (${BCHNODE2}): "
if bitcoin-cli -rpcconnect=${BCHNODE2} -rpcuser=${RPC_USER} -rpcpassword=${RPC_PASS} getblockcount 2>/dev/null; then
    echo " ✓ Connected"
else
    echo " ✗ Failed"
fi
EOF
chmod +x "$INSTALL_DIR/test-nodes.sh"

# Monitor script
cat > "$INSTALL_DIR/monitor.sh" << 'EOF'
#!/bin/bash
clear
echo "=== EloPool Monitor ==="
echo ""

# Check which mode is running
if pgrep -f "ckpool.*lean" > /dev/null; then
    echo "Mode: LEAN (empty blocks)"
elif pgrep -f "ckpool" > /dev/null; then
    echo "Mode: NORMAL (full blocks)"
else
    echo "Status: Not running"
    exit 1
fi

echo ""
echo "Recent Lean Blocks:"
grep "LEAN_BLOCK" logs/ckpool.log 2>/dev/null | tail -3 || echo "  No lean blocks yet"

echo ""
echo "Dual Submit Results:"
grep "DUAL_SUBMIT" logs/ckpool.log 2>/dev/null | tail -3 || echo "  No dual submits yet"

echo ""
echo "Block Solutions:"
grep -E "BLOCK ACCEPTED|Block solved" logs/ckpool.log 2>/dev/null | tail -3 || echo "  No blocks found yet"

echo ""
echo "Pool Statistics:"
if [ -S /tmp/ckpool/stratifier ]; then
    ./ckpmsg -s /tmp/ckpool/stratifier stats 2>/dev/null | grep -E "runtime|Users|Workers" || true
fi
EOF
chmod +x "$INSTALL_DIR/monitor.sh"

# Quick switch script
cat > "$INSTALL_DIR/switch-mode.sh" << 'EOF'
#!/bin/bash
cd $(dirname $0)

echo "Current pool status:"
if pgrep -f "ckpool.*lean" > /dev/null; then
    echo "  Running in LEAN mode"
    MODE="lean"
elif pgrep -f "ckpool" > /dev/null; then
    echo "  Running in NORMAL mode"
    MODE="normal"
else
    echo "  Not running"
    MODE="stopped"
fi

echo ""
echo "Select mode:"
echo "1) Normal mode (full blocks)"
echo "2) Lean mode (empty blocks)"
echo "3) Stop pool"
echo "4) Cancel"
read -p "Choice [1-4]: " choice

case $choice in
    1)
        echo "Switching to NORMAL mode..."
        pkill -f ckpool 2>/dev/null || true
        sleep 2
        ./start-normal.sh &
        echo "Started in NORMAL mode"
        ;;
    2)
        echo "Switching to LEAN mode..."
        pkill -f ckpool 2>/dev/null || true
        sleep 2
        ./start-lean.sh &
        echo "Started in LEAN mode"
        ;;
    3)
        echo "Stopping pool..."
        pkill -f ckpool 2>/dev/null
        echo "Pool stopped"
        ;;
    4)
        echo "Cancelled"
        ;;
    *)
        echo "Invalid choice"
        ;;
esac
EOF
chmod +x "$INSTALL_DIR/switch-mode.sh"

# View logs helper
cat > "$INSTALL_DIR/logs.sh" << 'EOF'
#!/bin/bash
cd $(dirname $0)
echo "Viewing pool logs (Ctrl+C to exit)..."
echo "Filtering for: LEAN, DUAL, BLOCK, ERROR"
echo ""
tail -f logs/ckpool.log | grep -E "LEAN|DUAL|BLOCK|ERROR|Solved|Accept"
EOF
chmod +x "$INSTALL_DIR/logs.sh"

echo -e "${GREEN}✓ Helper scripts created${NC}"

# Summary
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}Installed to: ${INSTALL_DIR}${NC}"
echo ""
echo -e "${YELLOW}Test nodes configured:${NC}"
echo "  • Node 1: ${BCHNODE1}:8332"
echo "  • Node 2: ${BCHNODE2}:8332"
echo ""
echo -e "${YELLOW}Quick commands:${NC}"
echo "  Test nodes:    ${GREEN}cd ~/ckpool && ./test-nodes.sh${NC}"
echo "  Normal mode:   ${GREEN}cd ~/ckpool && ./start-normal.sh${NC}"
echo "  Lean mode:     ${GREEN}cd ~/ckpool && ./start-lean.sh${NC}"
echo "  Switch modes:  ${GREEN}cd ~/ckpool && ./switch-mode.sh${NC}"
echo "  Monitor:       ${GREEN}cd ~/ckpool && ./monitor.sh${NC}"
echo "  View logs:     ${GREEN}cd ~/ckpool && ./logs.sh${NC}"
echo ""
echo -e "${YELLOW}Lean blocks mode (WITH COINBASE FIX):${NC}"
echo "  • Fixed coinbase calculation - no more bad-cb-amount errors!"
echo "  • Coinbase now correctly = subsidy + kept_fees"
echo "  • Three modes: coinbase_only, top_n, size_cap"
echo "  • Dual submits to both nodes (optional)"
echo "  • Best for high hashrate bursts"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Test node connectivity: ~/ckpool/test-nodes.sh"
echo "  2. Start in normal mode: ~/ckpool/start-normal.sh"
echo "  3. Monitor performance: ~/ckpool/monitor.sh"
echo ""