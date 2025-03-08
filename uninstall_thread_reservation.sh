#!/bin/bash

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, execute como root (use sudo)"
    exit 1
fi

# Para e desabilita os serviços
systemctl stop reserve-threads.service monitor-miners.service
systemctl disable reserve-threads.service monitor-miners.service

# Remove os arquivos
rm -f /etc/systemd/system/reserve-threads.service
rm -f /etc/systemd/system/monitor-miners.service
rm -f /usr/local/bin/reserve_system_threads.sh
rm -f /usr/local/bin/monitor_miners.sh

# Recarrega o systemd
systemctl daemon-reload

# Opcional: desmonta o cpuset
if mountpoint -q /sys/fs/cgroup/cpuset; then
    umount /sys/fs/cgroup/cpuset
    rmdir /sys/fs/cgroup/cpuset/system /sys/fs/cgroup/cpuset/user /sys/fs/cgroup/cpuset
fi

echo "Desinstalação concluída! Reserva de threads removida."
echo "Reinicie o sistema pra voltar ao normal."
