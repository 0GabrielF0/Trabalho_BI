-- =====================================================================
-- PROJETO FINAL BI - DATA WAREHOUSE RH
-- Disciplina: Business Intelligence - CEUB
-- Dataset: Hr1m.csv (1 milhão de funcionários - Kaggle)
-- =====================================================================
-- Estrutura:
--   repositorio  -> dados brutos (staging)
--   dw           -> modelo estrela (1 fato + 6 dimensões)
--   datamart     -> views analíticas para Power BI
--   security     -> views e perfis de acesso (controle de permissão)
-- =====================================================================

-- Limpeza para permitir reexecução do script sem duplicar dados
DROP SCHEMA IF EXISTS datamart CASCADE;
DROP SCHEMA IF EXISTS security CASCADE;
DROP SCHEMA IF EXISTS dw CASCADE;
DROP SCHEMA IF EXISTS repositorio CASCADE;

CREATE SCHEMA repositorio;
CREATE SCHEMA dw;
CREATE SCHEMA datamart;
CREATE SCHEMA security;


-- =====================================================================
-- 1. CAMADA DE DADOS BRUTOS (STAGING)
-- =====================================================================
-- Tabela espelho do CSV: todos os campos como TEXT (sem transformação).
-- Tipagem e limpeza só acontecem no ETL para a camada DW.
-- =====================================================================

CREATE TABLE repositorio.rh_raw (
    emp_id                  TEXT,
    name_prefix             TEXT,
    first_name              TEXT,
    middle_initial          TEXT,
    last_name               TEXT,
    gender                  TEXT,
    email                   TEXT,
    fathers_name            TEXT,
    mothers_name            TEXT,
    mothers_maiden_name     TEXT,
    date_of_birth           TEXT,
    time_of_birth           TEXT,
    age_in_yrs              TEXT,
    weight_in_kgs           TEXT,
    date_of_joining         TEXT,
    quarter_of_joining      TEXT,
    half_of_joining         TEXT,
    year_of_joining         TEXT,
    month_of_joining        TEXT,
    month_name_of_joining   TEXT,
    short_month             TEXT,
    day_of_joining          TEXT,
    dow_of_joining          TEXT,
    short_dow               TEXT,
    age_in_company          TEXT,
    salary                  TEXT,
    last_hike_percent       TEXT,
    ssn                     TEXT,
    phone                   TEXT,
    place_name              TEXT,
    county                  TEXT,
    city                    TEXT,
    state                   TEXT,
    zip                     TEXT,
    region                  TEXT,
    user_name               TEXT,
    password                TEXT
);

-- Carga do CSV.

COPY repositorio.rh_raw FROM 'C:/Users/Public/Hr1m.csv' DELIMITER ',' CSV HEADER;


-- =====================================================================
-- 2. DATA WAREHOUSE - MODELO ESTRELA
-- =====================================================================
-- Granularidade da fato: 1 linha por funcionário (snapshot de admissão).
--
-- Conceitos avançados aplicados:
--   [1] DIMENSÃO TEMPO       -> dim_tempo enriquecida (trimestre, semestre,
--                               nome do mês, dia da semana, fim de semana)
--   [2] ROLE-PLAYING         -> dim_tempo referenciada 2x na fato
--                               (admissão e nascimento)
--   [3] SNOWFLAKE             -> dim_localizacao -> dim_estado -> dim_pais
--   [4] DIMENSÃO DEGENERADA   -> emp_id armazenado diretamente na fato
-- =====================================================================

-- ----- DIMENSÕES SNOWFLAKE: LOCALIZAÇÃO -----

CREATE TABLE dw.dim_pais (
    pais_id     SERIAL PRIMARY KEY,
    country     TEXT NOT NULL UNIQUE
);

CREATE TABLE dw.dim_estado (
    estado_id   SERIAL PRIMARY KEY,
    state       TEXT NOT NULL,
    pais_id     INT NOT NULL REFERENCES dw.dim_pais(pais_id),
    UNIQUE (state, pais_id)
);

CREATE TABLE dw.dim_localizacao (
    localizacao_id  SERIAL PRIMARY KEY,
    city            TEXT NOT NULL,
    region          TEXT,
    estado_id       INT NOT NULL REFERENCES dw.dim_estado(estado_id),
    UNIQUE (city, estado_id)
);

-- ----- DIMENSÃO FUNCIONÁRIO -----

