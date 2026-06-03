# WhatPromo — Contexto do Projeto

## O que é
Bot automatizado de curadoria e distribuição de ofertas via WhatsApp e Telegram.
Raspa ofertas de lojas, filtra com IA, envia para grupos segmentados por nicho.

---

## Stack
| Camada | Tecnologia |
|---|---|
| Raspador | Python 3.11 + Playwright |
| Orquestração | Apache Airflow (DAGs) |
| IA (plugável) | Groq por padrão — troca via .env sem alterar código |
| WhatsApp | Evolution API (Docker) |
| Painel Admin | Laravel 11 + Vue 3 + Inertia.js (Fase 4) |
| Banco | MySQL / MariaDB |
| Proxy | Nginx (Fase 4) |
| Infra | VPS própria — Ubuntu, 150GB, €4,50/mês |

## Infraestrutura
| Item | Valor |
|---|---|
| IP | 144.91.70.44 |
| SO | Ubuntu (headless) |
| Acesso | VS Code Remote SSH (root@144.91.70.44) |
| Disco | 150 GB |
| Custo | €4,50/mês |
| Desenvolvimento | Direto na VPS via VS Code Remote SSH — sem ambiente local |

---

## Roadmap
```
F1  — Configuração da VPS           ← EM ANDAMENTO (Etapas 1-5 concluídas, parado na Etapa 6)
F2  — Raspador + IA + DAG           ← MVP real (WhatsApp + Telegram funcionando)
F3  — Bot Telegram de controle      ← após MVP validado
F4  — Painel Admin (Laravel + Vue)  ← após retorno financeiro
F5  — Dashboard Analítico           ← após Fase 4
```

---

## Status de Execução (atualizar a cada sessão)

**Fase atual:** F1 — Configuração da VPS
**Última sessão:** 2026-06-03
**Próxima ação:** Etapa 6 — Criar estrutura de diretórios na VPS

### Etapas F1
| # | Etapa | Status |
|---|---|---|
| 1 | Atualização do sistema (`apt update && apt upgrade`) | ✅ |
| 2 | Dependências essenciais (`curl wget unzip nano ufw fail2ban`) | ✅ |
| 3 | Firewall UFW (portas 22, 443, 80, 8080, 8081) | ✅ |
| 4 | Fail2ban (proteção SSH) | ✅ |
| 5 | Docker (v29.5.2) + Docker Compose (v5.1.4) | ✅ |
| 6 | Estrutura de diretórios `/srv/whatpromo` | ✅ |
| 7 | Node.js + Claude Code | ✅ |
| 8 | Git (config + init) | ✅ |
| 9 | .gitignore | ✅ |
| 10 | .env.exemplo e .env | ✅ |
| 11 | Migrations SQL | ✅ |
| 12 | docker-compose.yml | ⏳ |
| 13 | AIRFLOW_CHAVE_FERNET | ⏳ |
| 14 | Subir containers | ⏳ |
| 15 | Verificar banco (4 tabelas) | ⏳ |
| 16 | Conectar WhatsApp (Evolution API) | ⏳ |
| 17 | Verificar Airflow UI | ⏳ |
| 18 | requirements.txt | ⏳ |
| 19 | Primeiro commit | ⏳ |

### Acesso SSH
```
ssh -p 443 root@144.91.70.44
```
Porta 443 configurada via systemd socket override (`/etc/systemd/system/ssh.socket.d/override.conf`) pois porta 22 é bloqueada na rede do desenvolvedor.

---

## Convenção OBRIGATÓRIA — Português em tudo
Todo o projeto em português sem exceção:
- Variáveis: `preco_original`, `percentual_desconto`, `hash_url`
- Métodos: `pontuar_oferta()`, `gerar_mensagem()`, `raspar()`, `disparar()`
- Classes: `ProvedorBase`, `ProvedorGroq`, `AranhaBase`, `AranhaAmazon`, `CanalBase`, `CanalWhatsApp`
- Colunas do banco: `preco_original`, `preco_promocional`, `pontuacao_ia`, `enviado_em`
- Rotas Laravel: `/ofertas`, `/grupos`, `/disparos`, `/configuracoes`
- DAG tasks: `raspar_lojas`, `validar_ofertas`, `pontuar_com_ia`, `gerar_links_afiliado`, `disparar`
- Comentários, docstrings, logs, variáveis de ambiente: português
- Exceção permitida: nomes de libs externas (Playwright, Airflow, Docker, etc.)

---

