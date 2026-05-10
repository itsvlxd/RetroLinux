#!/bin/bash

# Password hashing helper functions for RetroLinux installer
# Uses yescrypt (Arch Linux default) instead of SHA-512

rx_hash_password() {
    local password="$1"
    
    if [[ -z $password ]]; then
        return 1
    fi
    
    # Create a temporary file to safely pass the password to Python
    local temp_pw_file
    temp_pw_file=$(mktemp)
    printf '%s' "$password" > "$temp_pw_file"
    chmod 600 "$temp_pw_file"
    
    local hash
    hash=$(python3 << EOF 2>/dev/null
import sys
import os

# Suppress archinstall log warnings
os.environ['ARCHINSTALL_LOG_SILENT'] = '1'

# Try to find archinstall in common locations
search_paths = [
    '/opt/retrolinux/archinstall',
    '/usr/lib/python3.14/site-packages/archinstall',
    '/usr/lib/python3.13/site-packages/archinstall',
    '/usr/lib/python3.12/site-packages/archinstall',
]

for path in search_paths:
    if os.path.exists(path):
        sys.path.insert(0, path)
        break

try:
    from archinstall.lib.crypt import crypt_yescrypt
    with open('$temp_pw_file', 'r') as f:
        password = f.read()
    print(crypt_yescrypt(password))
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
)
    
    local exit_code=$?
    rm -f "$temp_pw_file"
    
    if [[ $exit_code -ne 0 ]] || [[ -z $hash ]] || [[ $hash == Error:* ]]; then
        return 1
    fi
    
    # Extract only the hash (filter out any log messages)
    local yescrypt_hash
    yescrypt_hash=$(echo "$hash" | grep '^\$y\$' | head -n1)
    
    if [[ -z $yescrypt_hash ]]; then
        return 1
    fi
    
    echo "$yescrypt_hash"
    return 0
}