CREATE TABLE dw.dim_funcionario (
    funcionario_id          SERIAL PRIMARY KEY,
    emp_id                  INT UNIQUE NOT NULL,
    name_prefix             TEXT,
    first_name              TEXT,
    last_name               TEXT,
    email                   TEXT,
    ssn                     TEXT,
    last_hike_percent       NUMERIC(5,2)   -- já convertido de "21%" para 21.00
);

-- ----- DIMENSÃO GÊNERO -----

CREATE TABLE dw.dim_genero (
    genero_id       SERIAL PRIMARY KEY,
    sigla           CHAR(1) NOT NULL UNIQUE,
    descricao       TEXT NOT NULL
);

-- ----- DIMENSÃO FAIXA ETÁRIA -----

CREATE TABLE dw.dim_faixa_etaria (
    faixa_etaria_id SERIAL PRIMARY KEY,
    faixa           TEXT NOT NULL UNIQUE,
    idade_min       INT NOT NULL,
    idade_max       INT NOT NULL
);

-- ----- DIMENSÃO FAIXA SALARIAL -----

CREATE TABLE dw.dim_faixa_salarial (
    faixa_salarial_id   SERIAL PRIMARY KEY,
    faixa               TEXT NOT NULL UNIQUE,
    salario_min         NUMERIC(12,2) NOT NULL,
    salario_max         NUMERIC(12,2) NOT NULL
);

-- ----- DIMENSÃO TEMPO (rica, para role-playing) -----

CREATE TABLE dw.dim_tempo (
    tempo_id        SERIAL PRIMARY KEY,
    data_completa   DATE NOT NULL UNIQUE,
    ano             INT NOT NULL,
    semestre        INT NOT NULL,
    trimestre       INT NOT NULL,
    mes             INT NOT NULL,
    nome_mes        TEXT NOT NULL,
    dia             INT NOT NULL,
    dia_semana_num  INT NOT NULL,
    nome_dia_semana TEXT NOT NULL,
    eh_fim_semana   BOOLEAN NOT NULL
);

-- ----- TABELA FATO -----

CREATE TABLE dw.fato_rh (
    fato_id                 SERIAL PRIMARY KEY,

    -- Dimensão degenerada: emp_id direto na fato (identificador de evento)
    emp_id                  INT NOT NULL,

    -- FKs para dimensões
    funcionario_id          INT NOT NULL REFERENCES dw.dim_funcionario(funcionario_id),
    localizacao_id          INT NOT NULL REFERENCES dw.dim_localizacao(localizacao_id),
    genero_id               INT NOT NULL REFERENCES dw.dim_genero(genero_id),
    faixa_etaria_id         INT NOT NULL REFERENCES dw.dim_faixa_etaria(faixa_etaria_id),
    faixa_salarial_id       INT NOT NULL REFERENCES dw.dim_faixa_salarial(faixa_salarial_id),

    -- ROLE-PLAYING: dim_tempo referenciada duas vezes
    tempo_id_admissao       INT NOT NULL REFERENCES dw.dim_tempo(tempo_id),
    tempo_id_nascimento     INT NOT NULL REFERENCES dw.dim_tempo(tempo_id),

    -- Métricas (additive / semi-additive)
    salario                 NUMERIC(12,2) NOT NULL,
    peso_kg                 NUMERIC(5,2),
    idade_anos              NUMERIC(5,2),
    tempo_empresa_anos      NUMERIC(5,2),
    percentual_ultimo_aumento NUMERIC(5,2)
);

CREATE INDEX idx_fato_funcionario   ON dw.fato_rh(funcionario_id);
CREATE INDEX idx_fato_tempo_adm     ON dw.fato_rh(tempo_id_admissao);
CREATE INDEX idx_fato_tempo_nasc    ON dw.fato_rh(tempo_id_nascimento);
CREATE INDEX idx_fato_localizacao   ON dw.fato_rh(localizacao_id);


-- =====================================================================
-- 3. ETL - CARGA E TRANSFORMAÇÕES
-- =====================================================================

-- ----- DIM_PAIS -----
-- TRANSFORMAÇÃO: dataset é 100% EUA, então país é fixo "USA".
INSERT INTO dw.dim_pais (country) VALUES ('USA');

-- ----- DIM_ESTADO -----
-- TRANSFORMAÇÃO: UPPER + TRIM para padronizar (ex.: " ca " e "CA" viram "CA").
INSERT INTO dw.dim_estado (state, pais_id)
SELECT DISTINCT UPPER(TRIM(s.state)), p.pais_id
FROM repositorio.rh_raw s
CROSS JOIN dw.dim_pais p
WHERE s.state IS NOT NULL AND TRIM(s.state) <> '';

