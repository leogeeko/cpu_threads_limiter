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
# Calcula 20% pra reservar (mínimo 1)
RESERVED=$((TOTAL * 20 / 100))
[ $RESERVED -lt 1 ] && RESERVED=1
# Define o início dos threads reservados
START_RESERVED=$((TOTAL - RESERVED))
# Define os ranges
SYSTEM_CPUS="$START_RESERVED-$((TOTAL-1))"
USER_CPUS="0-$((START_RESERVED-1))"

# Configura o cpuset raiz
echo "0-$((TOTAL-1))" > "$MOUNT_POINT/cpuset.cpus"
echo "0" > "$MOUNT_POINT/cpuset.mems"

# Configura cpuset pro sistema
mkdir -p "$MOUNT_POINT/system"
echo "$SYSTEM_CPUS" > "$MOUNT_POINT/system/cpuset.cpus"
echo "0" > "$MOUNT_POINT/system/cpuset.mems"

# Configura cpuset pros processos de usuário
mkdir -p "$MOUNT_POINT/user"
echo "$USER_CPUS" > "$MOUNT_POINT/user/cpuset.cpus"
echo "0" > "$MOUNT_POINT/user/cpuset.mems"

# Move processos existentes pro grupo 'user'
while read -r pid; do
    echo "$pid" > "$MOUNT_POINT/user/tasks" 2>/dev/null
done < "$MOUNT_POINT/tasks"

# Log pra debug
echo "$(date): Total=$TOTAL, Reserved=$RESERVED, System=$SYSTEM_CPUS, User=$USER_CPUS" >> /var/log/reserve_threads.log
EOF

# Dá permissão ao script
chmod +x /usr/local/bin/reserve_system_threads.sh

# Cria o serviço systemd
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

# Recarrega o systemd e habilita o serviço
systemctl daemon-reload
systemctl enable reserve-threads.service
systemctl start reserve-threads.service

echo "Instalação concluída! 20% dos threads estão reservados. Reinicie o sistema para aplicar."
echo "Para verificar após o reboot, use: cat /var/log/reserve_threads.log"
