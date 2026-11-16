# O formato dos registros, e por que ele é assim

Este projeto migra um lote bancário em COBOL para C#, e a prova de
equivalência é **comparação byte a byte** da saída. Para isso existir, o
formato precisa ser especificado ao caractere — que é exatamente como sistemas
de mainframe sempre trocaram dados.

Nada aqui é nostalgia: arquivo de largura fixa continua sendo o formato de
intercâmbio de boa parte do sistema financeiro, e ler um layout como o de
baixo é o primeiro trabalho de quem chega num projeto de legado.

## Entrada: `dados/contas.dat`, 26 caracteres por registro

| posição | campo | COBOL `PICTURE` | significado |
|---|---|---|---|
| 1–8 | `conta` | `9(8)` | número da conta, com zeros à esquerda |
| 9 | `sinal` | `X` | `+` ou `-` |
| 10–21 | `saldo` | `9(10)V99` | 12 dígitos, **ponto decimal implícito** |
| 22–25 | `taxa` | `9(4)` | taxa anual em pontos-base (`1250` = 12,50 %) |
| 26 | `tipo` | `X` | `C` corrente, `P` poupança, `I` investimento |

```
00000001+0000001000001250C
^^^^^^^^|^^^^^^^^^^^^^^^^^^
conta   sinal   saldo=10000.00  taxa=12.50%  tipo=C
```

### O ponto decimal implícito é o detalhe que importa

`9(10)V99` não guarda um ponto. O `V` marca onde o ponto **estaria**, e o
arquivo tem só dígitos: `000000100000` é `1000,00`.

Isso não é economia de espaço — é uma decisão de **tipo**. O número é um
decimal de ponto fixo com exatamente duas casas, e toda aritmética sobre ele é
decimal exata. Não há `0,1` que não se representa, porque não há binário no
caminho.

É a razão pela qual COBOL ainda roda dinheiro, e é o que este projeto mede.

### A taxa em pontos-base, e não em fração

`1250` em vez de `0.125`. Um inteiro, porque `0,125` em binário é exato mas
`0,127` não é — e uma taxa de juros lida de arquivo não pode depender de qual
valor por acaso cabe em base 2.

Converter para fração acontece **uma vez**, na divisão da fórmula, e o COBOL a
faz em decimal.

## Saída: `relatorio.dat`, 52 caracteres por registro

| posição | campo | `PICTURE` | |
|---|---|---|---|
| 1–8 | `conta` | `9(8)` | |
| 9–21 | `saldo` | `S9(10)V99` | sinal + 12 dígitos |
| 22–31 | `juros` | `S9(7)V99` | sinal + 9 dígitos |
| 32–39 | `tarifa` | `9(6)V99` | 8 dígitos, nunca negativa |
| 40–52 | `novo` | `S9(10)V99` | sinal + 12 dígitos |

```
00000001+0000001000000+000104160000150+000000103501
```

O sinal é **separado e à esquerda** (`SIGN IS LEADING SEPARATE` em COBOL).

A alternativa histórica é o *overpunch*: codificar o sinal no último dígito,
de forma que `-123` vire `12L`. Funciona, economiza um byte, e é a origem de
uma geração de bugs — porque o arquivo deixa de ser legível por qualquer coisa
que não conheça a tabela. Este projeto usa sinal separado, que é o que
qualquer migração sensata escolhe.

## A regra de negócio

Para cada conta:

```
juros  = saldo × (taxa / 10000) / 12     arredondado a 2 casas
tarifa = conforme o tipo (abaixo)
novo   = saldo + juros − tarifa
```

| tipo | tarifa |
|---|---|
| `C` corrente | `15,00` se o saldo for menor que `1000,00`; senão `5,00` |
| `P` poupança | zero |
| `I` investimento | `0,1 %` do saldo, mínimo `2,00`, máximo `50,00`, arredondado a 2 casas |

### O arredondamento é meio-para-cima, e isso é escolha

`ROUNDED` em COBOL arredonda **meio para longe de zero** por padrão: `0,005`
vira `0,01`, e `−0,005` vira `−0,01`.

O C# faz **meio para o par** por padrão (`MidpointRounding.ToEven`), em que
`0,005` vira `0,00` porque zero é par. **São resultados diferentes**, e essa é
a primeira coisa que quebra numa migração de COBOL para .NET.

A equivalência exige `MidpointRounding.AwayFromZero` explícito. Está testado.

## Os casos de borda do conjunto de dados

O arquivo não é aleatório. Ele tem, de propósito:

| conta | o que ela testa |
|---|---|
| `00000003` | juros que caem **exatamente** em meio centavo — onde o modo de arredondamento decide |
| `00000006` | saldo negativo, para o sinal separado e os juros negativos |
| `00000007` | saldo de `999,99`, um centavo abaixo da faixa de tarifa de `1000,00` |
| `00000008` | saldo de `1000,00` exato, **na** fronteira da faixa |
| `00000011` | tipo `I` com tarifa que bate no mínimo de `2,00` |
| `00000012` | tipo `I` com tarifa que bate no máximo de `50,00` |

Fronteira de faixa e empate de arredondamento são onde migração de legado
falha, e onde um teste de caminho feliz não olha.
