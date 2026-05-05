CREATE SCHEMA staging;
CREATE SCHEMA DW;
CREATE SCHEMA security;

---Tabela Dados Brutos
CREATE TABLE staging.rh_raw (
    emp_id INT,
    name_prefix TEXT,
    first_name TEXT,
    middle_initial TEXT,
    last_name TEXT,
    gender TEXT,
    email TEXT,
    fathers_name TEXT,
    mothers_name TEXT,
    mothers_maiden_name TEXT,
    date_of_birth TEXT,
    time_of_birth TEXT,
    age_in_yrs NUMERIC,
    weight_in_kgs NUMERIC,
    date_of_joining TEXT,
    quarter_of_joining TEXT,
    half_of_joining TEXT,
    year_of_joining INT,
    month_of_joining INT,
    month_name_of_joining TEXT,
    short_month TEXT,
    day_of_joining INT,
    dow_of_joining TEXT,
    short_dow TEXT,
    age_in_company NUMERIC,
    salary NUMERIC,
    last_hike_percent TEXT,
    ssn TEXT,
    phone TEXT,
    place_name TEXT,
    county TEXT,
    city TEXT,
    state TEXT,
    zip TEXT,
    region TEXT,
    user_name TEXT,
    password TEXT
);

---TABELAS DIM
CREATE TABLE dw.dim_funcionario (
    funcionario_id SERIAL PRIMARY KEY,
    emp_id INT,
    first_name TEXT,
    last_name TEXT,
    gender TEXT,
    date_of_birth DATE,
    age INT,
    email TEXT,
    ssn TEXT,
    last_hike_percent_raw TEXT
);

CREATE TABLE dw.dim_pais (
    pais_id SERIAL PRIMARY KEY,
    country TEXT UNIQUE
);

CREATE TABLE dw.dim_estado (
    estado_id SERIAL PRIMARY KEY,
    state TEXT UNIQUE,
    pais_id INT REFERENCES dw.dim_pais(pais_id)
);

CREATE TABLE dw.dim_localizacao (
    localizacao_id SERIAL PRIMARY KEY,
    city TEXT,
    estado_id INT REFERENCES dw.dim_estado(estado_id)
);

CREATE TABLE dw.dim_tempo (
    tempo_id SERIAL PRIMARY KEY,
    ano INT,
    mes INT,
    dia INT
);

--- 4. Tabela FATO
CREATE TABLE dw.fato_rh (
    fato_id SERIAL PRIMARY KEY,
    funcionario_id INT REFERENCES dw.dim_funcionario(funcionario_id),
    localizacao_id INT REFERENCES dw.dim_localizacao(localizacao_id),
    tempo_id INT REFERENCES dw.dim_tempo(tempo_id),
    salary NUMERIC
);

--- 5. VIEWS de Acesso
CREATE OR REPLACE VIEW security.vw_funcionario AS
SELECT
    fr.funcionario_id,
    d.first_name || ' ' || d.last_name AS nome_completo,
    d.gender,
    d.email,
    t.dia,
    t.mes,
    t.ano,
    l.city,
    e.state,
    fr.salary
FROM dw.fato_rh fr
JOIN dw.dim_funcionario d ON fr.funcionario_id = d.funcionario_id
JOIN dw.dim_tempo t ON fr.tempo_id = t.tempo_id
JOIN dw.dim_localizacao l ON fr.localizacao_id = l.localizacao_id
JOIN dw.dim_estado e ON l.estado_id = e.estado_id;

CREATE OR REPLACE VIEW security.vw_rh AS
SELECT
    d.funcionario_id,
    d.first_name || ' ' || d.last_name AS nome_completo,
    d.gender,
    d.age,
    d.email,
    fr.salary,
    CAST(NULLIF(REPLACE(d.last_hike_percent_raw, '%', ''), '') AS NUMERIC) AS percentual_ultimo_aumento,
    l.city,
    e.state,
    p.country,
    LEFT(d.ssn, 3) || '***' AS ssn_mask
FROM dw.fato_rh fr
JOIN dw.dim_funcionario d ON fr.funcionario_id = d.funcionario_id
JOIN dw.dim_localizacao l ON fr.localizacao_id = l.localizacao_id
JOIN dw.dim_estado e ON l.estado_id = e.estado_id
JOIN dw.dim_pais p ON e.pais_id = p.pais_id;

---View do Manda chuva 
CREATE VIEW security.vw_diretor AS
SELECT
    fr.fato_id,
    d.funcionario_id,
    d.emp_id,
    
    d.first_name || ' ' || d.last_name AS nome_completo,
    d.gender AS genero,
    d.age AS idade,
    d.email,
    d.ssn AS ssn_completo,
    
    fr.salary AS salario_atual,
    CAST(NULLIF(REPLACE(d.last_hike_percent_raw, '%', ''), '') AS NUMERIC) AS percentual_ultimo_aumento,
    
    t.dia,
    t.mes,
    t.ano,
    t.dia || '/' || t.mes || '/' || t.ano AS data_contratacao_completa,
    
    ---Snowflake 
    l.city AS cidade,
    e.state AS estado,
    p.country AS pais
    
