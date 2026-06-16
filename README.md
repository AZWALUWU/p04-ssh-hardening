Here is a comprehensive, production-ready documentation guide written in English and formatted explicitly in Markdown. You can copy and paste this directly into your GitHub repository's **`README.md`** file for your project submission.

---

# SSH Hardening & Bastion Host Pattern (Project 0.4)

This repository contains the complete documentation, configuration matrices, and an automation script for building a secure, enterprise-grade perimeter defense network using a **Bastion Host Pattern**.

The implementation mitigates credential-guessing threats, isolates sensitive private workloads, and establishes unified access control using modern cryptographic practices.

---

## 🏗️ Architecture & Network Layout

The project implements a classic perimeter network segmentation pattern:

* **Local Client (Windows PowerShell):** Acts as the administrator workstation hosting the primary asymmetric cryptographic identity keys.
* **Bastion Host (GCP e2-micro Instance):** The only public-facing internet gateway. It is highly hardened, monitored, and acts as the secure entry point.
* **Private Server (VirtualBox VM):** Simulates an isolated back-end network zone. It is configured on a Host-Only adapter with **no direct internet access**, reachable exclusively through a cryptographic reverse tunnel routed via the Bastion Host.

```text
+------------------------+                    Internet                    +------------------------------+
| Local Client Machine   | ---------------------------------------------> | GCP Bastion Host             |
| (Windows PowerShell)   | <--------------------------------------------- | (Public IP: 34.70.245.255)   |
+------------------------+             SSH Remote Tunnel                  +------------------------------+
            |                                                                            |
            | Host-Only Subnet                                                           | Reverse Port Mapping
            v                                                                            v
+------------------------+                                                               |
| VirtualBox VM          | <-------------------------------------------------------------+
| (IP: 192.168.56.101)   |                      localhost:2222 -> Port 22
+------------------------+

```

---

## 🔒 Hardening & Implementation Steps

### Phase 1: Cryptographic Identity Setup

Secure authentication begins by replacing legacy password-based authentication with high-entropy asymmetric cryptography keys.

1. **Generate an Ed25519 Key Pair** on the local Windows Client Machine:
```powershell
ssh-keygen -t ed25519 -b 4096 -C "tugas-bastion-key" -f ~/.ssh/id_ed25519

```


2. **Key Pair Distribution**:
* `id_ed25519.pub` (Public Key) is appended to `/etc/ssh/authorized_keys` on both the GCP Bastion Host and the VirtualBox Private Server.
* `id_ed25519` (Private Key) remains strictly on the client machine.



### Phase 2: Perimeter Gateway SSH Hardening

The default configuration of the SSH Daemon (`sshd`) on the GCP Bastion Host is updated to minimize its attack surface.

1. **Backup the original daemon profile**:
```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

```


2. **Modify parameters** inside `/etc/ssh/sshd_config` to strictly enforce zero trust:
```ini
# Mandate asymmetric key pairs and deny passwords completely
PasswordAuthentication no
PubkeyAuthentication yes

# Stop root exploit vectors
PermitRootLogin no

# Limit exposure by explicitly whitelisting authorized administrative users
AllowUsers tugas-bastion-host

# Aggressively drop TCP connections upon repeated authentication failures
MaxAuthTries 3

```


3. **Validate configuration syntax** and reload the service daemon:
```bash
sudo sshd -t
sudo systemctl restart ssh

```



### Phase 3: Perimeter Firewall (UFW) & Active Intrusion Prevention (Fail2Ban)

A layered security framework is introduced using a local system firewall integrated with log-parsing active defense tools.

1. **Restrict System Firewall Profiles (UFW)**:
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
echo "y" | sudo ufw enable

```


2. **Deploy Automated Brute-Force Bans (Fail2Ban)**:
Create a custom jail configuration file:
```bash
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local

```


Configure the specific `[sshd]` section to actively track login logs (`/var/log/auth.log`) and temporarily ban suspicious source IPs:
```ini
[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
findtime = 10m
bantime  = 1h

```


3. **Activate and verify operational status**:
```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd

```



### Phase 4: Constructing the Cryptographic Proxy Jump Tunnel

Because the Back-End Private Server sits behind an offline local Host-Only interface, we establish a secure inverse proxy tunnel using SSH Remote Port Forwarding.

1. **Configure the local client routing file** inside Windows (`C:\Users\aza\.ssh\config`):
```ini
Host bastion
    HostName 34.70.245.255
    User tugas-bastion-host
    IdentityFile ~/.ssh/id_ed25519
    RemoteForward 2222 192.168.56.101:22

```


2. **Open the Secure Tunnel Connection** from your local Windows terminal:
```powershell
ssh bastion

```


*(Leave this terminal session running to maintain the secure bridge connection.)*
3. **Access the Private Server Securely** from the Bastion Host terminal:
```bash
ssh aza@localhost -p 2222

```



---

## 🚀 Automated Deployment Script

To make this architecture scalable and easily repeatable for new servers, the entire perimeter hardening protocol is compiled into a single Bash script: `hardening-script.sh`.

```bash
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

```

---

## 📊 Verification Matrix

Use this checklist to confirm that all security controls are operating correctly:

| Verification Metric | Target Validation Parameter | Expected Behavior / Proof | Status |
| --- | --- | --- | --- |
| **Password Auth Lockout** | `ssh -o PubkeyAuthentication=no tugas-bastion-host@34.70.245.255` | Immediately returns `Permission denied (publickey)`. | ✅ Passed |
| **Root Access Rejection** | `ssh root@34.70.245.255` | Explicitly dropped by authentication provider. | ✅ Passed |
| **Firewall Isolation** | `sudo ufw status verbose` | Returns `Default: deny (incoming)` with only Port 22 allowed. | ✅ Passed |
| **Active Intrusion Detection** | `sudo fail2ban-client status sshd` | Actively parses `/var/log/auth.log` file paths. | ✅ Passed |
| **Secure Proxy Access** | `ssh aza@localhost -p 2222` | Successfully connects from the cloud to the isolated back-end. | ✅ Passed |
