#!/bin/bash

# CGI Script para Kiosk Manager
# Baseado no sistema de diagnóstico funcionando

# Cabeçalhos CGI
echo "Content-Type: text/plain"
echo "Cache-Control: no-cache"
echo ""

# === CONFIGURAÇÕES ===
KIOSK_DIR="/home/administrador/kiosk"
WEB_DIR="/var/www/html"
LOG_FILE="/var/log/kiosk-manager.log"

# === FUNÇÕES DE LOGGING ===
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null
    echo "ERROR: $1" >&2
}

# === FUNÇÕES DE LIMPEZA ===
cleanup_and_exit() {
    local exit_code=${1:-0}
    wait 2>/dev/null
    jobs -p | xargs -r kill -TERM 2>/dev/null
    sleep 1
    jobs -p | xargs -r kill -KILL 2>/dev/null
    exit $exit_code
}

trap 'cleanup_and_exit 1' EXIT INT TERM

# === FUNÇÕES DE RETORNO ===
return_error() {
    log_error "$1"
    echo "ERROR: $1"
    cleanup_and_exit 1
}

return_success() {
    log_message "SUCCESS: $1"
    echo "$1"
    cleanup_and_exit 0
}

return_json() {
    echo "$1"
    cleanup_and_exit 0
}

# === FUNÇÕES DE PARSING ===
decode_url() {
    echo -e "$(echo "$1" | sed 's/+/ /g; s/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')"
}

