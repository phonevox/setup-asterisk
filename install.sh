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

# Instalando Node.js
msg "Instalando Node.js..."
sudo apt install -y ca-certificates curl gnupg
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update -y
sudo apt install -y nodejs
success_check "Node.js instalado com sucesso."

# Instalando MySQL
msg "Instalando MySQL..."
sudo service mysql stop
sudo apt remove --purge mysql-server mysql-client mysql-common -y
sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
sudo apt autoremove -y && sudo apt autoclean -y
sudo apt install mysql-server -y
sudo service mysql start
success_check "MySQL instalado e iniciado com sucesso."

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
sudo service apache2 stop || true
sudo apt remove -y apache2 || true
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

# Instalando MongoDB
msg "Instalando MongoDB..."
# Parar o serviço MongoDB
echo "Parando o serviço MongoDB..."
sudo systemctl stop mongod || true

# Remover todos os arquivos MongoDB
echo "Removendo pacotes MongoDB e arquivos de dados..."
sudo apt-get purge -y mongodb-org*
sudo rm -rf /var/lib/mongodb
sudo rm -rf /var/log/mongodb
sudo rm -f /etc/mongod.conf

# Verificar processos MongoDB
echo "Verificando processos MongoDB..."
processes=$(ps aux | grep '[m]ongod')

if [ -n "$processes" ]; then
    echo "Processos MongoDB encontrados. Finalizando processos..."
    echo "$processes" | awk '{print $2}' | xargs sudo kill -9
else
    echo "Nenhum processo MongoDB encontrado."
fi

# Instalar novamente o MongoDB 7.0
echo "Instalando MongoDB 7.0..."
sudo apt-get install -y gnupg curl
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
success_check "MongoDB instalado com sucesso."

# Iniciando o serviço MongoDB
echo "Iniciando o serviço MongoDB..."
sudo systemctl start mongod
sudo systemctl status mongod

# Configurar o usuário administrador
echo "Configurando o usuário administrador..."
mongo <<EOF
use admin
db.createUser({
  user: "admin",
  pwd: "yourPassword",
  roles: [ { role: "root", db: "admin" } ]
})
EOF
success_check "Usuário administrador do MongoDB configurado com sucesso."

# Reiniciar o MongoDB
echo "Reiniciando o MongoDB..."
sudo systemctl restart mongod
success_check "MongoDB reiniciado com sucesso."

success_check "Instalação e configuração finalizadas com sucesso!"