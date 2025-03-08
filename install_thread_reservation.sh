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
    mount -t cgroup -o cpuset cpuset "$MOUNT_POINT"
fi

# Pega o total de threads
TOTAL=$(nproc)
# Calcula 10% pra reservar (mínimo 1)
RESERVED=$((TOTAL * 10 / 100))
[ $RESERVED -lt 1 ] && RESERVED=1
# Define o início dos threads reservados
START_RESERVED=$((TOTAL - RESERVED))
# Define os ranges
SYSTEM_CPUS="$START_RESERVED-$((TOTAL-1))"
USER_CPUS="0-$((START_RESERVED-1))"

# Configura o cpuset raiz (todos os threads)
echo "0-$((TOTAL-1))" > "$MOUNT_POINT/cpuset.cpus"
echo "0" > "$MOUNT_POINT/cpuset.mems"

# Configura cpuset pro sistema (10%)
mkdir -p "$MOUNT_POINT/system"
echo "$SYSTEM_CPUS" > "$MOUNT_POINT/system/cpuset.cpus"
echo "0" > "$MOUNT_POINT/system/cpuset.mems"

# Configura cpuset pros mineradores (90%)
mkdir -p "$MOUNT_POINT/user"
echo "$USER_CPUS" > "$MOUNT_POINT/user/cpuset.cpus"
echo "0" > "$MOUNT_POINT/user/cpuset.mems"

# Log pra debug
echo "$(date): Total=$TOTAL, Reserved=$RESERVED, System=$SYSTEM_CPUS, User=$USER_CPUS" >> /var/log/reserve_threads.log
EOF

# Dá permissão ao script
chmod +x /usr/local/bin/reserve_system_threads.sh

# Cria o script de monitoramento de mineradores
cat > /usr/local/bin/monitor_miners.sh << 'EOF'
#!/bin/bash
while true; do
    # Lista processos de mineradores comuns no HiveOS
    for miner in tnn-miner xmrig cpuminer; do
        # Encontra PIDs de mineradores pelo nome
        pids=$(pgrep -f "$miner")
        for pid in $pids; do
            # Move pro grupo user (90% dos threads)
            echo "$pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null
        done
    done
    # Verifica processos em /hive/miners/
    for pid in $(ps -eo pid,cmd | grep '/hive/miners/' | grep -v grep | awk '{print $1}'); do
        echo "$pid" > /sys/fs/cgroup/cpuset/user/tasks 2>/dev/null
    done
    sleep 5  # Checa a cada 5 segundos
done
EOF
chmod +x /usr/local/bin/monitor_miners.sh

# Cria o serviço de reserva de threads
cat > /etc/systemd/system/reserve-threads.service << 'EOF'
[Unit]
Description=Reserva 10% dos threads com cpuset no boot
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

echo "Instalação concluída! 10% dos threads estão reservados pro sistema e HiveOS."
echo "Mineradores serão automaticamente restritos aos 90% restantes."
echo "Verifique após reboot: cat /var/log/reserve_threads.log"