-- ----- DIM_LOCALIZACAO -----
-- TRANSFORMAÇÃO: chave composta (city, state) - cidades com mesmo nome em
-- estados diferentes (ex.: Springfield) são tratadas como localizações distintas.
INSERT INTO dw.dim_localizacao (city, region, estado_id)
SELECT DISTINCT
    TRIM(s.city),
    TRIM(s.region),
    e.estado_id
FROM repositorio.rh_raw s
JOIN dw.dim_estado e ON UPPER(TRIM(s.state)) = e.state
WHERE s.city IS NOT NULL AND TRIM(s.city) <> '';

-- ----- DIM_GENERO -----
-- TRANSFORMAÇÃO: padroniza siglas com descrição amigável.
-- Inclui categoria 'U' (Não informado) para tratar registros do CSV com
-- gender NULL/vazio sem assumir um valor padrão arbitrário (M ou F).
INSERT INTO dw.dim_genero (sigla, descricao) VALUES
    ('M', 'Masculino'),
    ('F', 'Feminino'),
    ('U', 'Não informado');

-- ----- DIM_FAIXA_ETARIA -----
INSERT INTO dw.dim_faixa_etaria (faixa, idade_min, idade_max) VALUES
    ('Até 25 anos',      0, 25),
    ('26 a 35 anos',    26, 35),
    ('36 a 45 anos',    36, 45),
    ('46 a 55 anos',    46, 55),
    ('56 a 65 anos',    56, 65),
    ('Acima de 65',     66, 200);

-- ----- DIM_FAIXA_SALARIAL -----
INSERT INTO dw.dim_faixa_salarial (faixa, salario_min, salario_max) VALUES
    ('Até 40k',          0,      40000),
    ('40k a 70k',    40001,      70000),
    ('70k a 100k',   70001,     100000),
    ('100k a 150k', 100001,     150000),
    ('Acima de 150k', 150001, 9999999);

-- ----- DIM_TEMPO -----
-- TRANSFORMAÇÃO: gera um registro por data distinta encontrada no source
-- (tanto datas de admissão quanto de nascimento), enriquecido com vários
-- atributos calendário. Necessário para role-playing.
INSERT INTO dw.dim_tempo (
    data_completa, ano, semestre, trimestre, mes, nome_mes,
    dia, dia_semana_num, nome_dia_semana, eh_fim_semana
)
SELECT
    d                                     AS data_completa,
    EXTRACT(YEAR    FROM d)::INT          AS ano,
    CASE WHEN EXTRACT(MONTH FROM d) <= 6 THEN 1 ELSE 2 END AS semestre,
    EXTRACT(QUARTER FROM d)::INT          AS trimestre,
    EXTRACT(MONTH   FROM d)::INT          AS mes,
    TO_CHAR(d, 'TMMonth')                 AS nome_mes,
    EXTRACT(DAY     FROM d)::INT          AS dia,
    EXTRACT(ISODOW  FROM d)::INT          AS dia_semana_num,
    TO_CHAR(d, 'TMDay')                   AS nome_dia_semana,
    EXTRACT(ISODOW FROM d) IN (6,7)       AS eh_fim_semana
FROM (
    SELECT DISTINCT TO_DATE(date_of_joining, 'MM/DD/YYYY') AS d
        FROM repositorio.rh_raw
        WHERE date_of_joining IS NOT NULL
    UNION
    SELECT DISTINCT TO_DATE(date_of_birth,   'MM/DD/YYYY') AS d
        FROM repositorio.rh_raw
        WHERE date_of_birth IS NOT NULL
) datas
WHERE d IS NOT NULL;

-- ----- DIM_FUNCIONARIO -----
-- TRANSFORMAÇÕES:
--   - emp_id convertido TEXT -> INT
--   - last_hike_percent: remove '%', converte para NUMERIC, NULL se inválido
--   - GROUP BY emp_id garante unicidade (se vier duplicado no source)
INSERT INTO dw.dim_funcionario (
    emp_id, name_prefix, first_name, last_name, email, ssn, last_hike_percent
)
SELECT
    CAST(emp_id AS INT),
    MIN(TRIM(name_prefix)),
    MIN(TRIM(first_name)),
    MIN(TRIM(last_name)),
    MIN(LOWER(TRIM(email))),
    MIN(TRIM(ssn)),
    MIN(CAST(NULLIF(REPLACE(TRIM(last_hike_percent), '%', ''), '') AS NUMERIC))
