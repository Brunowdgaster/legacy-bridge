// Juros.cs — a migração do lote COBOL para C#, e a armadilha ao lado.
//
//     dotnet build csharp -c Release
//     dotnet csharp/bin/Release/net10.0/juros.dll dados/contas.dat saida/csharp.dat
//     dotnet csharp/bin/Release/net10.0/juros.dll --double dados/contas.dat saida/double.dat
//
// ## O que este arquivo prova, e o que ele desmente
//
// **Prova:** a migração de COBOL para C# pode ser byte a byte exata. O
// arquivo gerado no modo padrão é idêntico ao do `cobol/juros.cob`, e a suíte
// usa `cmp`.
//
// **Desmente:** que isso aconteça por acaso. O modo `--double` é a mesma
// regra, a mesma ordem de operações, o mesmo arredondamento pedido — e só
// troca o TIPO. Ele produz um arquivo diferente, e a suíte exige que
// produza.
//
// ## As três coisas que precisam estar certas
//
// **1. `decimal`, e não `double`.**
//
// O `decimal` do C# é ponto fixo decimal de 128 bits: `0,1` é exatamente um
// décimo, como no `PIC S9(10)V99` do COBOL. O `double` é binário IEEE 754, em
// que `0,1` é `0,1000000000000000055511151231257827…`.
//
// Em dinheiro isso não é detalhe: é o centavo que não fecha no fim do mês.
//
// **2. `MidpointRounding.AwayFromZero`, explícito.**
//
// O `ROUNDED` do COBOL arredonda meio **para longe de zero**: `0,005 → 0,01`.
// O `Math.Round` do C# arredonda meio **para o par** por padrão: `0,005 →
// 0,00`, porque zero é par.
//
// São resultados diferentes, e é a primeira coisa que quebra numa migração de
// COBOL para .NET. A conta `00000003` do conjunto de dados cai exatamente em
// meio centavo para fixar isso.
//
// **3. A formatação de largura fixa, com sinal separado.**
//
// `PIC S9(10)V99 SIGN IS LEADING SEPARATE` vira sinal + 12 dígitos, sem
// ponto. Em C# isso é `(valor < 0 ? "-" : "+")` mais o inteiro escalado por
// 100, preenchido com zeros à esquerda.
//
// E o escalonamento é feito em `decimal`, não em `double`: `(long)(x * 100m)`
// é exato, e `(long)(x * 100.0)` pode devolver o inteiro de baixo.

using System;
using System.Globalization;
using System.IO;

internal static class Juros
{
    // As constantes da regra, como `decimal` literal (o sufixo `m`).
    //
    // `1000.00m` e nao `1000.00`: sem o sufixo, o literal e `double`, e a
    // comparacao de faixa passaria por uma conversao -- que e exatamente o
    // tipo de detalhe que faz uma migracao divergir num registro de cada mil.
    private const decimal FaixaCorrente = 1000.00m;
    private const decimal TarifaAlta = 15.00m;
    private const decimal TarifaBaixa = 5.00m;
    private const decimal TarifaMin = 2.00m;
    private const decimal TarifaMax = 50.00m;

