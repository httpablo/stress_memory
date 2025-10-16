#!/usr/bin/env bash
# Teste automatizado de swappiness - utilizado na maquina2

set -euo pipefail

# Requer root
if [ "$EUID" -ne 0 ]; then 
    echo "Este script precisa ser executado como root (use sudo)"
    echo "Exemplo: sudo $0"
    exit 1
fi

STRESS_SCRIPT="stress_memory.py"
DISK_DEVICE="sda"
SWAPPINESS_VALUES=(10 60 100)
TIMEOUT_SECONDS=300

cleanup_processes() {
    local pid=$1
    if kill -0 "$pid" 2>/dev/null; then
        echo "  Terminando processo $pid..."
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Forçando término do processo $pid..."
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
}

reset_system_state() {
    echo "Resetando estado do sistema..."
    echo "  Desativando swap..."
    swapoff -a 2>/dev/null || echo "  Aviso: Não foi possível desativar swap completamente"
    echo "  Limpando caches de memória..."
    sync && sync
    echo 3 > /proc/sys/vm/drop_caches
    echo "  Reativando swap..."
    swapon -a
    sleep 3
    echo "  Sistema resetado."
}

echo "### INICIANDO SUÍTE DE TESTES DE SWAPPINESS ###"
echo "O script deve ser executado com sudo"
echo "Timeout por teste: ${TIMEOUT_SECONDS}s"
echo "----------------------------------------------------"

if [ ! -f "$STRESS_SCRIPT" ]; then
    echo "ERRO: Script $STRESS_SCRIPT não encontrado!"
    exit 1
fi

echo "Estado inicial do sistema:"
free -h | head -3 | sed 's/^/  /'
echo ""

read -p "Deseja continuar com os testes? (s/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Testes cancelados."
    exit 0
fi

for swappy in "${SWAPPINESS_VALUES[@]}"; do
    echo ""
    echo "=== INICIANDO TESTE PARA SWAPPINESS = $swappy ==="
    reset_system_state
    echo "Definindo vm.swappiness = $swappy"
    sysctl vm.swappiness=$swappy > /dev/null

    echo "Estado da memória antes do teste:"
    free -h | head -3 | sed 's/^/  /'

    VMSTAT_LOG="vmstat_log_swappiness_${swappy}.txt"
    IOSTAT_LOG="iostat_log_swappiness_${swappy}.txt"
    STRESS_LOG="output_swappiness_${swappy}.txt"
    TIME_LOG="time_log_swappiness_${swappy}.txt"

    echo "Iniciando monitores em background..."
    timeout ${TIMEOUT_SECONDS} vmstat 1 > "$VMSTAT_LOG" 2>/dev/null &
    VMSTAT_PID=$!
    timeout ${TIMEOUT_SECONDS} iostat -d "$DISK_DEVICE" 1 > "$IOSTAT_LOG" 2>/dev/null &
    IOSTAT_PID=$!

    sleep 2

    echo "Executando script de estresse (timeout: ${TIMEOUT_SECONDS}s)..."
    if command -v /usr/bin/time >/dev/null 2>&1; then
        timeout ${TIMEOUT_SECONDS} /usr/bin/time -p python3 "$STRESS_SCRIPT" > "$STRESS_LOG" 2> "$TIME_LOG" || {
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 124 ]; then
                echo "  AVISO: Teste atingiu timeout de ${TIMEOUT_SECONDS}s"
                echo "real ${TIMEOUT_SECONDS}.00" >> "$TIME_LOG"
            else
                echo "  AVISO: Script de stress terminou com código $EXIT_CODE"
            fi
        }
    else
        (timeout ${TIMEOUT_SECONDS} bash -c "time python3 $STRESS_SCRIPT" > "$STRESS_LOG") 2> "$TIME_LOG" || {
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 124 ]; then
                echo "  AVISO: Teste atingiu timeout de ${TIMEOUT_SECONDS}s"
                echo -e "real\t${TIMEOUT_SECONDS}.00s" >> "$TIME_LOG"
            else
                echo "  AVISO: Script de stress terminou com código $EXIT_CODE"
            fi
        }
    fi

    echo "Script de estresse finalizado. Encerrando monitores..."
    cleanup_processes $VMSTAT_PID
    cleanup_processes $IOSTAT_PID
    wait $VMSTAT_PID 2>/dev/null || true
    wait $IOSTAT_PID 2>/dev/null || true

    echo "Teste para swappiness=$swappy concluído."
    echo "Logs salvos: $VMSTAT_LOG, $IOSTAT_LOG, $STRESS_LOG, $TIME_LOG"
    echo "----------------------------------------------------"
    sleep 3
