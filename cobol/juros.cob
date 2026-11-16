      *> juros.cob — o lote bancário original, em COBOL.
      *>
      *>     cobc -x -free -o cobol/juros cobol/juros.cob
      *>     ./cobol/juros dados/contas.dat saida/cobol.dat
      *>
      *> ## Este é o sistema que está sendo migrado
      *>
      *> O projeto inteiro existe para provar que a versão em C# faz
      *> exatamente o que este programa faz -- byte a byte, no arquivo de
      *> saída. Então este arquivo é a ESPECIFICAÇÃO EXECUTÁVEL, e não uma
      *> tradução de algo escrito antes.
      *>
      *> É assim que migração de legado funciona de verdade: o código antigo
      *> é a única fonte confiável da regra, porque a documentação envelheceu
      *> e quem escreveu saiu.
      *>
      *> ## Por que COBOL ainda roda dinheiro
      *>
      *> Por causa de três linhas abaixo, e não por inércia.
      *>
      *> `PIC S9(10)V99` declara um número **decimal de ponto fixo** com
      *> exatamente duas casas. Não é `double`, não é aproximação binária: é
      *> um tipo em que `0,10` é exatamente um décimo, e em que somar centavos
      *> mil vezes dá o valor certo.
      *>
      *> `COMPUTE ... ROUNDED` arredonda de forma especificada pelo padrão da
      *> linguagem, e não pela biblioteca que por acaso está ligada.
      *>
      *> E `MOVE` entre PICTURES diferentes **trunca ou estende de forma
      *> definida**, com as regras escritas no padrão desde 1985.
      *>
      *> Nenhuma linguagem de propósito geral criada depois tratou dinheiro
      *> como tipo de primeira classe. O `decimal` do C# -- de 2000 -- é o
      *> primeiro equivalente real, e é por isso que a migração deste projeto
      *> é possível byte a byte.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. JUROS.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *> LINE SEQUENTIAL, e nao RECORD SEQUENTIAL: o arquivo tem quebra de
      *> linha entre registros, o que o torna legivel por `cat`, `wc -l` e
      *> `cmp` -- e portanto comparavel pelas outras implementacoes sem
      *> nenhuma delas precisar conhecer formato de bloco de mainframe.
           SELECT ARQ-CONTAS ASSIGN TO WS-ARQ-ENTRADA
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-STATUS-ENT.
           SELECT ARQ-SAIDA ASSIGN TO WS-ARQ-SAIDA
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-STATUS-SAI.

       DATA DIVISION.
       FILE SECTION.

      *> O registro de entrada, campo por campo, nas posicoes que FORMATO.md
      *> especifica. A declaracao E o layout: nao ha parser, nao ha split por
      *> delimitador, nao ha indice calculado a mao.
      *>
      *> E a leitura de `REG-SALDO` como PIC 9(10)V99 ja entrega o numero
      *> decimal pronto -- o ponto implicito e aplicado pelo tipo, nao por
      *> uma divisao por 100 que alguem pode esquecer.
       FD ARQ-CONTAS.
       01 REG-CONTA.
           05 REG-NUMERO       PIC 9(8).
           05 REG-SINAL        PIC X.
           05 REG-SALDO        PIC 9(10)V99.
           05 REG-TAXA         PIC 9(4).
           05 REG-TIPO         PIC X.

       FD ARQ-SAIDA.
       01 REG-REL.
           05 REL-NUMERO       PIC 9(8).
           05 REL-SALDO        PIC S9(10)V99 SIGN IS LEADING SEPARATE.
           05 REL-JUROS        PIC S9(7)V99 SIGN IS LEADING SEPARATE.
           05 REL-TARIFA       PIC 9(6)V99.
           05 REL-NOVO         PIC S9(10)V99 SIGN IS LEADING SEPARATE.

       WORKING-STORAGE SECTION.
       01 WS-ARQ-ENTRADA       PIC X(256).
       01 WS-ARQ-SAIDA         PIC X(256).
       01 WS-STATUS-ENT        PIC XX.
       01 WS-STATUS-SAI        PIC XX.
       01 WS-FIM               PIC X VALUE "N".
       01 WS-LIDOS             PIC 9(8) VALUE 0.

      *> O saldo COM SINAL, montado a partdo campo de sinal da entrada.
      *>
      *> A entrada guarda sinal e magnitude separados; o calculo precisa do
      *> numero. Esta variavel e a ponte, e ela existe explicitamente em vez
      *> de um truque de redefinicao -- porque num projeto de migracao o
      *> codigo tem de ser LEGIVEL por quem vai traduzi-lo.
       01 WS-SALDO             PIC S9(10)V99.
       01 WS-JUROS             PIC S9(7)V99.
       01 WS-TARIFA            PIC 9(6)V99.
       01 WS-NOVO              PIC S9(10)V99.

      *> A tarifa do tipo I antes dos limites de minimo e maximo.
       01 WS-TARIFA-BRUTA      PIC 9(9)V99.

      *> As constantes da regra, declaradas com o tipo do dominio.
      *>
      *> `VALUE 1000.00` num PIC 9(6)V99 e exatamente mil -- nao
      *> 999,9999999999. E a diferenca entre a comparacao de faixa funcionar
      *> e falhar no centavo da fronteira, que e o que a conta 00000008 testa.
       01 CT-FAIXA-CORRENTE    PIC 9(6)V99 VALUE 1000.00.
       01 CT-TARIFA-ALTA       PIC 9(4)V99 VALUE 15.00.
       01 CT-TARIFA-BAIXA      PIC 9(4)V99 VALUE 5.00.
       01 CT-TARIFA-MIN        PIC 9(4)V99 VALUE 2.00.
       01 CT-TARIFA-MAX        PIC 9(4)V99 VALUE 50.00.

       PROCEDURE DIVISION.

       PRINCIPAL.
           ACCEPT WS-ARQ-ENTRADA FROM ARGUMENT-VALUE
           ACCEPT WS-ARQ-SAIDA FROM ARGUMENT-VALUE

           IF WS-ARQ-ENTRADA = SPACES OR WS-ARQ-SAIDA = SPACES
      *> Falha ALTO, com codigo de saida. Um lote que termina em zero tendo
      *> processado nada e a falha mais caalada que existe num sistema batch:
      *> o escalonador marca sucesso e ninguem olha o arquivo vazio.
               DISPLAY "uso: juros <entrada> <saida>" UPON SYSERR
               MOVE 64 TO RETURN-CODE
               STOP RUN
           END-IF

           OPEN INPUT ARQ-CONTAS
           IF WS-STATUS-ENT NOT = "00"
               DISPLAY "nao abri a entrada, status " WS-STATUS-ENT
                   UPON SYSERR
               MOVE 66 TO RETURN-CODE
               STOP RUN
           END-IF

           OPEN OUTPUT ARQ-SAIDA
           IF WS-STATUS-SAI NOT = "00"
               DISPLAY "nao abri a saida, status " WS-STATUS-SAI
                   UPON SYSERR
               MOVE 73 TO RETURN-CODE
               STOP RUN
           END-IF

           PERFORM UNTIL WS-FIM = "S"
               READ ARQ-CONTAS
                   AT END
                       MOVE "S" TO WS-FIM
                   NOT AT END
                       PERFORM PROCESSA-CONTA
                       ADD 1 TO WS-LIDOS
               END-READ
           END-PERFORM

           CLOSE ARQ-CONTAS
           CLOSE ARQ-SAIDA

      *> Um lote que nao processou registro nenhum e ERRO, nao sucesso.
           IF WS-LIDOS = 0
               DISPLAY "nenhum registro processado" UPON SYSERR
               MOVE 65 TO RETURN-CODE
               STOP RUN
           END-IF

           DISPLAY "registros: " WS-LIDOS UPON SYSERR
           STOP RUN.

       PROCESSA-CONTA.
      *> Monta o saldo com sinal.
           MOVE REG-SALDO TO WS-SALDO
           IF REG-SINAL = "-"
               COMPUTE WS-SALDO = 0 - REG-SALDO
           END-IF

      *> Os juros.
      *>
      *> `ROUNDED` sem qualificador usa NEAREST-AWAY-FROM-ZERO: meio centavo
      *> sobe, e meio centavo negativo desce. E o padrao da linguagem, nao da
      *> biblioteca -- e e por isso que a versao em C# precisa pedir
      *> `MidpointRounding.AwayFromZero` explicitamente, porque o padrao DELA
      *> e meio-para-o-par.
      *>
      *> A ordem das operacoes esta escrita como a regra: taxa sobre 10000
      *> para virar fracao, e depois dividido por 12 para virar mensal. Um
      *> `COMPUTE` em COBOL usa precisao intermediaria suficiente para a
      *> expressao, o que e definido no padrao.
           COMPUTE WS-JUROS ROUNDED =
               WS-SALDO * (REG-TAXA / 10000) / 12

      *> A tarifa, por tipo.
           EVALUATE REG-TIPO
               WHEN "C"
      *> A comparacao de faixa usa `<`, estritamente. Saldo de exatamente
      *> 1000,00 cai na tarifa BAIXA -- e a conta 00000008 existe para fixar
      *> essa decisao, porque "menor que" e "menor ou igual" dão relatorios
      *> diferentes e ninguem lembra qual a especificacao dizia.
                   IF WS-SALDO < CT-FAIXA-CORRENTE
                       MOVE CT-TARIFA-ALTA TO WS-TARIFA
                   ELSE
                       MOVE CT-TARIFA-BAIXA TO WS-TARIFA
                   END-IF

               WHEN "P"
                   MOVE 0 TO WS-TARIFA

               WHEN "I"
      *> 0,1 % do saldo. Saldo negativo nao gera tarifa negativa: a tarifa e
      *> um custo, e o `PIC 9(6)V99` sem sinal ja impediria -- mas depender do
      *> tipo para expressar a regra seria esconder a regra. O IF esta
      *> explicito.
                   IF WS-SALDO > 0
                       COMPUTE WS-TARIFA-BRUTA ROUNDED =
                           WS-SALDO * 1 / 1000
                   ELSE
                       MOVE 0 TO WS-TARIFA-BRUTA
                   END-IF

                   IF WS-TARIFA-BRUTA < CT-TARIFA-MIN
                       MOVE CT-TARIFA-MIN TO WS-TARIFA
                   ELSE
                       IF WS-TARIFA-BRUTA > CT-TARIFA-MAX
                           MOVE CT-TARIFA-MAX TO WS-TARIFA
                       ELSE
                           MOVE WS-TARIFA-BRUTA TO WS-TARIFA
                       END-IF
                   END-IF

               WHEN OTHER
      *> Tipo desconhecido e ERRO, e nao "trata como corrente". Um lote que
      *> adivinha o que fazer com dado que nao reconhece e um lote que produz
      *> relatorio errado em silencio.
                   DISPLAY "tipo invalido na conta " REG-NUMERO
                       ": " REG-TIPO UPON SYSERR
                   MOVE 65 TO RETURN-CODE
                   STOP RUN
           END-EVALUATE

           COMPUTE WS-NOVO = WS-SALDO + WS-JUROS - WS-TARIFA

           MOVE REG-NUMERO TO REL-NUMERO
           MOVE WS-SALDO TO REL-SALDO
           MOVE WS-JUROS TO REL-JUROS
           MOVE WS-TARIFA TO REL-TARIFA
           MOVE WS-NOVO TO REL-NOVO

           WRITE REG-REL.

       END PROGRAM JUROS.
