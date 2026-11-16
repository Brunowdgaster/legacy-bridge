#!/usr/bin/env bash
# verifica.sh — a suíte do p13-legacy-bridge.
#
# A prova que este projeto entrega é a que bancos pagam caro: **o lote em
# COBOL e o lote migrado produzem o mesmo arquivo, byte a byte.**
#
# O instrumento é o `cmp`, e isso é deliberado. Ao contrário do
# `p05-datalab`, aqui não há tolerância a definir — porque o domínio é
# decimal de ponto fixo, e em decimal de ponto fixo a resposta certa é uma só.
# Se precisasse de tolerância, a migração estaria errada.
#
# E a suíte **exige que a versão em `double` divirja**: é a previsão do
# projeto, e se um dia ela coincidir, é porque o conjunto de dados perdeu os
# casos de borda.
set -uo pipefail

cd "$(dirname "$0")"

OK=0
FALHOU=0
PULADO=0

EXIGE="${P13_EXIGE:-0}"

verde()    { printf '\033[32m%s\033[0m' "$1"; }
vermelho() { printf '\033[31m%s\033[0m' "$1"; }
cinza()    { printf '\033[90m%s\033[0m' "$1"; }

passa() { printf '  %s    %s\n' "$(verde ok)" "$1"; OK=$((OK+1)); }
falha() { printf '  %s %s\n' "$(vermelho FALHA)" "$1"; FALHOU=$((FALHOU+1)); }
pula()  {
    if [ "$EXIGE" = "1" ]; then
        printf '  %s %s\n' "$(vermelho FALHA)" "$1 (P13_EXIGE=1)"
        FALHOU=$((FALHOU+1))
    else
        printf '  %s  %s\n' "$(cinza pulado)" "$1"
        PULADO=$((PULADO+1))
    fi
}
secao() { printf '\n%s\n' "$(cinza "$1")"; }
tem()   { command -v "$1" >/dev/null 2>&1; }

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

mkdir -p saida

printf '\n%s\n' '=============================================================='
printf '%s\n' 'legacy-bridge — o lote em COBOL e o migrado, byte a byte'
printf '%s\n' '=============================================================='

# ---------------------------------------------------------------------------
secao 'dados/ — o formato de largura fixa'

if ! tem python3; then
    pula 'python3 ausente: não posso regerar os dados'
else
    if python3 dados/gera.py >/dev/null 2>&1; then
        passa 'dados/contas.dat é regerado deterministicamente'
    else
        falha 'a geração dos dados falhou'
    fi
fi

# Todo registro com a largura EXATA. Um registro curto lido como se estivesse
# certo produz numeros plausiveis e errados, que e o pior resultado possivel
# num lote financeiro.
larguras=$(awk '{print length}' dados/contas.dat | sort -u | tr '\n' ' ')
if [ "$(printf '%s' "$larguras" | tr -d ' ')" = "26" ]; then
    passa 'todos os registros de entrada têm 26 caracteres'
else
    falha "larguras encontradas na entrada: $larguras"
fi

n_contas=$(wc -l < dados/contas.dat)
if [ "$n_contas" -ge 14 ]; then
    passa "$n_contas contas, com os casos de borda do FORMATO.md"
else
    falha "só $n_contas contas: os casos de borda sumiram"
fi

# ---------------------------------------------------------------------------
secao 'cobol/ — o sistema original, que é a especificação executável'

if ! tem cobc; then
    pula 'cobc ausente: sudo apt-get install gnucobol'
else
    # O aviso `_FORTIFY_SOURCE redefined` vem do gcc invocado pelo cobc nesta
    # distribuicao, e nao do programa COBOL. Filtra-lo por NOME e mais honesto
    # que silenciar tudo: qualquer outro aviso continua aparecendo.
    saida_cob=$(cobc -x -free -Wall -o cobol/juros cobol/juros.cob 2>&1 \
        | grep -vE '_FORTIFY_SOURCE|previous definition|^<command-line>')

    if [ -z "$saida_cob" ] && [ -x cobol/juros ]; then
        passa 'o COBOL compila com -Wall, sem aviso do programa'
    else
        falha 'o COBOL não compila limpo'
        printf '%s\n' "$saida_cob" | head -4 | sed 's/^/        /'
    fi

    if [ -x cobol/juros ]; then
        if ./cobol/juros dados/contas.dat saida/cobol.dat >/dev/null 2>&1; then
            passa 'o lote COBOL roda e grava o relatório'
        else
            falha 'o lote COBOL falhou'
        fi

        larg_rel=$(awk '{print length}' saida/cobol.dat | sort -u | tr -d '\n ')
        if [ "$larg_rel" = "52" ]; then
            passa 'todo registro de saída tem 52 caracteres'
        else
            falha "larguras na saída: $larg_rel"
        fi

        # Um lote vazio tem de FALHAR, e nao terminar em zero. Um batch que
        # reporta sucesso tendo processado nada e a falha mais calada que
        # existe: o escalonador marca ok e ninguem olha o arquivo.
        : > saida/vazio.dat
        if ./cobol/juros saida/vazio.dat saida/lixo.dat >/dev/null 2>&1; then
            falha 'o COBOL aceitou entrada vazia e saiu com zero'
        else
            passa 'entrada vazia faz o lote falhar, em vez de reportar sucesso'
        fi
        rm -f saida/vazio.dat saida/lixo.dat
    fi
