#!/bin/bash

# Script para instalar e configurar o ambiente

set -e

# Função para exibir mensagens
function msg {
    echo "==========================="
    echo "$1"
    echo "==========================="
}

# Função para mostrar check verde
function success_check {
    echo -e "\033[0;32m✔️ $1\033[0m"  # Código ANSI para texto verde
}

# Atualizando o sistema
msg "Atualizando o sistema..."
sudo apt update -y && sudo apt upgrade -y
success_check "Sistema atualizado com sucesso."

# Verificando a versão do Node.js
NODE_VERSION=$(node -v 2>/dev/null | sed 's/v//')
if [[ -z "$NODE_VERSION" || "$NODE_VERSION" < "20.0.0" ]]; then
    msg "Instalando Node.js..."
    sudo apt install -y ca-certificates curl gnupg
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    NODE_MAJOR=20
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt update -y
    sudo apt install -y nodejs
    success_check "Node.js instalado com sucesso."
else
    success_check "Node.js já está na versão $NODE_VERSION ou superior."
fi

# Verifica a versão do MySQL
MYSQL_VERSION=$(mysql --version | awk '{ print $5 }' | awk -F. '{ print $1"."$2"."$3 }')

# Define a versão mínima
MIN_VERSION="8.0.39"

# Compara as versões
if [[ "$(printf '%s\n' "$MIN_VERSION" "$MYSQL_VERSION" | sort -V | head -n1)" == "$MYSQL_VERSION" ]]; then
  # Instalando MySQL
    msg "Instalando MySQL..."
    sudo service mysql stop
    sudo apt remove --purge mysql-server mysql-client mysql-common -y
    sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
    sudo apt autoremove -y && sudo apt autoclean -y
    sudo apt install mysql-server -y
    sudo service mysql start
    success_check "MySQL instalado e iniciado com sucesso."
else
    echo "A versão do MySQL ($MYSQL_VERSION) é maior ou igual a $MIN_VERSION. Nenhuma instalação necessária."
fi


# Configurando o bind-address
msg "Configurando o bind-address do MySQL..."
echo "Configurando o bind-address para permitir conexões externas..."
sudo bash -c 'cat <<EOF > /etc/mysql/mysql.conf.d/mysqld.cnf
[mysqld]
bind-address = 0.0.0.0
EOF'

# Configurando MySQL
sudo mysql -u root <<EOF
DELETE FROM mysql.user WHERE User='';
UPDATE mysql.user SET Host='localhost' WHERE User='root' AND Host='%';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
success_check "MySQL configurado com sucesso."

# Instalando Asterisk
msg "Instalando Asterisk..."
sudo apt install -y asterisk
success_check "Asterisk instalado com sucesso."

# Configurando Asterisk
msg "Configurando Asterisk..."
sudo sed -i 's/noload => chan_console.so/load => chan_console.so/' /etc/asterisk/modules.conf || echo "chan_console.so já está carregado."
sudo bash -c 'cat <<EOF >> /etc/asterisk/asterisk.conf
[options]
verbose = 3
debug = 3
EOF'
success_check "Asterisk configurado com sucesso."

# Instalando Nginx
msg "Configurando a WEB do servidor..."
# Remover Apache se estiver instalado
if dpkg -l | grep -q apache2; then
    msg "Removendo Apache..."
    sudo service apache2 stop || true
    sudo service apache2 stop || true
    sudo apt remove -y apache2 || true
    success_check "Apache removido com sucesso."
else
    success_check "Apache não está instalado."
fi

sudo apt install -y nginx
success_check "Nginx instalado com sucesso."

# Configurando log do Asterisk
msg "Configurando logs do Asterisk..."
sudo bash -c 'echo "full => notice,warning,error,debug,verbose,dtmf,fax" >> /etc/asterisk/logger.conf'
success_check "Logs do Asterisk configurados com sucesso."

# Perguntando pela porta SIP
read -p "Informe a porta SIP (padrão 50007): " SIP_PORT
SIP_PORT=${SIP_PORT:-50007}

msg "Configurando porta SIP para $SIP_PORT..."
sudo sed -i "s/^bindport=.*/bindport=$SIP_PORT/" /etc/asterisk/sip.conf || echo "Configuração da porta SIP não encontrada."
success_check "Porta SIP configurada com sucesso."

# Habilitando criptografia
sudo bash -c 'echo "encryption=yes" >> /etc/asterisk/sip.conf'


# Remover completamente o MongoDB, se estiver instalado
msg "Removendo MongoDB..."
sudo apt remove --purge mongodb-org* -y
sudo rm -rf /var/lib/mongodb /etc/mongod.conf /var/log/mongodb
sudo rm /usr/share/keyrings/mongodb-archive-keyring.gpg
sudo rm /etc/apt/sources.list.d/mongodb-org-*.list
sudo apt update

# Instalar dependências necessárias
msg "Instalando dependências necessárias..."
sudo apt install -y wget gnupg

# Adicionar a chave e o repositório do MongoDB 8.0 para o Ubuntu 22.04
msg "Adicionando chave e repositório do MongoDB..."
wget -qO - https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-archive-keyring.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list

# Atualizar o índice de pacotes e instalar o MongoDB
msg "Atualizando pacotes e instalando MongoDB..."
sudo apt update
sudo apt install -y mongodb-org
success_check "MongoDB instalado com sucesso."

# Remover o arquivo de socket, se existir
sudo rm -f /tmp/mongodb-27017.sock

# Iniciar o serviço MongoDB
msg "Iniciando o serviço MongoDB..."
sudo systemctl start mongod

# Verificar o status do serviço MongoDB
if sudo systemctl status mongod | grep "running"; then
    success_check "MongoDB iniciado com sucesso."
else
    echo "❌ O MongoDB não conseguiu iniciar. Verifique os logs para mais detalhes."
    exit 1
fi

# Configurar o usuário administrador
msg "Configurando o usuário administrador..."
read -s -p "Digite a senha para o usuário administrador: " admin_password
echo # Para pular a linha após a entrada da senha

# Usar mongosh para configurar o usuário
mongosh <<EOF
use admin
db.createUser({
  user: "admin",
  pwd: "${admin_password}",  // A senha digitada é usada aqui
  roles: [ { role: "root", db: "admin" } ]
})
EOF

# Reiniciar o MongoDB
msg "Reiniciando o MongoDB..."
sudo systemctl restart mongod

success_check "Instalação e configuração do MongoDB concluídas com sucesso!"

echo ""
echo ""

success_check "Sua instalação foi finalizada!"

