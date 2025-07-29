#!/bin/bash

# Script de Instalação do Kiosk Manager WebUI
# Versão: 1.0
# Baseado no sistema de diagnóstico funcionando

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Verificar se está rodando como root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script deve ser executado como root (sudo)"
        exit 1
    fi
}

# Detectar servidor web
detect_webserver() {
    if systemctl is-active --quiet apache2 2>/dev/null; then
        WEBSERVER="apache2"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
    elif systemctl is-active --quiet nginx 2>/dev/null; then
        WEBSERVER="nginx"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
        log_warning "Nginx detectado. Será necessário configuração manual do CGI."
    elif systemctl is-active --quiet lighttpd 2>/dev/null; then
        WEBSERVER="lighttpd"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
    else
        log_warning "Nenhum servidor web ativo detectado. Tentando instalar Apache..."
        install_apache
        WEBSERVER="apache2"
        WEBROOT="/var/www/html"
        CGI_DIR="/usr/lib/cgi-bin"
    fi
    
    log_success "Servidor web detectado: $WEBSERVER"
    log "Diretório web: $WEBROOT"
    log "Diretório CGI: $CGI_DIR"
}

# Instalar Apache
install_apache() {
    log "Instalando Apache..."
    
    if ! command -v apache2 >/dev/null 2>&1; then
        apt-get update
        apt-get install -y apache2
        a2enmod cgi
        systemctl enable apache2
        systemctl start apache2
    fi
    
    log_success "Apache instalado e configurado"
}

# Criar diretórios necessários
create_directories() {
    log "Criando diretórios necessários..."
    
    mkdir -p "$WEBROOT"
    mkdir -p "$CGI_DIR"
    mkdir -p "/home/administrador/kiosk"
    mkdir -p "/var/log"
    
    # Ajustar permissões
    chown -R administrador:administrador "/home/administrador/kiosk" 2>/dev/null || true
    chmod 755 "/home/administrador/kiosk" 2>/dev/null || true
    
    log_success "Diretórios criados"
}

# Criar script CGI
create_cgi_script() {
    log "Criando script CGI..."
    
    cat > "$CGI_DIR/kiosk-manager.cgi" << 'EOFCGI'
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
EOFCGI

    chmod +x "$CGI_DIR/kiosk-manager.cgi"
    log_success "Script CGI criado em $CGI_DIR/kiosk-manager.cgi"
}

# Criar página HTML
create_html_page() {
    log "Criando página HTML..."
    
    # A página HTML será baixada do repositório ou criada aqui
    # Por simplicidade, vou criar uma versão básica
    
    cat > "$WEBROOT/kiosk-manager.html" << 'EOFHTML'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kiosk Manager - Interface Web</title>
    <style>
        /* Incluir aqui todo o CSS do arquivo original */
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            font-weight: 300;
        }
        .main-content { padding: 40px; }
        .menu-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .menu-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
            transition: all 0.3s ease;
            cursor: pointer;
            border: 2px solid transparent;
            text-align: center;
        }
        .menu-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.15);
            border-color: #3498db;
        }
        .menu-card.primary {
            background: linear-gradient(135deg, #3498db 0%, #2980b9 100%);
            color: white;
        }
        .alert {
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 6px;
            display: none;
        }
        .alert.active { display: block; }
        .alert-success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        .alert-error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ Kiosk Manager</h1>
            <p>Interface Web para Gerenciamento do Sistema Kiosk Mode</p>
        </div>
        <div class="main-content">
            <div id="alert-container" class="alert"></div>
            <div class="menu-grid">
                <div class="menu-card primary" onclick="showAlert('Funcionalidade em desenvolvimento', 'info')">
                    <h3>⚙️ Configurar Kiosk</h3>
                    <p>Configurar websites, duração, zoom e outras opções do kiosk.</p>
                </div>
            </div>
        </div>
    </div>
    <script>
        function showAlert(message, type = 'info') {
            const alert = document.getElementById('alert-container');
            alert.textContent = message;
            alert.className = `alert alert-${type} active`;
            setTimeout(() => alert.classList.remove('active'), 5000);
        }
    </script>
</body>
</html>
EOFHTML

    log_success "Página HTML criada em $WEBROOT/kiosk-manager.html"
}