FROM repositorio.rh_raw
WHERE emp_id IS NOT NULL
GROUP BY CAST(emp_id AS INT);

-- ----- FATO_RH -----
-- TRANSFORMAÇÕES:
--   - todos os campos numéricos com CAST explícito
--   - datas convertidas via TO_DATE
--   - bucketização por faixa etária e faixa salarial via JOIN BETWEEN
--   - gênero NULL/vazio mapeado para 'U' (Não informado) ao invés de assumir
--     um valor arbitrário; preserva a integridade do dado original.
INSERT INTO dw.fato_rh (
    emp_id, funcionario_id, localizacao_id, genero_id,
    faixa_etaria_id, faixa_salarial_id,
    tempo_id_admissao, tempo_id_nascimento,
    salario, peso_kg, idade_anos, tempo_empresa_anos, percentual_ultimo_aumento
)
SELECT
    CAST(s.emp_id AS INT),
    df.funcionario_id,
    dl.localizacao_id,
    dg.genero_id,
    dfe.faixa_etaria_id,
    dfs.faixa_salarial_id,
    dt_adm.tempo_id,
    dt_nasc.tempo_id,
    CAST(s.salary AS NUMERIC),
    CAST(NULLIF(s.weight_in_kgs, '') AS NUMERIC),
    CAST(NULLIF(s.age_in_yrs, '')    AS NUMERIC),
    CAST(NULLIF(s.age_in_company, '') AS NUMERIC),
    CAST(NULLIF(REPLACE(s.last_hike_percent, '%', ''), '') AS NUMERIC)
FROM repositorio.rh_raw s
JOIN dw.dim_funcionario df
     ON df.emp_id = CAST(s.emp_id AS INT)
JOIN dw.dim_estado de
     ON de.state = UPPER(TRIM(s.state))
JOIN dw.dim_localizacao dl
     ON dl.city = TRIM(s.city) AND dl.estado_id = de.estado_id
JOIN dw.dim_genero dg
     ON dg.sigla = COALESCE(NULLIF(UPPER(TRIM(s.gender)), ''), 'U')
JOIN dw.dim_faixa_etaria dfe
     ON CAST(s.age_in_yrs AS NUMERIC) BETWEEN dfe.idade_min AND dfe.idade_max
JOIN dw.dim_faixa_salarial dfs
     ON CAST(s.salary AS NUMERIC) BETWEEN dfs.salario_min AND dfs.salario_max
JOIN dw.dim_tempo dt_adm
     ON dt_adm.data_completa = TO_DATE(s.date_of_joining, 'MM/DD/YYYY')
JOIN dw.dim_tempo dt_nasc
     ON dt_nasc.data_completa = TO_DATE(s.date_of_birth,   'MM/DD/YYYY')
WHERE s.emp_id IS NOT NULL
  AND s.salary IS NOT NULL
  AND s.date_of_joining IS NOT NULL
  AND s.date_of_birth IS NOT NULL;


-- =====================================================================
-- 4. DATA MART - VIEWS ANALÍTICAS PARA POWER BI
-- =====================================================================
-- O Power BI consome este schema (não o dw direto): tabelas já achatadas,
-- nomeadas em português, prontas para virar tabela / fato no modelo do BI.
-- =====================================================================

-- ----- View achatada principal (a "tabela fato" do BI) -----
CREATE OR REPLACE VIEW datamart.vw_fato_rh AS
SELECT
    f.fato_id,
    f.emp_id                                         AS cod_funcionario,
    df.first_name || ' ' || df.last_name             AS nome_completo,
    df.name_prefix                                   AS prefixo,
    dg.descricao                                     AS genero,
    dfe.faixa                                        AS faixa_etaria,
    dfs.faixa                                        AS faixa_salarial,
    dl.city                                          AS cidade,
    de.state                                         AS estado,
    dl.region                                        AS regiao,
    dp.country                                       AS pais,
    dt_adm.data_completa                             AS data_admissao,
    dt_adm.ano                                       AS ano_admissao,
    dt_adm.trimestre                                 AS trimestre_admissao,
    dt_adm.nome_mes                                  AS mes_admissao,
    dt_nasc.data_completa                            AS data_nascimento,
    dt_nasc.ano                                      AS ano_nascimento,
    f.salario,
    f.peso_kg,
    f.idade_anos,
    f.tempo_empresa_anos,
    f.percentual_ultimo_aumento
