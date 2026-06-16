#!/bin/bash

# ====================================================================
# PROJECT 0.5: AUTOMATED SSH HARDENING, UFW & FAIL2BAN PROVISIONER
# ====================================================================

# Enforce script execution with administrative privileges
if [ "$EUID" -ne 0 ]; then
  echo "[-] Critical Error: This runtime instance requires root or escalated privileges."
  exit 1
fi

echo "[+] Step 1/4: Syncing Package Indexes and Installing System Dependencies..."
apt update && apt upgrade -y
apt install fail2ban ufw -y

echo "[+] Step 2/4: Applying Asymmetric SSH Daemon Hardening Protocols..."
SSH_CONF="/etc/ssh/sshd_config"
BACKUP_SSH="/etc/ssh/sshd_config.bak_$(date +%F_%T)"
cp "$SSH_CONF" "$BACKUP_SSH"
echo "[*] System configuration backup preserved at: $BACKUP_SSH"

# Modify targeted parameters safely via Stream Editors (sed)
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' "$SSH_CONF"
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' "$SSH_CONF"
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' "$SSH_CONF"
sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' "$SSH_CONF"

# Append safety boundaries cleanly if missing entirely
if ! grep -q "MaxAuthTries" "$SSH_CONF"; then
    echo "MaxAuthTries 3" >> "$SSH_CONF"
fi

# Dry-run validation of configuration syntax before committing the service reload
sshd -t
if [ $? -eq 0 ]; then
    systemctl restart ssh
    echo "[+] System SSH engine parameters hardened and reloaded successfully."
else
    echo "[-] Configuration syntax errors detected. Initiating immediate recovery roll-back..."
    cp "$BACKUP_SSH" "$SSH_CONF"
    systemctl restart ssh
fi

echo "[+] Step 3/4: Enforcing Inbound Firewall Policies (UFW)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
echo "y" | ufw enable
ufw status verbose

echo "[+] Step 4/4: Constructing Active IDS Log-Scanning Architecture (Fail2Ban)..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Safely inject the isolated sshd configuration block via end-of-text redirection
cat <<EOT >> /etc/fail2ban/jail.local

[sshd]
enabled = true
port    = ssh
maxretry = 3
findtime = 10m
bantime  = 1h
EOT

systemctl restart fail2ban
systemctl enable fail2ban

echo "===================================================================="
echo "[SUCCESS] PERIMETER HARDENING PROCEDURES COMPLETED SECURELY!"
echo "===================================================================="