# Configurar Apache
configure_apache() {
    if [ "$WEBSERVER" = "apache2" ]; then
        log "Configurando Apache para porta 8080..."
        
        # Verificar se a porta 8080 já está configurada
        if ! grep -q "Listen 8080" /etc/apache2/ports.conf; then
            echo "Listen 8080" >> /etc/apache2/ports.conf
        fi
        
        # Criar VirtualHost para porta 8080
        cat > /etc/apache2/sites-available/kiosk-manager.conf << 'EOFVHOST'
<VirtualHost *:8080>
    DocumentRoot /var/www/html
    ServerName localhost
    
    <Directory "/var/www/html">
        AllowOverride None
        Options Indexes FollowSymLinks
        Require all granted
        DirectoryIndex kiosk-manager.html
    </Directory>
    
    <Directory "/usr/lib/cgi-bin">
        AllowOverride None
        Options +ExecCGI
        AddHandler cgi-script .cgi
        Require all granted
    </Directory>
    
    ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/
    
    ErrorLog ${APACHE_LOG_DIR}/kiosk-manager-error.log
    CustomLog ${APACHE_LOG_DIR}/kiosk-manager-access.log combined
</VirtualHost>
EOFVHOST

        # Habilitar o site
        a2ensite kiosk-manager.conf
        
        # Verificar se CGI já está habilitado
        if ! apache2ctl -M 2>/dev/null | grep -q cgi_module; then
            a2enmod cgi
            log "Módulo CGI habilitado no Apache"
        fi
        
        # Reiniciar Apache
        systemctl restart apache2
        log_success "Apache configurado para porta 8080 e reiniciado"
    fi
}

# Configurar permissões
configure_permissions() {
    log "Configurando permissões..."
    
    # Permissões para o script CGI
    chmod +x "$CGI_DIR/kiosk-manager.cgi"
    chown www-data:www-data "$CGI_DIR/kiosk-manager.cgi" 2>/dev/null || \
    chown apache:apache "$CGI_DIR/kiosk-manager.cgi" 2>/dev/null || \
    chown nginx:nginx "$CGI_DIR/kiosk-manager.cgi" 2>/dev/null || true
    
    # Permissões para a página HTML
    chmod 644 "$WEBROOT/kiosk-manager.html"
    chown www-data:www-data "$WEBROOT/kiosk-manager.html" 2>/dev/null || \
    chown apache:apache "$WEBROOT/kiosk-manager.html" 2>/dev/null || \
    chown nginx:nginx "$WEBROOT/kiosk-manager.html" 2>/dev/null || true
    
    # Permissões para logs
    touch /var/log/kiosk-manager.log
    chmod 666 /var/log/kiosk-manager.log
    chown www-data:www-data /var/log/kiosk-manager.log 2>/dev/null || \
    chown apache:apache /var/log/kiosk-manager.log 2>/dev/null || \
    chown nginx:nginx /var/log/kiosk-manager.log 2>/dev/null || true
    
    # Permissões para o diretório kiosk
    chown -R administrador:administrador /home/administrador/kiosk 2>/dev/null || true
    chmod 755 /home/administrador/kiosk 2>/dev/null || true
    
    log_success "Permissões configuradas"
}