    private static int Main(string[] args)
    {
        bool usarDouble = Array.IndexOf(args, "--double") >= 0;
        string[] livres = Array.FindAll(args, a => !a.StartsWith("--", StringComparison.Ordinal));

        if (livres.Length != 2)
        {
            Console.Error.WriteLine("uso: juros [--double] <entrada> <saida>");
            return 64;
        }

        string entrada = livres[0];
        string saida = livres[1];

        if (!File.Exists(entrada))
        {
            Console.Error.WriteLine($"não achei {entrada}");
            return 66;
        }

        int lidos = 0;

        // `\n` explícito, e não `Environment.NewLine`.
        //
        // No Windows o padrão seria `\r\n`, e o arquivo deixaria de ser
        // idêntico ao do COBOL em Linux. Um projeto cuja prova é `cmp` não
        // pode deixar o terminador de linha para o sistema operacional
        // decidir -- e este é o tipo de divergência que só aparece quando
        // alguém roda a migração na própria máquina.
        using (var sw = new StreamWriter(saida) { NewLine = "\n" })
        {
            foreach (string linha in File.ReadLines(entrada))
            {
                if (linha.Length == 0)
                {
                    continue;
                }

                if (linha.Length != 26)
                {
                    // Falha ALTO. Um registro de largura errada lido como se
                    // estivesse certo produz numeros plausiveis e errados, que
                    // e o pior resultado possivel num lote financeiro.
                    Console.Error.WriteLine(
                        $"registro {lidos + 1} tem {linha.Length} chars, esperado 26");
                    return 65;
                }

                // `string?`, e nao `string`: as duas rotinas devolvem nulo
                // quando o tipo de conta e invalido, e o compilador com
                // `Nullable` ligado recusou a atribuicao -- CS8600, tratado
                // como erro pelo .csproj.
                //
                // Foi a politica de aviso-como-erro pegando um bug real de
                // quem a escreveu: sem ela, um tipo invalido faria o
                // `WriteLine` receber nulo e o lote gravaria a palavra vazia
                // em vez de abortar.
                string? resultado = usarDouble
                    ? ProcessaComDouble(linha)
                    : ProcessaComDecimal(linha);

                if (resultado is null)
                {
                    return 65;
                }

                sw.WriteLine(resultado);
                lidos++;
            }
        }

        if (lidos == 0)
        {
            Console.Error.WriteLine("nenhum registro processado");
            return 65;
        }

        Console.Error.WriteLine($"registros: {lidos:D8}");
        return 0;
    }

    // ---------------------------------------------------------------- campos

    private static decimal LeValor(string s, char sinal)
    {
        // O ponto decimal implícito: 12 dígitos, duas casas.
        //
        // A divisão por 100m é em `decimal`, então é exata. Fazê-la em
        // `double` introduziria erro antes da primeira conta.
        decimal magnitude = decimal.Parse(s, CultureInfo.InvariantCulture) / 100m;
        return sinal == '-' ? -magnitude : magnitude;
    }

    private static string Formata(decimal valor, int digitos, bool comSinal)
    {
        // Escalonamento em `decimal`, e arredondamento explícito antes do
        // truncamento: `(long)` em C# TRUNCA, e um valor que já deveria estar
        // em duas casas pode ter resíduo se tiver passado por `double`.
        decimal q = Math.Round(valor, 2, MidpointRounding.AwayFromZero);
        long escalado = (long)Math.Abs(q * 100m);

        string corpo = escalado.ToString(CultureInfo.InvariantCulture)
                               .PadLeft(digitos, '0');

        if (corpo.Length > digitos)
        {
            throw new OverflowException(
                $"{valor} não cabe em {digitos} dígitos");
        }

        if (!comSinal)
        {
            return corpo;
        }

        return (q < 0 ? "-" : "+") + corpo;
    }

    // --------------------------------------------------------- com `decimal`