done

echo ""
echo "### SUÍTE DE TESTES CONCLUÍDA ###"
echo ""
echo "Analisando resultados..."

printf "\n========= RESUMO DOS RESULTADOS =========\n"
printf "%-20s | %-15s | %-20s | %-20s | %-15s\n" \
       "Swappiness" "Duração (s)" "Início Swap-Out (s)" "Pico Swap-Out (KB/s)" "Pico TPS"
printf "%-20s-+-%-15s-+-%-20s-+-%-20s-+-%-15s\n" \
       "--------------------" "---------------" "--------------------" "--------------------" "---------------"

for swappy in "${SWAPPINESS_VALUES[@]}"; do
    TIME_LOG="time_log_swappiness_${swappy}.txt"
    VMSTAT_LOG="vmstat_log_swappiness_${swappy}.txt"
    IOSTAT_LOG="iostat_log_swappiness_${swappy}.txt"

    if [ -f "$TIME_LOG" ] && [ -s "$TIME_LOG" ]; then
        if grep -q '^real' "$TIME_LOG" 2>/dev/null; then
            DURATION=$(grep '^real' "$TIME_LOG" | awk '{print $2}')
        elif grep -q 'real.*[0-9]m[0-9]' "$TIME_LOG" 2>/dev/null; then
            DURATION=$(grep 'real' "$TIME_LOG" | awk '{print $2}' | sed -e 's/0m//' -e 's/s//')
        else
            DURATION="N/A"
        fi
    else
        DURATION="N/A"
    fi

    if [ -f "$VMSTAT_LOG" ]; then
        SWAP_START=$(awk 'NR > 3 && $8 > 100 {print NR-3; exit}' "$VMSTAT_LOG")
        [ -z "$SWAP_START" ] && SWAP_START="N/A"
        PEAK_SO=$(awk 'NR > 2 {if($8 ~ /^[0-9]+$/) print $8}' "$VMSTAT_LOG" | sort -n | tail -1)
        [ -z "$PEAK_SO" ] && PEAK_SO="0"
    else
        SWAP_START="N/A"
        PEAK_SO="N/A"
    fi

    if [ -f "$IOSTAT_LOG" ]; then
        PEAK_TPS=$(awk 'NR > 3 && $2 ~ /^[0-9]/ {print $2}' "$IOSTAT_LOG" | sort -n | tail -1)
        [ -z "$PEAK_TPS" ] && PEAK_TPS="N/A"
    else
        PEAK_TPS="N/A"
    fi

    case $swappy in
        10)  LABEL="$swappy (Conservador)" ;;
        60)  LABEL="$swappy (Padrão)" ;;
        100) LABEL="$swappy (Agressivo)" ;;
        *)   LABEL="$swappy" ;;
    esac

    printf "%-20s | %-15s | %-20s | %-20s | %-15s\n" \
           "$LABEL" "$DURATION" "$SWAP_START" "$PEAK_SO" "$PEAK_TPS"
done

printf "==========================================\n\n"

echo "Verificação dos arquivos de log:"
for swappy in "${SWAPPINESS_VALUES[@]}"; do
    echo "  Swappiness $swappy:"
    for prefix in vmstat iostat; do
        LOG="${prefix}_log_swappiness_${swappy}.txt"
        if [ -f "$LOG" ]; then
            SIZE=$(wc -l < "$LOG")
            echo "    ✓ ${LOG} (${SIZE} linhas)"
        else
            echo "    ✗ ${LOG} não encontrado"
        fi
    done

    OUTPUT_LOG="output_swappiness_${swappy}.txt"
    if [ -f "$OUTPUT_LOG" ]; then
        SIZE=$(wc -l < "$OUTPUT_LOG")
        echo "    ✓ ${OUTPUT_LOG} (${SIZE} linhas)"
    else
        echo "    ✗ ${OUTPUT_LOG} não encontrado"
    fi

    TIME_LOG="time_log_swappiness_${swappy}.txt"
    if [ -f "$TIME_LOG" ]; then
        SIZE=$(wc -l < "$TIME_LOG")
        echo "    ✓ ${TIME_LOG} (${SIZE} linhas)"
    else
        echo "    ✗ ${TIME_LOG} não encontrado"
    fi
done

echo ""
echo "Script finalizado com sucesso!"