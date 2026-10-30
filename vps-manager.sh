#!/bin/bash
# =====================================================================
#  VPS MANAGER - terminal menu
#  Run on the SOURCE VPS as root:   bash vps-manager.sh
# =====================================================================

LOGDIR="/root/vps-manager-logs"
mkdir -p "$LOGDIR"

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; C='\033[1;36m'; N='\033[0m'

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

EXCLUDES=(
  '--exclude=/dev/*' '--exclude=/proc/*' '--exclude=/sys/*' '--exclude=/run/*'
  '--exclude=/tmp/*' '--exclude=/mnt/*' '--exclude=/media/*' '--exclude=/lost+found'
  '--exclude=/boot/*' '--exclude=/swapfile' '--exclude=/etc/fstab'
  '--exclude=/etc/hostname' '--exclude=/etc/hosts' '--exclude=/etc/resolv.conf'
  '--exclude=/etc/network/*' '--exclude=/etc/netplan/*' '--exclude=/etc/ssh/*'
  '--exclude=/etc/machine-id' '--exclude=/root/.ssh/*' '--exclude=/var/lib/cloud/*'
  "--exclude=$LOGDIR/*"
)

pause() { read -rp "Press Enter to continue..." _; }

need_root() {
  if [ "$(id -u)" != 0 ]; then
    echo -e "${R}Please run this script as root.${N}"
    exit 1
  fi
}

install_tools() {
  if command -v rsync >/dev/null && command -v sshpass >/dev/null; then
    return 0
  fi
  echo -e "${Y}Installing rsync and sshpass...${N}"
  if command -v apt-get >/dev/null; then
    apt-get update -y && apt-get install -y rsync sshpass
  elif command -v dnf >/dev/null; then
    dnf install -y rsync sshpass
  elif command -v yum >/dev/null; then
    yum install -y rsync sshpass
  else
    echo -e "${R}Unsupported package manager. Install rsync and sshpass manually.${N}"
    return 1
  fi
}

banner() {
  clear
  echo -e "${C}╔════════════════════════════════════════════╗"
  echo -e "║               VPS MANAGER                  ║"
  echo -e "╠════════════════════════════════════════════╣${N}"
  echo -e "${C}║${N}  1. Data Transfer (this VPS -> other VPS)  ${C}║"
  echo -e "║${N}  2. Test connection to a VPS               ${C}║"
  echo -e "║${N}  3. View transfer logs                     ${C}║"
  echo -e "║${N}  4. Install requirements                   ${C}║"
  echo -e "║${N}  0. Exit                                   ${C}║"
  echo -e "╚════════════════════════════════════════════╝${N}"
}

# test_conn IP PORT USER PASSWORD
test_conn() {
  SSHPASS="$4" sshpass -e ssh -p "$2" $SSH_OPTS "$3@$1" "echo ok" >/dev/null 2>&1
}

test_connection() {
  local ip port usr pw
  echo -e "${C}--- Test connection ---${N}"
  read -rp "IP: " ip
  read -rp "SSH port [22]: " port; port=${port:-22}
  read -rp "User [root]: " usr; usr=${usr:-root}
  read -rsp "Password: " pw; echo
  install_tools || { pause; return; }
  if test_conn "$ip" "$port" "$usr" "$pw"; then
    echo -e "${G}Connection successful.${N}"
  else
    echo -e "${R}Connection failed. Check IP, port, user, password and that password login is enabled.${N}"
  fi
  pause
}

