#!/bin/bash

set -e

# --- Prerequisites ---
# This script assumes you have Docker and Docker Compose installed.
# It will also require sudo privileges for editing the /etc/hosts file and
# for trusting the self-signed certificate.

echo "--- HashiCorp Vault Self-Hosting Setup Script ---"
echo "This script will:"
echo "1. Create project directories, including a local 'vault-data' directory."
echo "2. Generate a self-signed TLS certificate using OpenSSL."
echo "3. Add a 'vault.example.com' entry to your /etc/hosts file."
echo "4. On Linux, it will automatically trust the generated certificate."
echo "5. Start a Vault container using Docker Compose with a local data mount."
echo ""
echo "Press Enter to continue or Ctrl+C to cancel."
read -r

# --- Step 1: Create directories and config files ---

echo "Creating project directories and configuration files..."
mkdir -p certs vault vault-data

cat <<EOF > vault-cert.conf
[req]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_req
prompt             = no

[req_distinguished_name]
CN = vault.example.com

[req_ext]
subjectAltName = @alt_names

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = vault.example.com
EOF

cat <<EOF > vault/vault.hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault.example.com.crt"
  tls_key_file  = "/vault/tls/vault.example.com.key"
}

storage "file" {
  path = "/vault/data"
}

ui = true
EOF

cat <<EOF > docker-compose.yml
version: '3.7'
services:
  vault:
    image: hashicorp/vault:1.15
    container_name: vault
    ports:
      - "8200:8200"
    cap_add:
      - IPC_LOCK
    volumes:
      - ./vault/vault.hcl:/vault/config/vault.hcl
      - ./certs:/vault/tls:ro
      - ./vault-data:/vault/data
    environment:
      VAULT_LOCAL_CONFIG: /vault/config/vault.hcl
    command: ["vault", "server", "-config=/vault/config/vault.hcl"]
EOF

echo "Done."

# --- Step 2: Generate TLS certificate ---

echo "Generating self-signed TLS certificate..."
(
    cd certs
    openssl genrsa -out vault.example.com.key 2048
    openssl req -x509 -new -nodes \
        -key vault.example.com.key \
        -sha256 -days 365 \
        -out vault.example.com.crt \
        -config ../vault-cert.conf
)
echo "Done. Certificate and key are in the 'certs' directory."

# --- Step 3: Add to /etc/hosts and trust the cert on Linux ---

echo "Adding 'vault.example.com' to /etc/hosts..."
if ! grep -q "127.0.0.1 vault.example.com" /etc/hosts; then
    echo "127.0.0.1 vault.example.com" | sudo tee -a /etc/hosts > /dev/null
    echo "Done. Sudo privileges were required for this step."
else
    echo "Entry already exists. Skipping."
fi

echo "Setting permissions for the 'vault-data' directory..."
sudo chown -R 1000:1000 vault-data
echo "Done."

# Automatically trust the certificate on Linux systems
if [[ "$(uname)" == "Linux" ]]; then
    echo "Automatically trusting the certificate on Linux..."

    if command -v update-ca-certificates &> /dev/null; then
        echo "Detected Debian/Ubuntu-based system."
        if [ ! -d "/usr/local/share/ca-certificates/" ]; then
            sudo mkdir -p "/usr/local/share/ca-certificates/"
            echo "Created directory /usr/local/share/ca-certificates/."
        fi
        sudo cp certs/vault.example.com.crt /usr/local/share/ca-certificates/
        sudo update-ca-certificates
        echo "Certificate successfully trusted."

    elif command -v update-ca-trust &> /dev/null; then
        echo "Detected RHEL/Fedora/CentOS-based system."
        if ! rpm -q ca-certificates &> /dev/null; then
            sudo dnf install -y ca-certificates
        fi
        sudo cp certs/vault.example.com.crt /etc/pki/ca-trust/source/anchors/
        sudo update-ca-trust extract
        echo "Certificate successfully trusted."
    else
        echo "Warning: Could not find a command to automatically trust certificates."
        echo "Please install the 'ca-certificates' package and run the appropriate trust command for your distribution."
    fi
else
    echo "Note: Certificate trust has not been automated for your OS ($(uname))."
    echo "You will need to manually trust 'certs/vault.example.com.crt' to avoid browser warnings."
fi

# --- Step 4: Run Vault with Docker Compose ---

echo "Starting Vault container..."
docker compose up -d

echo ""
echo "----------------------------------------"
echo "🎉 Setup complete!"
echo ""
echo "You can now access Vault at: https://vault.example.com:8200"
echo ""
echo "If you are not on Linux, you will need to manually trust the certificate."
echo "Refer to the original instructions for macOS and Windows."
echo ""
echo "To initialize Vault and get started via the CLI:"
echo 'export VAULT_ADDR=https://vault.example.com:8200'
echo 'vault operator init'
echo 'vault operator unseal'
echo "----------------------------------------"