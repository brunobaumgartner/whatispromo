# WhatPromo — Execução da Fase 1: Configuração da VPS

Registro do que foi feito, por que foi feito e como verificar cada item.

---

## Dados da VPS

| Item | Valor |
|---|---|
| IP | 144.91.70.44 |
| Sistema | Ubuntu 24.04.4 LTS |
| Disco | 150 GB |
| Custo | €4,50/mês |
| Provedor | Contabo |
| Acesso SSH | `ssh -p 443 root@144.91.70.44` |

---

## Etapa 1 — Atualização do sistema ✅

**Comando:**
```bash
apt update && apt upgrade -y
```

**O que é:**
`apt` é o gerenciador de pacotes do Ubuntu. `update` atualiza a lista de pacotes disponíveis. `upgrade` instala as versões mais recentes dos pacotes já instalados.

**Por que precisamos:**
O Ubuntu recém instalado pode ter pacotes com falhas de segurança já conhecidas. Atualizar antes de qualquer coisa garante que partimos de uma base segura e sem vulnerabilidades conhecidas.

**Resultado:** Sistema já estava atualizado (0 pacotes para atualizar).

---

## Etapa 2 — Dependências essenciais ✅

**Comando:**
```bash
apt install -y curl wget unzip nano ufw fail2ban
```

**O que cada pacote é e para que serve:**

| Pacote | O que é | Para que usamos |
|---|---|---|
| `curl` | Ferramenta de transferência de dados via HTTP | Baixar scripts de instalação (Docker, Node.js) e fazer requisições HTTP para testar APIs |
| `wget` | Downloader de arquivos via HTTP/FTP | Download de arquivos durante a configuração |
| `unzip` | Descompactador de arquivos .zip | Extrair pacotes e arquivos compactados |
| `nano` | Editor de texto simples no terminal | Editar arquivos de configuração diretamente no servidor |
| `ufw` | Uncomplicated Firewall — interface simples para o firewall do Linux (iptables) | Controlar quais portas aceitam conexões externas |
| `fail2ban` | Monitor de logs que bloqueia IPs suspeitos | Proteção automática contra ataques de força bruta no SSH |

**Versões instaladas:**
- curl 8.5.0
- ufw 0.36.2
- fail2ban 1.0.2

---

## Etapa 3 — Firewall UFW ✅

**Comandos:**
```bash
ufw allow 22      # SSH padrão
ufw allow 443     # SSH alternativo (nossa porta para redes que bloqueiam a 22)
ufw allow 80      # HTTP — painel Laravel (Fase 4)
ufw allow 8080    # Evolution API — gateway WhatsApp
ufw allow 8081    # Airflow UI — interface das DAGs
ufw enable
```

**O que é o UFW:**
O UFW (Uncomplicated Firewall) é uma camada de segurança que fica na frente do servidor e decide quais conexões externas são permitidas ou bloqueadas. Por padrão, após ativar, ele bloqueia tudo que não foi explicitamente liberado.

**Por que precisamos:**
Qualquer servidor com IP público fica exposto a varreduras automáticas de bots e hackers que tentam encontrar portas abertas. Sem firewall, qualquer serviço que subir fica acessível para o mundo inteiro. Com o UFW, só as portas que precisamos ficam abertas.

**Por que a porta 443 além da 22:**
A rede corporativa onde o desenvolvedor trabalha bloqueia conexões de saída na porta 22 (SSH padrão). Configuramos o SSH para escutar também na porta 443 (HTTPS), que raramente é bloqueada, permitindo acesso de qualquer rede.

**Como verificar:**
```bash
ufw status
```

**Resultado:**
```
Status: active

To          Action  From
--          ------  ----
22          ALLOW   Anywhere
443         ALLOW   Anywhere
80          ALLOW   Anywhere
8080        ALLOW   Anywhere
8081        ALLOW   Anywhere
```

---

## Etapa 4 — Fail2ban ✅