fi

# ---------------------------------------------------------------------------
secao 'a migração: C# e VB.NET contra o COBOL'

if ! tem dotnet; then
    pula 'dotnet ausente'
elif [ ! -s saida/cobol.dat ]; then
    pula 'sem o relatório do COBOL não há o que comparar'
else
    # --- C# ---------------------------------------------------------------
    if dotnet build csharp -c Release -v q --nologo >/dev/null 2>&1; then
        passa 'o C# compila com avisos tratados como erro e Nullable ligado'
    else
        falha 'o C# não compila'
    fi

    DLL_CS=$(find csharp/bin -name juros.dll 2>/dev/null | head -1)
    if [ -n "$DLL_CS" ]; then
        dotnet "$DLL_CS" dados/contas.dat saida/csharp.dat >/dev/null 2>&1

        # ESTA e a prova do projeto.
        if cmp -s saida/cobol.dat saida/csharp.dat; then
            passa 'C# com decimal: IDÊNTICO ao COBOL, byte a byte'
        else
            falha 'C# divergiu do COBOL'
            diff saida/cobol.dat saida/csharp.dat | head -6 | sed 's/^/        /'
        fi

        # E esta e a previsao que a suite EXIGE que se cumpra.
        dotnet "$DLL_CS" --double dados/contas.dat saida/double.dat >/dev/null 2>&1
        if cmp -s saida/cobol.dat saida/double.dat; then
            falha 'C# com double NÃO divergiu: os casos de borda sumiram dos dados'
        else
            n=$(diff saida/cobol.dat saida/double.dat | grep -c '^<')
            passa "C# com double diverge em $n registro(s), como previsto"
            diff saida/cobol.dat saida/double.dat \
                | grep -E '^[<>]' | head -4 | sed 's/^/        /'
        fi
    fi

    # --- VB.NET -----------------------------------------------------------
    if dotnet build vbnet -c Release -v q --nologo >/dev/null 2>&1; then
        passa 'o VB.NET compila com Option Strict e Explicit ligados'
    else
        falha 'o VB.NET não compila'
    fi

    DLL_VB=$(find vbnet/bin -name 'juros-vb.dll' 2>/dev/null | head -1)
    if [ -n "$DLL_VB" ]; then
        dotnet "$DLL_VB" dados/contas.dat saida/vbnet.dat >/dev/null 2>&1
        if cmp -s saida/cobol.dat saida/vbnet.dat; then
            passa 'VB.NET: IDÊNTICO ao COBOL, byte a byte'
        else
            falha 'VB.NET divergiu do COBOL'
            diff saida/cobol.dat saida/vbnet.dat | head -6 | sed 's/^/        /'
        fi
    fi
fi

# ---------------------------------------------------------------------------
secao 'as decisões que a regra fixou'

# Cada uma destas confere um CASO DE BORDA no relatorio, e nao a media. Sao os
# lugares onde migracao de legado falha, e onde teste de caminho feliz nao
# olha.
if [ -s saida/cobol.dat ]; then
    # Conta 3: juros de exatamente meio centavo -> sobe (away from zero).
    if grep -q '^00000003+000000000120+00000000100000000' saida/cobol.dat; then
        passa 'meio centavo exato arredonda PARA CIMA (0,005 → 0,01)'
    else
        falha 'o arredondamento de meio centavo mudou'
        grep '^00000003' saida/cobol.dat | sed 's/^/        /'
    fi

    # Conta 7 (999,99) paga tarifa ALTA; conta 8 (1000,00) paga BAIXA.
    if grep -q '^00000007.*0001500' saida/cobol.dat \
       && grep -q '^00000008.*0000500' saida/cobol.dat; then
        passa 'a faixa de 1000,00 usa < estrito: 999,99 paga 15, 1000,00 paga 5'
    else
        falha 'a fronteira da faixa de tarifa mudou'
    fi

    # Conta 6: saldo negativo -> sinal separado, e juros negativos.
    if grep -q '^00000006-000000120000-00000125' saida/cobol.dat; then
        passa 'saldo negativo dá juros negativos, com sinal separado'
    else
        falha 'o tratamento de saldo negativo mudou'
    fi

    # Contas 11 e 12: tarifa do tipo I presa no minimo e no maximo.
    if grep -q '^00000011.*0000200' saida/cobol.dat \
       && grep -q '^00000012.*0005000' saida/cobol.dat; then
        passa 'a tarifa do tipo I respeita o mínimo de 2,00 e o máximo de 50,00'
    else
        falha 'os limites da tarifa do tipo I mudaram'
    fi
fi

printf '\n%s\n' '=============================================================='
if [ "$PULADO" -gt 0 ]; then
    printf '  %s passaram, %s falharam, %s pulado(s)\n' \
        "$(verde "$OK")" "$FALHOU" "$(cinza "$PULADO")"
else
    printf '  %s passaram, %s falharam\n' "$(verde "$OK")" "$FALHOU"
fi
printf '%s\n\n' '=============================================================='

[ "$FALHOU" -eq 0 ]
