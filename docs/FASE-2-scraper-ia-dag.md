# WhatPromo — Fase 2: Raspador + IA + DAG Airflow

## Objetivo
Pipeline completo funcionando: raspador coleta ofertas do Mercado Livre e Shopee,
IA pontua e gera mensagens, e os grupos WhatsApp e Telegram recebem as ofertas
automaticamente a cada 30 minutos.

## Pré-requisitos
- Fase 1 concluída (banco rodando, Evolution API conectada, Airflow acessível)
- Chave da Groq Cloud obtida em console.groq.com (gratuito)
- Playwright instalado (`playwright install chromium`)

---

## Estrutura de arquivos desta fase

```
raspador/
├── configuracao.py
├── requirements.txt
├── aranhas/
│   ├── aranha_base.py
│   ├── mercado_livre.py
│   └── shopee.py
├── ia/
│   ├── provedor_base.py
│   ├── provedor_groq.py
│   ├── provedor_claude.py
│   └── fabrica.py
├── canais/
│   ├── canal_base.py
│   ├── fabrica_canais.py
│   └── whatsapp/
│       ├── canal_whatsapp.py
│       └── formatador.py
└── utilitarios/
    ├── banco.py
    ├── deduplicacao.py
    └── afiliados.py
airflow/
└── dags/
    └── pipeline_whatpromo.py
```

---

## Etapa 1 — configuracao.py (ponto central)

Crie `/srv/whatpromo/raspador/configuracao.py`:

```python
# ================================================================
# WhatPromo — Configuração central do sistema
# Para adicionar categoria, loja ou canal: alterar APENAS este arquivo.
# Nenhuma outra parte do código precisa ser alterada.
# ================================================================

# Categorias válidas — valor usado no banco e na segmentação de grupos
CATEGORIAS_VALIDAS = [
    "eletronicos",
    "games",
    "casa_cozinha",
    "moda_calcados",
    "ferramentas",
    # Para adicionar nova categoria: incluir a string aqui
    # Exemplos: "esportes", "bebes", "pet", "livros"
]

# Emoji exibido na mensagem WhatsApp por categoria
EMOJI_POR_CATEGORIA = {
    "eletronicos":   "📱",
    "games":         "🎮",
    "casa_cozinha":  "🏠",
    "moda_calcados": "👟",
    "ferramentas":   "🔧",
}

# Lojas ativas — cada loja tem um arquivo correspondente em aranhas/
LOJAS_ATIVAS = [
    "mercado_livre",
    "shopee",
    # Para adicionar nova loja: incluir aqui e criar raspador/aranhas/nome.py
]

# Canais de distribuição ativos
CANAIS_ATIVOS = [
    "whatsapp",
    "telegram",
    # "instagram",  # descomentar quando implementar (Fase futura)
    # "twitter",    # descomentar quando implementar (Fase futura)
]

# Categoria padrão quando a loja não informa a categoria do produto
CATEGORIA_PADRAO = "eletronicos"

# Regras de qualidade (podem ser sobrescritas por grupo individualmente)
PONTUACAO_MINIMA_PADRAO = 7       # Score mínimo de 1-10 para aprovar oferta
DESCONTO_MINIMO_PADRAO  = 15      # Percentual mínimo de desconto
FATOR_FAKE_OFF          = 0.95    # Se preco_atual >= preco_minimo_30d * 0.95 → fake off
JANELA_DEDUP_HORAS      = 24      # Horas antes de reavaliar uma URL já vista
HORAS_ENVIO_INICIO      = 7       # Hora de início dos envios (07:00 Brasília)
HORAS_ENVIO_FIM         = 22      # Hora de fim dos envios (22:00 Brasília)
INTERVALO_MINIMO_GRUPO  = 180     # Segundos mínimos entre mensagens no mesmo grupo
```

**Por que um arquivo central?**
Sem ele, as constantes ficam espalhadas pelo código e quando você quiser
adicionar uma categoria nova vai precisar caçar em 5 arquivos diferentes.
Com ele, é uma linha e pronto.

---

## Etapa 2 — utilitarios/banco.py

Crie `/srv/whatpromo/raspador/utilitarios/banco.py`:

