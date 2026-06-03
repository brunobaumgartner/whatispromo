# WhatPromo — Fase 3: Bot Telegram de Controle

## Objetivo
Bot no Telegram que permite controlar o pipeline e consultar status
sem precisar acessar o servidor via SSH ou abrir o Airflow UI.

## Pré-requisitos
- Fases 1 e 2 concluídas e MVP validado (ofertas chegando nos grupos)
- Conta no Telegram
- Bot criado via @BotFather (obter CHAVE_BOT_TELEGRAM)
- ID do seu chat pessoal no Telegram (obter via @userinfobot)

---

## Comandos disponíveis

| Comando | O que faz |
|---|---|
| `/status` | Resumo do dia: ofertas coletadas, aprovadas, rejeitadas, enviadas |
| `/hoje` | Lista as últimas 5 ofertas enviadas hoje |
| `/erros` | Últimas falhas registradas nas tasks do Airflow |
| `/pausar` | Pausa a DAG pipeline_whatpromo (para os envios) |
| `/resumir` | Retoma a DAG pausada |
| `/forcar` | Força execução imediata da DAG |
| `/ajuda` | Lista todos os comandos disponíveis |

---

## Estrutura de arquivos desta fase

```
bot_telegram/
├── bot.py                  # Ponto de entrada — inicia o bot
├── configuracao.py         # Tokens, IDs autorizados
├── comandos/
│   ├── __init__.py
│   ├── status.py           # /status e /hoje
│   ├── erros.py            # /erros
│   └── airflow.py          # /pausar, /resumir, /forcar
└── requirements.txt
```

---

## Etapa 1 — Criar o bot no Telegram

1. Abra o Telegram e procure por **@BotFather**
2. Envie `/newbot`
3. Escolha um nome: `WhatPromo Admin`
4. Escolha um username: `whatpromo_admin_bot`
5. Copie o token gerado e cole em `CHAVE_BOT_TELEGRAM` no `.env`
6. Obtenha seu ID: procure **@userinfobot**, envie qualquer mensagem
7. Copie o ID retornado e cole em `ID_CHAT_ADMIN_TELEGRAM` no `.env`

---

## Etapa 2 — requirements.txt do bot

Crie `/srv/whatpromo/bot_telegram/requirements.txt`:

```txt
python-telegram-bot==21.3
SQLAlchemy==2.0.30
PyMySQL==1.1.1
python-dotenv==1.0.1
httpx==0.27.0
```

---

## Etapa 3 — configuracao.py do bot

Crie `/srv/whatpromo/bot_telegram/configuracao.py`:

```python
# ================================================================
# WhatPromo — Configuração do bot Telegram
# ================================================================

import os
from dotenv import load_dotenv

load_dotenv()

# Token do bot criado via @BotFather
CHAVE_BOT = os.getenv("CHAVE_BOT_TELEGRAM")

# Apenas este ID pode usar o bot — segurança básica para evitar
# que qualquer pessoa que encontre o bot controle o sistema
IDS_AUTORIZADOS = [
    int(os.getenv("ID_CHAT_ADMIN_TELEGRAM", "0"))
]

# URL da API REST do Airflow (interna — não exposta externamente)
AIRFLOW_URL      = os.getenv("AIRFLOW_URL", "http://localhost:8081")
AIRFLOW_USUARIO  = os.getenv("AIRFLOW_USUARIO_ADMIN", "admin")
AIRFLOW_SENHA    = os.getenv("AIRFLOW_SENHA_ADMIN", "")

# Nome da DAG principal
NOME_DAG = "pipeline_whatpromo"
```

---

## Etapa 4 — comandos/status.py

Crie `/srv/whatpromo/bot_telegram/comandos/status.py`:

