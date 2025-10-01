#!/bin/bash
set -e

# --- CONFIGURAÇÃO ---
REPO="DuowardTecnologiaEInovacao/grafana"
INSTALL_DIR="/opt/sentinel-ark-grafana"
# --------------------

# Cores
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Início do Script
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}🚀 Iniciando Instalação do Sentinel Ark 🚀${NC}"
echo -e "${GREEN}=====================================================${NC}"

# --- PASSO 1: INSTALAR DEPENDÊNCIAS ESSENCIAIS ---
echo -e "\n${YELLOW}>>> Instalando dependências (curl, wget, postgresql)...${NC}"
sudo apt-get update -qq
sudo apt-get install -y wget ca-certificates curl postgresql

# --- PASSO 2: CONFIGURAR SENHA DO BANCO DE DADOS ---
echo -e "\n${YELLOW}>>> Configurando o Banco de Dados PostgreSQL...${NC}"
DB_NAME="grafana"
DB_USER="grafana"
while true; do
    read -sp "Crie uma senha para o novo usuário do banco de dados ('$DB_USER'): " DB_PASSWORD
    echo ""
    read -sp "Confirme a senha: " DB_PASSWORD_CONFIRM
    echo ""
    if [ "$DB_PASSWORD" == "$DB_PASSWORD_CONFIRM" ] && [ -n "$DB_PASSWORD" ]; then
        break
    else
        echo -e "${RED}As senhas não conferem ou estão vazias. Tente novamente.${NC}"
    fi
done

# --- PASSO 3: PREPARAR O POSTGRESQL ---
echo -e "\n${YELLOW}>>> Preparando o banco de dados e usuário...${NC}"
PG_HBA_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')
if sudo grep -q "local.*all.*all.*peer" "$PG_HBA_CONF"; then
    sudo sed -i -E 's/^(local\s+all\s+all\s+)peer$/\1md5/' "$PG_HBA_CONF"
    sudo systemctl restart postgresql
fi
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};"
sudo -u postgres psql -c "DROP USER IF EXISTS ${DB_USER};"
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};"

# --- PASSO 4: INSTALAR O SEU GRAFANA CUSTOMIZADO ---
echo -e "\n${YELLOW}>>> Baixando e instalando a última release do Sentinel Ark...${NC}"
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep "browser_download_url" | grep ".tar.gz" | head -n 1 | cut -d '"' -f 4)
if [ -z "$DOWNLOAD_URL" ]; then error "Não foi possível encontrar a URL de download da última release!"; fi
wget -q -O /tmp/grafana-custom.tar.gz "$DOWNLOAD_URL"
sudo rm -rf "$INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo tar -xzf /tmp/grafana-custom.tar.gz -C "$INSTALL_DIR" --strip-components=1
rm /tmp/grafana-custom.tar.gz

# --- PASSO 5: CRIAR O custom.ini E AJUSTAR PERMISSÕES ---
echo -e "\n${YELLOW}>>> Configurando a conexão com o banco de dados...${NC}"
CONFIG_FILE="$INSTALL_DIR/conf/custom.ini"
sudo tee "$CONFIG_FILE" > /dev/null <<EOL
[database]
type = postgres
host = 127.0.0.1:5432
name = ${DB_NAME}
user = ${DB_USER}
password = ${DB_PASSWORD}
ssl_mode = disable
EOL
(id 'grafana' &>/dev/null || sudo useradd -rs /bin/false grafana)
sudo chown -R grafana:grafana "$INSTALL_DIR"

# --- PASSO 6: CRIAR E INICIAR O SERVIÇO ---
echo -e "\n${YELLOW}>>> Criando e iniciando o serviço 'sentinel-ark.service'...${NC}"
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
echo ""
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}✅ Instalação concluída com sucesso! ✅${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo "O usuário '${DB_USER}' do banco foi criado com a senha que você digitou."
echo "Para verificar o status, use: ${YELLOW}sudo systemctl status sentinel-ark.service${NC}"
echo "Acesse seu Grafana em: http://$(hostname -I | awk '{print $1'}):3000"