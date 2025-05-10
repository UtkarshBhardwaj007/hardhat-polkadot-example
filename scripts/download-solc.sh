#!/bin/bash

# Create binaries directory if it doesn't exist
mkdir -p binaries

# Download the latest solc binary based on platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    curl -L https://github.com/ethereum/solidity/releases/download/v0.8.20/solc-macos -o binaries/solc
    xattr -c binaries/solc
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    curl -L https://github.com/ethereum/solidity/releases/download/v0.8.20/solc-static-linux -o binaries/solc
else
    # Windows
    curl -L https://github.com/ethereum/solidity/releases/download/v0.8.20/solc-windows.exe -o binaries/solc.exe
fi

# Make the binary executable (Unix only)
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "win32" ]]; then
    chmod +x binaries/solc
fi

echo "solc binary downloaded successfully"
