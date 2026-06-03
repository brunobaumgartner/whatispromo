# WhatPromo — Fase 1: Configuração da VPS

## Objetivo
Ter a VPS configurada, segura e com todos os serviços rodando via Docker,
pronta para o desenvolvimento do WhatPromo.

## Dados da VPS
| Item | Valor |
|---|---|
| IP Público | 144.91.70.44 |
| Sistema | Ubuntu (sem interface gráfica) |
| Disco | 150 GB |
| Acesso | root via SSH |
| Região | EU |
| Custo | €4,50/mês |

## Como acessar
Via VS Code Remote SSH (já configurado):
- `Ctrl+Shift+P` → `Remote-SSH: Connect to Host`
- `root@144.91.70.44`
- Abrir pasta `/srv/whatpromo`

Via terminal:
```bash
ssh root@144.91.70.44
```

---

## Etapa 1 — Atualizar o sistema

```bash
apt update && apt upgrade -y
```

**Por que fazer isso primeiro?**
O Ubuntu recém instalado pode ter pacotes desatualizados com falhas de segurança.
Atualizar antes de instalar qualquer coisa garante uma base limpa e segura.

---

## Etapa 2 — Instalar dependências essenciais

```bash
apt install -y \
  git \
  curl \
  wget \
  unzip \
  nano \
  ufw \
  fail2ban
```

**O que cada pacote faz:**
- `git` — controle de versão do código
- `curl` / `wget` — download de arquivos e scripts
- `unzip` — descompactar arquivos
- `nano` — editor de texto simples no terminal
- `ufw` — firewall simples para controlar portas abertas
- `fail2ban` — bloqueia IPs que tentam acesso por força bruta (segurança)

---

## Etapa 3 — Configurar firewall (UFW)

```bash
# Permite SSH (OBRIGATÓRIO antes de ativar — senão perde acesso)
ufw allow 22

# Portas dos serviços do WhatPromo
ufw allow 80    # HTTP (painel Laravel — Fase 4)
ufw allow 443   # HTTPS (SSL — Fase 4)
ufw allow 8080  # Evolution API (WhatsApp)
ufw allow 8081  # Airflow UI

# Ativa o firewall
ufw enable

# Verifica o status
ufw status
```

**Por que configurar o firewall?**
Por padrão, todas as portas estão abertas no Ubuntu recém instalado.
O firewall garante que só as portas necessárias sejam acessíveis externamente.
O `allow 22` antes do `enable` é crítico — sem ele você perde o acesso SSH.

---

## Etapa 4 — Configurar o fail2ban

```bash
# Ativa o serviço
systemctl enable fail2ban
systemctl start fail2ban

# Verifica se está rodando
systemctl status fail2ban
```

**Por que o fail2ban?**
Qualquer servidor com IP público recebe tentativas de acesso por força bruta
em poucos minutos. O fail2ban monitora as tentativas falhas de SSH e bloqueia
automaticamente o IP após 5 tentativas em 10 minutos.

---

## Etapa 5 — Instalar Docker e Docker Compose

```bash
# Baixa e executa o script oficial de instalação do Docker
curl -fsSL https://get.docker.com | sh

# Verifica se instalou corretamente
docker --version
docker compose version
```

**Por que Docker?**
Docker garante que todos os serviços (banco, Airflow, Evolution API) rodam
de forma isolada e consistente. Se precisar migrar de VPS no futuro,
é só copiar os arquivos e fazer `docker compose up -d`.

---

## Etapa 6 — Criar estrutura de diretórios

```bash
# Cria o diretório do projeto
mkdir -p /srv/whatpromo

# Entra no diretório
cd /srv/whatpromo

# Cria toda a estrutura de pastas de uma vez
mkdir -p \
  raspador/aranhas \
  raspador/ia \
  raspador/canais/whatsapp \
  raspador/canais/telegram \
  raspador/canais/instagram \
  raspador/canais/twitter \
  raspador/utilitarios \
  airflow/dags \
  airflow/logs \
  bot_telegram/comandos \
  painel \
  evolution \
  migrations \
  docs
```

---

## Etapa 7 — Instalar Node.js e Claude Code

```bash
# Instala Node.js 22 (LTS)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs

# Verifica a instalação
node --version
npm --version

# Instala o Claude Code globalmente
npm install -g @anthropic-ai/claude-code

# Verifica
claude --version
```

**Por que Node.js na VPS?**
O Claude Code é uma ferramenta CLI que roda em Node.js.
Com ele instalado na VPS, você pode usar o Claude Code diretamente
pelo VS Code Remote SSH sem instalar nada na máquina local.

---

## Etapa 8 — Configurar Git

