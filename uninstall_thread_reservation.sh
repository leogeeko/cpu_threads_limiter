#!/bin/bash

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, execute como root (use sudo)"
    exit 1
fi

# Para e desabilita o serviço
systemctl stop reserve-threads.service
systemctl disable reserve-threads.service

# Remove os arquivos
rm -f /etc/systemd/system/reserve-threads.service
rm -f /usr/local/bin/reserve_system_threads.sh

# Recarrega o systemd
systemctl daemon-reload

# Opcional: desmonta o cpuset
if mountpoint -q /sys/fs/cgroup/cpuset; then
    umount /sys/fs/cgroup/cpuset
    rmdir /sys/fs/cgroup/cpuset/system /sys/fs/cgroup/cpuset/user /sys/fs/cgroup/cpuset
fi

echo "Desinstalação concluída! A reserva de threads foi removida."
echo "Reinicie o sistema para garantir que tudo volte ao normal."
