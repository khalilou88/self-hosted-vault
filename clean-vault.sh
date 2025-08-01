#!/bin/bash

set -e

echo "--- HashiCorp Vault Cleanup Script (Updated) ---"
echo "This script will stop and remove all resources created by the setup script, including:"
echo "1. The Docker container."
echo "2. All generated files and directories (certs, vault, vault-cert.conf, docker-compose.yml, .env, and vault-data)."
echo "3. The 'vault.example.com' entry from /etc/hosts."
echo "4. The trusted certificate from your system's trust store."
echo ""
echo "⚠️ WARNING: This will permanently delete the Vault data volume."
echo "Press Enter to continue or Ctrl+C to cancel."
read -r

# --- Step 1: Stop and remove Docker container ---

echo "Stopping and removing Docker container..."
if [ -f docker-compose.yml ]; then
    docker compose --env-file .env down --remove-orphans || true
else
    echo "No docker-compose.yml found. Skipping Docker cleanup."
fi
echo "Done."

# --- Step 2: Remove project files and directories ---

echo "Removing project files and directories..."
rm -rf certs vault vault-data vault-cert.conf .env docker-compose.yml vault-cert.conf vault-cert.conf~ || true
echo "Done."

# --- Step 3: Remove the entry from /etc/hosts ---

echo "Removing 'vault.example.com' from /etc/hosts..."
if grep -q "127.0.0.1 vault.example.com" /etc/hosts; then
    sudo sed -i '/127.0.0.1 vault.example.com/d' /etc/hosts
    echo "Done. Sudo privileges were required for this step."
else
    echo "Entry not found. Skipping."
fi

# --- Step 4: Remove the certificate from the system trust store ---

OS_NAME=$(uname)

if [[ "$OS_NAME" == "Linux" ]]; then
    echo "Removing certificate from the system trust store..."

    if command -v update-ca-certificates &> /dev/null; then
        # Debian/Ubuntu-based system
        if [ -f /usr/local/share/ca-certificates/vault.example.com.crt ]; then
            sudo rm /usr/local/share/ca-certificates/vault.example.com.crt
            sudo update-ca-certificates
            echo "Certificate removed and trust store updated."
        else
            echo "No certificate found in /usr/local/share/ca-certificates/. Skipping."
        fi

    elif command -v update-ca-trust &> /dev/null; then
        # RHEL/Fedora/CentOS-based system
        if [ -f /etc/pki/ca-trust/source/anchors/vault.example.com.crt ]; then
            sudo rm /etc/pki/ca-trust/source/anchors/vault.example.com.crt
            sudo update-ca-trust extract
            echo "Certificate removed and trust store updated."
        else
            echo "No certificate found in /etc/pki/ca-trust/source/anchors/. Skipping."
        fi
    else
        echo "Could not determine certificate trust system. Manual removal may be required."
    fi

elif [[ "$OS_NAME" == "Darwin" ]]; then
    echo "macOS detected."
    echo "To manually remove the trusted cert, open 'Keychain Access', find 'vault.example.com', and delete it."
else
    echo "Note: Manual cleanup of the trusted certificate may be required for your OS ($OS_NAME)."
fi

echo ""
echo "----------------------------------------"
echo "✅ Cleanup complete!"
echo "----------------------------------------"