**Comandos:**
```bash
systemctl enable fail2ban
systemctl start fail2ban
```

**O que é o Fail2ban:**
O Fail2ban é um serviço que monitora os logs do sistema em tempo real. Quando detecta muitas tentativas de login falhas vindas do mesmo IP, ele bloqueia esse IP automaticamente no firewall por um período determinado.

**Por que precisamos:**
Qualquer servidor com SSH exposto na internet recebe centenas de tentativas de acesso por força bruta por dia — bots testando senhas comuns automaticamente. Sem o fail2ban, essas tentativas continuam indefinidamente. Com ele, após 5 tentativas falhas em 10 minutos, o IP fica bloqueado por 10 minutos. Ataques persistentes levam a banimentos mais longos.

**Como verificar:**
```bash
systemctl status fail2ban
fail2ban-client status sshd
```

**Resultado:** Serviço ativo (`active`) e configurado para iniciar automaticamente no boot.

---

## Etapa 5 — Docker ✅

**Comando:**
```bash
curl -fsSL https://get.docker.com | sh
```

**O que é:** Plataforma que roda aplicações em containers isolados. Cada serviço (banco, Airflow, Evolution API) roda em seu próprio container com tudo que precisa, sem conflitos.

**Por que precisamos:** Sem Docker, instalar MariaDB, Airflow e Evolution API diretamente no servidor gera conflitos de versão e é difícil de manter. Com Docker, cada serviço é isolado. Se precisar migrar de VPS no futuro, é só copiar os arquivos e rodar `docker compose up`.

**Versões instaladas:**
- Docker 29.5.2
- Docker Compose v5.1.4

---

## Etapa 6 — Estrutura de diretórios ✅

**Comando:**
```bash
mkdir -p /srv/whatpromo/{raspador/{aranhas,ia,canais/{whatsapp,telegram,instagram,twitter},utilitarios},airflow/{dags,logs},bot_telegram/comandos,painel,evolution,migrations,docs}
```

**O que é:**
Criação da árvore de diretórios do projeto em `/srv/whatpromo`. Cada pasta corresponde a um módulo do sistema.

**Por que precisamos:**
Os arquivos criados nas etapas seguintes precisam ir para os lugares certos desde o início. Sem a estrutura criada, qualquer `cp` ou `nano` em subpasta retornaria erro de diretório inexistente.

**Resultado:** 19 diretórios criados conforme estrutura definida no CLAUDE.md:
```
/srv/whatpromo/
├── airflow/dags/  airflow/logs/
├── bot_telegram/comandos/
├── docs/
├── evolution/
├── migrations/
├── painel/
└── raspador/
    ├── aranhas/
    ├── canais/whatsapp/  telegram/  instagram/  twitter/
    ├── ia/
    └── utilitarios/
```

---

## Etapa 7 — Node.js e Claude Code ✅

**Comando:**
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g --foreground-scripts @anthropic-ai/claude-code
```

**O que é:**
Node.js é o runtime JavaScript. O Claude Code é a CLI da Anthropic que permite usar o assistente de IA diretamente no terminal da VPS.

**Por que precisamos:**
Com o Claude Code na VPS, em sessões futuras é possível continuar o desenvolvimento com IA diretamente via SSH, sem depender do VS Code Remote SSH.

**Resultado:**
- Node.js 22.22.3 (já estava instalado via repositório nodesource)
- Claude Code 2.1.161

---

## Etapa 8 — Git ✅

**Comandos:**
```bash
cd /srv/whatpromo && git init
git config user.name 'Bruno Baumgartner'
git config user.email 'brunohbaumgartner@gmail.com'
git remote add origin https://github.com/brunobaumgartner/whatispromo.git
```

**O que é:**
Git é o sistema de controle de versão. Permite rastrear todas as mudanças no código e voltar a qualquer ponto anterior se algo quebrar.

**Por que precisamos:**
Base para o commit final da Fase 1 e para manter o histórico de todo o desenvolvimento do projeto. Configuração local (sem `--global`) para não afetar outros repositórios na conta root.

**Resultado:**
- Repositório inicializado em `/srv/whatpromo/.git/`
- Branch padrão: `main`
- Autor: `Bruno Baumgartner <brunohbaumgartner@gmail.com>` (config local do repo)
- Remote `origin` apontando para `https://github.com/brunobaumgartner/whatispromo.git`

