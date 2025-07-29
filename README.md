# Kiosk Manager WebUI

Uma interface web moderna e intuitiva para gerenciar o sistema Kiosk Mode, baseada no repositório [kiosk-mode](https://github.com/urbancompasspony/kiosk-mode) existente.

## 🚀 Características

- **Interface Web Responsiva**: Design moderno baseado no sistema de diagnóstico funcionando
- **Configuração Completa**: Todos os parâmetros do dialog original em interface web
- **Suporte Multi-Plataforma**: x86_64, Raspberry Pi 3, 4 e 5
- **Gerenciamento de Arquivos**: Upload e gerenciamento de vídeos/imagens
- **Monitoramento em Tempo Real**: Status do kiosk e informações do sistema
- **Integração Total**: Compatível com scripts originais existentes

## 📋 Pré-requisitos

- Sistema Linux (Ubuntu, Debian, etc.)
- Usuário `administrador` no sistema
- Servidor web (Apache, Nginx ou Lighttpd)
- Sudo/root para instalação
- Sistema kiosk-mode básico já configurado

## 🔧 Instalação Rápida

### 1. Download e Execução do Instalador

```bash
# Baixar o script de instalação
curl -O https://raw.githubusercontent.com/seu-usuario/kiosk-manager/main/install-kiosk-manager.sh

# Dar permissão de execução
chmod +x install-kiosk-manager.sh

# Executar como root
sudo ./install-kiosk-manager.sh
```

### 2. Acesso ao Sistema

Após a instalação, acesse:
- **Local**: http://localhost:8080/kiosk-manager.html
- **Rede**: http://IP_DO_HOST:8080/kiosk-manager.html

## 🖥️ Interface Web

### Menu Principal

A interface oferece as seguintes funcionalidades:

#### 1. **Configurar Kiosk** ⚙️
- Configuração de websites (URLs separadas por espaço)
- Duração entre alternância de sites
- Configuração de zoom (In/Out)
- Tempo de espera antes do início
- Validação automática de configurações

#### 2. **Reiniciar Sistema** 🔄
- Reinicialização segura do sistema
- Aplicação automática das mudanças
- Confirmação de segurança

#### 3. **Gerenciar Arquivos** 📁
- Upload de vídeos (MP4, AVI, MKV, MOV)
- Upload de imagens (JPG, PNG, GIF)
- Upload de arquivos de texto e HTML
- Visualização da lista de arquivos
- Exclusão segura de arquivos

#### 4. **Informações do Sistema** 📊
- Hardware (CPU, memória, armazenamento)
- Sistema operacional
- Status dos serviços
- Informações de display
- Status do kiosk em tempo real

#### 5. **Logs do Sistema** 📋
- Logs do Kiosk Manager
- Logs do sistema Linux
- Processos ativos do kiosk
- Histórico de ações

#### 6. **Parar Kiosk** ⏹️
- Parada segura do kiosk
- Modo manutenção
- Liberação de recursos

### Seletor de Plataforma

A interface permite selecionar entre diferentes plataformas:
- **x86_64 (AMD64)**: Sistemas desktop/laptop
- **Raspberry Pi 3**: Hardware específico RPi 3
- **Raspberry Pi 4**: Hardware específico RPi 4  
- **Raspberry Pi 5**: Hardware específico RPi 5 (suporte limitado)

## 🔧 Configuração Detalhada

### Parâmetros de Configuração

#### Websites
- **Campo**: URLs separadas por espaço
- **Exemplo**: `https://google.com https://time.is/São_Paulo`
- **Validação**: Pelo menos uma URL deve ser fornecida

#### Duração
- **Campo**: Tempo em segundos
- **Faixa**: 1-3600 segundos
- **Padrão**: 10 segundos
- **Descrição**: Tempo para alternar entre sites

#### Zoom
- **Tipos**: Zoom In, Zoom Out ou Nenhum
- **Zoom In**: 110%, 125%, 150%, 175%, 200%, 250%, 300%
- **Zoom Out**: 90%, 80%, 75%, 67%, 50%, 33%, 25%
- **Restrição**: Nunca usar In e Out simultaneamente

#### Tempo de Espera
- **Campo**: Segundos antes do início
- **Faixa**: 0-60 segundos
- **Padrão**: 10 segundos
- **Uso**: Máquinas lentas ou inicialização customizada

### Arquivos de Configuração

O sistema salva configurações em:
- `/home/administrador/kiosk/websites` - URLs configuradas
- `/home/administrador/kiosk/duration` - Duração da alternância
- `/home/administrador/kiosk/zoomin` - Configuração zoom in
- `/home/administrador/kiosk/zoomout` - Configuração zoom out
- `/home/administrador/kiosk/waittime` - Tempo de espera
- `/home/administrador/kiosk/Information` - Arquivo de compatibilidade

## 📱 Compatibilidade

### Navegadores Suportados
- Chrome/Chromium 60+
- Firefox 55+
- Safari 12+
- Edge 79+

### Sistemas Operacionais Testados
- Ubuntu 18.04, 20.04, 22.04, 24.04
- Debian 9, 10, 11, 12
- Raspberry Pi OS (Bullseye, Bookworm)

### Servidores Web
- Apache 2.4+ (configuração automática)
- Nginx 1.14+ (configuração manual necessária)
- Lighttpd 1.4+ (configuração manual necessária)

## 🛠️ Administração

### Comandos Úteis

```bash
# Configurar kiosk via terminal (método original)
menukiosk

# Ver logs em tempo real
tail -f /var/log/kiosk-manager.log

# Verificar status do Apache
sudo systemctl status apache2

# Reiniciar Apache
sudo systemctl restart apache2

# Verificar processos do kiosk
ps aux | grep -E "(chromium|vlc|openbox)"

# Parar kiosk manualmente
sudo pkill -f "chromium.*--kiosk"
sudo pkill -f "vlc.*fullscreen"

# Verificar configuração atual
cat /home/administrador/kiosk/Information
```

### Logs do Sistema

**Localização**: `/var/log/kiosk-manager.log`

**Conteúdo típico**:
```
[2024-01-15 10:30:15] === Nova requisição CGI ===
[2024-01-15 10:30:15] ACTION: get-config
[2024-01-15 10:30:15] PLATFORM: x86_64
[2024-01-15 10:30:15] SUCCESS: Configuração carregada
```

### Estrutura de Arquivos

```
/
├── usr/lib/cgi-bin/
│   └── kiosk-manager.cgi           # Script CGI principal
├── var/www/html/
│   ├── kiosk-manager.html          # Interface web
│   ├── *.mp4, *.jpg, *.png         # Arquivos de mídia
│   └── *.txt, *.html               # Outros arquivos
├── home/administrador/kiosk/
│   ├── Information                 # Compatibilidade com script original
│   ├── websites                    # URLs configuradas
│   ├── duration                    # Duração
│   ├── zoomin                      # Zoom in (opcional)
│   ├── zoomout                     # Zoom out (opcional)
│   └── waittime                    # Tempo de espera
├── etc/
│   ├── kiosk-manager.conf          # Configuração principal
│   └── sudoers.d/kiosk-manager     # Permissões sudo
└── var/log/
    └── kiosk-manager.log           # Logs do sistema
```

## 🐛 Solução de Problemas

### Erro 500 - Internal Server Error

**Possíveis causas:**
1. Permissões incorretas no script CGI
2. Módulo CGI não habilitado no Apache
3. Erro de sintaxe no script CGI

**Soluções:**
```bash
# Verificar permissões
ls -la /usr/lib/cgi-bin/kiosk-manager.cgi

# Corrigir permissões
sudo chmod +x /usr/lib/cgi-bin/kiosk-manager.cgi
sudo chown www-data:www-data /usr/lib/cgi-bin/kiosk-manager.cgi

# Habilitar CGI no Apache
sudo a2enmod cgi
sudo systemctl restart apache2

# Verificar logs de erro
sudo tail -f /var/log/apache2/error.log
```

### Interface Não Carrega

**Verificações:**
```bash
# Verificar se arquivo existe
ls -la /var/www/html/kiosk-manager.html

# Verificar servidor web
sudo systemctl status apache2

# Testar acesso local
curl -I http://localhost:8080/kiosk-manager.html
```

### Configuração Não Salva

**Verificações:**
```bash
# Verificar permissões do diretório kiosk
ls -la /home/administrador/kiosk/

# Criar diretório se não existir
sudo mkdir -p /home/administrador/kiosk
sudo chown administrador:administrador /home/administrador/kiosk

# Verificar logs
tail -f /var/log/kiosk-manager.log
```

### Kiosk Não Inicia Após Configuração

**Verificações:**
```bash
# Verificar se usuário administrador existe
id administrador

# Verificar arquivos de configuração
cat /home/administrador/kiosk/websites
cat /home/administrador/kiosk/duration

# Verificar se X11 está disponível (para GUI)
echo $DISPLAY
```

## 🔒 Segurança

### Controle de Acesso

**Restringir acesso por IP (Apache):**
```apache
<Directory "/var/www/html">
    <RequireAll>
        Require ip 192.168.1.0/24
        Require ip 10.0.0.0/8
        Require ip 127.0.0.1
    </RequireAll>
</Directory>
```

**Autenticação básica:**
```bash
# Criar arquivo de senhas
sudo htpasswd -c /etc/apache2/.htpasswd admin

# Adicionar ao VirtualHost
<Directory "/var/www/html">
    AuthType Basic
    AuthName "Kiosk Manager"
    AuthUserFile /etc/apache2/.htpasswd
    Require valid-user
</Directory>
```

### HTTPS

**Certificado SSL com Let's Encrypt:**
```bash
# Instalar certbot
sudo apt install certbot python3-certbot-apache

# Obter certificado
sudo certbot --apache -d seu-dominio.com

# Configurar renovação automática
sudo crontab -e
# Adicionar: 0 12 * * * /usr/bin/certbot renew --quiet
```

## 🔄 Integração com Sistema Existente

### Compatibilidade com Scripts Originais

O Kiosk Manager WebUI é **100% compatível** com o sistema kiosk-mode existente:

- Usa os mesmos arquivos de configuração
- Preserva o comando `menukiosk` original
- Mantém estrutura de diretórios
- Funciona com scripts de inicialização existentes

### Migração de Sistema Existente

Se você já tem o kiosk-mode funcionando:

1. **Instale o WebUI** sem medo - não quebra nada existente
2. **Mantenha o método original** como backup
3. **Use ambos conforme necessário** - são complementares
4. **Migre gradualmente** para a interface web

### Comando Original Disponível

O comando original continua funcionando:
```bash
# Método original (dialog em terminal)
menukiosk

# Novo método (interface web)
# http://localhost:8080/kiosk-manager.html
```

## 📈 Performance e Monitoramento

### Monitoramento do Sistema

A interface web oferece:
- Status em tempo real do kiosk
- Informações de hardware
- Uso de CPU e memória
- Status dos serviços críticos
- Logs centralizados

### Otimizações

**Para melhor performance:**
- Use URLs locais quando possível
- Configure duração adequada (não muito baixa)
- Monitore uso de memória em sistemas embarcados
- Faça limpeza periódica de logs

## 📜 Licença

Este projeto é baseado no repositório [kiosk-mode](https://github.com/urbancompasspony/kiosk-mode) original e mantém a mesma licença.

---

**Kiosk Manager WebUI** - Uma evolução natural do sistema kiosk-mode com interface web moderna! 🚀
