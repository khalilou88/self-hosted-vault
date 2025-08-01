#!/bin/bash

set -e

# --- Check for root privileges where needed ---
if [[ $EUID -ne 0 ]]; then
  echo "⚠️  This script requires sudo/root privileges for modifying /etc/hosts and trusting certificates."
  echo "Please run this script with sudo or as root."
  exit 1
fi

# --- Check for Docker Compose V2 ---
if ! docker compose version &> /dev/null; then
  echo "❌ Docker Compose V2 not found. Please install or upgrade Docker."
  exit 1
fi

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

# --- Check for vault CLI ---
if ! command -v vault &> /dev/null; then
  echo "⚠️ Warning: Vault CLI not found. Install it to run commands like 'vault operator init'."
fi

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

cat <<EOF > .env
VAULT_IMAGE=hashicorp/vault:1.15
VAULT_PORT=8200
EOF

cat <<EOF > docker-compose.yml
version: '3.7'
services:
  vault:
    image: \${VAULT_IMAGE}
    container_name: vault
    ports:
      - "\${VAULT_PORT}:8200"
    cap_add:
      - IPC_LOCK
    volumes:
      - ./vault/vault.hcl:/vault/config/vault.hcl
      - ./certs:/vault/tls:ro
      - ./vault-data:/vault/data
    environment:
      VAULT_LOCAL_CONFIG: /vault/config/vault.hcl
    command: ["vault", "server", "-config=/vault/config/vault.hcl"]
    healthcheck:
      test: ["CMD", "vault", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

echo "Done."

# --- Step 2: Generate TLS certificate ---

echo "Generating self-signed TLS certificate..."
(
    cd certs
    # Modern key generation with genpkey
    if ! openssl genpkey -algorithm RSA -out vault.example.com.key -pkeyopt rsa_keygen_bits:2048; then
        echo "❌ OpenSSL failed to generate private key."
        exit 1
    fi

    if ! openssl req -x509 -new -nodes \
        -key vault.example.com.key \
        -sha256 -days 365 \
        -out vault.example.com.crt \
        -config ../vault-cert.conf; then
        echo "❌ OpenSSL failed to generate certificate."
        exit 1
    fi
)
echo "Done. Certificate and key are in the 'certs' directory."

# --- Step 3: Add to /etc/hosts and trust the cert on Linux/macOS ---

echo "Adding 'vault.example.com' to /etc/hosts..."
HOST_ENTRY="127.0.0.1 vault.example.com"
if ! grep -q "$HOST_ENTRY" /etc/hosts; then
    echo "$HOST_ENTRY" | sudo tee -a /etc/hosts > /dev/null
    echo "Added entry to /etc/hosts."
else
    echo "Entry already exists. Skipping."
fi

echo "Setting permissions for the 'vault-data' directory..."
sudo chown -R 1000:1000 vault-data
echo "Done."

# --- DNS Resolution Check ---
if ! ping -c 1 vault.example.com &> /dev/null; then
  echo "⚠️ Warning: Could not resolve 'vault.example.com'. Please check your /etc/hosts or DNS settings."
fi

# Automatically trust the certificate on Linux systems
OS_NAME=$(uname)
if [[ "$OS_NAME" == "Linux" ]]; then
    echo "Automatically trusting the certificate on Linux..."

    if command -v update-ca-certificates &> /dev/null; then
        echo "Detected Debian/Ubuntu-based system."
        sudo cp certs/vault.example.com.crt /usr/local/share/ca-certificates/
        sudo update-ca-certificates
        echo "Certificate successfully trusted."

    elif command -v update-ca-trust &> /dev/null; then
        echo "Detected RHEL/Fedora/CentOS-based system."
        sudo cp certs/vault.example.com.crt /etc/pki/ca-trust/source/anchors/
        sudo update-ca-trust extract
        echo "Certificate successfully trusted."

    else
        echo "Warning: Could not detect your distro's trust update tool."
        echo "Please manually add and trust the certificate."
    fi

elif [[ "$OS_NAME" == "Darwin" ]]; then
    echo "Note: macOS detected. Manual trust is required."
    echo "Run the following to trust the certificate:"
    echo "sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain certs/vault.example.com.crt"
else
    echo "Note: Certificate trust has not been automated for your OS ($OS_NAME)."
    echo "Please manually trust 'certs/vault.example.com.crt' to avoid browser warnings."
fi

# --- Step 4: Run Vault with Docker Compose ---

echo "Starting Vault container..."
docker compose --env-file .env up -d

echo ""
echo "----------------------------------------"
echo "🎉 Setup complete!"
echo ""
echo "You can now access Vault at: https://vault.example.com:8200"
echo ""
echo "⚠️  This setup uses a self-signed TLS certificate and local file storage."
echo "   It is intended **only for local development**."
echo ""
echo "To initialize Vault and get started via the CLI:"
echo 'export VAULT_ADDR=https://vault.example.com:8200'
echo 'vault operator init'
echo 'vault operator unseal'
echo ""
echo "If you're on macOS or Windows, remember to manually trust the certificate."
echo "----------------------------------------"