data_transfer() {
  local count i svc_list stop_svc reboot_after confirm
  local -a IP PORT USR PASS PIDS

  echo -e "${C}--- Data Transfer ---${N}"
  install_tools || { pause; return; }

  read -rp "How many destination VPS? [2]: " count; count=${count:-2}
  if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 1 ]; then
    echo -e "${R}Invalid number.${N}"; pause; return
  fi

  for ((i = 1; i <= count; i++)); do
    echo -e "${Y}Destination VPS $i${N}"
    read -rp "  IP: " IP[$i]
    read -rp "  SSH port [22]: " PORT[$i]; PORT[$i]=${PORT[$i]:-22}
    read -rp "  User [root]: " USR[$i]; USR[$i]=${USR[$i]:-root}
    read -rsp "  Password: " PASS[$i]; echo
    if [ -z "${IP[$i]}" ] || [ -z "${PASS[$i]}" ]; then
      echo -e "${R}IP and password are required.${N}"; pause; return
    fi
  done

  echo
  read -rp "Stop services during transfer (recommended for databases)? [y/N]: " stop_svc
  svc_list="mariadb mysql docker wings"
  if [[ "$stop_svc" =~ ^[Yy]$ ]]; then
    read -rp "Services to stop [$svc_list]: " s; svc_list=${s:-$svc_list}
  fi
  read -rp "Reboot destination VPS after transfer? [y/N]: " reboot_after

  echo
  echo -e "${C}Checking connections...${N}"
  for ((i = 1; i <= count; i++)); do
    if test_conn "${IP[$i]}" "${PORT[$i]}" "${USR[$i]}" "${PASS[$i]}"; then
      echo -e "  VPS $i (${IP[$i]}): ${G}OK${N}"
    else
      echo -e "  VPS $i (${IP[$i]}): ${R}FAILED${N}"
      echo -e "${R}Fix the connection and try again.${N}"; pause; return
    fi
  done

  echo
  echo -e "${Y}This will copy ALL data from this VPS to $count VPS and overwrite files there.${N}"
  read -rp "Type YES to start: " confirm
  [ "$confirm" = "YES" ] || { echo "Cancelled."; pause; return; }

  if [[ "$stop_svc" =~ ^[Yy]$ ]]; then
    for s in $svc_list; do systemctl stop "$s" 2>/dev/null; done
  fi

  for ((i = 1; i <= count; i++)); do
    : > "$LOGDIR/vps$i.log"
    (
      SSHPASS="${PASS[$i]}" rsync -aAXHz --numeric-ids --info=progress2 "${EXCLUDES[@]}" \
        -e "sshpass -e ssh -p ${PORT[$i]} $SSH_OPTS" \
        / "${USR[$i]}@${IP[$i]}:/" > "$LOGDIR/vps$i.log" 2>&1
    ) &
    PIDS[$i]=$!
  done

  echo -e "${C}Transfer running... (Ctrl+C will stop it)${N}"
  local alive line out
  while true; do
    alive=0; out=""
    for ((i = 1; i <= count; i++)); do
      kill -0 "${PIDS[$i]}" 2>/dev/null && alive=1
      line=$(tr '\r' '\n' < "$LOGDIR/vps$i.log" | tail -n1 | cut -c1-60)
      out+="VPS$i: ${line:-starting}   "
    done
    printf "\r\033[K%s" "$out"
    [ "$alive" = 0 ] && break
    sleep 3
  done
  echo; echo

  local rc
  for ((i = 1; i <= count; i++)); do
    wait "${PIDS[$i]}"; rc=$?
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 24 ]; then
      echo -e "${G}[VPS $i] Done${N}"
    else
      echo -e "${R}[VPS $i] Failed (code $rc). Log: $LOGDIR/vps$i.log${N}"
    fi
  done

  if [[ "$stop_svc" =~ ^[Yy]$ ]]; then
    for s in $svc_list; do systemctl start "$s" 2>/dev/null; done
  fi

  if [[ "$reboot_after" =~ ^[Yy]$ ]]; then
    for ((i = 1; i <= count; i++)); do
      SSHPASS="${PASS[$i]}" sshpass -e ssh -p "${PORT[$i]}" $SSH_OPTS "${USR[$i]}@${IP[$i]}" reboot 2>/dev/null
      echo "Reboot sent to VPS $i"
    done
  fi

  echo -e "${G}All finished.${N}"
  pause
}

view_logs() {
  local f
  echo -e "${C}--- Transfer logs ---${N}"
  if ! ls "$LOGDIR"/*.log >/dev/null 2>&1; then
    echo "No logs yet."; pause; return
  fi
  for f in "$LOGDIR"/*.log; do
    echo -e "${Y}$f${N}"
    tr '\r' '\n' < "$f" | tail -n 5
    echo
  done
  pause
}

need_root

while true; do
  banner
  read -rp "Choose an option: " opt
  case "$opt" in
    1) data_transfer ;;
    2) test_connection ;;
    3) view_logs ;;
    4) install_tools && echo -e "${G}Requirements are installed.${N}"; pause ;;
    0) echo "Bye."; exit 0 ;;
    *) echo -e "${R}Invalid option.${N}"; sleep 1 ;;
  esac
done
