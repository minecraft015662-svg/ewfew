#!/bin/bash
# ===== LXD FULL VPS MIGRATION (A to Z) =====
# Purane VPS pe chalao. Naye VPS ki details puchega aur saare LXD containers data ke saath copy karega.

if [ "$(id -u)" -ne 0 ]; then
  echo "Root se chalao (sudo -i karke)"; exit 1
fi

echo "===== VPS Migration Tool ====="
read -p "Naye VPS ka IP: " NEW_IP </dev/tty
read -p "Naye VPS ka SSH port (default 22): " PORT </dev/tty; PORT=${PORT:-22}
read -p "Naye VPS ka username (default root): " USR </dev/tty; USR=${USR:-root}
read -s -p "Naye VPS ka password: " PASS </dev/tty; echo

apt-get update -y >/dev/null 2>&1
apt-get install -y sshpass rsync >/dev/null 2>&1
export PATH=$PATH:/snap/bin
SSH="sshpass -p $PASS ssh -p $PORT -o StrictHostKeyChecking=no $USR@$NEW_IP"

$SSH "echo connected" >/dev/null 2>&1 || { echo "SSH connect nahi hua, IP/password/port check karo"; exit 1; }

echo ">> [1/5] Naye VPS pe LXD setup..."
$SSH 'export PATH=$PATH:/snap/bin
command -v lxc >/dev/null || (apt-get update -y && apt-get install -y snapd && snap install lxd)
lxd init --auto 2>/dev/null
lxc config set core.https_address "[::]:8443"
modprobe overlay; modprobe br_netfilter
printf "overlay\nbr_netfilter\n" > /etc/modules-load.d/docker.conf'

echo ">> [2/5] Connection bana raha hu..."
TOKEN=$($SSH 'export PATH=$PATH:/snap/bin; lxc config trust add --name migrate 2>&1' | tail -1)
lxc remote remove newvps >/dev/null 2>&1
lxc remote add newvps "$TOKEN" --accept-certificate || { echo "Remote add fail (port 8443 open hai?)"; exit 1; }

echo ">> [3/5] Profiles copy ho rahe hain..."
for p in $(lxc profile list --format csv | cut -d, -f1); do
  $SSH "export PATH=\$PATH:/snap/bin; lxc profile create $p" >/dev/null 2>&1
  lxc profile show $p | $SSH "export PATH=\$PATH:/snap/bin; lxc profile edit $p" >/dev/null 2>&1
done

echo ">> [4/5] Containers copy ho rahe hain (data ke saath)..."
for c in $(lxc list -c n --format csv); do
  echo "---- $c ----"
  WAS=$(lxc info $c | grep -i '^Status' | awk '{print $2}')
  lxc stop $c --force 2>/dev/null
  if lxc copy $c newvps:$c --mode=push; then
    echo "$c COPY DONE"
    [ "$WAS" = "RUNNING" ] && lxc start newvps:$c
  else
    echo "$c FAIL HUA"
  fi
  [ "$WAS" = "RUNNING" ] && lxc start $c
done

echo ">> [5/5] Firewall rules backup bhej raha hu..."
iptables-save > /root/old-iptables.rules 2>/dev/null
sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no /root/old-iptables.rules $USR@$NEW_IP:/root/ 2>/dev/null

echo ""
echo "===== NAYE VPS KI CONTAINER LIST ====="
$SSH 'export PATH=$PATH:/snap/bin; lxc list'
echo "Migration complete. Ab DNS / Panel Node IP naye VPS pe update karo."
