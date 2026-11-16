' Juros.vb — a MESMA regra, em Visual Basic .NET.
'
' ## Por que VB.NET está num projeto de migração de legado
'
' Porque ele é a ponte que existiu de verdade.
'
' Quando o VB6 saiu de suporte, milhares de sistemas corporativos foram
' portados para VB.NET em vez de C# — porque a sintaxe era familiar e a
' equipe não precisava reaprender a escrever. Muitos nunca saíram de lá.
'
' Então num projeto que migra COBOL para .NET, o VB.NET é a etapa que muitas
' empresas de fato tomaram: o salto mínimo que já põe o código na plataforma
' nova. E este arquivo mostra que ele produz o MESMO arquivo byte a byte —
' a escolha entre VB.NET e C# é de equipe, não de resultado.
'
' ## O detalhe que decide, e que está no .vbproj
'
' `Option Strict On` e `Option Explicit On` fazem o compilador recusar
' conversão implícita que perde dados e variável não declarada. Com
' `Option Strict Off`, que é o padrão histórico, o VB converte String para
' Double em silêncio — e é assim que migração de VB6 vira um sistema que erra
' centavo.

Option Strict On
Option Explicit On

Imports System
Imports System.Globalization
Imports System.IO

' ## O `Namespace` NAO aparece neste arquivo, e isso e obrigatorio
'
' O VB.NET PREPENDE o `RootNamespace` do projeto ao namespace
' declarado no arquivo. Com `RootNamespace=LegacyBridge` no .vbproj e
' `Namespace LegacyBridge` aqui, o tipo real passa a ser
'
'     LegacyBridge.LegacyBridge.Juros
'
' e o `StartupObject=LegacyBridge.Juros` nao resolve. O compilador
' responde `BC30420: Sub Main was not found` -- uma mensagem que manda
' procurar a funcao, quando o defeito e o namespace duplicado.
'
' No C# ao lado o namespace do arquivo e ABSOLUTO, e `RootNamespace`
' so afeta arquivos novos criados por ferramenta. Duas linguagens da
' MESMA plataforma, com regra oposta para a mesma propriedade de
' projeto -- e nada no erro aponta para isso.
'
' Custou tres tentativas: trocar Friend por Public, mover o
' declarador de array, e so entao testar o minimo em vez de supor.

