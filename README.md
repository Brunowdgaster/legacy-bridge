# legacy-bridge — o lote em COBOL e o migrado, byte a byte

Um lote bancário em **COBOL**, com arquivos de largura fixa, migrado para
**C#** e **VB.NET** — e a equivalência provada por `cmp`, não por confiança.

> **Status:** 3 das 9 linguagens previstas, com **16 verificações**. COBOL, C#
> e VB.NET estão completos e produzem o **mesmo arquivo, byte a byte**. Ver
> [Roadmap](#roadmap).

## A prova, em uma linha

```
  ok    C# com decimal: IDÊNTICO ao COBOL, byte a byte
  ok    VB.NET: IDÊNTICO ao COBOL, byte a byte
  ok    C# com double diverge em 2 registro(s), como previsto
        < 00000013+000000140000+00000000400000000+000000140004
        > 00000013+000000140000+00000000300000000+000000140003
```

Três implementações da mesma regra sobre 14 contas. Duas são idênticas ao
original. A terceira troca **um único tipo** e perde um centavo.

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
| **Object Pascal** | o cliente desktop legado (Free Pascal já instalado) | a fazer |
| **SQL** | a mesma regra como consulta, para relatório | a fazer |
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