## Estrutura de Diretórios
```
/srv/whatpromo/
├── CLAUDE.md
├── .env.exemplo
├── .env                           # nunca commitar
├── .gitignore
├── docker-compose.yml
├── docs/
│   ├── FASE-1-configuracao-vps.md
│   ├── FASE-2-scraper-ia-dag.md
│   ├── FASE-3-bot-telegram.md
│   ├── FASE-4-painel-admin.md
│   └── FASE-5-dashboard.md
├── migrations/
│   └── 001_criar_tabelas.sql
├── raspador/
│   ├── configuracao.py            # PONTO CENTRAL: categorias, lojas, canais
│   ├── requirements.txt
│   ├── aranhas/
│   │   ├── aranha_base.py         # Classe abstrata AranhaBase
│   │   ├── mercado_livre.py       # MVP — implementar primeiro
│   │   └── shopee.py              # MVP — implementar segundo
│   ├── ia/
│   │   ├── provedor_base.py       # Classe abstrata ProvedorBase
│   │   ├── provedor_groq.py       # Padrão — gratuito
│   │   ├── provedor_claude.py
│   │   ├── provedor_openai.py
│   │   └── fabrica.py             # obter_provedor_ia()
│   ├── canais/
│   │   ├── canal_base.py          # Classe abstrata CanalBase
│   │   ├── fabrica_canais.py      # obter_canais_ativos()
│   │   ├── whatsapp/
│   │   │   ├── canal_whatsapp.py  # MVP
│   │   │   └── formatador.py
│   │   ├── telegram/              # MVP
│   │   │   ├── canal_telegram.py
│   │   │   └── formatador.py
│   │   ├── instagram/             # FUTURO
│   │   └── twitter/               # FUTURO
│   └── utilitarios/
│       ├── banco.py
│       ├── deduplicacao.py
│       └── afiliados.py
├── airflow/
│   ├── dags/
│   │   └── pipeline_whatpromo.py
│   └── logs/
├── bot_telegram/
│   ├── bot.py
│   ├── configuracao.py
│   └── comandos/
│       ├── status.py
│       └── airflow.py
├── painel/                        # Laravel 11 + Vue 3 (Fase 4)
└── evolution/
```

---

## Banco de Dados (MySQL) — Tabelas

### ofertas
```
id, hash_url (SHA-256 UNIQUE), titulo, loja, categoria,
preco_original, preco_promocional, percentual_desconto,
cupom, url_original, url_afiliado, url_curta,
pontuacao_ia, provedor_ia, mensagem_wa,
status (pendente|aprovada|rejeitada|enviada|expirada),
motivo_rejeicao (desconto_insuficiente|fake_off|categoria_invalida|pontuacao_baixa),
preco_minimo_30d, raspado_em, enviado_em, expira_em
```

### grupos
```
id, id_grupo_wa, nome, canal (whatsapp|telegram),
categorias (JSON), pontuacao_minima, desconto_minimo,
maximo_por_hora, ativo (BOOLEAN), plano (gratuito|premium)
```

### disparos
```
id, oferta_id (FK), grupo_id (FK nullable),
canal (whatsapp|telegram|instagram_feed|instagram_story|twitter),
id_publicacao, disparado_em, cliques, status, erro
```

### historico_precos
```
id, hash_url, preco, registrado_em
```

---

## Pipeline da DAG (pipeline_whatpromo.py)
```
Task 1: raspar_lojas
  → Playwright raspa ML e Shopee
  → Calcula hash_url (SHA-256 sem parâmetros de rastreamento)
  → Grava em historico_precos (SEMPRE)
  → Se hash_url existe com raspado_em < 24h → descarta
  → Senão → salva em ofertas com status = "pendente"

Task 2: validar_ofertas  [status = "pendente"]
  → percentual_desconto < 15% → rejeitada, motivo="desconto_insuficiente"
  → preco_promocional >= preco_minimo_30d * 0.95 → rejeitada, motivo="fake_off"
  → categoria não em CATEGORIAS_VALIDAS → rejeitada, motivo="categoria_invalida"
  → Passou tudo → aprovada

Task 3: pontuar_com_ia  [status = "aprovada"]
  → Chama obter_provedor_ia().pontuar_oferta(oferta)
  → Grava pontuacao_ia e provedor_ia
  → pontuacao_ia < 7 → rejeitada, motivo="pontuacao_baixa"
  → pontuacao_ia >= 7 → chama gerar_mensagem(), grava mensagem_wa

Task 4: gerar_links_afiliado
  → url_original → url_afiliado → url_curta
  → Fallbacks: afiliado falhou → url_original | encurtador falhou → url_afiliado

Task 5: disparar
  → Para cada canal em obter_canais_ativos():
      Para cada grupo ativo:
        Verifica categoria, pontuacao_ia, desconto, rate limit, horário 07-22h
        Publica via canal.publicar(oferta)
        Grava em disparos
        Falha em 1 canal não para os outros

DAG schedule: "*/30 7-22 * * *"
```

---

## Padrão Provedor de IA (plugável)
```python
# Trocar provider = mudar 1 linha no .env
# PROVEDOR_IA=groq | claude | openai

class ProvedorBase(ABC):
    def pontuar_oferta(self, oferta: dict) -> int: ...   # retorna 1-10
    def gerar_mensagem(self, oferta: dict) -> str: ...   # retorna markdown WA

def obter_provedor_ia() -> ProvedorBase:
    # fabrica.py — lê PROVEDOR_IA do .env
```

---

## Padrão Canal (plugável)
```python
# MVP: ["whatsapp", "telegram"]
# Futuro: ["instagram", "twitter"]

class CanalBase(ABC):
    def formatar(self, oferta: dict) -> dict: ...
    def publicar(self, oferta: dict, grupo: dict) -> dict: ...
    @property
    def nome(self) -> str: ...

# Instagram: 2 registros por oferta — instagram_feed e instagram_story
```

