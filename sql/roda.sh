#!/usr/bin/env bash
# roda.sh — executa `juros.sql` num dos dois motores.
#
#     ./sql/roda.sh postgres  saida/sql.dat          NUMERIC exato
#     ./sql/roda.sh sqlite    saida/sql_real.dat     sem decimal: DIVERGE
#
# ## O que este runner isola
#
# O `juros.sql` é o MESMO arquivo nos dois motores, executado sem uma linha de
# alteração. O que muda — e a única coisa que muda — é **como a linha crua
# entra na tabela**, porque carregar arquivo é a parte que o SQL padrão nunca
# especificou.
#
# Manter essa diferença AQUI, e não dentro do `juros.sql`, é o que permite
# afirmar que o cálculo é o mesmo arquivo. Se o parse ou a aritmética
# precisassem de dialeto, a comparação entre os motores mediria o dialeto.
#
# ## As duas cargas, e por que as duas são geradas em shell
#
# Nenhuma usa o carregador nativo do motor, e as razões são diferentes:
#
#   * o `COPY` do PostgreSQL é executado pelo SERVIDOR, que roda como o
#     usuário `postgres` e não alcança `/mnt/c`. O `\copy` resolve (é do
#     cliente), e recebe por STDIN;
#
#   * o `.import` do SQLite com `.mode ascii` carregou **o arquivo inteiro
#     numa única linha** — o modo `ascii` usa 0x1F e 0x1E como separadores, e
#     o arquivo não tem nenhum dos dois. E a falha foi SILENCIOSA: o `SUBSTR`
#     pegou os 26 primeiros caracteres, a conta 1 foi calculada, e a saída
#     teve uma linha em vez de catorze, com números plausíveis.
#
#     Um `diff` contra o COBOL diria "divergiu em 14 de 14", e eu teria
#     registrado isso como divergência numérica. Por isso a carga do SQLite
#     agora **confere a contagem** antes de prosseguir.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$AQUI")"
cd "$RAIZ" || exit 1

MOTOR="${1:-postgres}"
SAIDA="${2:-saida/sql.dat}"
ENTRADA="dados/contas.dat"

mkdir -p "$(dirname "$SAIDA")"

case "$MOTOR" in
postgres)
    command -v psql >/dev/null 2>&1 || { echo 'psql ausente' >&2; exit 127; }

    # `-X` ignora o `~/.psqlrc`, que poderia ligar `timing` ou mudar a
    # formatação e sujar a saída com texto que o `cmp` leria como dado.
    PG=(sudo -n -u postgres psql -X -q -v ON_ERROR_STOP=1)

    "${PG[@]}" -d postgres -c 'DROP DATABASE IF EXISTS legado' >/dev/null 2>&1
    "${PG[@]}" -d postgres -c 'CREATE DATABASE legado' >/dev/null 2>&1 || {
        echo 'não consegui criar o banco' >&2; exit 1; }

    "${PG[@]}" -d legado -c \
        'CREATE TABLE linhas (id INTEGER PRIMARY KEY, bruta VARCHAR(26) NOT NULL)' \
        >/dev/null || exit 1

    # A numeração vem do `grep -n`, que prefixa `N:`, e o delimitador do
    # `\copy` passa a ser `:`.
    #
    # O dado é seguro para esse delimitador: o registro de 26 caracteres só
    # tem dígitos, `+`, `-` e uma letra de tipo. Se algum dia contiver `:`,
    # este comentário é o aviso de que a carga precisa mudar.
    grep -n '' "$ENTRADA" \
        | "${PG[@]}" -d legado -c \
            "\\copy linhas(id, bruta) FROM STDIN WITH (FORMAT text, DELIMITER ':')" \
            >/dev/null \
        || { echo 'falha ao carregar contas.dat' >&2; exit 1; }

    carregadas=$("${PG[@]}" -d legado -t -A -c 'SELECT COUNT(*) FROM linhas')
    esperadas=$(wc -l < "$ENTRADA")
    if [ "$carregadas" != "$esperadas" ]; then
        echo "carga do PostgreSQL: $carregadas linhas, esperava $esperadas" >&2
        exit 1
    fi

    # E o `juros.sql` SEM ALTERAÇÃO.
    #
    # `-t` tira cabeçalho e rodapé, `-A` tira o alinhamento por colunas. Sem
    # os dois, cada registro viria com espaços de preenchimento e o `cmp`
    # acusaria diferença em TODAS as linhas — uma falha de formatação do
    # cliente aparecendo como erro de cálculo.
    "${PG[@]}" -d legado -t -A -f "$AQUI/juros.sql" > "$SAIDA" || exit 1
    ;;

sqlite)
    command -v sqlite3 >/dev/null 2>&1 || { echo 'sqlite3 ausente' >&2; exit 127; }

    BANCO="$(mktemp -t legado.XXXXXX.db)"
    trap 'rm -f "$BANCO"' EXIT

    # A carga é um `INSERT` por linha, gerado por um laço do shell.
    #
    # Nem `.import` (ver o cabeçalho) nem `sed` com grupos de captura: a
    # versão com `sed` foi escrita por um script que reescreveu este arquivo, e
    # as contrabarras dos grupos não sobreviveram — o resultado foram
    # `INSERT INTO linhas VALUES (, '');`, que o SQLite recusou com
    # "unrecognized token".
    #
    # Um laço `while read` não tem escape nenhum para errar.
    {
        echo 'CREATE TABLE linhas (id INTEGER PRIMARY KEY, bruta TEXT NOT NULL);'
        n=0
        while IFS= read -r linha; do
            n=$((n + 1))
            echo "INSERT INTO linhas VALUES ($n, '$linha');"
        done < "$ENTRADA"
    } | sqlite3 "$BANCO" || { echo 'falha ao carregar no SQLite' >&2; exit 1; }

    carregadas=$(sqlite3 "$BANCO" 'SELECT COUNT(*) FROM linhas')
    esperadas=$(wc -l < "$ENTRADA")
    if [ "$carregadas" != "$esperadas" ]; then
        echo "carga do SQLite: $carregadas linhas, esperava $esperadas" >&2
        exit 1
    fi

    # E o `juros.sql` SEM ALTERAÇÃO, como no PostgreSQL.
    sqlite3 -noheader -list "$BANCO" < "$AQUI/juros.sql" > "$SAIDA" || exit 1
    ;;

*)
    echo "motor desconhecido: $MOTOR (use postgres ou sqlite)" >&2
    exit 64
    ;;
esac

# O arquivo tem de terminar com nova linha, como os das outras
# implementações: um `cmp` entre um arquivo com `\n` final e outro sem acusa
# diferença de TAMANHO, e a mensagem fala de EOF em vez de falar do dado.
if [ -s "$SAIDA" ] && [ "$(tail -c1 "$SAIDA" | wc -l)" -eq 0 ]; then
    echo >> "$SAIDA"
fi

exit 0
