-- juros.sql — o mesmo lote bancário, em SQL puro.
--
-- Roda com:   bash sql/roda.sh postgres      (NUMERIC: bate byte a byte)
--             bash sql/roda.sh sqlite        (REAL: DIVERGE, por construção)
--
-- ## Por que SQL entra num projeto sobre COBOL
--
-- Porque é para onde esse tipo de lote vai quando é migrado, e porque o
-- problema central do projeto — **dinheiro não é ponto flutuante** — tem no
-- SQL a resposta mais clara de todas as linguagens aqui:
--
--     NUMERIC(p, s)  é ponto fixo decimal, exato, definido no SQL-92.
--
-- O COBOL resolveu isso em 1959 com `PICTURE 9(10)V99`. O C# resolveu em 2002
-- com `decimal`. O SQL resolveu em 1992 com `NUMERIC`. As três são a mesma
-- ideia, e a linguagem que NÃO a tem — qualquer uma com só `double` — é a que
-- erra.
--
-- ## O achado deste arquivo: o mesmo SQL, dois motores, dois resultados
--
-- Este arquivo roda em **PostgreSQL e SQLite sem alteração**. E dá respostas
-- diferentes:
--
--   * no PostgreSQL, `NUMERIC` é decimal exato e `ROUND(x, 2)` arredonda
--     **meio para longe de zero** — que é exatamente o `ROUNDED` do COBOL. A
--     saída é **idêntica byte a byte** à do `cobol/juros.cob`;
--
--   * no SQLite **não existe NUMERIC de verdade** — e o mecanismo da falha
--     não é o que eu previ aqui na primeira versão. Eu escrevera que "o valor
--     vira REAL, ou seja double". **Medido, é pior:**
--
--         sqlite> SELECT typeof(CAST('000000000120' AS NUMERIC));
--         integer
--         sqlite> SELECT CAST('000000000120' AS NUMERIC) / 100;
--         1
--
--     O SQLite tem **afinidade** de tipo, não tipo: `NUMERIC` converte a
--     string para `integer` quando ela parece um inteiro. E `integer /
--     integer` **trunca**. Então `120 / 100` é `1`, e não `1,20`.
--
--     A mesma coluna guarda tipos diferentes conforme o valor:
--
--         CREATE TABLE t (v NUMERIC(12,2));
--         INSERT INTO t VALUES (1.20), (120);
--         -- v=1.2 typeof=real   |   v=120 typeof=integer
--
--     E `taxa / 10000` com `1250` inteiro dá **zero**: todos os juros do lote
--     saem nulos. Medido: a saída divergiu em **13 das 14 contas**.
--
-- O SQLite não avisa em nenhum desses passos. Aceita `NUMERIC(12,2)`, aceita
-- `ROUND(x, 2)`, e devolve números plausíveis.
--
-- ### E a "correção óbvia" troca um erro catastrófico por um SILENCIOSO
--
-- A reação natural é trocar `/ 100` por `/ 100.0`, forçando divisão real. Foi
-- medido numa sonda (não committada), com as 15 divisões do arquivo trocadas:
--
--     / 100   (inteira)  ->  diverge em 13 de 14 contas
--     / 100.0 (real)     ->  diverge em  2 de 14 contas
--
-- E as duas que sobram são **as contas 13 e 14**, que existem neste conjunto
-- justamente para testar arredondamento:
--
--     conta 13:  1400,00 × 0,03 % / 12  =  0,035  exatamente
--     conta 14:    840,00 × 0,05 % / 12  =  0,035  exatamente
--
--     COBOL (ROUNDED, meio para longe de zero)  ->  0,04
--     SQLite com divisão real                    ->  0,03
--
-- `0,035` **não é representável em binário**. O `double` mais próximo fica
-- ABAIXO do empate, então a pergunta "meio para cima ou meio para o par?"
-- nunca chega a ser feita: o valor simplesmente não está no meio.
--
-- É o ponto do projeto inteiro em duas contas: o erro que se vê (13 de 14) se
-- corrige num minuto; o que fica (2 de 14) só aparece quando alguém confere
-- centavo por centavo.
--
-- A suíte **exige** a divergência: se o SQLite passar a bater, a afirmação
-- deste comentário ficou obsoleta e o teste tem de falhar.
--
-- ## O ponto decimal implícito, em SQL
--
-- A entrada tem 26 caracteres de largura fixa e **nenhum ponto**: o campo
-- `9(10)V99` são 12 dígitos onde os dois últimos são centavos.
--
-- Em SQL isso é `SUBSTR` mais uma divisão por 100.
--
-- A primeira versão deste comentário dizia: *"a divisão precisa ser `/ 100`
-- sobre NUMERIC, nunca `/ 100.0`, porque dividir por inteiro mantém o tipo"*.
--
-- **Isso está certo no PostgreSQL e é exatamente o que quebra no SQLite** —
-- onde "manter o tipo" significa manter `integer`, e a divisão trunca. O
-- conselho que eu dei no arquivo era a causa do bug num dos dois motores.
--
-- Fica `/ 100` de propósito: o PostgreSQL é o alvo da migração, e a
-- divergência do SQLite é o conteúdo. Mas quem copiar esta linha para um
-- motor sem decimal exato precisa ler a seção acima.