```python
# ================================================================
# WhatPromo — Comandos de status do bot Telegram
# Consulta o banco de dados e retorna resumo das operações do dia.
# ================================================================

from datetime import date
from raspador.utilitarios.banco import executar_sql


def obter_resumo_hoje() -> str:
    """
    Retorna resumo das ofertas do dia atual formatado para o Telegram.
    """
    hoje = date.today().isoformat()

    resultado = executar_sql("""
        SELECT
            COUNT(*) as total,
            SUM(status = 'pendente')   as pendentes,
            SUM(status = 'aprovada')   as aprovadas,
            SUM(status = 'rejeitada')  as rejeitadas,
            SUM(status = 'enviada')    as enviadas
        FROM ofertas
        WHERE DATE(raspado_em) = :hoje
    """, {"hoje": hoje})

    r = resultado[0] if resultado else {}

    disparos = executar_sql("""
        SELECT canal, COUNT(*) as total, SUM(status = 'sucesso') as sucesso
        FROM disparos
        WHERE DATE(disparado_em) = :hoje
        GROUP BY canal
    """, {"hoje": hoje})

    linhas = [
        f"📊 *Status de hoje ({hoje})*",
        "",
        f"🔍 Coletadas:  {r.get('total', 0)}",
        f"✅ Aprovadas:  {r.get('aprovadas', 0)}",
        f"❌ Rejeitadas: {r.get('rejeitadas', 0)}",
        f"📤 Enviadas:   {r.get('enviadas', 0)}",
    ]

    if disparos:
        linhas += ["", "📡 *Disparos por canal:*"]
        for d in disparos:
            linhas.append(f"  • {d['canal']}: {d['sucesso']}/{d['total']} com sucesso")

    return "\n".join(linhas)


def obter_ultimas_enviadas(limite: int = 5) -> str:
    """
    Retorna as últimas ofertas enviadas hoje.
    """
    hoje = date.today().isoformat()

    ofertas = executar_sql("""
        SELECT titulo, loja, percentual_desconto, pontuacao_ia, enviado_em
        FROM ofertas
        WHERE DATE(enviado_em) = :hoje AND status = 'enviada'
        ORDER BY enviado_em DESC
        LIMIT :limite
    """, {"hoje": hoje, "limite": limite})

    if not ofertas:
        return "📭 Nenhuma oferta enviada hoje ainda."

    linhas = [f"📦 *Últimas {len(ofertas)} ofertas enviadas hoje:*", ""]
    for o in ofertas:
        hora = str(o["enviado_em"])[-8:-3]  # HH:MM
        linhas.append(
            f"• [{hora}] {o['titulo'][:40]} — "
            f"{o['percentual_desconto']}% OFF | Score: {o['pontuacao_ia']}/10"
        )

    return "\n".join(linhas)
```

---

## Etapa 5 — comandos/airflow.py

Crie `/srv/whatpromo/bot_telegram/comandos/airflow.py`:

```python
# ================================================================
# WhatPromo — Controle do Airflow via bot Telegram
# Usa a REST API nativa do Airflow para pausar, resumir e forçar DAGs.
# ================================================================

import httpx
from bot_telegram.configuracao import AIRFLOW_URL, AIRFLOW_USUARIO, AIRFLOW_SENHA, NOME_DAG


def _cabecalhos() -> dict:
    """Cabeçalhos de autenticação básica para a API do Airflow."""
    import base64
    credencial = base64.b64encode(
        f"{AIRFLOW_USUARIO}:{AIRFLOW_SENHA}".encode()
    ).decode()
    return {
        "Authorization": f"Basic {credencial}",
        "Content-Type": "application/json",
    }


def pausar_dag() -> str:
    """Pausa a DAG principal — interrompe os envios automáticos."""
    try:
        resposta = httpx.patch(
            f"{AIRFLOW_URL}/api/v1/dags/{NOME_DAG}",
            json={"is_paused": True},
            headers=_cabecalhos(),
            timeout=10,
        )
        if resposta.status_code == 200:
            return "⏸️ DAG pausada com sucesso. Nenhum envio automático até /resumir."
        return f"❌ Erro ao pausar: {resposta.status_code} — {resposta.text}"
    except Exception as erro:
        return f"❌ Falha na conexão com Airflow: {erro}"


def resumir_dag() -> str:
    """Retoma a DAG pausada."""
    try:
        resposta = httpx.patch(
            f"{AIRFLOW_URL}/api/v1/dags/{NOME_DAG}",
            json={"is_paused": False},
            headers=_cabecalhos(),
            timeout=10,
        )
        if resposta.status_code == 200:
            return "▶️ DAG retomada. Os envios automáticos estão ativos novamente."
        return f"❌ Erro ao retomar: {resposta.status_code}"
    except Exception as erro:
        return f"❌ Falha na conexão com Airflow: {erro}"


def forcar_execucao() -> str:
    """Força uma execução imediata da DAG, independente do agendamento."""
    from datetime import datetime, timezone
    try:
        resposta = httpx.post(
            f"{AIRFLOW_URL}/api/v1/dags/{NOME_DAG}/dagRuns",
            json={
                "dag_run_id": f"manual__{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}",
                "conf": {},
            },
            headers=_cabecalhos(),
            timeout=10,
        )
        if resposta.status_code == 200:
            return "🚀 Execução forçada iniciada! Acompanhe em http://localhost:8081"
        return f"❌ Erro ao forçar execução: {resposta.status_code}"
    except Exception as erro:
        return f"❌ Falha na conexão com Airflow: {erro}"
```