FROM dw.fato_rh fr
JOIN dw.dim_funcionario d ON fr.funcionario_id = d.funcionario_id
JOIN dw.dim_tempo t ON fr.tempo_id = t.tempo_id
JOIN dw.dim_localizacao l ON fr.localizacao_id = l.localizacao_id
JOIN dw.dim_estado e ON l.estado_id = e.estado_id
JOIN dw.dim_pais p ON e.pais_id = p.pais_id;

---Perfis
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'diretor') THEN CREATE ROLE diretor; END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'rh') THEN CREATE ROLE rh; END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'funcionario') THEN CREATE ROLE funcionario; END IF;
END $$;

---Permissões
GRANT USAGE ON SCHEMA dw TO diretor, rh, funcionario;
GRANT USAGE ON SCHEMA security TO diretor, rh, funcionario;

-- Diretor
GRANT SELECT ON security.vw_diretor TO diretor;
GRANT SELECT ON dw.fato_rh, dw.dim_funcionario, dw.dim_localizacao, dw.dim_tempo, dw.dim_estado, dw.dim_pais TO diretor;

-- RH
GRANT SELECT ON security.vw_rh TO rh;
GRANT SELECT ON dw.fato_rh, dw.dim_funcionario, dw.dim_localizacao, dw.dim_estado, dw.dim_pais TO rh;

-- Funcionario
GRANT SELECT ON security.vw_funcionario TO funcionario;
GRANT SELECT ON dw.fato_rh, dw.dim_funcionario, dw.dim_tempo, dw.dim_localizacao, dw.dim_estado TO funcionario;


COPY staging.rh_raw
FROM 'C:\Users\Public\Hr1m.csv'
DELIMITER ','
CSV HEADER;

---povoando o povo
INSERT INTO dw.dim_funcionario (emp_id, first_name, last_name, gender, date_of_birth, age, email, ssn, last_hike_percent_raw)
SELECT 
    emp_id, MIN(first_name), MIN(last_name), MIN(gender), 
    TO_DATE(MIN(date_of_birth), 'MM/DD/YYYY'), 
    MIN(CAST(age_in_yrs AS NUMERIC)), 
    MIN(email), MIN(ssn), MIN(last_hike_percent)
FROM staging.rh_raw GROUP BY emp_id;

INSERT INTO dw.dim_pais (country)
SELECT DISTINCT 'USA' FROM staging.rh_raw;

INSERT INTO dw.dim_estado (state, pais_id)
SELECT DISTINCT s.state, p.pais_id
FROM staging.rh_raw s
CROSS JOIN dw.dim_pais p;

INSERT INTO dw.dim_localizacao (city, estado_id)
SELECT DISTINCT s.city, e.estado_id
FROM staging.rh_raw s
JOIN dw.dim_estado e ON s.state = e.state;

INSERT INTO dw.dim_tempo (ano, mes, dia)
SELECT DISTINCT year_of_joining, month_of_joining, day_of_joining
FROM staging.rh_raw;

INSERT INTO dw.fato_rh (funcionario_id, localizacao_id, tempo_id, salary)
SELECT df.funcionario_id, dl.localizacao_id, dt.tempo_id, s.salary
FROM staging.rh_raw s
JOIN dw.dim_funcionario df ON s.emp_id = df.emp_id
JOIN dw.dim_estado de ON s.state = de.state
JOIN dw.dim_localizacao dl ON s.city = dl.city AND dl.estado_id = de.estado_id
JOIN dw.dim_tempo dt ON s.year_of_joining = dt.ano AND s.month_of_joining = dt.mes AND s.day_of_joining = dt.dia;


-----  só TESTES  -----
SELECT * FROM staging.rh_raw LIMIT 20;
SELECT COUNT(*) FROM staging.rh_raw;
SELECT COUNT(*) FROM dw.fato_rh; 

SET ROLE diretor;
SELECT * FROM security.vw_diretor LIMIT 10; --- Tem q Funfar  

SET ROLE rh;
SELECT * FROM security.vw_rh LIMIT 10; --- Tem q Funfar        
SELECT * FROM security.vw_diretor;     --- Tem q dar erro       

SET ROLE funcionario;
SELECT * FROM security.vw_funcionario LIMIT 10; --- Tem q Funfar 
SELECT * FROM security.vw_rh;                   --- Tem q dar erro 
RESET ROLE;