-- ## O contrato de entrada: a tabela `linhas` JÁ EXISTE
--
-- Este arquivo **não** cria nem carrega `linhas(id, bruta)`. Quem faz isso é
-- o `sql/roda.sh`, e a razão é que carregar arquivo é a única parte que o SQL
-- padrão nunca especificou: o PostgreSQL usa `\copy`, o SQLite usa `.import`,
-- e os dois têm sintaxe própria.
--
-- Isolar a carga no runner é o que permite afirmar que **o cálculo é o mesmo
-- arquivo nos dois motores**. Se o parse ou a aritmética precisassem de
-- dialeto, a comparação entre eles mediria o dialeto em vez da aritmética.
--
-- `id` dá a ORDEM, que o arquivo de saída tem de preservar: sem `ORDER BY id`
-- no final, o SQL pode devolver as linhas em qualquer ordem, e o `cmp`
-- acusaria diferença sem que nenhum número esteja errado.

DROP TABLE IF EXISTS contas;
CREATE TABLE contas (
    id     INTEGER PRIMARY KEY,
    conta  CHAR(8)       NOT NULL,
    saldo  NUMERIC(12,2) NOT NULL,
    -- `NUMERIC(4,0)` porque a taxa vem em PONTOS-BASE: `1250` = 12,50 %.
    --
    -- A primeira versao declarava `NUMERIC(6,4)`, confundindo a UNIDADE
    -- guardada com a unidade lida, e o PostgreSQL recusou na hora:
    --
    --     ERROR: numeric field overflow
    --     DETAIL: A field with precision 6, scale 4 must round to an
    --             absolute value less than 10^2.
    --
    -- Recusar e o comportamento certo, e vale notar o contraste com o resto
    -- deste projeto: um `double` teria aceitado 1250 e seguido em frente.
    -- Tipo decimal com precisao declarada transforma erro de unidade em erro
    -- de carga -- que e onde ele custa minutos em vez de meses.
    taxa   NUMERIC(4,0)  NOT NULL,
    tipo   CHAR(1)       NOT NULL
);

-- O parse do registro de largura fixa.
--
-- `SUBSTR(bruta, 10, 12)` pega os 12 dígitos do saldo; a divisão por 100 põe
-- o ponto que o arquivo não tem. O sinal está SEPARADO, na posição 9, e é
-- aplicado por multiplicação -- não por concatenação, que falharia se o campo
-- tivesse espaços à esquerda.
INSERT INTO contas (id, conta, saldo, taxa, tipo)
SELECT
    id,
    SUBSTR(bruta, 1, 8),
    CAST(SUBSTR(bruta, 10, 12) AS NUMERIC) / 100
        * CASE WHEN SUBSTR(bruta, 9, 1) = '-' THEN -1 ELSE 1 END,
    -- A taxa vem em pontos-base: `1250` = 12,50 %. Dividir por 10000 aqui
    -- deixaria a conta de juros com uma divisão a menos, MAS mudaria a ordem
    -- das operações -- e a ordem é parte do contrato com o COBOL. Então a
    -- taxa fica em pontos-base até a hora do cálculo.
    CAST(SUBSTR(bruta, 22, 4) AS NUMERIC),
    SUBSTR(bruta, 26, 1)
FROM linhas;

-- ---------------------------------------------------------------------------
-- O cálculo.
--
-- A ordem das operações é a MESMA do `COMPUTE` do COBOL e do C#:
--
--     juros = ROUND(saldo * (taxa / 10000) / 12, 2)
--
-- e não `saldo * taxa / 10000 / 12`, que é algebricamente igual e
-- numericamente diferente em qualquer aritmética de precisão finita.
--
-- `ROUND` do PostgreSQL sobre NUMERIC arredonda meio para LONGE DE ZERO, que
-- é o `ROUNDED` do COBOL. O C# precisou de `MidpointRounding.AwayFromZero`
-- explícito porque o padrão dele é meio-para-par; o PostgreSQL acerta por
-- omissão, e o SQLite nem tem a pergunta, porque opera em binário.
DROP TABLE IF EXISTS resultado;
CREATE TABLE resultado (
    id     INTEGER PRIMARY KEY,
    conta  CHAR(8)       NOT NULL,
    saldo  NUMERIC(12,2) NOT NULL,
    juros  NUMERIC(9,2)  NOT NULL,
    tarifa NUMERIC(8,2)  NOT NULL,
    novo   NUMERIC(12,2) NOT NULL
);