---

## Etapa 6 — bot.py (ponto de entrada)

Crie `/srv/whatpromo/bot_telegram/bot.py`:

```python
# ================================================================
# WhatPromo — Bot Telegram de controle administrativo
# Permite controlar o pipeline e consultar status via Telegram.
# Apenas IDs em IDS_AUTORIZADOS podem usar os comandos.
# ================================================================

import logging
import sys
sys.path.insert(0, "/srv/whatpromo")

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
from bot_telegram.configuracao import CHAVE_BOT, IDS_AUTORIZADOS
from bot_telegram.comandos import status as cmd_status
from bot_telegram.comandos import airflow as cmd_airflow

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def apenas_admin(funcao):
    """
    Decorador de segurança: bloqueia qualquer usuário não autorizado.
    Importante — sem isso qualquer pessoa que encontrar o bot
    consegue pausar os envios ou ver dados do sistema.
    """
    async def wrapper(update: Update, contexto: ContextTypes.DEFAULT_TYPE):
        if update.effective_user.id not in IDS_AUTORIZADOS:
            await update.message.reply_text("⛔ Acesso não autorizado.")
            logger.warning(f"Tentativa não autorizada: {update.effective_user.id}")
            return
        return await funcao(update, contexto)
    return wrapper


@apenas_admin
async def comando_status(update: Update, contexto: ContextTypes.DEFAULT_TYPE):
    """Envia resumo das operações do dia."""
    mensagem = cmd_status.obter_resumo_hoje()
    await update.message.reply_text(mensagem, parse_mode="Markdown")


@apenas_admin
async def comando_hoje(update: Update, contexto: ContextTypes.DEFAULT_TYPE):
    """Lista as últimas ofertas enviadas hoje."""
    mensagem = cmd_status.obter_ultimas_enviadas()
    await update.message.reply_text(mensagem, parse_mode="Markdown")


@apenas_admin
async def comando_pausar(update: Update, contexto: ContextTypes.DEFAULT_TYPE):
    """Pausa a DAG principal."""
    mensagem = cmd_airflow.pausar_dag()
    await update.message.reply_text(mensagem)


@apenas_admin
async def comando_resumir(update: Update, contexto: ContextTypes.DEFAULT_TYPE):
    """Retoma a DAG pausada."""
    mensagem = cmd_airflow.resumir_dag()
    await update.message.reply_text(mensagem)


@apenas_admin
async def comando_forcar(update: Update, contexto: ContextTypes.DEFAULT_TYPE):
    """Força execução imediata da DAG."""
    mensagem = cmd_airflow.forcar_execucao()
    await update.message.reply_text(mensagem)


@apenas_admin
async def comando_ajuda(update: Update, contexto: ContextTypes.DEFAULT_TYPE):
    """Lista todos os comandos disponíveis."""
    texto = (
        "🤖 *WhatPromo Admin Bot*\n\n"
        "Comandos disponíveis:\n\n"
        "/status — Resumo das operações de hoje\n"
        "/hoje — Últimas 5 ofertas enviadas\n"
        "/erros — Últimas falhas do pipeline\n"
        "/pausar — Pausa os envios automáticos\n"
        "/resumir — Retoma os envios automáticos\n"
        "/forcar — Força execução imediata\n"
        "/ajuda — Esta mensagem"
    )
    await update.message.reply_text(texto, parse_mode="Markdown")


def iniciar_bot():
    """Inicializa e coloca o bot em modo de escuta (polling)."""
    aplicacao = Application.builder().token(CHAVE_BOT).build()

    aplicacao.add_handler(CommandHandler("status",  comando_status))
    aplicacao.add_handler(CommandHandler("hoje",    comando_hoje))
    aplicacao.add_handler(CommandHandler("pausar",  comando_pausar))
    aplicacao.add_handler(CommandHandler("resumir", comando_resumir))
    aplicacao.add_handler(CommandHandler("forcar",  comando_forcar))
    aplicacao.add_handler(CommandHandler("ajuda",   comando_ajuda))
    aplicacao.add_handler(CommandHandler("start",   comando_ajuda))

    logger.info("Bot WhatPromo iniciado. Aguardando comandos...")
    aplicacao.run_polling()


if __name__ == "__main__":
    iniciar_bot()
```