```python
# ================================================================
# WhatPromo — Utilitário de conexão com o banco de dados
# Centraliza a criação da engine e da sessão SQLAlchemy.
# Todo módulo que precisar do banco importa daqui.
# ================================================================

import os
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from dotenv import load_dotenv

load_dotenv()


def obter_url_conexao() -> str:
    """
    Monta a URL de conexão com o banco a partir das variáveis de ambiente.
    Usando PyMySQL como driver — puro Python, sem dependências nativas.
    """
    usuario  = os.getenv("BD_USUARIO")
    senha    = os.getenv("BD_SENHA")
    host     = os.getenv("BD_HOST", "localhost")
    porta    = os.getenv("BD_PORTA", "3306")
    nome     = os.getenv("BD_NOME", "whatpromo_db")
    return f"mysql+pymysql://{usuario}:{senha}@{host}:{porta}/{nome}?charset=utf8mb4"


# Engine compartilhada — criada uma vez, reutilizada em todas as conexões
# pool_pre_ping=True verifica se a conexão ainda está viva antes de usar
_motor = create_engine(obter_url_conexao(), pool_pre_ping=True, echo=False)
FabricaSessao = sessionmaker(bind=_motor)


def obter_sessao() -> Session:
    """
    Retorna uma sessão do banco pronta para uso.
    Usar sempre com 'with' para garantir o fechamento:

        with obter_sessao() as sessao:
            sessao.execute(...)
    """
    return FabricaSessao()


def executar_sql(consulta: str, parametros: dict = None) -> list:
    """
    Executa uma consulta SQL bruta e retorna os resultados como lista de dicts.
    Útil para consultas complexas que o ORM tornaria verboso.
    """
    with _motor.connect() as conexao:
        resultado = conexao.execute(text(consulta), parametros or {})
        return [dict(linha._mapping) for linha in resultado]
```

---

## Etapa 3 — utilitarios/deduplicacao.py

Crie `/srv/whatpromo/raspador/utilitarios/deduplicacao.py`:

```python
# ================================================================
# WhatPromo — Deduplicação de ofertas
# Evita enviar a mesma oferta duas vezes em menos de 24 horas.
# Usa SHA-256 da URL normalizada como chave única.
# ================================================================

import hashlib
import re
from datetime import datetime, timedelta
from urllib.parse import urlparse, urlencode, parse_qs, urlunparse

from raspador.utilitarios.banco import obter_sessao
from raspador.configuracao import JANELA_DEDUP_HORAS


# Parâmetros de rastreamento que devem ser removidos da URL
# antes de calcular o hash — eles mudam por afiliado mas a oferta é a mesma
PARAMETROS_RASTREAMENTO = {
    "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term",
    "ref", "referrer", "source", "aff_id", "affiliate", "tag",
}


def normalizar_url(url: str) -> str:
    """
    Remove parâmetros de rastreamento da URL.
    Garante que a mesma oferta de fontes diferentes gere o mesmo hash.

    Exemplo:
      Entrada: https://produto.com/item?id=123&utm_source=whatsapp&ref=promo
      Saída:   https://produto.com/item?id=123
    """
    partes = urlparse(url)
    parametros = parse_qs(partes.query, keep_blank_values=True)

    # Remove todos os parâmetros de rastreamento conhecidos
    parametros_limpos = {
        chave: valor
        for chave, valor in parametros.items()
        if chave.lower() not in PARAMETROS_RASTREAMENTO
    }

    url_limpa = urlunparse((
        partes.scheme, partes.netloc, partes.path,
        partes.params, urlencode(parametros_limpos, doseq=True), ""
    ))
    return url_limpa.rstrip("/")


def calcular_hash(url: str) -> str:
    """
    Calcula o SHA-256 da URL normalizada.
    Este hash é a chave de deduplicação na tabela ofertas.
    """
    url_normalizada = normalizar_url(url)
    return hashlib.sha256(url_normalizada.encode("utf-8")).hexdigest()


def ja_processada(hash_url: str) -> bool:
    """
    Verifica se uma oferta com este hash já foi processada
    dentro da janela de deduplicação (padrão: 24 horas).

    Retorna True se deve ser descartada, False se deve ser processada.
    """
    limite_tempo = datetime.now() - timedelta(hours=JANELA_DEDUP_HORAS)

    with obter_sessao() as sessao:
        resultado = sessao.execute(
            "SELECT id FROM ofertas WHERE hash_url = :hash AND raspado_em > :limite LIMIT 1",
            {"hash": hash_url, "limite": limite_tempo}
        ).fetchone()

    return resultado is not None


def registrar_historico_preco(hash_url: str, preco: float) -> None:
    """
    Registra o preço atual no histórico.
    Chamado SEMPRE, independente de a oferta ser aprovada ou rejeitada.
    É a base do sistema anti-fake-off.
    """
    with obter_sessao() as sessao:
        sessao.execute(
            "INSERT INTO historico_precos (hash_url, preco) VALUES (:hash, :preco)",
            {"hash": hash_url, "preco": preco}
        )
        sessao.commit()


def obter_preco_minimo_30d(hash_url: str) -> float | None:
    """
    Retorna o menor preço registrado nos últimos 30 dias para este produto.
    Retorna None se não há histórico (produto novo).
    """
    resultado = obter_sessao().execute(
        """
        SELECT MIN(preco) as preco_minimo
        FROM historico_precos
        WHERE hash_url = :hash
          AND registrado_em >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        """,
        {"hash": hash_url}
    ).fetchone()

    return float(resultado.preco_minimo) if resultado and resultado.preco_minimo else None
```

---

## Etapa 4 — ia/provedor_base.py

Crie `/srv/whatpromo/raspador/ia/provedor_base.py`:

```python
# ================================================================
# WhatPromo — Contrato do provedor de IA
# Todo provedor (Groq, Claude, OpenAI) deve implementar esta interface.
# O pipeline nunca importa um provedor diretamente — usa a fábrica.
# ================================================================

from abc import ABC, abstractmethod


class ProvedorBase(ABC):
    """
    Define o contrato que todo provedor de IA deve seguir.
    Isso garante que trocar de Groq para Claude seja apenas
    alterar PROVEDOR_IA no .env, sem tocar no pipeline.
    """

    @abstractmethod
    def pontuar_oferta(self, oferta: dict) -> int:
        """
        Avalia a qualidade de uma oferta e retorna um score de 1 a 10.

        Parâmetros do dict oferta:
          - titulo (str): nome do produto
          - loja (str): mercado_livre | shopee
          - preco_original (float)
          - preco_promocional (float)
          - percentual_desconto (int)
          - categoria (str)

        Retorna int de 1 a 10.
        Lança ValueError se a resposta da IA não for um número válido.
        """
        ...

    @abstractmethod
    def gerar_mensagem(self, oferta: dict) -> str:
        """
        Gera o texto criativo da mensagem WhatsApp/Telegram.
        A IA retorna APENAS chamada_curta e urgencia em JSON.
        O código monta o restante da mensagem com os dados do banco.

        Parâmetros adicionais no dict oferta (além dos de pontuar_oferta):
          - url_curta (str): link encurtado da oferta
          - cupom (str | None): cupom de desconto se houver

        Retorna str com a mensagem completa formatada em Markdown WhatsApp.
        """
        ...
```

---

## Etapa 5 — ia/provedor_groq.py

Crie `/srv/whatpromo/raspador/ia/provedor_groq.py`:

```python
# ================================================================
# WhatPromo — Provedor de IA: Groq
# Usa o modelo Llama 3.3 70B via API da Groq Cloud (gratuita).
# É o provedor padrão do MVP — custo zero, qualidade boa em PT-BR.
# ================================================================

import os
import json
from groq import Groq
from raspador.ia.provedor_base import ProvedorBase
from raspador.configuracao import EMOJI_POR_CATEGORIA


class ProvedorGroq(ProvedorBase):
    """
    Implementação do provedor usando Groq Cloud.
    Requer CHAVE_API_GROQ no .env.
    """

    def __init__(self):
        # O cliente Groq lê GROQ_API_KEY automaticamente — mapeamos
        # nossa variável CHAVE_API_GROQ para o nome esperado pela lib
        os.environ["GROQ_API_KEY"] = os.getenv("CHAVE_API_GROQ", "")
        self.cliente = Groq()
        self.modelo  = "llama-3.3-70b-versatile"

    def pontuar_oferta(self, oferta: dict) -> int:
        """
        Pede à IA um score de 1-10 para a oferta.
        A resposta deve ser APENAS o número — qualquer texto extra levanta erro.
        """
        prompt = self._prompt_pontuacao(oferta)

        resposta = self.cliente.chat.completions.create(
            model=self.modelo,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=10,       # Score é só 1-2 dígitos, não precisa de mais
            temperature=0.1,     # Baixa aleatoriedade — queremos resultado consistente
        )

        texto = resposta.choices[0].message.content.strip()

        try:
            score = int(texto)
            if not 1 <= score <= 10:
                raise ValueError(f"Score fora do intervalo: {score}")
            return score
        except (ValueError, TypeError) as erro:
            raise ValueError(f"Groq retornou score inválido '{texto}': {erro}")

    def gerar_mensagem(self, oferta: dict) -> str:
        """
        Pede à IA apenas chamada_curta e urgencia em JSON.
        Monta a mensagem completa com os dados reais do banco.
        """
        prompt = self._prompt_mensagem(oferta)

        resposta = self.cliente.chat.completions.create(
            model=self.modelo,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=150,
            temperature=0.7,     # Um pouco mais criativo para o texto
        )

        texto = resposta.choices[0].message.content.strip()

        try:
            dados = json.loads(texto)
            chamada  = dados.get("chamada_curta", "OFERTA IMPERDÍVEL")[:40].upper()
            urgencia = dados.get("urgencia", "Corra, oferta por tempo limitado!")[:50]
        except (json.JSONDecodeError, KeyError):
            # Fallback seguro se a IA não retornar JSON válido
            chamada  = "OFERTA IMPERDÍVEL"
            urgencia = "Corra, oferta por tempo limitado!"

        return self._montar_mensagem(oferta, chamada, urgencia)

    def _prompt_pontuacao(self, oferta: dict) -> str:
        return f"""Avalie esta oferta de 1 a 10. Responda APENAS com o número inteiro, nada mais.

Critérios:
- 9-10: desconto excepcional (>50%), produto muito procurado, loja confiável
- 7-8:  bom desconto (30-50%), produto relevante
- 5-6:  desconto razoável (20-30%)
- 1-4:  desconto baixo ou produto pouco relevante

Oferta:
Produto: {oferta['titulo']}
Loja: {oferta['loja']}
Desconto: {oferta['percentual_desconto']}%
Preço original: R$ {oferta['preco_original']:.2f}
Preço promocional: R$ {oferta['preco_promocional']:.2f}
Categoria: {oferta['categoria']}"""

    def _prompt_mensagem(self, oferta: dict) -> str:
        return f"""Você é copywriter de um canal de ofertas brasileiro no WhatsApp.
Gere APENAS um JSON com dois campos, nada mais além do JSON:

{{
  "chamada_curta": "máximo 40 caracteres, CAIXA ALTA, sem emoji, impactante",
  "urgencia": "máximo 50 caracteres, senso de urgência real, sem inventar dados"
}}

Produto: {oferta['titulo']}
Loja: {oferta['loja']}
Desconto: {oferta['percentual_desconto']}%
Categoria: {oferta['categoria']}"""

    def _montar_mensagem(self, oferta: dict, chamada: str, urgencia: str) -> str:
        """
        Monta a mensagem final com os dados reais.
        A IA gera só o texto criativo — os números e links vêm do banco.
        Isso evita que a IA invente preços ou links errados.
        """
        emoji    = EMOJI_POR_CATEGORIA.get(oferta.get("categoria", ""), "🛍️")
        economia = oferta['preco_original'] - oferta['preco_promocional']
        url      = oferta.get("url_curta") or oferta.get("url_afiliado") or oferta.get("url_original")

        linhas = [
            f"{emoji} *{chamada}*",
            "",
            f"🛍️ *{oferta['titulo']}*",
            f"🏪 {oferta['loja'].replace('_', ' ').title()}",
            "",
            f"~~R$ {oferta['preco_original']:.2f}~~ → *R$ {oferta['preco_promocional']:.2f}*",
            f"💰 Economia de R$ {economia:.2f} ({oferta['percentual_desconto']}% OFF)",
        ]

        # Adiciona linha do cupom apenas se existir
        if oferta.get("cupom"):
            linhas += ["", f"🎟️ Cupom: `{oferta['cupom']}`"]

        linhas += ["", f"🔗 {url}", "", f"⏰ _{urgencia}_"]

        return "\n".join(linhas)
```

