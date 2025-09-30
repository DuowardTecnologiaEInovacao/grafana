[#!/bin/bash
# Aborta o script imediatamente se qualquer comando falhar
set -e

# --- CONFIGURAÇÃO ---
REPO="DuowardTecnologiaEInovacao/grafana"
INSTALL_DIR="/opt/sentinel-ark-grafana"
# --------------------

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Função para executar e verificar cada passo com feedback visual
run_step() {
    echo -e "\n${YELLOW}>>> $1...${NC}"
    shift
    # CORREÇÃO: Removido o 'eval' para evitar problemas com expansão de variáveis
    if "$@"; then
        echo -e "${GREEN}✅ Sucesso!${NC}"
    else
        echo -e "${RED}❌ ERRO no passo anterior. Abortando.${NC}"
        exit 1
    fi
}

# Função separada e mais segura para configurar o banco de dados
setup_database() {
    echo "  - Verificando se o banco de dados '$DB_NAME' já existe..."
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "  - ${RED}AVISO: O banco de dados '$DB_NAME' já existe.${NC}"
        read -p "  - Deseja apagá-lo e recriá-lo do zero? (s/n): " CONFIRM
        if [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]]; then
            sudo -u postgres psql -c "DROP DATABASE $DB_NAME;"
        else
            echo "Instalação cancelada."
            exit 1
        fi
    fi

    echo "  - Verificando se o usuário '$DB_USER' já existe..."
    if sudo -u postgres psql -c '\du' | cut -d \| -f 1 | grep -qw "$DB_USER"; then
       echo -e "  - ${RED}AVISO: O usuário '$DB_USER' já existe. Ele será removido.${NC}"
       sudo -u postgres psql -c "DROP USER $DB_USER;"
    fi

    echo "  - Criando banco de dados, usuário e concedendo privilégios..."
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
    sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO $DB_USER;"
}


echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}🚀 Iniciando Instalação Profissional do Sentinel Ark 🚀${NC}"
echo -e "${GREEN}=====================================================${NC}"

# --- PASSO 1: DEPENDÊNCIAS ---
run_step "Passo 1/6: Verificando e instalando dependências do sistema" \
"sudo apt-get update -qq && sudo apt-get install -y wget ca-certificates curl postgresql openssl"

# --- PASSO 2: CONFIGURAÇÃO INTERATIVA DO BANCO DE DADOS ---
echo -e "\n${YELLOW}>>> Passo 2/6: Configuração do Banco de Dados PostgreSQL...${NC}"
read -p "Digite o nome para o banco de dados [padrão: grafana]: " DB_NAME
DB_NAME=${DB_NAME:-grafana}

read -p "Digite o nome para o usuário do banco de dados [padrão: grafana]: " DB_USER
DB_USER=${DB_USER:-grafana}

# --- PASSO 3: CORREÇÃO E CONFIGURAÇÃO DO POSTGRESQL ---
PG_HBA_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')
if sudo grep -q "local.*all.*all.*peer" "$PG_HBA_CONF"; then
    run_step "Passo 3/6: Corrigindo autenticação do PostgreSQL (peer -> md5)" \
    "sudo sed -i 's/local   all             all                                     peer/local   all             all                                     md5/g' '$PG_HBA_CONF' && sudo systemctl restart postgresql"
else
    echo -e "\n${GREEN}>>> Passo 3/6: Verificação de autenticação do PostgreSQL... ✅ Sucesso! (Já está correto).${NC}"
fi

DB_PASSWORD=$(openssl rand -base64 12)
# A chamada agora é para a função 'setup_database', que é mais segura
run_step "Passo 4/6: Preparando o banco de dados" "setup_database"

# --- PASSO 5: INSTALAR O GRAFANA ---
# Usamos a função run_step para o curl também
run_step "Passo 5/6a: Buscando a URL da última release" \
'DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep "browser_download_url" | grep ".tar.gz" | head -n 1 | cut -d '"'"'"' -f 4)'

run_step "Passo 5/6b: Baixando e instalando o Sentinel Ark" \
"wget -q -O /tmp/grafana-custom.tar.gz '$DOWNLOAD_URL' && \
 sudo rm -rf '$INSTALL_DIR' && \
 sudo mkdir -p '$INSTALL_DIR' && \
 sudo tar -xzf /tmp/grafana-custom.tar.gz -C '$INSTALL_DIR' --strip-components=1 && \
 rm /tmp/grafana-custom.tar.gz"

# --- PASSO 6: CONFIGURAR O GRAFANA ---
TEMPLATE_URL="https://raw.githubusercontent.com/$REPO/main/conf/custom.ini.template"
CONFIG_FILE="$INSTALL_DIR/conf/custom.ini"
PASSWORD_FILE="$INSTALL_DIR/conf/.pgpass"
run_step "Passo 6/6: Criando arquivo de configuração e ajustando permissões" \
"wget -q -O /tmp/custom.ini.template '$TEMPLATE_URL' && \
 sed -e 's/%%DB_NAME%%/$DB_NAME/' \
     -e 's/%%DB_USER%%/$DB_USER/' \
     -e 's/%%DB_PASSWORD%%/$DB_PASSWORD/' \
     /tmp/custom.ini.template | sudo tee '$CONFIG_FILE' > /dev/null && \
 rm /tmp/custom.ini.template && \
 echo '$DB_PASSWORD' | sudo tee '$PASSWORD_FILE' > /dev/null && \
 sudo chmod 640 '$PASSWORD_FILE' && \
 (id 'grafana' &>/dev/null || sudo useradd -rs /bin/false grafana) && \
 sudo chown -R grafana:grafana '$INSTALL_DIR'"

# --- FINALIZAÇÃO ---
echo ""
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}✅ Instalação Full-Stack concluída com sucesso! ✅${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo "Um banco de dados PostgreSQL foi configurado."
echo -e "A senha para o usuário '${DB_USER}' do banco foi salva em: ${YELLOW}${PASSWORD_FILE}${NC}"
echo "Para visualizá-la, use o comando: sudo cat ${PASSWORD_FILE}"
echo ""
echo "Para iniciar o servidor, execute:"
echo -e "${GREEN}sudo $INSTALL_DIR/bin/grafana server --homepath $INSTALL_DIR${NC}"]