FROM dw.fato_rh f
JOIN dw.dim_funcionario     df       ON f.funcionario_id      = df.funcionario_id
JOIN dw.dim_genero          dg       ON f.genero_id           = dg.genero_id
JOIN dw.dim_faixa_etaria    dfe      ON f.faixa_etaria_id     = dfe.faixa_etaria_id
JOIN dw.dim_faixa_salarial  dfs      ON f.faixa_salarial_id   = dfs.faixa_salarial_id
JOIN dw.dim_localizacao     dl       ON f.localizacao_id      = dl.localizacao_id
JOIN dw.dim_estado          de       ON dl.estado_id          = de.estado_id
JOIN dw.dim_pais            dp       ON de.pais_id            = dp.pais_id
JOIN dw.dim_tempo           dt_adm   ON f.tempo_id_admissao   = dt_adm.tempo_id
JOIN dw.dim_tempo           dt_nasc  ON f.tempo_id_nascimento = dt_nasc.tempo_id;

-- ----- View agregada: salário por estado -----
CREATE OR REPLACE VIEW datamart.vw_salario_por_estado AS
SELECT
    de.state                              AS estado,
    dl.region                             AS regiao,
    COUNT(*)                              AS qtd_funcionarios,
    ROUND(AVG(f.salario), 2)              AS salario_medio,
    MIN(f.salario)                        AS salario_minimo,
    MAX(f.salario)                        AS salario_maximo,
    SUM(f.salario)                        AS folha_total
FROM dw.fato_rh f
JOIN dw.dim_localizacao dl ON f.localizacao_id = dl.localizacao_id
JOIN dw.dim_estado      de ON dl.estado_id     = de.estado_id
GROUP BY de.state, dl.region;

-- ----- View agregada: admissões por ano -----
CREATE OR REPLACE VIEW datamart.vw_admissoes_por_ano AS
SELECT
    dt.ano                                AS ano_admissao,
    dt.trimestre,
    COUNT(*)                              AS qtd_admissoes,
    ROUND(AVG(f.salario), 2)              AS salario_medio_admissao
FROM dw.fato_rh f
JOIN dw.dim_tempo dt ON f.tempo_id_admissao = dt.tempo_id
GROUP BY dt.ano, dt.trimestre;

-- ----- View agregada: distribuição por faixa salarial e gênero -----
CREATE OR REPLACE VIEW datamart.vw_faixa_genero AS
SELECT
    dfs.faixa                             AS faixa_salarial,
    dg.descricao                          AS genero,
    COUNT(*)                              AS qtd_funcionarios,
    ROUND(AVG(f.salario), 2)              AS salario_medio
FROM dw.fato_rh f
JOIN dw.dim_faixa_salarial dfs ON f.faixa_salarial_id = dfs.faixa_salarial_id
JOIN dw.dim_genero         dg  ON f.genero_id         = dg.genero_id
GROUP BY dfs.faixa, dg.descricao;


-- =====================================================================
-- 5. CAMADA DE SEGURANÇA - PERFIS E VIEWS DE ACESSO
-- =====================================================================
-- Extra (além do escopo do enunciado): três perfis com graus diferentes
-- de acesso à informação sensível.
-- =====================================================================

-- ----- View para perfil Funcionário (acesso mínimo) -----
CREATE OR REPLACE VIEW security.vw_funcionario AS
SELECT
    f.fato_id,
    df.first_name || ' ' || df.last_name  AS nome_completo,
    dg.descricao                          AS genero,
    dl.city                               AS cidade,
    de.state                              AS estado,
    dt.data_completa                      AS data_admissao
FROM dw.fato_rh f
JOIN dw.dim_funcionario df ON f.funcionario_id    = df.funcionario_id
JOIN dw.dim_genero      dg ON f.genero_id         = dg.genero_id
JOIN dw.dim_localizacao dl ON f.localizacao_id    = dl.localizacao_id
JOIN dw.dim_estado      de ON dl.estado_id        = de.estado_id
JOIN dw.dim_tempo       dt ON f.tempo_id_admissao = dt.tempo_id;

-- ----- View para perfil RH (acesso intermediário, SSN mascarado) -----
CREATE OR REPLACE VIEW security.vw_rh AS
SELECT
    f.fato_id,
    df.first_name || ' ' || df.last_name  AS nome_completo,
    dg.descricao                          AS genero,
    f.idade_anos                          AS idade,
    df.email,
    f.salario,
    f.percentual_ultimo_aumento,
    dl.city                               AS cidade,
    de.state                              AS estado,
    LEFT(df.ssn, 3) || '***'              AS ssn_mascarado