---

## Etapa 6 — ia/fabrica.py

Crie `/srv/whatpromo/raspador/ia/fabrica.py`:

```python
# ================================================================
# WhatPromo — Fábrica de provedores de IA
# Lê PROVEDOR_IA do .env e retorna a instância correta.
# O pipeline nunca importa um provedor diretamente — usa esta função.
# ================================================================

import os
from raspador.ia.provedor_base import ProvedorBase


def obter_provedor_ia() -> ProvedorBase:
    """
    Retorna o provedor de IA configurado em PROVEDOR_IA no .env.
    Padrão: groq (gratuito, sem custo por requisição).

    Para trocar de provedor: alterar PROVEDOR_IA no .env e reiniciar
    o scheduler do Airflow. Nenhum código precisa ser alterado.
    """
    # Importações locais para evitar erros se a lib não estiver instalada
    provedor = os.getenv("PROVEDOR_IA", "groq").lower().strip()

    match provedor:
        case "groq":
            from raspador.ia.provedor_groq import ProvedorGroq
            return ProvedorGroq()

        case "claude":
            from raspador.ia.provedor_claude import ProvedorClaude
            return ProvedorClaude()

        case "openai":
            from raspador.ia.provedor_openai import ProvedorOpenAI
            return ProvedorOpenAI()

        case _:
            raise ValueError(
                f"Provedor de IA desconhecido: '{provedor}'. "
                f"Valores aceitos: groq | claude | openai"
            )
```

---

## Etapa 7 — aranhas/aranha_base.py

Crie `/srv/whatpromo/raspador/aranhas/aranha_base.py`:

```python
# ================================================================
# WhatPromo — Classe base para raspadores de lojas
# Todo raspador herda desta classe e implementa raspar() e normalizar_oferta().
# O pipeline chama apenas raspar() — não conhece a implementação de cada loja.
# ================================================================

from abc import ABC, abstractmethod
from playwright.sync_api import sync_playwright, Browser, Page
import logging

logger = logging.getLogger(__name__)


class AranhaBase(ABC):
    """
    Contrato que todo raspador de loja deve seguir.
    Cada loja tem seu próprio arquivo em raspador/aranhas/.
    """

    # Configurações padrão do navegador — podem ser sobrescritas por loja
    TEMPO_LIMITE_MS  = 30_000   # 30 segundos por página
    DELAY_MINIMO_MS  = 1_000    # Delay mínimo entre requisições
    DELAY_MAXIMO_MS  = 3_000    # Delay máximo entre requisições

    # User-agent realista para evitar bloqueio
    AGENTE_USUARIO = (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )

    @property
    @abstractmethod
    def nome(self) -> str:
        """Identificador da loja. Ex: 'mercado_livre', 'shopee'"""
        ...

    @abstractmethod
    def raspar(self) -> list[dict]:
        """
        Raspa as ofertas da loja e retorna lista de dicts normalizados.
        Cada dict deve conter os campos de normalizar_oferta().
        """
        ...

    @abstractmethod
    def normalizar_oferta(self, dado_bruto: dict) -> dict | None:
        """
        Converte o dado bruto da loja para o formato padrão do WhatPromo.
        Retorna None se o dado não tem informações suficientes.

        Formato de saída obrigatório:
        {
            "titulo": str,
            "loja": str,             # nome da loja (self.nome)
            "categoria": str,        # deve estar em CATEGORIAS_VALIDAS
            "preco_original": float,
            "preco_promocional": float,
            "percentual_desconto": int,
            "url_original": str,
            "cupom": str | None,
        }
        """
        ...

    def criar_navegador(self) -> tuple[Browser, Page]:
        """
        Cria e configura o navegador Playwright.
        Reutilizar este método garante configuração consistente entre lojas.
        """
        playwright = sync_playwright().start()
        navegador = playwright.chromium.launch(
            headless=True,       # Sem interface gráfica no servidor
            args=["--no-sandbox", "--disable-dev-shm-usage"],
        )
        pagina = navegador.new_page(
            user_agent=self.AGENTE_USUARIO,
            viewport={"width": 1280, "height": 720},
        )
        pagina.set_default_timeout(self.TEMPO_LIMITE_MS)
        return navegador, pagina

    def calcular_desconto(self, preco_original: float, preco_promocional: float) -> int:
        """Calcula o percentual de desconto de forma segura."""
        if preco_original <= 0:
            return 0
        desconto = ((preco_original - preco_promocional) / preco_original) * 100
        return max(0, min(100, round(desconto)))
```

---

## Etapa 8 — canais/canal_base.py

Crie `/srv/whatpromo/raspador/canais/canal_base.py`:

```python
# ================================================================
# WhatPromo — Contrato do canal de distribuição
# Todo canal (WhatsApp, Telegram, Instagram, Twitter) deve seguir esta interface.
# ================================================================

from abc import ABC, abstractmethod


class CanalBase(ABC):
    """
    Define o contrato que todo canal de distribuição deve seguir.
    Adicionar novo canal = criar uma classe que herda CanalBase.
    O pipeline nunca importa um canal diretamente — usa a fábrica.
    """

    @property
    @abstractmethod
    def nome(self) -> str:
        """
        Identificador do canal para logs e registros na tabela disparos.
        Exemplos: 'whatsapp', 'telegram', 'instagram_feed', 'twitter'
        """
        ...

    @abstractmethod
    def publicar(self, oferta: dict, grupo: dict) -> dict:
        """
        Publica a oferta no canal para o grupo especificado.

        Parâmetros:
          oferta: dict com todos os campos da tabela ofertas
          grupo:  dict com os campos da tabela grupos

        Retorna dict com:
          {
            "sucesso": bool,
            "id_publicacao": str | None,  # ID retornado pela API do canal
            "erro": str | None,           # Mensagem de erro se sucesso=False
          }
        """
        ...
```

---

## Etapa 9 — canais/fabrica_canais.py

Crie `/srv/whatpromo/raspador/canais/fabrica_canais.py`:

```python
# ================================================================
# WhatPromo — Fábrica de canais de distribuição
# Retorna instâncias de todos os canais definidos em CANAIS_ATIVOS.
# ================================================================

from raspador.configuracao import CANAIS_ATIVOS
from raspador.canais.canal_base import CanalBase


def obter_canais_ativos() -> list[CanalBase]:
    """
    Retorna lista com instâncias de todos os canais ativos.
    Para ativar/desativar canal: alterar CANAIS_ATIVOS em configuracao.py.
    """
    from raspador.canais.whatsapp.canal_whatsapp import CanalWhatsApp
    from raspador.canais.telegram.canal_telegram import CanalTelegram
    # from raspador.canais.instagram.canal_instagram import CanalInstagram
    # from raspador.canais.twitter.canal_twitter import CanalTwitter

    mapa_canais = {
        "whatsapp": CanalWhatsApp,
        "telegram": CanalTelegram,
        # "instagram": CanalInstagram,
        # "twitter":   CanalTwitter,
    }

    return [
        mapa_canais[nome]()
        for nome in CANAIS_ATIVOS
        if nome in mapa_canais
    ]
```

---

## Etapa 10 — DAG principal (pipeline_whatpromo.py)

Crie `/srv/whatpromo/airflow/dags/pipeline_whatpromo.py`:

```python
# ================================================================
# WhatPromo — DAG principal do pipeline de ofertas
# Executa a cada 30 minutos entre 07h e 22h (horário de Brasília).
# 5 tasks em sequência: raspar → validar → pontuar → links → disparar
# ================================================================

from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator
import logging
import os
import sys

# Adiciona o diretório do raspador ao path para importações funcionarem
sys.path.insert(0, "/opt/airflow")

logger = logging.getLogger(__name__)

# ----------------------------------------------------------------
# Configuração da DAG
# ----------------------------------------------------------------
argumentos_padrao = {
    "owner":            "whatpromo",
    "retries":          2,           # Tenta 2x antes de marcar como falha
    "retry_delay":      300,         # Aguarda 5 minutos entre tentativas
    "email_on_failure": True,
    "email":            [os.getenv("EMAIL_ADMIN", "")],
}

dag = DAG(
    dag_id="pipeline_whatpromo",
    description="Pipeline completo: raspar → validar → pontuar IA → links afiliado → disparar",
    schedule_interval="*/30 7-22 * * *",  # A cada 30min das 07h às 22h
    start_date=datetime(2024, 1, 1),
    catchup=False,                         # Não executa runs atrasadas
    default_args=argumentos_padrao,
    tags=["whatpromo", "producao"],
)

# ----------------------------------------------------------------
# Task 1: raspar_lojas
# ----------------------------------------------------------------
def tarefa_raspar_lojas(**contexto):
    """
    Raspa ofertas de todas as lojas ativas (LOJAS_ATIVAS em configuracao.py).
    Cada loja roda de forma independente — falha em uma não para as outras.
    Salva ofertas novas no banco com status='pendente'.
    """
    from raspador.configuracao import LOJAS_ATIVAS
    from raspador.utilitarios.deduplicacao import (
        calcular_hash, ja_processada, registrar_historico_preco
    )
    from raspador.utilitarios.banco import obter_sessao

    total_novas = 0

    for nome_loja in LOJAS_ATIVAS:
        try:
            # Importa dinamicamente o raspador da loja
            modulo = __import__(
                f"raspador.aranhas.{nome_loja}",
                fromlist=["obter_aranha"]
            )
            aranha = modulo.obter_aranha()
            ofertas_brutas = aranha.raspar()

            logger.info(f"[{nome_loja}] {len(ofertas_brutas)} ofertas coletadas")

            for oferta in ofertas_brutas:
                hash_url = calcular_hash(oferta["url_original"])

                # Registra no histórico SEMPRE (base do anti-fake-off)
                registrar_historico_preco(hash_url, oferta["preco_promocional"])

                # Descarta se já processou nas últimas 24h
                if ja_processada(hash_url):
                    continue

                # Salva oferta nova com status pendente
                with obter_sessao() as sessao:
                    sessao.execute("""
                        INSERT INTO ofertas
                            (hash_url, titulo, loja, categoria, preco_original,
                             preco_promocional, percentual_desconto, cupom, url_original)
                        VALUES
                            (:hash, :titulo, :loja, :categoria, :preco_original,
                             :preco_promocional, :percentual_desconto, :cupom, :url_original)
                    """, {**oferta, "hash": hash_url})
                    sessao.commit()
                    total_novas += 1

        except Exception as erro:
            logger.error(f"[{nome_loja}] Falha ao raspar: {erro}", exc_info=True)
            # Continua para a próxima loja — falha isolada

    logger.info(f"Total de ofertas novas salvas: {total_novas}")
    return total_novas


# ----------------------------------------------------------------
# Task 2: validar_ofertas
# ----------------------------------------------------------------
def tarefa_validar_ofertas(**contexto):
    """
    Aplica os filtros de qualidade nas ofertas pendentes:
    - Desconto mínimo (RN-02)
    - Anti-fake-off comparando com histórico de preços (RN-03)
    - Categoria válida (RN-01)
    """
    from raspador.configuracao import (
        CATEGORIAS_VALIDAS, DESCONTO_MINIMO_PADRAO, FATOR_FAKE_OFF
    )
    from raspador.utilitarios.deduplicacao import obter_preco_minimo_30d
    from raspador.utilitarios.banco import obter_sessao

    with obter_sessao() as sessao:
        pendentes = sessao.execute(
            "SELECT * FROM ofertas WHERE status = 'pendente'"
        ).fetchall()

    aprovadas = rejeitadas = 0

    for oferta in pendentes:
        oferta = dict(oferta._mapping)
        motivo = None

        # Verificação 1: desconto mínimo
        if oferta["percentual_desconto"] < DESCONTO_MINIMO_PADRAO:
            motivo = "desconto_insuficiente"

        # Verificação 2: anti-fake-off
        elif oferta.get("preco_minimo_30d"):
            limite = oferta["preco_minimo_30d"] * FATOR_FAKE_OFF
            if oferta["preco_promocional"] >= limite:
                motivo = "fake_off"

        # Verificação 3: categoria válida
        elif oferta["categoria"] not in CATEGORIAS_VALIDAS:
            motivo = "categoria_invalida"

        novo_status = "rejeitada" if motivo else "aprovada"

        with obter_sessao() as sessao:
            sessao.execute(
                """UPDATE ofertas SET status = :status, motivo_rejeicao = :motivo
                   WHERE id = :id""",
                {"status": novo_status, "motivo": motivo, "id": oferta["id"]}
            )
            sessao.commit()

        if motivo:
            rejeitadas += 1
            logger.info(f"Oferta {oferta['id']} rejeitada: {motivo}")
        else:
            aprovadas += 1

    logger.info(f"Validação: {aprovadas} aprovadas, {rejeitadas} rejeitadas")


# ----------------------------------------------------------------
# Task 3: pontuar_com_ia
# ----------------------------------------------------------------
def tarefa_pontuar_com_ia(**contexto):
    """
    Usa o provedor de IA (definido em PROVEDOR_IA no .env) para
    pontuar cada oferta aprovada e gerar o texto da mensagem.
    """
    from raspador.ia.fabrica import obter_provedor_ia
    from raspador.utilitarios.banco import obter_sessao
    from raspador.configuracao import PONTUACAO_MINIMA_PADRAO

    ia = obter_provedor_ia()
    provedor_nome = os.getenv("PROVEDOR_IA", "groq")

    with obter_sessao() as sessao:
        aprovadas = sessao.execute(
            "SELECT * FROM ofertas WHERE status = 'aprovada'"
        ).fetchall()

    for oferta in aprovadas:
        oferta = dict(oferta._mapping)
        try:
            pontuacao = ia.pontuar_oferta(oferta)

            if pontuacao < PONTUACAO_MINIMA_PADRAO:
                with obter_sessao() as sessao:
                    sessao.execute(
                        """UPDATE ofertas SET status='rejeitada',
                           motivo_rejeicao='pontuacao_baixa',
                           pontuacao_ia=:score, provedor_ia=:provedor
                           WHERE id=:id""",
                        {"score": pontuacao, "provedor": provedor_nome, "id": oferta["id"]}
                    )
                    sessao.commit()
                continue

            mensagem = ia.gerar_mensagem(oferta)

            with obter_sessao() as sessao:
                sessao.execute(
                    """UPDATE ofertas SET pontuacao_ia=:score,
                       provedor_ia=:provedor, mensagem_wa=:mensagem
                       WHERE id=:id""",
                    {"score": pontuacao, "provedor": provedor_nome,
                     "mensagem": mensagem, "id": oferta["id"]}
                )
                sessao.commit()

        except Exception as erro:
            logger.error(f"Erro ao pontuar oferta {oferta['id']}: {erro}")
            # Oferta fica como 'aprovada' e será reavaliada na próxima execução


# ----------------------------------------------------------------
# Task 4: gerar_links_afiliado
# ----------------------------------------------------------------
def tarefa_gerar_links_afiliado(**contexto):
    """
    Converte as URLs originais em links de afiliado e depois encurta.
    Fallback: se afiliado falhar → usa url_original
              se encurtador falhar → usa url_afiliado
    """
    from raspador.utilitarios.afiliados import gerar_link_afiliado, encurtar_url
    from raspador.utilitarios.banco import obter_sessao

    with obter_sessao() as sessao:
        ofertas = sessao.execute(
            "SELECT * FROM ofertas WHERE mensagem_wa IS NOT NULL AND url_afiliado IS NULL"
        ).fetchall()

    for oferta in ofertas:
        oferta = dict(oferta._mapping)

        url_afiliado = gerar_link_afiliado(oferta["url_original"], oferta["loja"])
        url_curta    = encurtar_url(url_afiliado or oferta["url_original"])

        with obter_sessao() as sessao:
            sessao.execute(
                "UPDATE ofertas SET url_afiliado=:af, url_curta=:curta WHERE id=:id",
                {"af": url_afiliado, "curta": url_curta, "id": oferta["id"]}
            )
            sessao.commit()


# ----------------------------------------------------------------
# Task 5: disparar
# ----------------------------------------------------------------
def tarefa_disparar(**contexto):
    """
    Publica cada oferta pronta em todos os canais ativos.
    Verifica rate limit, horário e critérios do grupo antes de cada envio.
    Uma falha em um canal não impede os outros.
    """
    from raspador.canais.fabrica_canais import obter_canais_ativos
    from raspador.utilitarios.banco import obter_sessao
    from datetime import datetime
    import pytz

    fuso_brasilia = pytz.timezone("America/Sao_Paulo")
    hora_atual = datetime.now(fuso_brasilia).hour

    from raspador.configuracao import HORAS_ENVIO_INICIO, HORAS_ENVIO_FIM
    if not (HORAS_ENVIO_INICIO <= hora_atual < HORAS_ENVIO_FIM):
        logger.info(f"Fora do horário de envio ({hora_atual}h). Pulando.")
        return

    canais = obter_canais_ativos()

    with obter_sessao() as sessao:
        ofertas = sessao.execute(
            "SELECT * FROM ofertas WHERE url_curta IS NOT NULL AND status = 'aprovada'"
        ).fetchall()
        grupos = sessao.execute(
            "SELECT * FROM grupos WHERE ativo = TRUE"
        ).fetchall()

    for oferta in ofertas:
        oferta = dict(oferta._mapping)
        enviada = False

        for canal in canais:
            grupos_canal = [
                dict(g._mapping) for g in grupos
                if dict(g._mapping).get("canal", "whatsapp") == canal.nome
            ]

            for grupo in grupos_canal:
                import json
                categorias_grupo = json.loads(grupo["categorias"])
                aceita_categoria = (
                    "*" in categorias_grupo or
                    oferta["categoria"] in categorias_grupo
                )
                if not aceita_categoria:
                    continue
                if oferta["pontuacao_ia"] < grupo["pontuacao_minima"]:
                    continue
                if oferta["percentual_desconto"] < grupo["desconto_minimo"]:
                    continue

                try:
                    resultado = canal.publicar(oferta, grupo)

                    with obter_sessao() as sessao:
                        sessao.execute("""
                            INSERT INTO disparos
                                (oferta_id, grupo_id, canal, id_publicacao, status, erro)
                            VALUES
                                (:oferta_id, :grupo_id, :canal, :id_pub, :status, :erro)
                        """, {
                            "oferta_id": oferta["id"],
                            "grupo_id":  grupo["id"],
                            "canal":     canal.nome,
                            "id_pub":    resultado.get("id_publicacao"),
                            "status":    "sucesso" if resultado["sucesso"] else "falhou",
                            "erro":      resultado.get("erro"),
                        })
                        sessao.commit()

                    if resultado["sucesso"]:
                        enviada = True

                except Exception as erro:
                    logger.error(
                        f"Erro ao disparar oferta {oferta['id']} no canal {canal.nome}: {erro}"
                    )

        if enviada:
            with obter_sessao() as sessao:
                sessao.execute(
                    "UPDATE ofertas SET status='enviada', enviado_em=NOW() WHERE id=:id",
                    {"id": oferta["id"]}
                )
                sessao.commit()


# ----------------------------------------------------------------
# Definição das tasks e ordem de execução
# ----------------------------------------------------------------
task_raspar = PythonOperator(
    task_id="raspar_lojas",
    python_callable=tarefa_raspar_lojas,
    dag=dag,
)

task_validar = PythonOperator(
    task_id="validar_ofertas",
    python_callable=tarefa_validar_ofertas,
    dag=dag,
)

task_pontuar = PythonOperator(
    task_id="pontuar_com_ia",
    python_callable=tarefa_pontuar_com_ia,
    dag=dag,
)

task_links = PythonOperator(
    task_id="gerar_links_afiliado",
    python_callable=tarefa_gerar_links_afiliado,
    dag=dag,
)

task_disparar = PythonOperator(
    task_id="disparar",
    python_callable=tarefa_disparar,
    dag=dag,
)

# Define a ordem: cada task só inicia após a anterior concluir
task_raspar >> task_validar >> task_pontuar >> task_links >> task_disparar
```