---

## Etapa 9 — .gitignore ✅

**O que é:**
Arquivo que lista o que o Git deve ignorar e nunca incluir em commits.

**Por que precisamos:**
O `.env` contém senhas e chaves de API — se for commitado por acidente, ficará exposto publicamente no GitHub. Também ignoramos logs, cache Python e arquivos gerados automaticamente que não pertencem ao repositório.

**Resultado:** `/srv/whatpromo/.gitignore` criado cobrindo:
- `.env` (senhas e chaves)
- `__pycache__/`, `*.pyc` (cache Python)
- `airflow/logs/`, `*.log` (logs)
- `raspador/venv/`, `bot_telegram/venv/` (dependências)
- `painel/vendor/`, `painel/node_modules/` (Laravel, Fase 4)
- `evolution/instances/` (dados da Evolution API)

---

## Etapa 10 — .env.exemplo e .env ✅

**O que é:**
- `.env.exemplo` — template com todas as variáveis, sem valores reais. Vai ao GitHub.
- `.env` — cópia com os valores reais preenchidos. Nunca vai ao GitHub (está no `.gitignore`).

**Por que precisamos:**
Centraliza toda configuração sensível em um lugar. O código lê via `os.getenv()`. Trocar provedor de IA ou ambiente é só editar esse arquivo.

**Resultado:** Ambos criados em `/srv/whatpromo/`. Valores fixos já preenchidos (nomes de containers, portas, URLs internas). Pendente de preenchimento manual no `.env`:
- `CHAVE_API_GROQ` — pegar em console.groq.com
- `BD_SENHA` / `BD_SENHA_ROOT` — definir senhas fortes
- `EVOLUTION_CHAVE` — gerada ao subir o container (Etapa 14)
- `AIRFLOW_CHAVE_FERNET` — gerado na Etapa 13
- `AIRFLOW_SENHA_ADMIN` — definir senha

---

## Etapa 11 — Migrations SQL ✅

**O que é:**
Script SQL que cria as 4 tabelas do banco de dados.

**Por que precisamos:**
Ter as tabelas definidas em arquivo versionado garante que qualquer pessoa que clonar o projeto recrie o banco idêntico rodando um único arquivo — sem precisar criar tabelas manualmente.

**Resultado:** `/srv/whatpromo/migrations/001_criar_tabelas.sql` criado com:
- `ofertas` — registro central de cada oferta raspada (hash_url UNIQUE, status, pontuação IA)
- `grupos` — grupos WhatsApp/Telegram com filtros por categoria e rate limit
- `disparos` — log de cada envio com FK para ofertas e grupos
- `historico_precos` — série temporal de preços para detectar fake-off

As tabelas serão criadas no banco na Etapa 15, após os containers subirem.

---

## Etapa 12 — docker-compose.yml ⏳

> A registrar após execução.

---

## Etapa 13 — AIRFLOW_CHAVE_FERNET ⏳

> A registrar após execução.

---

## Etapa 14 — Subir containers ⏳

> A registrar após execução.

---

## Etapa 15 — Verificar banco ⏳

> A registrar após execução.

---

## Etapa 16 — Conectar WhatsApp ⏳

> A registrar após execução.

---

## Etapa 17 — Verificar Airflow ⏳

> A registrar após execução.

---

## Etapa 18 — requirements.txt ⏳

> A registrar após execução.

---

## Etapa 19 — Primeiro commit ⏳

> A registrar após execução.
