# CPU Threads Limiter

Scripts para reservar 10% dos threads da CPU para o sistema e HiveOS no Ubuntu 22.04, deixando 90% para mineradores, sem precisar ajustar Flight Sheets.

## Instalação
```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/leogeeko/cpu_threads_limiter/main/install_thread_reservation.sh)"
sudo reboot
