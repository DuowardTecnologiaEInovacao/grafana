#!/bin/bash
# Script de Instalação Otimizado para Sentinel Ark Grafana (Uso via Web)

# CONFIGURAÇÃO
# -----------------------------------------------------------------------------
set -euo pipefail # Para o script em qualquer erro (mais seguro)
REPO="DuowardTecnologiaEInovacao/grafana"
INSTALL_DIR="/opt/sentinel-ark-grafana"
DB_NAME="grafana"
DB_USER="grafana"
LOG_FILE="/var/log/sentinel-ark-install-$(date +%F).log"

# CORES E FUNÇÕES DE LOG
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# FUNÇÃO DE LIMPEZA EM CASO DE ERRO (ROLLBACK)
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "A instalação falhou (código de saída: $exit_code). Revertendo alterações..."
        sudo systemctl stop sentinel-ark.service 2>/dev/null || true
        sudo systemctl disable sentinel-ark.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/sentinel-ark.service 2>/dev/null || true
        sudo rm -rf "$INSTALL_DIR" 2>/dev/null || true
        warn "Rollback concluído."
    fi
}
trap cleanup EXIT

# INÍCIO DO SCRIPT
# -----------------------------------------------------------------------------
exec > >(tee -a "$LOG_FILE") 2>&1

log "====================================================="
log "🚀 Iniciando Instalação Otimizada do Sentinel Ark 🚀"
log "====================================================="

# --- VERIFICAÇÕES INICIAIS ---
log "Passo 1/7: Verificações iniciais..."
if [ "$EUID" -ne 0 ]; then error "Este script precisa ser executado com sudo."; fi

# --- DEPENDÊNCIAS ---
log "Passo 2/7: Instalando dependências (postgresql, etc.)..."
sudo apt-get update -qq
sudo apt-get install -y wget ca-certificates curl postgresql openssl

# --- CONFIGURAÇÃO DO POSTGRESQL ---
log "Passo 3/7: Configurando o PostgreSQL..."
PG_HBA_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')
if sudo grep -q "local.*all.*all.*peer" "$PG_HBA_CONF"; then
    log "  - Corrigindo método de autenticação para 'md5'..."
    sudo sed -i -E 's/^(local\s+all\s+all\s+)peer$/\1md5/' "$PG_HBA_CONF"
    sudo systemctl restart postgresql
else
    log "  - Método de autenticação já está correto."
fi

# --- PREPARAÇÃO DO BANCO DE DADOS ---
log "Passo 4/7: Preparando o banco de dados..."
DB_PASSWORD=$(openssl rand -base64 16)
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};"
sudo -u postgres psql -c "DROP USER IF EXISTS ${DB_USER};"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};"

# --- INSTALAÇÃO DO GRAFANA (VIA GITHUB RELEASE) ---
log "Passo 5/7: Baixando e instalando a última release do Sentinel Ark do GitHub..."
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep "browser_download_url" | grep ".tar.gz" | head -n 1 | cut -d '"' -f 4)
if [ -z "$DOWNLOAD_URL" ]; then error "Não foi possível encontrar a URL de download da última release!"; fi

log "  - URL: $DOWNLOAD_URL"
wget -q -O /tmp/grafana-custom.tar.gz "$DOWNLOAD_URL"
sudo rm -rf "$INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo tar -xzf /tmp/grafana-custom.tar.gz -C "$INSTALL_DIR" --strip-components=1
rm /tmp/grafana-custom.tar.gz

# --- CONFIGURAÇÃO DO GRAFANA ---
log "Passo 6/7: Configurando a conexão com o banco de dados..."
# Este script assume que o pacote .tar.gz contém o arquivo 'conf/custom.ini.template'
TEMPLATE_FILE="$INSTALL_DIR/conf/custom.ini.template"
CONFIG_FILE="$INSTALL_DIR/conf/custom.ini"
PASSWORD_FILE="$INSTALL_DIR/conf/.pgpass"
if [ ! -f "$TEMPLATE_FILE" ]; then error "Arquivo 'conf/custom.ini.template' não encontrado no pacote de instalação!"; fi

sudo sed -e "s/%%DB_NAME%%/$DB_NAME/" \
    -e "s/%%DB_USER%%/$DB_USER/" \
    -e "s/%%DB_PASSWORD%%/$DB_PASSWORD/" \
    "$TEMPLATE_FILE" | sudo tee "$CONFIG_FILE" > /dev/null
echo "$DB_PASSWORD" | sudo tee "$PASSWORD_FILE" > /dev/null
sudo chmod 600 "$PASSWORD_FILE" "$CONFIG_FILE"
(id 'grafana' &>/dev/null || sudo useradd -rs /bin/false grafana)
sudo chown -R grafana:grafana "$INSTALL_DIR"

# --- CRIAÇÃO DO SERVIÇO SYSTEMD ---
log "Passo 7/7: Criando e habilitando o serviço 'sentinel-ark.service'..."
cat <<EOF | sudo tee /etc/systemd/system/sentinel-ark.service
[Unit]
Description=Sentinel Ark Grafana Service
Wants=network-online.target postgresql.service
After=network-online.target postgresql.service
[Service]
User=grafana
Group=grafana
Type=simple
ExecStart=$INSTALL_DIR/bin/grafana server --homepath $INSTALL_DIR
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable sentinel-ark.service
sudo systemctl start sentinel-ark.service

# --- FINALIZAÇÃO ---
log "======================================================="
log "✅ Instalação concluída com sucesso! ✅"
log "======================================================="
log "A senha para o usuário '${DB_USER}' do banco foi salva em: ${YELLOW}${PASSWORD_FILE}${NC}"
log "Para verificar o status do serviço, use: ${YELLOW}sudo systemctl status sentinel-ark.service${NC}"
log "Acesse seu Grafana em: http://$(hostname -I | awk '{print $1'}):3000"