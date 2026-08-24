#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
apt-get update && apt-get install -y python3 python3-pip git expect logrotate
mkdir -p /home/user/.config/systemd/user/
mkdir -p /home/user/operator-logs/
mkdir -p /home/user/workspace/
git config --global user.email "user@example.com"
git config --global user.name "User"
# Create Bare Git Repo
git init --bare /home/user/k8s-manifests.git
# Create Workspace Repo
cd /home/user/workspace
git clone /home/user/k8s-manifests.git
cd k8s-manifests
echo "apiVersion: v1" > config.yaml
git add config.yaml
git commit -m "Initial commit"
# Create interactive push wrapper
cat << 'EOF' > /home/user/push-manifests.sh
#!/bin/bash
cd /home/user/workspace/k8s-manifests
echo -n "Deploy Passphrase: "
read -s pass
echo ""
if [ "$pass" = "k8s-oper-2024" ]; then
    echo "Authentication successful. Pushing..."
    git push origin main
else
    echo "Authentication failed."
    exit 1
fi
EOF
# Create systemd units
cat << 'EOF' > /home/user/.config/systemd/user/k8s-mock-api.service
[Unit]
Description=Mock K8s API
[Service]
ExecStart=/bin/sleep infinity
[Install]
WantedBy=default.target
EOF
cat << 'EOF' > /home/user/.config/systemd/user/manifest-operator.service
[Unit]
Description=Manifest Operator
# BUG: Missing After/Requires
[Service]
ExecStart=/bin/sleep infinity
[Install]
WantedBy=default.target
EOF
chown -R user:user /home/user/
rm -rf /home/user/.setup_tmp
