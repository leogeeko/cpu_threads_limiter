#!/bin/bash

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, execute como root (use sudo)"
    exit 1
fi

# Cria o script de reserva de threads
cat > /usr/local/bin/reserve_system_threads.sh << 'EOF'
#!/bin/bash
# Monta o cgroup v1 com cpuset, se não estiver montado
MOUNT_POINT="/sys/fs/cgroup/cpuset"
if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
    mount -t cgroup -o cpuset cpuset "$MOUNT_POINT" || { echo "Falha ao montar cpuset"; exit 1; }
fi

# Pega o total de threads
TOTAL=$(nproc)
# Calcula 20% pra reservar (mínimo 1)
RESERVED=$((TOTAL * 20 / 100))
[ $RESERVED -lt 1 ] && RESERVED=1
# Define o início dos threads reservados
START_RESERVED=$((TOTAL - RESERVED))
# Define os ranges
SYSTEM_CPUS="$START_RESERVED-$((TOTAL-1))"
USER_CPUS="0-$((START_RESERVED-1))"

# Configura o cpuset raiz (todos os threads inicialmente)
echo "0-$((TOTAL-1))" > "$MOUNT_POINT/cpuset.cpus"
echo "0" > "$MOUNT_POINT/cpuset.mems"

# Configura cpuset pro sistema (20%)
mkdir -p "$MOUNT_POINT/system"
echo "$SYSTEM_CPUS" > "$MOUNT_POINT/system/cpuset.cpus"
echo "0" > "$MOUNT_POINT/system/cpuset.mems"
echo "1" > "$MOUNT_POINT/system/cpuset.cpu_exclusive"  # Exclusivo pro sistema

# Configura cpuset pros mineradores (80%)
mkdir -p "$MOUNT_POINT/user"
echo "$USER_CPUS" > "$MOUNT_POINT/user/cpuset.cpus"
echo "0" > "$MOUNT_POINT/user/cpuset.mems"
echo "1" > "$MOUNT_POINT/user/cpuset.cpu_exclusive"  # Exclusivo pros mineradores

# Move todos os processos existentes pro grupo user inicialmente
while read -r pid; do
    echo "$pid" > "$MOUNT_POINT/user/tasks" 2>/dev/null
done < "$MOUNT_POINT/tasks"

# Log pra debug
echo "$(date): Total=$TOTAL, Reserved=$RESERVED, System=$SYSTEM_CPUS, User=$USER_CPUS" >> /var/log/reserve_threads.log
EOF

# Dá permissão ao script
chmod +x /usr/local/bin/reserve_system_threads.sh

# Cria o script de monitoramento de mineradores
cat > /usr/local/bin/monitor_miners.sh << 'EOF'
#!/bin/bash
# Lista de mineradores comuns no HiveOS
MINERS="tnn-miner xmrig cpuminer lolminer nanominer phoenixminer ethminer"
while true; do
    # Move processos de mineradores e seus filhos pro grupo user
    for miner in $MINERS; do
        pids=$(pidof "$miner" 2>/dev/null || pgrep -f "$miner")
        for pid in $pids; do
            # Move o processo principal
            echo "$pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved $miner (PID $pid) to user" >> /var/log/monitor_miners.log
            # Move todos os filhos
            child_pids=$(pstree -p "$pid" 2>/dev/null | grep -o '[0-9]\+' || ps -o pid --ppid "$pid" | grep -v PID)
            for child_pid in $child_pids; do
                echo "$child_pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved child (PID $child_pid) of $miner to user" >> /var/log/monitor_miners.log
            done
        done
    done
    # Move qualquer processo em /hive/miners/
    pids=$(ps -eo pid,cmd | grep -E '/hive/miners/[^ ]*/[^ ]*$' | grep -v grep | awk '{print $1}')
    for pid in $pids; do
        echo "$pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved miner (PID $pid) from /hive/miners/ to user" >> /var/log/monitor_miners.log
        child_pids=$(pstree -p "$pid" 2>/dev/null | grep -o '[0-9]\+' || ps -o pid --ppid "$pid" | grep -v PID)
        for child_pid in $child_pids; do
            echo "$child_pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved child (PID $child_pid) from /hive/miners/ to user" >> /var/log/monitor_miners.log
        done
    done
    sleep 0.1  # Checa a cada 0,1 segundos
done
EOF
chmod +x /usr/local/bin/monitor_miners.sh

# Cria o serviço de reserva de threads
cat > /etc/systemd/system/reserve-threads.service << 'EOF'
[Unit]
Description=Reserva 20% dos threads com cpuset no boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reserve_system_threads.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Cria o serviço de monitoramento
cat > /etc/systemd/system/monitor-miners.service << 'EOF'
[Unit]
Description=Monitora e move mineradores pro cpuset user
After=reserve-threads.service

[Service]
Type=simple
ExecStart=/usr/local/bin/monitor_miners.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Recarrega o systemd e habilita os serviços
systemctl daemon-reload
systemctl enable reserve-threads.service monitor-miners.service
systemctl start reserve-threads.service monitor-miners.service

echo "Instalação concluída! 20% dos threads estão reservados pro sistema e HiveOS."
echo "Mineradores serão restritos aos 80% automaticamente."
echo "Verifique: cat /var/log/reserve_threads.log e /var/log/monitor_miners.log"