```bash
# Configura identidade do Git (aparece nos commits)
git config --global user.name "Seu Nome"
git config --global user.email "seu@email.com"

# Configura branch padrão como main
git config --global init.defaultBranch main

# Inicializa o repositório
cd /srv/whatpromo
git init
```

---

## Etapa 9 — Criar o .gitignore

Crie `/srv/whatpromo/.gitignore`:

```gitignore
# Variáveis de ambiente — NUNCA versionar
.env

# Python
__pycache__/
*.pyc
*.pyo
.venv/
venv/
*.egg-info/

# Laravel
painel/vendor/
painel/node_modules/
painel/.env
painel/storage/logs/
painel/bootstrap/cache/

# Airflow
airflow/logs/
airflow/__pycache__/

# Docker volumes locais
volumes/

# Sistema operacional
.DS_Store
Thumbs.db

# Claude Code
.claude/
```

---

## Etapa 10 — Criar o .env.exemplo e o .env

Crie `/srv/whatpromo/.env.exemplo`:

```env
# ================================================================
# WhatPromo — Arquivo de configuração de ambiente
# Copie: cp .env.exemplo .env
# Preencha os valores reais no .env — nunca commite o .env
# ================================================================

# IA
PROVEDOR_IA=groq
CHAVE_API_GROQ=gsk_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
CHAVE_API_ANTHROPIC=sk-ant-xxxxxxxxxxxxxxxxxxxxxxxxxxxx
CHAVE_API_OPENAI=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Banco de dados
# BD_HOST usa o nome do serviço Docker — não localhost
BD_HOST=banco_dados
BD_PORTA=3306
BD_NOME=whatpromo_db
BD_USUARIO=whatpromo_usuario
BD_SENHA=senha_forte_aqui
BD_SENHA_ROOT=senha_root_aqui

# WhatsApp — Evolution API
EVOLUTION_URL=http://evolution_api:8080
EVOLUTION_CHAVE=chave_secreta_evolution_aqui
EVOLUTION_INSTANCIA=whatpromo

# Telegram
CHAVE_BOT_TELEGRAM=0000000000:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ID_CHAT_ADMIN_TELEGRAM=0000000000

# Afiliados
TAG_AFILIADO_ML=whatpromo_ml
TAG_AFILIADO_SHOPEE=whatpromo_shopee

# Encurtador de URLs (Dub.co — 25k cliques/mês gratuito)
CHAVE_ENCURTADOR=dub_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
DOMINIO_ENCURTADOR=wtp.to

# Airflow
AIRFLOW_CHAVE_FERNET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
AIRFLOW_USUARIO_ADMIN=admin
AIRFLOW_SENHA_ADMIN=senha_airflow_aqui

# Laravel (Fase 4)
APP_CHAVE=base64:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
APP_AMBIENTE=production
APP_DEBUG=false
APP_URL=http://144.91.70.44

# Alertas de falha
EMAIL_ADMIN=seu_email@exemplo.com
SMTP_HOST=smtp.gmail.com
SMTP_PORTA=587
SMTP_USUARIO=seu_email@exemplo.com
SMTP_SENHA=senha_de_app_gmail_aqui
```

Agora copia e preenche:

```bash
cp .env.exemplo .env
nano .env
```

---

## Etapa 11 — Criar as migrations SQL

Crie `/srv/whatpromo/migrations/001_criar_tabelas.sql`:

```sql
-- ================================================================
-- WhatPromo — Migration 001: Criação das tabelas principais
-- Executado automaticamente pelo MariaDB na primeira inicialização
-- ================================================================

USE whatpromo_db;

CREATE TABLE IF NOT EXISTS ofertas (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hash_url            CHAR(64) NOT NULL UNIQUE,
    titulo              VARCHAR(500) NOT NULL,
    loja                VARCHAR(100) NOT NULL,
    categoria           VARCHAR(100) NOT NULL,
    preco_original      DECIMAL(10,2) NOT NULL,
    preco_promocional   DECIMAL(10,2) NOT NULL,
    percentual_desconto TINYINT UNSIGNED NOT NULL,
    cupom               VARCHAR(50) NULL,
    url_original        TEXT NOT NULL,
    url_afiliado        TEXT NULL,
    url_curta           VARCHAR(255) NULL,
    pontuacao_ia        TINYINT UNSIGNED NULL,
    provedor_ia         VARCHAR(50) NULL,
    mensagem_wa         TEXT NULL,
    status              ENUM('pendente','aprovada','rejeitada','enviada','expirada')
                        NOT NULL DEFAULT 'pendente',
    motivo_rejeicao     VARCHAR(50) NULL,
    preco_minimo_30d    DECIMAL(10,2) NULL,
    raspado_em          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    enviado_em          TIMESTAMP NULL,
    expira_em           TIMESTAMP NULL,
    INDEX idx_status (status),
    INDEX idx_loja (loja),
    INDEX idx_categoria (categoria),
    INDEX idx_raspado_em (raspado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS grupos (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_grupo_wa         VARCHAR(100) NOT NULL UNIQUE,
    nome                VARCHAR(200) NOT NULL,
    canal               ENUM('whatsapp','telegram') NOT NULL DEFAULT 'whatsapp',
    categorias          JSON NOT NULL,
    pontuacao_minima    TINYINT UNSIGNED NOT NULL DEFAULT 7,
    desconto_minimo     TINYINT UNSIGNED NOT NULL DEFAULT 20,
    maximo_por_hora     TINYINT UNSIGNED NOT NULL DEFAULT 5,
    ativo               BOOLEAN NOT NULL DEFAULT TRUE,
    plano               ENUM('gratuito','premium') NOT NULL DEFAULT 'gratuito',
    criado_em           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ativo (ativo),
    INDEX idx_canal (canal)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS disparos (
    id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    oferta_id       BIGINT UNSIGNED NOT NULL,
    grupo_id        BIGINT UNSIGNED NULL,
    canal           VARCHAR(50) NOT NULL,
    id_publicacao   VARCHAR(100) NULL,
    disparado_em    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cliques         INT UNSIGNED NOT NULL DEFAULT 0,
    status          ENUM('sucesso','falhou','limite_atingido') NOT NULL,
    erro            TEXT NULL,
    FOREIGN KEY (oferta_id) REFERENCES ofertas(id) ON DELETE CASCADE,
    FOREIGN KEY (grupo_id)  REFERENCES grupos(id)  ON DELETE SET NULL,
    INDEX idx_oferta_id (oferta_id),
    INDEX idx_canal (canal),
    INDEX idx_disparado_em (disparado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS historico_precos (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hash_url      CHAR(64) NOT NULL,
    preco         DECIMAL(10,2) NOT NULL,
    registrado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hash_url (hash_url),
    INDEX idx_registrado_em (registrado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## Etapa 12 — Criar o docker-compose.yml

Crie `/srv/whatpromo/docker-compose.yml`:

```yaml
# ================================================================
# WhatPromo — Docker Compose (VPS)
# Sobe: banco de dados, Evolution API e Airflow
# ================================================================

services:

  banco_dados:
    image: mariadb:11
    container_name: whatpromo_banco
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${BD_SENHA_ROOT}
      MARIADB_DATABASE: whatpromo_db
      MARIADB_USER: ${BD_USUARIO}
      MARIADB_PASSWORD: ${BD_SENHA}
    volumes:
      - dados_banco:/var/lib/mysql
      - ./migrations:/docker-entrypoint-initdb.d:ro
    ports:
      - "3306:3306"
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5

  evolution_api:
    image: atendai/evolution-api:latest
    container_name: whatpromo_evolution
    restart: unless-stopped
    environment:
      AUTHENTICATION_API_KEY: ${EVOLUTION_CHAVE}
      DATABASE_ENABLED: "false"
    volumes:
      - dados_evolution:/evolution/instances
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080"]
      interval: 15s
      timeout: 5s
      retries: 3

  airflow_init:
    image: apache/airflow:2.9-python3.11
    container_name: whatpromo_airflow_init
    depends_on:
      banco_dados:
        condition: service_healthy
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: >-
        mysql+mysqldb://${BD_USUARIO}:${BD_SENHA}@banco_dados:3306/whatpromo_db
      AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW_CHAVE_FERNET}
      AIRFLOW__CORE__LOAD_EXAMPLES: "false"
      _AIRFLOW_DB_MIGRATE: "true"
      _AIRFLOW_WWW_USER_CREATE: "true"
      _AIRFLOW_WWW_USER_USERNAME: ${AIRFLOW_USUARIO_ADMIN}
      _AIRFLOW_WWW_USER_PASSWORD: ${AIRFLOW_SENHA_ADMIN}
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./raspador:/opt/airflow/raspador
      - ./airflow/logs:/opt/airflow/logs
    command: version
    restart: "no"

  airflow_webserver:
    image: apache/airflow:2.9-python3.11
    container_name: whatpromo_airflow_web
    restart: unless-stopped
    depends_on:
      banco_dados:
        condition: service_healthy
      airflow_init:
        condition: service_completed_successfully
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: >-
        mysql+mysqldb://${BD_USUARIO}:${BD_SENHA}@banco_dados:3306/whatpromo_db
      AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW_CHAVE_FERNET}
      AIRFLOW__CORE__LOAD_EXAMPLES: "false"
      AIRFLOW__WEBSERVER__SECRET_KEY: ${AIRFLOW_CHAVE_FERNET}
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./raspador:/opt/airflow/raspador
      - ./airflow/logs:/opt/airflow/logs
    ports:
      - "8081:8080"
    command: webserver

  airflow_scheduler:
    image: apache/airflow:2.9-python3.11
    container_name: whatpromo_airflow_scheduler
    restart: unless-stopped
    depends_on:
      banco_dados:
        condition: service_healthy
      airflow_init:
        condition: service_completed_successfully
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: >-
        mysql+mysqldb://${BD_USUARIO}:${BD_SENHA}@banco_dados:3306/whatpromo_db
      AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW_CHAVE_FERNET}
      AIRFLOW__CORE__LOAD_EXAMPLES: "false"
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./raspador:/opt/airflow/raspador
      - ./airflow/logs:/opt/airflow/logs
    command: scheduler