FROM dw.fato_rh f
JOIN dw.dim_funcionario df ON f.funcionario_id = df.funcionario_id
JOIN dw.dim_genero      dg ON f.genero_id      = dg.genero_id
JOIN dw.dim_localizacao dl ON f.localizacao_id = dl.localizacao_id
JOIN dw.dim_estado      de ON dl.estado_id     = de.estado_id;

-- ----- View para perfil Diretor (acesso total) -----
CREATE OR REPLACE VIEW security.vw_diretor AS
SELECT
    f.fato_id,
    f.emp_id,
    df.first_name || ' ' || df.last_name  AS nome_completo,
    dg.descricao                          AS genero,
    f.idade_anos                          AS idade,
    df.email,
    df.ssn                                AS ssn_completo,
    f.salario,
    f.percentual_ultimo_aumento,
    dt_adm.data_completa                  AS data_admissao,
    dt_nasc.data_completa                 AS data_nascimento,
    dl.city                               AS cidade,
    de.state                              AS estado,
    dp.country                            AS pais
FROM dw.fato_rh f
JOIN dw.dim_funcionario df      ON f.funcionario_id      = df.funcionario_id
JOIN dw.dim_genero      dg      ON f.genero_id           = dg.genero_id
JOIN dw.dim_tempo       dt_adm  ON f.tempo_id_admissao   = dt_adm.tempo_id
JOIN dw.dim_tempo       dt_nasc ON f.tempo_id_nascimento = dt_nasc.tempo_id
JOIN dw.dim_localizacao dl      ON f.localizacao_id      = dl.localizacao_id
JOIN dw.dim_estado      de      ON dl.estado_id          = de.estado_id
JOIN dw.dim_pais        dp      ON de.pais_id            = dp.pais_id;

-- ----- Roles e permissões -----
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'diretor')     THEN CREATE ROLE diretor;     END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'rh')          THEN CREATE ROLE rh;          END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'funcionario') THEN CREATE ROLE funcionario; END IF;
END $$;

GRANT USAGE ON SCHEMA dw, datamart, security TO diretor, rh, funcionario;

GRANT SELECT ON security.vw_diretor     TO diretor;
GRANT SELECT ON security.vw_rh          TO rh;
GRANT SELECT ON security.vw_funcionario TO funcionario;
GRANT SELECT ON ALL TABLES IN SCHEMA datamart TO diretor, rh;


-- =====================================================================
-- 6. TESTES DE VALIDAÇÃO
-- =====================================================================

-- Conferência das contagens
SELECT 'staging'        AS camada, COUNT(*) FROM repositorio.rh_raw
UNION ALL SELECT 'fato', COUNT(*) FROM dw.fato_rh
UNION ALL SELECT 'dim_funcionario',     COUNT(*) FROM dw.dim_funcionario
UNION ALL SELECT 'dim_localizacao',     COUNT(*) FROM dw.dim_localizacao
UNION ALL SELECT 'dim_estado',          COUNT(*) FROM dw.dim_estado
UNION ALL SELECT 'dim_pais',            COUNT(*) FROM dw.dim_pais
UNION ALL SELECT 'dim_genero',          COUNT(*) FROM dw.dim_genero
UNION ALL SELECT 'dim_faixa_etaria',    COUNT(*) FROM dw.dim_faixa_etaria
UNION ALL SELECT 'dim_faixa_salarial',  COUNT(*) FROM dw.dim_faixa_salarial
UNION ALL SELECT 'dim_tempo',           COUNT(*) FROM dw.dim_tempo;

-- Amostras do data mart (o BI vai consumir daqui)
SELECT * FROM datamart.vw_fato_rh             LIMIT 10;
SELECT * FROM datamart.vw_salario_por_estado  ORDER BY folha_total DESC LIMIT 10;
SELECT * FROM datamart.vw_admissoes_por_ano   ORDER BY ano_admissao;
SELECT * FROM datamart.vw_faixa_genero        ORDER BY faixa_salarial, genero;

-- Testes de segurança
SET ROLE diretor;
SELECT * FROM security.vw_diretor LIMIT 5;          -- deve funcionar

SET ROLE rh;
SELECT * FROM security.vw_rh LIMIT 5;               -- deve funcionar
-- SELECT * FROM security.vw_diretor;               -- deve dar erro

SET ROLE funcionario;
SELECT * FROM security.vw_funcionario LIMIT 5;      -- deve funcionar
-- SELECT * FROM security.vw_rh;                    -- deve dar erro

RESET ROLE;
