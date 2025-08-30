#!/bin/bash
#
# Local testing script for lean blocks feature
# Uses local bitcoind instances for testing
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Local Testing - Lean Blocks Feature${NC}"
echo -e "${GREEN}============================================${NC}"

# Check if bitcoind is running
echo -e "${YELLOW}Checking Bitcoin Cash nodes...${NC}"

# Test connection to first node
if bitcoin-cli -rpcconnect=10.0.0.61 -rpcuser=skaisser -rpcpassword=Leprechal22 -rpcport=8332 getblockcount >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Node 1 (10.0.0.61:8332) is running${NC}"
    BLOCKS1=$(bitcoin-cli -rpcconnect=10.0.0.61 -rpcuser=skaisser -rpcpassword=Leprechal22 -rpcport=8332 getblockcount)
    echo "  Block height: $BLOCKS1"
else
    echo -e "${RED}✗ Node 1 (10.0.0.61:8332) is not accessible${NC}"
    echo "  Check connection to bchnode1"
fi

# Test connection to second node (if configured)
if bitcoin-cli -rpcconnect=10.0.1.238 -rpcuser=skaisser -rpcpassword=Leprechal22 -rpcport=8332 getblockcount >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Node 2 (10.0.1.238:8332) is running${NC}"
    BLOCKS2=$(bitcoin-cli -rpcconnect=10.0.1.238 -rpcuser=skaisser -rpcpassword=Leprechal22 -rpcport=8332 getblockcount)
    echo "  Block height: $BLOCKS2"
else
    echo -e "${YELLOW}! Node 2 (10.0.1.238:8332) not running (optional for dual submit)${NC}"
    echo "  Check connection to bchnode2"
fi

# Build if needed
if [ ! -f "ckpool" ]; then
    echo -e "${YELLOW}Building ckpool...${NC}"
    ./autogen.sh
    ./configure
    make
fi

# Create logs directory
mkdir -p logs

# Menu
echo ""
echo -e "${YELLOW}Select test mode:${NC}"
echo "1) Test LEAN mode (empty blocks)"
echo "2) Test NORMAL mode (full blocks)"
echo "3) Compare both modes"
echo "4) Monitor existing pool"
echo ""
read -p "Choice [1-4]: " choice

case $choice in
    1)
        echo -e "${GREEN}Starting pool in LEAN mode...${NC}"
        echo "Mining empty blocks for maximum speed"
        ./ckpool -c ckpool-test-lean.conf
        ;;
    2)
        echo -e "${GREEN}Starting pool in NORMAL mode...${NC}"
        echo "Mining full blocks with transactions"
        # Create normal test config
        cp ckpool-test-lean.conf ckpool-test-normal.conf
        sed -i 's/"lean_blocks": true/"lean_blocks": false/' ckpool-test-normal.conf
        ./ckpool -c ckpool-test-normal.conf
        ;;
    3)
        echo -e "${YELLOW}Comparison test...${NC}"
        echo "This will run both modes and compare metrics"
        echo ""
        
        # Run lean mode for 60 seconds
        echo "Testing LEAN mode for 60 seconds..."
        timeout 60 ./ckpool -c ckpool-test-lean.conf 2>&1 | tee logs/lean-test.log &
        LEAN_PID=$!
        sleep 60
        
        # Count lean metrics
        LEAN_BLOCKS=$(grep -c "LEAN_BLOCK" logs/lean-test.log 2>/dev/null || echo "0")
        echo "Lean blocks generated: $LEAN_BLOCKS"
        
        # Run normal mode for 60 seconds
        echo "Testing NORMAL mode for 60 seconds..."
        cp ckpool-test-lean.conf ckpool-test-normal.conf
        sed -i 's/"lean_blocks": true/"lean_blocks": false/' ckpool-test-normal.conf
        timeout 60 ./ckpool -c ckpool-test-normal.conf 2>&1 | tee logs/normal-test.log &
        NORMAL_PID=$!
        sleep 60
        
        echo -e "${GREEN}Comparison Results:${NC}"
        echo "Lean mode blocks: $LEAN_BLOCKS"
        echo "Check logs/lean-test.log and logs/normal-test.log for details"
        ;;
    4)
        echo -e "${YELLOW}Monitoring pool...${NC}"
        echo ""
        
        # Check if pool is running
        if [ -S /tmp/ckpool/stratifier ]; then
            echo "Pool Statistics:"
            ./ckpmsg -s /tmp/ckpool/stratifier stats
            echo ""
            echo "Recent Lean Blocks:"
            grep "LEAN_BLOCK" logs/ckpool.log 2>/dev/null | tail -5 || echo "No lean blocks found"
            echo ""
            echo "Dual Submit Results:"
            grep "DUAL_SUBMIT" logs/ckpool.log 2>/dev/null | tail -5 || echo "No dual submits found"
        else
            echo -e "${RED}Pool is not running${NC}"
            echo "Start with option 1 or 2"
        fi
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  Check logs:     tail -f logs/ckpool.log | grep LEAN"
echo "  Pool stats:     ./ckpmsg -s /tmp/ckpool/stratifier stats"
echo "  Worker info:    ./ckpmsg -s /tmp/ckpool/stratifier workers"
echo "  Stop pool:      killall ckpool"