volumes:
  dados_banco:
  dados_evolution:
```

---

## Etapa 13 — Gerar a AIRFLOW_CHAVE_FERNET

```bash
# Instala a biblioteca necessária
pip3 install cryptography

# Gera a chave
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Copie o resultado e cole no `.env` em `AIRFLOW_CHAVE_FERNET=`.

---

## Etapa 14 — Subir os containers

```bash
cd /srv/whatpromo
docker compose up -d

# Acompanha os logs
docker compose logs -f

# Verifica status de todos os containers
docker compose ps
```

---

## Etapa 15 — Verificar o banco de dados

```bash
docker exec -it whatpromo_banco mariadb \
  -u${BD_USUARIO} -p${BD_SENHA} whatpromo_db \
  -e "SHOW TABLES;"
```

Resultado esperado:
```
+----------------------+
| Tables_in_whatpromo_db |
+----------------------+
| disparos             |
| grupos               |
| historico_precos     |
| ofertas              |
+----------------------+
```

---

## Etapa 16 — Conectar o WhatsApp

1. Acesse `http://144.91.70.44:8080` no navegador
2. Autentique com a `EVOLUTION_CHAVE` do `.env`
3. Crie a instância `whatpromo`
4. Escaneie o QR Code com o número dedicado

> Use um número dedicado — nunca o pessoal. Risco de ban permanente.

---

## Etapa 17 — Verificar o Airflow

1. Acesse `http://144.91.70.44:8081`
2. Login com `AIRFLOW_USUARIO_ADMIN` e `AIRFLOW_SENHA_ADMIN`
3. Interface deve abrir sem erros

---

## Etapa 18 — Criar o requirements.txt do raspador

Crie `/srv/whatpromo/raspador/requirements.txt`:

```txt
playwright==1.44.0
beautifulsoup4==4.12.3
httpx==0.27.0
SQLAlchemy==2.0.30
PyMySQL==1.1.1
cryptography==42.0.8
groq==0.9.0
anthropic==0.28.0
openai==1.30.0
python-dotenv==1.0.1
redis==5.0.4
pytz==2024.1
```

---

## Etapa 19 — Primeiro commit no Git

```bash
cd /srv/whatpromo

git add .
git commit -m "inicializa estrutura do projeto WhatPromo"
```

Para conectar a um repositório remoto (GitHub/GitLab):

```bash
git remote add origin https://github.com/SEU_USUARIO/whatpromo.git
git push -u origin main
```

---

## Checklist final da Fase 1

- [ ] Sistema atualizado (`apt update && apt upgrade`)
- [ ] Dependências instaladas (git, curl, ufw, fail2ban)
- [ ] Firewall UFW configurado (portas 22, 80, 443, 8080, 8081)
- [ ] Fail2ban ativo
- [ ] Docker instalado e funcionando
- [ ] Node.js e Claude Code instalados
- [ ] Estrutura de diretórios criada em `/srv/whatpromo`
- [ ] Git configurado
- [ ] `.gitignore` criado
- [ ] `.env.exemplo` criado e commitado
- [ ] `.env` criado e preenchido com valores reais
- [ ] `migrations/001_criar_tabelas.sql` criado
- [ ] `docker-compose.yml` criado
- [ ] `AIRFLOW_CHAVE_FERNET` gerada e no `.env`
- [ ] `docker compose up -d` executado sem erros
- [ ] 4 tabelas criadas no banco (verificado)
- [ ] WhatsApp conectado na Evolution API
- [ ] Airflow acessível em `144.91.70.44:8081`
- [ ] `raspador/requirements.txt` criado
- [ ] Primeiro commit feito

**Fase 1 concluída → partir para a Fase 2 (Raspador + IA + DAG)**
