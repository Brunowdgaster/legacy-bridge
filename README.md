# legacy-bridge — o lote em COBOL e o migrado, byte a byte

Um lote bancário em **COBOL**, com arquivos de largura fixa, migrado para
**C#** e **VB.NET** — e a equivalência provada por `cmp`, não por confiança.

> **Status:** 5 das 9 linguagens previstas, com **24 verificações**. COBOL,
> C#, VB.NET e Object Pascal estão completos e produzem o **mesmo arquivo,
> byte a byte**. Ver [Roadmap](#roadmap).

## A prova, em uma linha

```
  ok    C# com decimal: IDÊNTICO ao COBOL, byte a byte
  ok    VB.NET: IDÊNTICO ao COBOL, byte a byte
  ok    Object Pascal com Currency: IDÊNTICO ao COBOL, byte a byte
  ok    C# com double diverge em 2 registro(s), como previsto
  ok    o Double do Pascal e o do C# erram IDENTICAMENTE: é o tipo
        < 00000013+000000140000+00000000400000000+000000140004
        > 00000013+000000140000+00000000300000000+000000140003
```

Quatro implementações da mesma regra sobre 14 contas, em linguagens de **três
épocas** — COBOL de 1959, Object Pascal de 1986, C# e VB.NET de 2000. Todas
idênticas ao original.

E duas delas, com **um único tipo trocado**, perdem um centavo — e perdem
**exatamente o mesmo centavo**, byte a byte entre si.

> Se o erro fosse da linguagem, dois `double` de linguagens diferentes
> errariam de formas diferentes. Eles erram identicamente: **o defeito é do
> tipo, não de quem o usa.**

## Por que `cmp`, e não tolerância

O `p05-datalab` deste portfólio compara com tolerância justificada, porque o
domínio é ponto flutuante e exigir igualdade reprovaria implementações
corretas.

**Aqui é o contrário, e por um motivo de domínio:** dinheiro é decimal de
ponto fixo, e em decimal de ponto fixo a resposta certa é **uma só**. Se esta
migração precisasse de tolerância, ela estaria errada.

A diferença entre os dois projetos não é de rigor — é de qual tipo o problema
pede.

## O que faz COBOL ainda rodar dinheiro

Três linhas, e não inércia:

```cobol
01 WS-SALDO  PIC S9(10)V99.
COMPUTE WS-JUROS ROUNDED = WS-SALDO * (REG-TAXA / 10000) / 12
MOVE WS-SALDO TO REL-SALDO
```

`PIC S9(10)V99` declara um **decimal de ponto fixo** com exatamente duas
casas. Não é `double`, não é aproximação binária: `0,10` é exatamente um
décimo, e somar centavos mil vezes dá o valor certo.

`COMPUTE ... ROUNDED` arredonda de forma especificada **pelo padrão da
linguagem**, não pela biblioteca que por acaso está ligada. E `MOVE` entre
`PICTURE`s diferentes trunca ou estende de forma definida, com as regras
escritas desde 1985.

> Nenhuma linguagem de propósito geral criada depois tratou dinheiro como tipo
> de primeira classe. O `decimal` do C# é o primeiro equivalente real — e é
> por isso que esta migração é possível byte a byte.

## As três coisas que a migração tem de acertar

### 1. `decimal`, e não `double`

O `--double` do C# é a **mesma regra, mesma ordem de operações, mesmo
arredondamento pedido**. Só o tipo muda. E ele diverge.

```
conta 13: saldo 1400,00 a 0,03% ao ano
  juros exatos:  0,035   (= 1400 × 0,0003 ÷ 12)
  em decimal:    0,04    meio para longe de zero
  em double:     0,03    um centavo a menos
```

`0,0003` não é representável em binário. O produto cai logo abaixo de `0,035`,
e o arredondamento desce em vez de subir.

### 2. `MidpointRounding.AwayFromZero`, explícito

O `ROUNDED` do COBOL arredonda meio **para longe de zero**: `0,005 → 0,01`.

O `Math.Round` do C# arredonda meio **para o par** por padrão: `0,005 → 0,00`,
porque zero é par.

São resultados diferentes, e é a primeira coisa que quebra numa migração de
COBOL para .NET. A conta `00000003` existe só para fixar isso.

### 3. O terminador de linha não pode ser decisão do sistema operacional

`NewLine = "\n"` explícito nas duas implementações .NET. No Windows o padrão
seria `\r\n`, e o arquivo deixaria de ser idêntico ao do COBOL em Linux.

Num projeto cuja prova é `cmp`, isso não é detalhe de portabilidade — é a
prova inteira.

## A previsão falhou primeiro, e eu procurei o contraexemplo

A primeira versão do conjunto de dados tinha 12 contas escolhidas à mão, e o
modo `--double` saiu **idêntico** ao COBOL. A afirmação "`double` está errado
para dinheiro" é verdadeira, mas aqueles 12 registros não a exibiam.

Em vez de afrouxar a afirmação, um programa varreu **saldos de 0,01 a 2000,00
contra taxas de 1 a 2500 pontos-base**, emulando os dois caminhos, e achou
onde eles divergem. As contas `00000013` e `00000014` vieram dessa busca, e
está escrito em `dados/gera.py` que vieram.

Taxas de 0,03 % ao ano são realistas — é a ordem de uma tarifa de custódia. E
é justamente em valor pequeno sobre saldo grande que o centavo perdido passa
despercebido.

## VB.NET, e três erros que custaram tempo

VB.NET está aqui porque foi a ponte que existiu de verdade: quando o VB6 saiu
de suporte, milhares de sistemas corporativos foram para VB.NET em vez de C#,
porque a sintaxe era familiar. Muitos nunca saíram de lá.

E ele produz o mesmo arquivo byte a byte — **a escolha entre VB.NET e C# é de
equipe, não de resultado.**

Fazê-lo compilar custou três tentativas, todas com a mesma mensagem:

```
BC30420: 'Sub Main' was not found in 'LegacyBridge.Juros'
```

| tentativa | hipótese | resultado |
|---|---|---|
| 1 | `Friend Module` esconde o ponto de entrada | errado |
| 2 | o declarador de array: `args() As String` em vez de `args As String()` | errado (embora a forma correta seja essa) |
| 3 | **testar o mínimo** em vez de supor | achou |

A causa: **o VB.NET prepende o `RootNamespace` do projeto ao namespace
declarado no arquivo.** Com `RootNamespace=LegacyBridge` no `.vbproj` e
`Namespace LegacyBridge` no `.vb`, o tipo real é
`LegacyBridge.LegacyBridge.Juros` — e o `StartupObject` não resolve.

No C# ao lado, o namespace do arquivo é **absoluto**, e `RootNamespace` só
afeta arquivos novos criados por ferramenta. **Duas linguagens da mesma
plataforma, com regra oposta para a mesma propriedade de projeto** — e nada no
erro aponta para isso.

A lição é a de sempre neste portfólio: a terceira tentativa foi a que parou de
supor e mediu.

## Object Pascal, e o bug que escondia o bug

O Object Pascal entra como o **cliente desktop** que acompanha o lote — o
arranjo é tão comum que virou arquétipo: processamento noturno em COBOL no
mainframe, e o atendente num aplicativo Delphi lendo os mesmos arquivos.
Quando o COBOL é migrado, o cliente tem de continuar concordando.

E ele tem o **mesmo par de tipos** que o C#, com nomes ainda mais explícitos:

| | para dinheiro | binário |
|---|---|---|
| **C#** | `decimal` (128 bits) | `double` |
| **Object Pascal** | `Currency` (Int64 escalado por 10 000, 4 casas) | `Double` |

`Currency` bate byte a byte com o COBOL. `Double` perde o centavo. Igual.

### Mas o `--double` do Pascal concordava com o COBOL, e por acidente

A primeira versão passou no teste errado: ela **não divergia**. Em vez de
aceitar, uma sonda mediu o porquê — e o achado é melhor que a demonstração
original.

`pascal/sonda_precisao.pas` imprime a mesma fração em três formas:

```
a fracao taxa/10000, em tres formas:
  constante literal : 0.00030000001424923539
  variavel Double   : 0.00029999999999999997
  variavel Single   : 0.00030000001424923539
```

**O FPC avalia `Integer / <literal real>` em precisão simples**, não em
`Double`. O erro relativo é `4,7e-08` — **cinco ordens de grandeza pior** que
o `1,1e-16` do `Double`.

E a consequência:

```
os juros, e o centavo que cada um grava:
  com constante literal: 0.03500000166241079600  -> 4
  com variavel Double  : 0.03499999999999999600  -> 3
```

O erro de precisão empurrou o valor para o **outro lado** do meio centavo, e
o programa gravava o centavo certo por um motivo errado.

> **Dois defeitos que se cancelam é o pior caso de correção que existe:** o
> teste passa, a demonstração parece funcionar, e o programa está errado por
> dois motivos ao mesmo tempo.

A correção são três constantes com tipo declarado (`DIVISOR_TAXA: Double =
10000.0`), e a suíte tem dois testes para isso: um que exige as constantes
tipadas no **código** — distinguindo código de comentário, porque o
comentário cita a forma errada para explicá-la — e um que **roda a sonda** e
exige que ela ainda reproduza o achado. Evidência que não executa envelhece
em silêncio.

## SQL: o mesmo arquivo, dois motores, 13 de 14 contas erradas

`sql/juros.sql` é **um arquivo**, executado sem alteração em PostgreSQL e
SQLite. O que muda é só a carga do arquivo de largura fixa, que fica no
`sql/roda.sh` — porque carregar arquivo é a única parte que o SQL padrão nunca
especificou.

O resultado:

| motor | saída |
|---|---|
| **PostgreSQL** | **idêntica ao COBOL, byte a byte**, nas 14 contas |
| **SQLite** | **13 das 14 contas erradas** |

### Por que o SQL acerta: `NUMERIC` é a mesma ideia do `PICTURE`

O problema central deste projeto — **dinheiro não é ponto flutuante** — tem no
SQL a resposta mais antiga de todas as linguagens aqui:

| | resolveu em |
|---|---|
| COBOL, `PICTURE 9(10)V99` | 1959 |
| SQL, `NUMERIC(p, s)` | 1992 (SQL-92) |
| C#, `decimal` | 2002 |

As três são a mesma coisa: ponto fixo decimal, exato. E o `ROUND` do
PostgreSQL sobre `NUMERIC` arredonda **meio para longe de zero** — que é
exatamente o `ROUNDED` do COBOL, **por omissão**. O C# precisou de
`MidpointRounding.AwayFromZero` explícito; o PostgreSQL acerta sem pedir.

### Por que o SQLite erra, e não é o que eu previ

Eu havia escrito no arquivo que o SQLite "trata o valor como `REAL`, ou seja
`double`". **Medido, é pior:**

```
sqlite> SELECT typeof(CAST('000000000120' AS NUMERIC));
integer
sqlite> SELECT CAST('000000000120' AS NUMERIC) / 100;
1
sqlite> SELECT CAST('1250' AS NUMERIC) / 10000;
0
```

O SQLite tem **afinidade** de tipo, não tipo. `NUMERIC` converte a string para
`integer` quando ela parece um inteiro — e `integer / integer` **trunca**.
Então `120 / 100` é `1` em vez de `1,20`, e `1250 / 10000` é **zero**: todos
os juros do lote saem nulos.

A mesma coluna chega a guardar tipos diferentes conforme o valor:

```sql
CREATE TABLE t (v NUMERIC(12,2));
INSERT INTO t VALUES (1.20), (120);
-- v=1.2  typeof=real   |   v=120  typeof=integer
```

E nada avisa em nenhum desses passos.

### A "correção óbvia" troca um erro catastrófico por um silencioso

A reação natural é trocar `/ 100` por `/ 100.0`. Medi, numa sonda com as 15
divisões do arquivo trocadas:

| divisão | contas erradas |
|---|---|
| `/ 100` (inteira) | **13 de 14** |
| `/ 100.0` (real) | **2 de 14** |

E as duas que sobram são **as contas 13 e 14**, que existem neste conjunto
justamente para testar arredondamento:

| | conta 13 | conta 14 |
|---|---|---|
| cálculo | 1400,00 × 0,03 % ÷ 12 | 840,00 × 0,05 % ÷ 12 |
| resultado exato | **0,035** | **0,035** |
| COBOL (`ROUNDED`) | 0,04 | 0,04 |
| SQLite, divisão real | **0,03** | **0,03** |

`0,035` **não é representável em binário**. O `double` mais próximo fica
*abaixo* do empate — então a pergunta "meio para cima ou meio para o par?"
nunca chega a ser feita: o valor simplesmente não está no meio.

> É o projeto inteiro em duas contas: o erro que se vê — 13 de 14 — se corrige
> num minuto. O que fica — 2 de 14 — só aparece quando alguém confere centavo
> por centavo.

A suíte **exige** a divergência: se o SQLite passar a bater, a afirmação acima
ficou obsoleta e o teste falha. É o mesmo desenho do `--double` do C# e do
Pascal.

### E o conselho que eu mesmo escrevi era a causa do bug

O comentário original do `juros.sql` dizia:

> *"a divisão precisa ser `/ 100` sobre NUMERIC, nunca `/ 100.0`, porque
> dividir por inteiro mantém o tipo."*

Está **certo no PostgreSQL** e é **exatamente o que quebra no SQLite**, onde
"manter o tipo" significa manter `integer`. O arquivo ficou com `/ 100` de
propósito — o PostgreSQL é o alvo da migração e a divergência é o conteúdo —
mas a frase foi corrigida para dizer isso.

### Dois defeitos meus no caminho, e por que estão escritos

**A carga do SQLite punha o arquivo inteiro numa linha.** `.import` com
`.mode ascii` usa 0x1F e 0x1E como separadores, e o arquivo não tem nenhum dos
dois — então os 1378 caracteres entraram como um único registro. O `SUBSTR`
pegou os 26 primeiros, a conta 1 foi calculada, e a saída teve **uma** linha
em vez de catorze, com números plausíveis.

O `diff` contra o COBOL diria *"13 de 14 divergiram"*, e eu teria registrado
uma falha de carga como divergência numérica. Agora o runner **confere a
contagem** antes de comparar, e a suíte falha com mensagem própria se os
arquivos tiverem tamanhos diferentes.

**E `LPAD` não existe no SQLite.** A primeira versão do arquivo usava `LPAD(x,
12, '0')` afirmando que ele "existe nos dois motores" — não existe, é extensão
de PostgreSQL e Oracle. A alternativa óbvia (`SUBSTR(s, -12)`) também não
serve: o SQLite conta do fim com índice negativo e o **PostgreSQL não**.

A forma portátil é a verbosa: concatenar zeros e recortar com `SUBSTR` e
`LENGTH`. É o arquivo demonstrando o próprio assunto — **o SQL que roda em
dois motores é bem menor do que parece, e a parte que não roda só aparece
quando se testa nos dois.**

## Os casos de borda, e por que cada um existe

| conta | o que ela fixa |
|---|---|
| `00000003` | juros de **exatamente meio centavo** — onde o modo de arredondamento decide |
| `00000006` | saldo negativo: sinal separado e juros negativos |
| `00000007` | `999,99` — um centavo **abaixo** da faixa de tarifa |
| `00000008` | `1000,00` exato — **na** fronteira, e `<` estrito põe na tarifa baixa |
| `00000011` | tarifa do tipo `I` presa no **mínimo** de 2,00 |
| `00000012` | tarifa do tipo `I` presa no **máximo** de 50,00 |
| `00000013`, `00000014` | **achadas por busca**: onde o `double` perde um centavo |

Fronteira de faixa e empate de arredondamento são onde migração de legado
falha, e a suíte confere cada um por `grep` no relatório — não a média.

## E o lote vazio tem de falhar

```
  ok    entrada vazia faz o lote falhar, em vez de reportar sucesso
```

Um batch que termina em zero tendo processado nada é a falha mais calada que
existe: o escalonador marca sucesso, e ninguém olha o arquivo. O COBOL devolve
`RETURN-CODE 65`, e a suíte verifica.

## O formato de largura fixa

Está especificado ao caractere em **[FORMATO.md](FORMATO.md)** — entrada de 26
posições, saída de 52, com ponto decimal **implícito** e sinal **separado à
esquerda**.

O ponto implícito não é economia de espaço: é uma decisão de **tipo**.
`000000100000` é `1000,00`, e o `V` do `PIC 9(10)V99` marca onde o ponto
estaria. Não há `0,1` que não se representa, porque não há binário no
caminho.

## Rodando

```bash
sudo apt-get install -y gnucobol
# o .NET SDK 10 também é necessário
./verifica.sh
```

A suíte **pula** o que não está instalado, e `P13_EXIGE=1` transforma todo
"pulado" em falha — que é o que o CI liga.

## Roadmap

| linguagem | o que mostra | situação |
|---|---|---|
| **COBOL** | o sistema original, e a especificação executável | ✅ feito |
| **C#** | o destino da migração, com `decimal` — e a armadilha do `double` ao lado | ✅ feito |
| **VB.NET** | a ponte que as empresas de fato usaram | ✅ feito |
| **Object Pascal** | o cliente desktop, e o mesmo par `Currency`/`Double` | ✅ feito |
| **SQL** | que o mesmo arquivo em dois motores dá **13 de 14 contas erradas** num deles | ✅ feito |
| **PL/I** | o outro dialeto de mainframe — Iron Spring, gratuito para Linux | a fazer |
| **RPG** | IBM i, via PUB400.com (sistema público e gratuito) | a fazer — exige conta |
| **ABAP** | SAP, via BTP Trial | a fazer — conta de 90 dias |
| **Apex** | Salesforce, org de desenvolvedor gratuita | a fazer — exige conta |

Os quatro últimos entram como **módulos equivalentes documentados**: a mesma
regra de negócio traduzida, mais um ensaio sobre o ecossistema de cada um. É o
que o plano original pede, e é honesto sobre o que cada ambiente permite
automatizar.

## Licença

MIT, em `LICENSE`.