---

## Etapa 7 — Adicionar o bot ao docker-compose.yml

Adicione este serviço ao `docker-compose.yml` existente:

```yaml
  # ----------------------------------------------------------------
  # Bot Telegram — Controle administrativo via Telegram
  # Roda em paralelo com o Airflow, sem interferir no pipeline.
  # ----------------------------------------------------------------
  bot_telegram:
    image: python:3.11-slim
    container_name: whatpromo_bot_telegram
    restart: unless-stopped
    working_dir: /app
    environment:
      CHAVE_BOT_TELEGRAM: ${CHAVE_BOT_TELEGRAM}
      ID_CHAT_ADMIN_TELEGRAM: ${ID_CHAT_ADMIN_TELEGRAM}
      AIRFLOW_URL: http://airflow_webserver:8080
      AIRFLOW_USUARIO_ADMIN: ${AIRFLOW_USUARIO_ADMIN}
      AIRFLOW_SENHA_ADMIN: ${AIRFLOW_SENHA_ADMIN}
      BD_HOST: banco_dados
      BD_NOME: ${BD_NOME}
      BD_USUARIO: ${BD_USUARIO}
      BD_SENHA: ${BD_SENHA}
    volumes:
      - ./bot_telegram:/app/bot_telegram
      - ./raspador:/app/raspador
    command: >
      sh -c "pip install -r /app/bot_telegram/requirements.txt -q &&
             python -m bot_telegram.bot"
    depends_on:
      banco_dados:
        condition: service_healthy
```

---

## Etapa 8 — Subir o bot

```bash
cd /srv/whatpromo

# Sobe apenas o novo serviço sem reiniciar os outros
docker compose up -d bot_telegram

# Verifica se está rodando
docker compose logs -f bot_telegram
```

---

## Etapa 9 — Testar no Telegram

1. Abra o Telegram e procure pelo bot pelo username criado
2. Envie `/start` — deve responder com a lista de comandos
3. Envie `/status` — deve retornar o resumo do dia
4. Envie `/pausar` — deve pausar a DAG (verificar no Airflow UI)
5. Envie `/resumir` — deve retomar a DAG

---

## Checklist final da Fase 3

- [ ] Bot criado no @BotFather e token no `.env`
- [ ] ID do chat admin no `.env`
- [ ] `bot_telegram/configuracao.py` criado
- [ ] `bot_telegram/comandos/status.py` criado
- [ ] `bot_telegram/comandos/airflow.py` criado
- [ ] `bot_telegram/bot.py` criado
- [ ] Serviço `bot_telegram` adicionado ao `docker-compose.yml`
- [ ] `docker compose up -d bot_telegram` executado sem erros
- [ ] `/start` respondendo no Telegram
- [ ] `/status` retornando dados reais do banco
- [ ] `/pausar` e `/resumir` funcionando (verificar no Airflow UI)

**Fase 3 concluída → partir para a Fase 4 (Painel Admin Laravel + Vue)**