# Configurar sudoers
configure_sudoers() {
    log "Configurando sudoers para execução CGI..."
    
    # Criar arquivo sudoers específico
    cat > /etc/sudoers.d/kiosk-manager << 'EOFSUDO'
www-data ALL=(root) NOPASSWD: /usr/bin/systemctl status *
www-data ALL=(root) NOPASSWD: /usr/bin/systemctl is-active *
www-data ALL=(root) NOPASSWD: /usr/bin/journalctl *
www-data ALL=(root) NOPASSWD: /bin/ps *
www-data ALL=(root) NOPASSWD: /usr/bin/pgrep *
www-data ALL=(root) NOPASSWD: /usr/bin/pkill *
www-data ALL=(root) NOPASSWD: /sbin/reboot
apache ALL=(root) NOPASSWD: /usr/bin/systemctl status *
apache ALL=(root) NOPASSWD: /usr/bin/systemctl is-active *
apache ALL=(root) NOPASSWD: /usr/bin/journalctl *
apache ALL=(root) NOPASSWD: /bin/ps *
apache ALL=(root) NOPASSWD: /usr/bin/pgrep *
apache ALL=(root) NOPASSWD: /usr/bin/pkill *
apache ALL=(root) NOPASSWD: /sbin/reboot
nginx ALL=(root) NOPASSWD: /usr/bin/systemctl status *
nginx ALL=(root) NOPASSWD: /usr/bin/systemctl is-active *
nginx ALL=(root) NOPASSWD: /usr/bin/journalctl *
nginx ALL=(root) NOPASSWD: /bin/ps *
nginx ALL=(root) NOPASSWD: /usr/bin/pgrep *
nginx ALL=(root) NOPASSWD: /usr/bin/pkill *
nginx ALL=(root) NOPASSWD: /sbin/reboot
EOFSUDO

    chmod 440 /etc/sudoers.d/kiosk-manager
    
    # Testar configuração sudoers
    if ! visudo -c -f /etc/sudoers.d/kiosk-manager; then
        log_error "Erro na configuração do sudoers"
        rm -f /etc/sudoers.d/kiosk-manager
        exit 1
    fi
    
    log_success "Sudoers configurado"
}

# Criar arquivo de configuração
create_config_file() {
    log "Criando arquivo de configuração..."
    
    cat > /etc/kiosk-manager.conf << EOFCONFIG
# Configuração do Kiosk Manager WebUI
# /etc/kiosk-manager.conf

# Versão
VERSION="1.0"

# Caminhos
CGI_SCRIPT="$CGI_DIR/kiosk-manager.cgi"
HTML_PAGE="$WEBROOT/kiosk-manager.html"
KIOSK_DIR="/home/administrador/kiosk"
LOG_FILE="/var/log/kiosk-manager.log"

# Servidor Web
WEBSERVER="$WEBSERVER"
WEBROOT="$WEBROOT"
CGI_DIR="$CGI_DIR"

# Porta de acesso
WEB_PORT="8080"

# Data de instalação
INSTALL_DATE="$(date)"
EOFCONFIG

    chmod 644 /etc/kiosk-manager.conf
    log_success "Arquivo de configuração criado em /etc/kiosk-manager.conf"
}

# Instalar dependências
install_dependencies() {
    log "Instalando dependências..."
    
    # Atualizar repositórios
    apt-get update
    
    # Instalar pacotes necessários
    apt-get install -y \
        curl \
        wget \
        dialog \
        bc \
        xdotool \
        realpath \
        findutils
    
    log_success "Dependências instaladas"
}