' `Public`, e nao `Friend`: o compilador do VB recusou o modulo Friend
' com BC30420, "Sub Main was not found" -- o ponto de entrada tem de ser
' visivel de fora do assembly. O C# ao lado aceita `internal static` com
' `private static Main`, e essa assimetria entre as duas linguagens da
' MESMA plataforma e o tipo de detalhe que so aparece compilando.
Public Module Juros

    ' O sufixo `D` significa `Decimal` em VB.NET.
    '
    ' Sem ele, `1000.00` é `Double`, e a comparação de faixa passaria por
    ' conversão. Com `Option Strict On` o compilador reclama — que é
    ' exatamente o motivo de ligá-lo.
    Private Const FaixaCorrente As Decimal = 1000D
    Private Const TarifaAlta As Decimal = 15D
    Private Const TarifaBaixa As Decimal = 5D
    Private Const TarifaMin As Decimal = 2D
    Private Const TarifaMax As Decimal = 50D

    ' `args() As String`, e NAO `args As String()`.
    '
    ' As duas formas sao sintaxe valida de VB para um array de String --
    ' o declarador pode vir depois do nome ou depois do tipo. Mas o
    ' compilador so reconhece o PONTO DE ENTRADA com o declarador depois
    ' do NOME, e com a outra forma devolve
    '
    '     BC30420: Sub Main was not found in LegacyBridge.Juros
    '
    ' que fala de `Sub Main` quando o que existe e uma `Function Main`
    ' com assinatura quase certa. A mensagem manda procurar a funcao, e o
    ' defeito esta na posicao de dois parenteses.
    Public Function Main(args() As String) As Integer
        If args.Length <> 2 Then
            Console.Error.WriteLine("uso: juros-vb <entrada> <saida>")
            Return 64
        End If

        Dim entrada As String = args(0)
        Dim saida As String = args(1)

        If Not File.Exists(entrada) Then
            Console.Error.WriteLine("nao achei " & entrada)
            Return 66
        End If

        Dim lidos As Integer = 0

        ' `NewLine = vbLf` pelo mesmo motivo do C#: num projeto cuja prova
        ' é `cmp`, o terminador de linha não pode ser decisão do sistema
        ' operacional.
        Using sw As New StreamWriter(saida)
            sw.NewLine = vbLf

            For Each linha As String In File.ReadLines(entrada)
                If linha.Length = 0 Then
                    Continue For
                End If

                If linha.Length <> 26 Then
                    Console.Error.WriteLine("registro " & (lidos + 1).ToString(
                        CultureInfo.InvariantCulture) & " tem " &
                        linha.Length.ToString(CultureInfo.InvariantCulture) &
                        " chars, esperado 26")
                    Return 65
                End If

                Dim r As String = Processa(linha)
                If r Is Nothing Then
                    Return 65
                End If

                sw.WriteLine(r)
                lidos += 1
            Next
        End Using

        If lidos = 0 Then
            Console.Error.WriteLine("nenhum registro processado")
            Return 65
        End If

        Console.Error.WriteLine("registros: " & lidos.ToString("D8",
            CultureInfo.InvariantCulture))
        Return 0
    End Function

    Private Function Formata(valor As Decimal, digitos As Integer,
                             comSinal As Boolean) As String
        Dim q As Decimal = Math.Round(valor, 2, MidpointRounding.AwayFromZero)
        Dim escalado As Long = CLng(Math.Abs(q * 100D))
        Dim corpo As String = escalado.ToString(
            CultureInfo.InvariantCulture).PadLeft(digitos, "0"c)

        If Not comSinal Then
            Return corpo
        End If

        If q < 0D Then
            Return "-" & corpo
        End If
        Return "+" & corpo
    End Function

    Private Function Processa(linha As String) As String
        Dim numero As String = linha.Substring(0, 8)
        Dim sinal As Char = linha(8)

        Dim magnitude As Decimal = Decimal.Parse(
            linha.Substring(9, 12), CultureInfo.InvariantCulture) / 100D

        Dim saldo As Decimal = magnitude
        If sinal = "-"c Then
            saldo = -magnitude
        End If

        Dim taxa As Integer = Integer.Parse(
            linha.Substring(21, 4), CultureInfo.InvariantCulture)
        Dim tipo As Char = linha(25)

        Dim juros As Decimal = Math.Round(
            saldo * (CDec(taxa) / 10000D) / 12D, 2,
            MidpointRounding.AwayFromZero)

        Dim tarifa As Decimal

        Select Case tipo
            Case "C"c
                ' `<` estrito, como no COBOL: saldo de exatamente 1000,00
                ' cai na tarifa BAIXA.
                If saldo < FaixaCorrente Then
                    tarifa = TarifaAlta
                Else
                    tarifa = TarifaBaixa
                End If

            Case "P"c
                tarifa = 0D

            Case "I"c
                Dim bruta As Decimal = 0D
                If saldo > 0D Then
                    bruta = Math.Round(saldo * 1D / 1000D, 2,
                                       MidpointRounding.AwayFromZero)
                End If

                If bruta < TarifaMin Then
                    tarifa = TarifaMin
                ElseIf bruta > TarifaMax Then
                    tarifa = TarifaMax
                Else
                    tarifa = bruta
                End If

            Case Else
                Console.Error.WriteLine("tipo invalido na conta " &
                                        numero & ": " & tipo)
                Return Nothing
        End Select

        Dim novo As Decimal = saldo + juros - tarifa

        Return numero &
               Formata(saldo, 12, True) &
               Formata(juros, 9, True) &
               Formata(tarifa, 8, False) &
               Formata(novo, 12, True)
    End Function

End Module