parse_post_data() {
    if [ "$REQUEST_METHOD" = "POST" ]; then
        if [ "$CONTENT_TYPE" = "application/x-www-form-urlencoded" ]; then
            read -r POST_DATA
        else
            # Multipart form data (para uploads)
            return 0
        fi
    else
        return_error "Método não suportado. Use POST."
    fi
    
    log_message "POST_DATA: $POST_DATA"
    
    # Parse parameters
    IFS='&' read -ra PARAMS <<< "$POST_DATA"
    
    declare -A PARSED
    for param in "${PARAMS[@]}"; do
        IFS='=' read -ra KV <<< "$param"
        if [ ${#KV[@]} -eq 2 ]; then
            key=$(decode_url "${KV[0]}")
            value=$(decode_url "${KV[1]}")
            PARSED["$key"]="$value"
            log_message "Parsed: $key = $value"
        fi
    done
    
    # Export variables
    ACTION="${PARSED[action]}"
    PLATFORM="${PARSED[platform]:-x86_64}"
    WEBSITES="${PARSED[websites]}"
    DURATION="${PARSED[duration]}"
    ZOOM_IN="${PARSED[zoomIn]}"
    ZOOM_OUT="${PARSED[zoomOut]}"
    WAIT_TIME="${PARSED[waitTime]}"
    FILE_NAME="${PARSED[fileName]}"
}

# === FUNÇÕES DE CONFIGURAÇÃO ===
ensure_kiosk_dir() {
    if [ ! -d "$KIOSK_DIR" ]; then
        mkdir -p "$KIOSK_DIR" 2>/dev/null
        chown administrador:administrador "$KIOSK_DIR" 2>/dev/null
    fi
}

get_current_config() {
    ensure_kiosk_dir
    
    local websites=""
    local duration="10"
    local zoom_in="0"
    local zoom_out="0"
    local wait_time="10"
    
    # Ler configuração atual dos arquivos
    if [ -f "$KIOSK_DIR/websites" ]; then
        websites=$(cat "$KIOSK_DIR/websites" 2>/dev/null || echo "")
    fi
    
    if [ -f "$KIOSK_DIR/duration" ]; then
        duration=$(cat "$KIOSK_DIR/duration" 2>/dev/null || echo "10")
    fi
    
    if [ -f "$KIOSK_DIR/zoomin" ]; then
        zoom_in=$(cat "$KIOSK_DIR/zoomin" 2>/dev/null || echo "0")
    fi
    
    if [ -f "$KIOSK_DIR/zoomout" ]; then
        zoom_out=$(cat "$KIOSK_DIR/zoomout" 2>/dev/null || echo "0")
    fi
    
    if [ -f "$KIOSK_DIR/waittime" ]; then
        wait_time=$(cat "$KIOSK_DIR/waittime" 2>/dev/null || echo "10")
    fi
    
    # Retornar como JSON
    cat << EOF
{
    "websites": "$websites",
    "duration": "$duration",
    "zoomIn": "$zoom_in",
    "zoomOut": "$zoom_out",
    "waitTime": "$wait_time"
}
EOF
}

save_config() {
    ensure_kiosk_dir
    
    log_message "Salvando configuração - Websites: $WEBSITES, Duration: $DURATION"
    
    # Validações
    if [ -z "$WEBSITES" ]; then
        return_error "Websites não podem estar vazios"
    fi
    
    if [ -z "$DURATION" ] || [ "$DURATION" -lt 1 ]; then
        return_error "Duração deve ser maior que 0"
    fi
    
    # Salvar arquivos de configuração
    echo "$WEBSITES" > "$KIOSK_DIR/websites" || return_error "Erro ao salvar websites"
    echo "$DURATION" > "$KIOSK_DIR/duration" || return_error "Erro ao salvar duration"
    echo "$WAIT_TIME" > "$KIOSK_DIR/waittime" || return_error "Erro ao salvar waittime"
    
    # Salvar arquivo Information (compatibilidade com script original)
    cat > "$KIOSK_DIR/Information" << EOF
$WEBSITES
$DURATION
$ZOOM_IN
$ZOOM_OUT
$WAIT_TIME
EOF
    
    # Configurar zoom
    if [ "$ZOOM_IN" != "0" ]; then
        echo "$ZOOM_IN" > "$KIOSK_DIR/zoomin"
        rm -f "$KIOSK_DIR/zoomout" 2>/dev/null
    elif [ "$ZOOM_OUT" != "0" ]; then
        echo "$ZOOM_OUT" > "$KIOSK_DIR/zoomout"
        rm -f "$KIOSK_DIR/zoomin" 2>/dev/null
    else
        rm -f "$KIOSK_DIR/zoomin" "$KIOSK_DIR/zoomout" 2>/dev/null
    fi
    
    # Ajustar permissões
    chown -R administrador:administrador "$KIOSK_DIR" 2>/dev/null
    chmod -R 644 "$KIOSK_DIR"/* 2>/dev/null
    
    return_success "Configuração salva com sucesso!"
}

# === FUNÇÕES DE SISTEMA ===
check_kiosk_status() {
    # Verificar se há processo X rodando com kiosk
    if pgrep -f "ungoogled-chromium.*--kiosk" > /dev/null 2>&1; then
        echo "running"
    elif pgrep -f "chromium.*--kiosk" > /dev/null 2>&1; then
        echo "running"
    elif pgrep -f "vlc.*fullscreen.*loop" > /dev/null 2>&1; then
        echo "running"
    else
        echo "stopped"
    fi
}

restart_system() {
    log_message "Reiniciando sistema..."
    
    # Verificar se temos permissão para reiniciar
    if ! sudo -n reboot --help > /dev/null 2>&1; then
        return_error "Sem permissão para reiniciar o sistema"
    fi
    
    # Executar reinicialização
    nohup bash -c "sleep 2; sudo reboot" > /dev/null 2>&1 &
    
    return_success "Sistema reiniciando..."
}

stop_kiosk() {
    log_message "Parando kiosk..."
    
    # Parar processos do kiosk
    pkill -f "ungoogled-chromium.*--kiosk" 2>/dev/null
    pkill -f "chromium.*--kiosk" 2>/dev/null
    pkill -f "vlc.*fullscreen.*loop" 2>/dev/null
    pkill -f "openbox" 2>/dev/null
    
    sleep 2
    
    # Verificar se parou
    if [ "$(check_kiosk_status)" = "stopped" ]; then
        return_success "Kiosk parado com sucesso!"
    else
        return_error "Erro ao parar kiosk"
    fi
}

# === FUNÇÕES DE ARQUIVOS ===
list_files() {
    log_message "Listando arquivos em $WEB_DIR"
    
    if [ ! -d "$WEB_DIR" ]; then
        return_error "Diretório web não encontrado"
    fi
    
    # Listar arquivos relevantes
    find "$WEB_DIR" -maxdepth 1 -type f \( \
        -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" -o -name "*.mov" -o \
        -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o \
        -name "*.txt" -o -name "*.html" \
    \) -printf "%f\n" 2>/dev/null | sort
}

delete_file() {
    if [ -z "$FILE_NAME" ]; then
        return_error "Nome do arquivo não informado"
    fi
    
    # Verificar se arquivo existe e está no diretório web
    local file_path="$WEB_DIR/$FILE_NAME"
    
    if [ ! -f "$file_path" ]; then
        return_error "Arquivo não encontrado"
    fi
    
    # Verificar se está dentro do diretório permitido (segurança)
    local real_path=$(realpath "$file_path" 2>/dev/null)
    local real_web_dir=$(realpath "$WEB_DIR" 2>/dev/null)
    
    if [[ "$real_path" != "$real_web_dir"/* ]]; then
        return_error "Acesso negado - arquivo fora do diretório permitido"
    fi
    
    # Excluir arquivo
    if rm "$file_path" 2>/dev/null; then
        log_message "Arquivo excluído: $FILE_NAME"
        return_success "Arquivo excluído com sucesso!"
    else
        return_error "Erro ao excluir arquivo"
    fi
}

handle_file_upload() {
    log_message "Processando upload de arquivo"
    
    # Para upload de arquivos, precisamos processar multipart data
    # Por simplicidade, vamos usar uma abordagem básica
    
    # Criar diretório temporário
    local temp_dir="/tmp/kiosk_upload_$$"
    mkdir -p "$temp_dir"
    
    # Salvar dados POST em arquivo temporário
    cat > "$temp_dir/upload_data"
    
    # Processar arquivo (simplificado)
    # Em uma implementação real, seria necessário um parser completo de multipart
    
    # Por enquanto, retornar sucesso
    rm -rf "$temp_dir"
    return_success "Upload processado (funcionalidade em desenvolvimento)"
}

# === FUNÇÕES DE INFORMAÇÕES ===
get_system_info() {
    cat << EOF
📊 Informações do Sistema Kiosk
===============================

🖥️  Sistema Operacional:
$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "Desconhecido")

💻 Hardware:
   CPU: $(nproc) núcleo(s)
   Modelo: $(cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "Desconhecido")
   Memória Total: $(free -h | awk 'NR==2{print $2}')
   Memória Usada: $(free -h | awk 'NR==2{print $3}')

💾 Armazenamento:
$(df -h | grep -E '^/dev' | awk '{print "   " $6 ": " $3 "/" $2 " (" $5 " usado)"}')

🖥️  Display:
$(xrandr 2>/dev/null | grep ' connected' | head -5 || echo "   Informação não disponível (sem X11)")

🔧 Status dos Serviços:
   SSH: $(systemctl is-active ssh 2>/dev/null || echo "N/A")
   Apache: $(systemctl is-active apache2 2>/dev/null || echo "N/A")
   Docker: $(systemctl is-active docker 2>/dev/null || echo "N/A")

⏰ Sistema:
   Uptime: $(uptime -p 2>/dev/null || echo "Desconhecido")
   Data/Hora: $(date)
   Carga: $(uptime | awk '{print $(NF-2), $(NF-1), $NF}')

🖥️  Kiosk:
   Status: $(check_kiosk_status)
   Plataforma: $PLATFORM
   Diretório: $KIOSK_DIR
EOF
}

get_logs() {
    log_message "Coletando logs do sistema"
    
    echo "=== Logs do Kiosk Manager ==="
    if [ -f "$LOG_FILE" ]; then
        tail -50 "$LOG_FILE" 2>/dev/null
    else
        echo "Nenhum log disponível ainda."
    fi
    
    echo ""
    echo "=== Logs do Sistema (Últimas 20 linhas) ==="
    if command -v journalctl > /dev/null 2>&1; then
        sudo journalctl --since "1 hour ago" -n 20 --no-pager -q 2>/dev/null || echo "Logs não disponíveis"
    else
        tail -20 /var/log/syslog 2>/dev/null || echo "Logs não disponíveis"
    fi
    
    echo ""
    echo "=== Processos do Kiosk ==="
    ps aux | grep -E "(chromium|vlc|openbox)" | grep -v grep || echo "Nenhum processo ativo"
}

# === FUNÇÃO PRINCIPAL ===
main() {
    log_message "=== Nova requisição CGI ==="
    log_message "REQUEST_METHOD: $REQUEST_METHOD"
    log_message "CONTENT_TYPE: $CONTENT_TYPE"
    
    # Parse dos dados POST
    parse_post_data
    
    log_message "ACTION: $ACTION"
    log_message "PLATFORM: $PLATFORM"
    
    # Executar ação baseada no parâmetro
    case "$ACTION" in
        "get-config")
            get_current_config
            ;;
            
        "save-config")
            save_config
            ;;
            
        "check-status")
            check_kiosk_status
            ;;
            
        "restart-system")
            restart_system
            ;;
            
        "stop-kiosk")
            stop_kiosk
            ;;
            
        "list-files")
            list_files
            ;;
            
        "delete-file")
            delete_file
            ;;
            
        "upload-file")
            handle_file_upload
            ;;
            
        "system-info")
            get_system_info
            ;;
            
        "get-logs")
            get_logs
            ;;
            
        "ping")
            return_success "pong"
            ;;
            
        *)
            return_error "Ação não reconhecida: $ACTION"
            ;;
    esac
}

# Executar função principal
main "$@"