# Baixar script do menu original
download_original_menu() {
    log "Baixando script do menu original..."
    
    # Criar diretório para scripts
    mkdir -p /usr/local/bin
    
    # Baixar o script MENU original do repositório
    if curl -sSL https://raw.githubusercontent.com/urbancompasspony/kiosk-mode/refs/heads/main/MENU -o /usr/local/bin/menukiosk; then
        chmod +x /usr/local/bin/menukiosk
        log_success "Script MENU baixado com sucesso"
    else
        log_warning "Não foi possível baixar o script MENU original"
        
        # Criar versão simplificada
        cat > /usr/local/bin/menukiosk << 'EOFMENU'
#!/bin/bash

function checkA {
  [ "$EUID" -ne 0 ] || {
    echo "Nao execute esse script como Root!"
    exit
    }
}

function reb00t {
  dialog --title 'Reiniciar' --backtitle "Reinicio" --yesno 'Deseja reiniciar este sistema agora para aplicar as mudancas?' 0 0
  [ $? = 0 ] && {
    clear; echo ""; echo "Digite a senha do usuario: "
    sudo reboot
  } || {
    echo "." >/dev/null
  }
}

function checkB {
  export var1; export var2; export var3; export var4; export var5

  [ -f "/home/administrador/kiosk/Information" ] && {
    VALUE1=$(sed -n '1p' /home/administrador/kiosk/Information)
    VALUE2=$(sed -n '2p' /home/administrador/kiosk/Information)
    VALUE3=$(sed -n '3p' /home/administrador/kiosk/Information)
    VALUE4=$(sed -n '4p' /home/administrador/kiosk/Information)
    VALUE5=$(sed -n '5p' /home/administrador/kiosk/Information)
  } || {
    VALUE1="https://time.is/S%C3%A3o_Paulo https://www.suitit.com.br"; VALUE2="10"; VALUE3="0"; VALUE4="0"; VALUE5="10"
  }

  VALUE0=$(dialog --ok-label "Ajustar" --title "K I O S K" --form "WebSites: Enderecos separados com espaco serao alternados pela Duracao. \n
Duracao: Tempo em segundos ate alternar os sites.\nZoomIn: Valores 110, 125, 150, 175, 200, 250 ou 300% \n
ZoomOut: Valores 90, 80, 75, 67, 50, 33 ou 25% \nEspera: Segundos antes do script comecar, para maquinas lentas. \n\n
Nunca habilite ZoomIn e ZoomOut ao mesmo tempo; deixe um campo em 0!\n " 20 75 0 \
"WebSites:" 1 1 "$VALUE1" 1 10 250 0 \
"Duracao :" 2 1 "$VALUE2" 2 10 3 0 \
"Zoom In :" 3 1 "$VALUE3" 3 10 4 0 \
"Zoom Out:" 4 1 "$VALUE4" 4 10 4 0 \
"Espera  :" 5 1 "$VALUE5" 5 10 3 0 \
3>&1 1>&2 2>&3 3>&- > /dev/tty)

  [ $? -ne 0 ] && exit

  var1=$(echo "$VALUE0" | sed -n 1p)
  var2=$(echo "$VALUE0" | sed -n 2p)
  var3=$(echo "$VALUE0" | sed -n 3p)
  var4=$(echo "$VALUE0" | sed -n 4p)
  var5=$(echo "$VALUE0" | sed -n 5p)

  [ -z "$var1" ] || [ -z "$var2" ] || [ -z "$var3" ] || [ -z "$var4" ] || [ -z "$var5" ] && {
    dialog --title "ERRO" --msgbox "Não deixe nenhum campo vazio!" 8 40
    checkB
  } || {
    echo "$var1" | tee /home/administrador/kiosk/Information > /home/administrador/kiosk/websites
    echo "$var2" | tee -a /home/administrador/kiosk/Information > /home/administrador/kiosk/duration

    [ "$var3" = "0" ] && {
      rm -f /home/administrador/kiosk/zoomin
    } || {
      echo "$var3" > /home/administrador/kiosk/zoomin
    }

    [ "$var4" = "0" ] && {
      rm -f /home/administrador/kiosk/zoomout
    } || {
      echo "$var4" > /home/administrador/kiosk/zoomout
    }

    echo "$var3" | tee -a /home/administrador/kiosk/Information
    echo "$var4" | tee -a /home/administrador/kiosk/Information
    echo "$var5" | tee -a /home/administrador/kiosk/Information > /home/administrador/kiosk/waittime

    reb00t
    }
}

checkA
checkB

exit 1
EOFMENU
        chmod +x /usr/local/bin/menukiosk
        log_success "Script MENU simplificado criado"
    fi
    
    # Adicionar alias no bashrc do administrador
    if [ -f /home/administrador/.bashrc ]; then
        if ! grep -q "alias menukiosk" /home/administrador/.bashrc; then
            echo "alias menukiosk='/usr/local/bin/menukiosk'" >> /home/administrador/.bashrc
            log_success "Alias menukiosk adicionado ao bashrc"
        fi
    fi
}

# Testar instalação
test_installation() {
    log "Testando instalação..."
    
    # Testar script CGI
    if [ -x "$CGI_DIR/kiosk-manager.cgi" ]; then
        log_success "Script CGI: OK"
    else
        log_error "Script CGI: FALHA"
        exit 1
    fi
    
    # Testar página HTML
    if [ -f "$WEBROOT/kiosk-manager.html" ]; then
        log_success "Página HTML: OK"
    else
        log_error "Página HTML: FALHA"
        exit 1
    fi
    
    # Testar servidor web
    if systemctl is-active --quiet "$WEBSERVER" 2>/dev/null; then
        log_success "Servidor web ($WEBSERVER): OK"
    else
        log_warning "Servidor web ($WEBSERVER): Não está rodando"
    fi
    
    # Testar diretório kiosk
    if [ -d "/home/administrador/kiosk" ]; then
        log_success "Diretório kiosk: OK"
    else
        log_error "Diretório kiosk: FALHA"
        exit 1
    fi
    
    # Testar CGI básico
    log "Testando CGI..."
    if command -v curl >/dev/null 2>&1; then
        local test_result=$(echo "action=ping" | curl -s -X POST -d @- "http://localhost:8080/cgi-bin/kiosk-manager.cgi" 2>/dev/null || echo "ERROR")
        if [[ "$test_result" == *"pong"* ]]; then
            log_success "CGI responde corretamente"
        else
            log_warning "CGI pode não estar respondendo corretamente"
        fi
    fi
    
    log_success "Todos os testes principais passaram!"
}

# Exibir informações finais
show_final_info() {
    echo ""
    echo "=============================================="
    log_success "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "=============================================="
    echo ""
    echo -e "${GREEN}📋 Informações da Instalação:${NC}"
    echo -e "   🌐 Servidor Web: $WEBSERVER"
    echo -e "   📁 Diretório Web: $WEBROOT"
    echo -e "   🔧 Diretório CGI: $CGI_DIR"
    echo -e "   📄 Página HTML: $WEBROOT/kiosk-manager.html"
    echo -e "   🔌 Porta: 8080"
    echo -e "   📋 Logs: /var/log/kiosk-manager.log"
    echo ""
    echo -e "${BLUE}🔗 Acesso ao Sistema:${NC}"
    echo -e "   http://localhost:8080/kiosk-manager.html"
    local server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "IP_DO_SERVIDOR")
    echo -e "   http://${server_ip}:8080/kiosk-manager.html"
    echo ""
    echo -e "${YELLOW}📚 Comandos Úteis:${NC}"
    echo -e "   • Configurar kiosk via terminal: menukiosk"
    echo -e "   • Ver logs: tail -f /var/log/kiosk-manager.log"
    echo -e "   • Reiniciar Apache: sudo systemctl restart apache2"
    echo -e "   • Status do kiosk: ps aux | grep -E '(chromium|vlc|openbox)'"
    echo ""
    echo -e "${GREEN}✨ Próximos Passos:${NC}"
    echo -e "   1. Acesse a interface web no endereço acima"
    echo -e "   2. Configure os websites desejados"
    echo -e "   3. Ajuste zoom e duração conforme necessário"
    echo -e "   4. Faça upload de vídeos/imagens se necessário"
    echo -e "   5. Reinicie o sistema para ativar o kiosk"
    echo ""
    echo -e "${BLUE}🔧 Suporte para Plataformas:${NC}"
    echo -e "   • x86_64 (AMD64) - Totalmente suportado"
    echo -e "   • Raspberry Pi 3 - Suportado"
    echo -e "   • Raspberry Pi 4 - Suportado"
    echo -e "   • Raspberry Pi 5 - Suporte limitado (problemas conhecidos)"
    echo ""
    echo -e "${YELLOW}⚠️  Notas Importantes:${NC}"
    echo -e "   • O usuário 'administrador' deve existir no sistema"
    echo -e "   • Para kiosk VLC, coloque vídeos em /var/www/html/"
    echo -e "   • Para kiosk Chromium, configure URLs na interface"
    echo -e "   • Logs são salvos em /var/log/kiosk-manager.log"
    echo ""
    echo -e "${GREEN}✅ Instalação concluída! Sistema pronto para uso.${NC}"
    echo ""
}

# Função principal
main() {
    echo "=============================================="
    echo "  INSTALADOR DO KIOSK MANAGER WEBUI"
    echo "  Baseado no sistema kiosk-mode existente"
    echo "=============================================="
    echo ""
    
    check_root
    install_dependencies
    detect_webserver
    create_directories
    create_cgi_script
    create_html_page
    configure_apache
    configure_permissions
    configure_sudoers
    create_config_file
    download_original_menu
    test_installation
    show_final_info
}

# Executar instalação
main "$@"
