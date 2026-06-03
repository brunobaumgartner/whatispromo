-- =============================================================
-- WhatPromo — Migration 001: criação das tabelas
-- Executar dentro do container: docker exec -i whatpromo_banco
-- =============================================================

CREATE DATABASE IF NOT EXISTS whatpromo_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE whatpromo_db;

-- -------------------------------------------------------------
-- Tabela: ofertas
-- Registro central de cada oferta raspada.
-- hash_url evita duplicatas da mesma URL entre execuções.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ofertas (
    id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hash_url             CHAR(64) NOT NULL UNIQUE COMMENT 'SHA-256 da URL sem parâmetros de rastreamento',
    titulo               VARCHAR(500) NOT NULL,
    loja                 VARCHAR(50) NOT NULL COMMENT 'mercado_livre | shopee',
    categoria            VARCHAR(50) NOT NULL,
    preco_original       DECIMAL(10,2) NOT NULL,
    preco_promocional    DECIMAL(10,2) NOT NULL,
    percentual_desconto  DECIMAL(5,2) NOT NULL,
    cupom                VARCHAR(100) NULL,
    url_original         TEXT NOT NULL,
    url_afiliado         TEXT NULL,
    url_curta            VARCHAR(255) NULL,
    pontuacao_ia         TINYINT UNSIGNED NULL COMMENT '1 a 10',
    provedor_ia          VARCHAR(20) NULL COMMENT 'groq | claude | openai',
    mensagem_wa          TEXT NULL COMMENT 'Mensagem formatada para WhatsApp/Telegram',
    status               ENUM('pendente','aprovada','rejeitada','enviada','expirada')
                         NOT NULL DEFAULT 'pendente',
    motivo_rejeicao      ENUM('desconto_insuficiente','fake_off','categoria_invalida','pontuacao_baixa')
                         NULL,
    preco_minimo_30d     DECIMAL(10,2) NULL COMMENT 'Menor preço registrado nos últimos 30 dias',
    raspado_em           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    enviado_em           DATETIME NULL,
    expira_em            DATETIME NULL,
    INDEX idx_status     (status),
    INDEX idx_loja       (loja),
    INDEX idx_categoria  (categoria),
    INDEX idx_raspado_em (raspado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- Tabela: grupos
-- Grupos de WhatsApp e Telegram que recebem as ofertas.
-- categorias em JSON permite filtrar por nicho sem join.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS grupos (
    id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_grupo_wa       VARCHAR(100) NOT NULL COMMENT 'ID do grupo no WhatsApp ou Telegram',
    nome              VARCHAR(200) NOT NULL,
    canal             ENUM('whatsapp','telegram') NOT NULL,
    categorias        JSON NOT NULL COMMENT 'Ex: [eletronicos,games]',
    pontuacao_minima  TINYINT UNSIGNED NOT NULL DEFAULT 7,
    desconto_minimo   DECIMAL(5,2) NOT NULL DEFAULT 15.00,
    maximo_por_hora   TINYINT UNSIGNED NOT NULL DEFAULT 5,
    ativo             BOOLEAN NOT NULL DEFAULT TRUE,
    plano             ENUM('gratuito','premium') NOT NULL DEFAULT 'gratuito',
    criado_em         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_canal   (canal),
    INDEX idx_ativo   (ativo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- Tabela: disparos
-- Registro de cada envio de oferta para um canal/grupo.
-- grupo_id nullable pois futuramente pode haver canais sem grupo.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS disparos (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    oferta_id      INT UNSIGNED NOT NULL,
    grupo_id       INT UNSIGNED NULL,
    canal          ENUM('whatsapp','telegram','instagram_feed','instagram_story','twitter')
                   NOT NULL,
    id_publicacao  VARCHAR(255) NULL COMMENT 'ID da mensagem retornado pelo canal',
    disparado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cliques        INT UNSIGNED NOT NULL DEFAULT 0,
    status         ENUM('sucesso','falha') NOT NULL DEFAULT 'sucesso',
    erro           TEXT NULL,
    FOREIGN KEY (oferta_id) REFERENCES ofertas(id) ON DELETE CASCADE,
    FOREIGN KEY (grupo_id)  REFERENCES grupos(id)  ON DELETE SET NULL,
    INDEX idx_oferta_id   (oferta_id),
    INDEX idx_disparado_em (disparado_em),
    INDEX idx_canal        (canal)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -------------------------------------------------------------
-- Tabela: historico_precos
-- Série temporal de preços por URL — base para detectar fake-off.
-- Gravada sempre, mesmo quando a oferta é descartada por duplicata.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS historico_precos (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    hash_url      CHAR(64) NOT NULL,
    preco         DECIMAL(10,2) NOT NULL,
    registrado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hash_url      (hash_url),
    INDEX idx_registrado_em (registrado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