---

## Etapa 11 — Instalar dependências Python no Airflow

```bash
# Instala as dependências dentro dos containers do Airflow
docker exec whatpromo_airflow_web pip install -r /opt/airflow/raspador/requirements.txt
docker exec whatpromo_airflow_scheduler pip install -r /opt/airflow/raspador/requirements.txt

# Instala o browser do Playwright (necessário uma única vez)
docker exec whatpromo_airflow_web playwright install chromium
docker exec whatpromo_airflow_scheduler playwright install chromium
```

---

## Etapa 12 — Ativar a DAG no Airflow

1. Acesse `http://localhost:8081`
2. Localize `pipeline_whatpromo` na lista
3. Clique no toggle para **ativar** a DAG
4. Para testar manualmente: clique em ▶️ (Trigger DAG)
5. Acompanhe a execução clicando no nome da DAG → Graph View

---

## Checklist final da Fase 2

- [ ] `raspador/configuracao.py` criado
- [ ] `raspador/utilitarios/banco.py` criado
- [ ] `raspador/utilitarios/deduplicacao.py` criado
- [ ] `raspador/ia/provedor_base.py` criado
- [ ] `raspador/ia/provedor_groq.py` criado
- [ ] `raspador/ia/fabrica.py` criado
- [ ] `raspador/aranhas/aranha_base.py` criado
- [ ] `raspador/canais/canal_base.py` criado
- [ ] `raspador/canais/fabrica_canais.py` criado
- [ ] `airflow/dags/pipeline_whatpromo.py` criado
- [ ] Dependências instaladas nos containers do Airflow
- [ ] Playwright instalado nos containers
- [ ] DAG visível e ativa no Airflow UI
- [ ] Primeiro teste manual executado sem erros críticos
- [ ] Ofertas aparecendo na tabela `ofertas` do banco
- [ ] Mensagem de teste chegando no WhatsApp/Telegram

**Fase 2 concluída → MVP funcionando → partir para a Fase 3 (Bot Telegram de controle)**