INSERT INTO resultado (id, conta, saldo, juros, tarifa, novo)
SELECT
    id,
    conta,
    saldo,
    ROUND(saldo * (taxa / 10000) / 12, 2) AS juros,
    tarifa,
    saldo + ROUND(saldo * (taxa / 10000) / 12, 2) - tarifa AS novo
FROM (
    SELECT
        id, conta, saldo, taxa,
        CASE tipo
            -- `<` ESTRITO: saldo de exatamente 1000,00 cai na tarifa BAIXA.
            -- A conta 00000008 do conjunto fixa essa decisão, e foi colocada
            -- lá para que nenhuma implementação possa errar o limite sem a
            -- suíte perceber.
            WHEN 'C' THEN CASE WHEN saldo < 1000 THEN 15.00 ELSE 5.00 END
            WHEN 'P' THEN 0.00
            WHEN 'I' THEN
                -- 0,1 % do saldo, limitado a [2,00; 50,00]. Saldo negativo dá
                -- tarifa bruta zero, que o limite inferior eleva a 2,00 --
                -- igual ao `saldo > 0m ? ... : 0m` do C#.
                CASE
                    WHEN saldo <= 0 THEN 2.00
                    WHEN ROUND(saldo * 1 / 1000, 2) < 2.00 THEN 2.00
                    WHEN ROUND(saldo * 1 / 1000, 2) > 50.00 THEN 50.00
                    ELSE ROUND(saldo * 1 / 1000, 2)
                END
        END AS tarifa
    FROM contas
) t;

-- ---------------------------------------------------------------------------
-- A formatação do registro de saída: 52 caracteres, sinal separado à
-- esquerda, zeros à esquerda, e NENHUM ponto decimal.
--
-- `ABS(x) * 100` devolve o valor em centavos como inteiro, que é o que o
-- arquivo guarda. O `CAST(... AS BIGINT)` é necessário porque NUMERIC
-- formatado com `TO_CHAR` traria separador de milhar conforme a configuração
-- regional -- e a saída não pode depender de locale.
--
-- ### O preenchimento com zeros NÃO pode usar `LPAD`
--
-- A primeira versão usava `LPAD(x, 12, '0')`, afirmando que ele "existe nos
-- dois motores". **Não existe.** O SQLite recusou na hora:
--
--     Parse error near line 170: no such function: LPAD
--
-- `LPAD` é extensão de PostgreSQL e Oracle; não está no SQL-92 e o SQLite
-- não o tem. E a alternativa óbvia -- `SUBSTR(s, -12)` para pegar os últimos
-- 12 caracteres -- também não serve: o SQLite conta do fim com índice
-- negativo, e o **PostgreSQL não** (ele trata o negativo como início antes do
-- começo e devolve a string inteira).
--
-- Então a forma portátil é a verbosa: concatenar zeros à esquerda e recortar
-- os últimos N com `SUBSTR` e `LENGTH`, que os dois têm com a mesma
-- semântica.
--
-- Isso é o conteúdo deste arquivo em miniatura: **o SQL "padrão" que roda em
-- dois motores é bem menor do que parece**, e a parte que não roda só aparece
-- quando se testa nos dois.
SELECT
    conta
    || CASE WHEN saldo  < 0 THEN '-' ELSE '+' END
    || SUBSTR('000000000000' || CAST(CAST(ABS(saldo) * 100 AS BIGINT) AS VARCHAR(20)),
              LENGTH('000000000000' || CAST(CAST(ABS(saldo) * 100 AS BIGINT) AS VARCHAR(20))) - 11, 12)
    || CASE WHEN juros  < 0 THEN '-' ELSE '+' END
    || SUBSTR('000000000' || CAST(CAST(ABS(juros) * 100 AS BIGINT) AS VARCHAR(20)),
              LENGTH('000000000' || CAST(CAST(ABS(juros) * 100 AS BIGINT) AS VARCHAR(20))) - 8, 9)
    || SUBSTR('00000000' || CAST(CAST(ABS(tarifa) * 100 AS BIGINT) AS VARCHAR(20)),
              LENGTH('00000000' || CAST(CAST(ABS(tarifa) * 100 AS BIGINT) AS VARCHAR(20))) - 7, 8)
    || CASE WHEN novo   < 0 THEN '-' ELSE '+' END
    || SUBSTR('000000000000' || CAST(CAST(ABS(novo) * 100 AS BIGINT) AS VARCHAR(20)),
              LENGTH('000000000000' || CAST(CAST(ABS(novo) * 100 AS BIGINT) AS VARCHAR(20))) - 11, 12)
    AS registro
FROM resultado
ORDER BY id;
