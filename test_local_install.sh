#!/bin/bash
# Aborta o script imediatamente se qualquer comando falhar
set -e

# --- CONFIGURAÇÃO ---
PACKAGE_PATH="dist/sentinel-ark-grafana-v1.2.tar.gz"
TEST_INSTALL_DIR="/tmp/grafana-local-test"
DB_NAME="grafana_test"
DB_USER="grafana_test"
# --------------------

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}--- Iniciando Teste de Instalação Local (Versão Profissional) ---${NC}"

# --- PASSO 1: DEPENDÊNCIAS ---
echo -e "\n${YELLOW}>>> Verificando dependências...${NC}"
sudo apt-get update -qq
if ! command -v psql &> /dev/null; then
    echo "PostgreSQL não encontrado. Instalando..."
    sudo apt-get install -y postgresql
else
    echo "PostgreSQL já está instalado."
fi

# --- PASSO 2: VERIFICAÇÃO E LIMPEZA DO BANCO DE DADOS ---
DB_EXISTS=$(sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME" && echo "true" || echo "false")
USER_EXISTS=$(sudo -u postgres psql -c '\du' | cut -d \| -f 1 | grep -qw "$DB_USER" && echo "true" || echo "false")

if [ "$DB_EXISTS" = "true" ] || [ "$USER_EXISTS" = "true" ]; then
    echo -e "\n${RED}AVISO: O banco de dados '$DB_NAME' e/ou o usuário '$DB_USER' já existem.${NC}"
    read -p "Você deseja apagá-los e recriá-los do zero? (s/n): " CONFIRM
    if [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]]; then
        echo "Removendo banco de dados e usuário antigos..."
        sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"
        sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;"
    else
        echo "Instalação cancelada pelo usuário."
        exit 1
    fi
fi

# --- PASSO 3: CORREÇÃO AUTOMÁTICA DO POSTGRESQL (pg_hba.conf) ---
echo -e "\n${YELLOW}>>> Verificando e corrigindo a configuração de autenticação do PostgreSQL...${NC}"
PG_HBA_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')

# Verifica se a configuração já está correta (md5), se não, corrige
if sudo grep -q "local.*all.*all.*peer" "$PG_HBA_CONF"; then
    echo "Alterando método de autenticação de 'peer' para 'md5'..."
    sudo sed -i 's/local.*all.*all.*peer/local   all             all                                     md5/g' "$PG_HBA_CONF"
    sudo systemctl restart postgresql
    echo "Serviço do PostgreSQL reiniciado."
else
    echo "Método de autenticação já está correto."
fi

# --- PASSO 4: CRIAR BANCO DE DADOS, USUÁRIO E SENHA ---
echo -e "\n${YELLOW}>>> Configurando novo banco de dados e usuário...${NC}"
DB_PASSWORD=$(openssl rand -base64 12)

sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;"

# --- PASSO 5: INSTALAR O GRAFANA ---
echo -e "\n${YELLOW}>>> Instalando Grafana do pacote local...${NC}"
sudo rm -rf "$TEST_INSTALL_DIR"
sudo mkdir -p "$TEST_INSTALL_DIR"
sudo tar -xzf "$PACKAGE_PATH" -C "$TEST_INSTALL_DIR" --strip-components=1

# --- PASSO 6: CONFIGURAR O GRAFANA ---
echo -e "\n${YELLOW}>>> Configurando a conexão com o banco de dados...${NC}"
CONFIG_FILE="$TEST_INSTALL_DIR/conf/custom.ini"
PASSWORD_FILE="$TEST_INSTALL_DIR/conf/.pgpass"

sudo tee "$CONFIG_FILE" > /dev/null <<EOL
[database]
type = postgres
host = 127.0.0.1:5432
name = ${DB_NAME}
user = ${DB_USER}
password = ${DB_PASSWORD}
ssl_mode = disable
EOL

echo "$DB_PASSWORD" | sudo tee "$PASSWORD_FILE" > /dev/null
sudo chmod 640 "$PASSWORD_FILE"
if ! id "grafana" &>/dev/null; then sudo useradd -rs /bin/false grafana; fi
sudo chown -R grafana:grafana "$TEST_INSTALL_DIR"

# --- FINALIZAÇÃO ---
echo ""
echo -e "${GREEN}✅ Ambiente de teste local criado com sucesso!${NC}"
echo "A senha para o usuário '${DB_USER}' do banco de teste é: ${YELLOW}${DB_PASSWORD}${NC}"
echo -e "Ela também foi salva em: ${YELLOW}${PASSWORD_FILE}${NC}"
echo ""
echo "Para iniciar o servidor de teste, execute:"
echo -e "${GREEN}sudo $TEST_INSTALL_DIR/bin/grafana server --homepath $TEST_INSTALL_DIR${NC}"