---

## Lojas e Categorias (MVP)

### Lojas
- `mercado_livre` — implementar primeiro
- `shopee` — implementar segundo

### Categorias
```python
CATEGORIAS_VALIDAS = ["eletronicos", "games", "casa_cozinha", "moda_calcados", "ferramentas"]
EMOJI_POR_CATEGORIA = {
    "eletronicos": "📱", "games": "🎮",
    "casa_cozinha": "🏠", "moda_calcados": "👟", "ferramentas": "🔧"
}
```

---

## Formato da Mensagem WhatsApp/Telegram
```
📱 *CHAMADA CURTA EM CAIXA ALTA*   ← IA gera (max 40 chars)

🛍️ *Titulo do Produto*
🏪 Nome da Loja

~~R$ preco_original~~ → *R$ preco_promocional*
💰 Economia de R$ X (Y% OFF)

🎟️ Cupom: `CODIGO`    ← omitir linha inteira se NULL

🔗 url_curta

⏰ _chamada de urgência_            ← IA gera (max 50 chars)
```

A IA gera apenas `chamada_curta` e `urgencia` em JSON.
O restante é montado pelo código Python.

---

## Variáveis de Ambiente (.env)
```env
PROVEDOR_IA=groq
CHAVE_API_GROQ=gsk_xxx
CHAVE_API_ANTHROPIC=sk-ant-xxx
CHAVE_API_OPENAI=sk-xxx
BD_HOST=banco_dados
BD_PORTA=3306
BD_NOME=whatpromo_db
BD_USUARIO=whatpromo_usuario
BD_SENHA=senha_forte
BD_SENHA_ROOT=senha_root
EVOLUTION_URL=http://evolution_api:8080
EVOLUTION_CHAVE=chave_evolution
EVOLUTION_INSTANCIA=whatpromo
CHAVE_BOT_TELEGRAM=token_do_bot
ID_CHAT_ADMIN_TELEGRAM=seu_id
TAG_AFILIADO_ML=whatpromo_ml
TAG_AFILIADO_SHOPEE=whatpromo_shopee
CHAVE_ENCURTADOR=dub_xxx
DOMINIO_ENCURTADOR=wtp.to
AIRFLOW_CHAVE_FERNET=xxx=
AIRFLOW_USUARIO_ADMIN=admin
AIRFLOW_SENHA_ADMIN=senha_airflow
APP_CHAVE=base64:xxx=
APP_AMBIENTE=production
APP_DEBUG=false
APP_URL=http://144.91.70.44
EMAIL_ADMIN=email@exemplo.com
SMTP_HOST=smtp.gmail.com
SMTP_PORTA=587
SMTP_USUARIO=email@exemplo.com
SMTP_SENHA=senha_app_gmail
```

---

## Regras de Negócio (resumo)
| # | Regra | Detalhe |
|---|---|---|
| RN-01 | Deduplicação | SHA-256 da URL sem params; se existe < 24h → descarta |
| RN-02 | Desconto mínimo | percentual_desconto >= 15% |
| RN-03 | Anti-fake-off | preco_promocional < preco_minimo_30d * 0.95 |
| RN-04 | Score IA | pontuacao_ia >= 7 (configurável por grupo) |
| RN-05 | Rate limit | max maximo_por_hora msgs/hora; intervalo min 3min; 07h-22h |
| RN-06 | Segmentação | grupo.categorias deve conter oferta.categoria |
| RN-07 | Expiração | enviado_em > 48h → status = expirada |

---

## Afiliados (referência)
| Prioridade | Afiliado | Comissão | Cookie |
|---|---|---|---|
| MVP | Mercado Livre | 6–16% | 30 dias |
| MVP | Shopee | 3–30% | 7 dias |
| Futuro | Amazon | 2–13% | 24h |
| Futuro | Magalu | 4–8% | 30 dias |
| Futuro | Shein | 2–20%* | 30 dias |

---

## Regras para o assistente
- Todo código gerado deve seguir a convenção de português
- Cada entrega documentada com explicação detalhada de cada decisão
- Explicar o motivo de cada escolha técnica, não apenas o que fazer
- Nenhum código sem comentário explicativo em português
- Desenvolvimento acontece direto na VPS via VS Code Remote SSH

### Workflow de execução (padrão estabelecido pelo usuário)
1. Explicar o que é e por que precisamos — de forma concisa e resumida — ANTES de agir
2. Mostrar o comando e perguntar "Posso rodar?"
3. Aguardar confirmação do usuário ("Sim")
4. Executar o comando na VPS
5. Atualizar `docs/EXECUCAO-FASE-1.md` com resultado
6. Atualizar o status da etapa no CLAUDE.md

### Comportamentos proibidos
- Nunca instalar software sem permissão explícita
- Nunca adicionar flags desnecessárias em comandos SSH ou outros
- Nunca tentar acessar a VPS via bibliotecas Python (paramiko etc.) — usar sempre Bash com SSH
- Não pular a explicação prévia mesmo quando a etapa parece óbvia