    private static string? ProcessaComDecimal(string linha)
    {
        string numero = linha.Substring(0, 8);
        char sinal = linha[8];
        decimal saldo = LeValor(linha.Substring(9, 12), sinal);
        int taxa = int.Parse(linha.Substring(21, 4), CultureInfo.InvariantCulture);
        char tipo = linha[25];

        // Os juros. A ordem das operações é a mesma do `COMPUTE` do COBOL, e
        // `MidpointRounding.AwayFromZero` é o que torna o `ROUNDED` dele
        // equivalente.
        decimal juros = Math.Round(
            saldo * (taxa / 10000m) / 12m, 2, MidpointRounding.AwayFromZero);

        decimal tarifa;
        switch (tipo)
        {
            case 'C':
                // `<` estrito: saldo de exatamente 1000,00 cai na tarifa
                // BAIXA. A conta 00000008 fixa essa decisão.
                tarifa = saldo < FaixaCorrente ? TarifaAlta : TarifaBaixa;
                break;

            case 'P':
                tarifa = 0m;
                break;

            case 'I':
                decimal bruta = saldo > 0m
                    ? Math.Round(saldo * 1m / 1000m, 2, MidpointRounding.AwayFromZero)
                    : 0m;
                tarifa = bruta < TarifaMin ? TarifaMin
                       : bruta > TarifaMax ? TarifaMax
                       : bruta;
                break;

            default:
                Console.Error.WriteLine($"tipo inválido na conta {numero}: {tipo}");
                return null;
        }

        decimal novo = saldo + juros - tarifa;

        return numero
             + Formata(saldo, 12, comSinal: true)
             + Formata(juros, 9, comSinal: true)
             + Formata(tarifa, 8, comSinal: false)
             + Formata(novo, 12, comSinal: true);
    }

    // ---------------------------------------------------------- com `double`
    //
    // A MESMA regra, a MESMA ordem de operações, o MESMO arredondamento
    // pedido. A única diferença é o tipo.
    //
    // Este método existe para ser medido, não para ser usado. Ele é a
    // migração que alguém escreve sem pensar no tipo -- e a suíte EXIGE que
    // ele produza arquivo diferente, porque se um dia ele passar a coincidir,
    // é porque o conjunto de dados perdeu os casos de borda.

    private static string? ProcessaComDouble(string linha)
    {
        string numero = linha.Substring(0, 8);
        char sinal = linha[8];
        double magnitude = double.Parse(linha.Substring(9, 12),
                                        CultureInfo.InvariantCulture) / 100.0;
        double saldo = sinal == '-' ? -magnitude : magnitude;
        int taxa = int.Parse(linha.Substring(21, 4), CultureInfo.InvariantCulture);
        char tipo = linha[25];

        double juros = Math.Round(
            saldo * (taxa / 10000.0) / 12.0, 2, MidpointRounding.AwayFromZero);

        double tarifa;
        switch (tipo)
        {
            case 'C':
                tarifa = saldo < 1000.00 ? 15.00 : 5.00;
                break;
            case 'P':
                tarifa = 0.0;
                break;
            case 'I':
                double bruta = saldo > 0.0
                    ? Math.Round(saldo * 1.0 / 1000.0, 2, MidpointRounding.AwayFromZero)
                    : 0.0;
                tarifa = bruta < 2.00 ? 2.00 : bruta > 50.00 ? 50.00 : bruta;
                break;
            default:
                Console.Error.WriteLine($"tipo inválido na conta {numero}: {tipo}");
                return null;
        }

        double novo = saldo + juros - tarifa;

        return numero
             + FormataDouble(saldo, 12, true)
             + FormataDouble(juros, 9, true)
             + FormataDouble(tarifa, 8, false)
             + FormataDouble(novo, 12, true);
    }

    private static string FormataDouble(double valor, int digitos, bool comSinal)
    {
        double q = Math.Round(valor, 2, MidpointRounding.AwayFromZero);

        // `(long)` TRUNCA, e aqui está a perda: `q * 100.0` para um valor que
        // deveria ser exatamente 104,17 pode dar 10416,999999999998, e o
        // truncamento devolve 10416 -- um centavo a menos.
        //
        // Usar `Math.Round` aqui mascararia o problema, e o objetivo deste
        // método é exibi-lo. A versão em `decimal` não precisa de nenhuma das
        // duas defesas, porque `q * 100m` é exato.
        long escalado = (long)Math.Abs(q * 100.0);

        string corpo = escalado.ToString(CultureInfo.InvariantCulture)
                               .PadLeft(digitos, '0');

        return comSinal ? (q < 0 ? "-" : "+") + corpo : corpo;
    }
}
