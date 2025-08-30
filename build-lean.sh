#!/bin/bash
# Build script for lean blocks feature on Ubuntu

echo "============================================"
echo "Building CKPool with Lean Blocks Support"
echo "============================================"

# Install dependencies if needed
echo "Checking build dependencies..."
if ! command -v automake &> /dev/null; then
    echo "Installing build dependencies..."
    sudo apt-get update
    sudo apt-get install -y build-essential autoconf automake libtool yasm
fi

# Clean previous builds
echo "Cleaning previous build..."
make distclean 2>/dev/null || true
rm -f Makefile configure

# Generate build files
echo "Running autogen..."
./autogen.sh

# Configure
echo "Configuring..."
./configure

# Build
echo "Building..."
make -j$(nproc)

if [ $? -eq 0 ]; then
    echo "============================================"
    echo "Build successful!"
    echo "============================================"
    echo ""
    echo "Lean blocks feature is now integrated."
    echo ""
    echo "To test lean blocks:"
    echo "1. Copy ckpool-lean.conf to your config location"
    echo "2. Run: ./ckpool -c ckpool-lean.conf"
    echo ""
    echo "Configuration options:"
    echo "- lean_blocks: true/false (enable/disable)"
    echo "- lean_mode: coinbase_only/top_n/size_cap"
    echo "- lean_maxtx: max transactions for top_n mode"
    echo "- lean_maxsize_kb: max block size for size_cap mode"
    echo "- dual_submit: true/false (submit to both nodes)"
    echo "- aggressive_preflight: true/false (skip validation for coinbase_only)"
else
    echo "============================================"
    echo "Build failed! Check errors above."
    echo "============================================"
    exit 1
fi