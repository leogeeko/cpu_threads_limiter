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
echo "1" > "$MOUNT_POINT/system/cpuset.cpu_exclusive"

# Configura cpuset pros mineradores (80%)
mkdir -p "$MOUNT_POINT/user"
echo "$USER_CPUS" > "$MOUNT_POINT/user/cpuset.cpus"
echo "0" > "$MOUNT_POINT/user/cpuset.mems"
echo "1" > "$MOUNT_POINT/user/cpuset.cpu_exclusive"

# Move processos do sistema HiveOS pro grupo system
SYSTEM_PROCESSES="init systemd sshd hive rsyslogd"
for proc in $SYSTEM_PROCESSES; do
    pids=$(pidof "$proc" 2>/dev/null || pgrep -f "$proc")
    for pid in $pids; do
        echo "$pid" > "$MOUNT_POINT/system/tasks" 2>/dev/null && echo "$(date): Moved $proc (PID $pid) to system" >> /var/log/reserve_threads.log
    done
done

# Move todos os outros processos pro grupo user
while read -r pid; do
    # Evita mover processos já no system
    if ! grep -q "$pid" "$MOUNT_POINT/system/tasks" 2>/dev/null; then
        echo "$pid" > "$MOUNT_POINT/user/tasks" 2>/dev/null
    fi
done < "$MOUNT_POINT/tasks"

# Log pra debug
echo "$(date): Total=$TOTAL, Reserved=$RESERVED, System=$SYSTEM_CPUS, User=$USER_CPUS" >> /var/log/reserve_threads.log
EOF
chmod +x /usr/local/bin/reserve_system_threads.sh

# Cria o script de monitoramento de mineradores
cat > /usr/local/bin/monitor_miners.sh << 'EOF'
#!/bin/bash
MINERS="tnn-miner xmrig cpuminer lolminer nanominer phoenixminer ethminer"
while true; do
    for miner in $MINERS; do
        pids=$(pidof "$miner" 2>/dev/null || pgrep -f "$miner")
        for pid in $pids; do
            echo "$pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved $miner (PID $pid) to user" >> /var/log/monitor_miners.log
            child_pids=$(pstree -p "$pid" 2>/dev/null | grep -o '[0-9]\+' || ps -o pid --ppid "$pid" | grep -v PID)
            for child_pid in $child_pids; do
                echo "$child_pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved child (PID $child_pid) of $miner to user" >> /var/log/monitor_miners.log
            done
        done
    done
    pids=$(ps -eo pid,cmd | grep -E '/hive/miners/[^ ]*/[^ ]*$' | grep -v grep | awk '{print $1}')
    for pid in $pids; do
        echo "$pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved miner (PID $pid) from /hive/miners/ to user" >> /var/log/monitor_miners.log
        child_pids=$(pstree -p "$pid" 2>/dev/null | grep -o '[0-9]\+' || ps -o pid --ppid "$pid" | grep -v PID)
        for child_pid in $child_pids; do
            echo "$child_pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null && echo "$(date): Moved child (PID $child_pid) from /hive/miners/ to user" >> /var/log/monitor_miners.log
        done
    done
    sleep 0.1
done
EOF
chmod +x /usr/local/bin/monitor_miners.sh

# Cria os serviços systemd
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

# Recarrega e inicia os serviços
systemctl daemon-reload
systemctl enable reserve-threads.service monitor-miners.service
systemctl start reserve-threads.service monitor-miners.service

echo "Instalação concluída! 20% dos threads reservados pro sistema e HiveOS."
echo "Mineradores restritos aos 80% automaticamente."
echo "Verifique: cat /var/log/reserve_threads.log e /var/log/monitor_miners.log"
