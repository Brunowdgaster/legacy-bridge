{ juros.pas — a MESMA regra, em Object Pascal (Free Pascal).

  Compilar e rodar:

      fpc -O2 -Mobjfpc -Sewn -obin_juros pascal/juros.pas
      ./pascal/bin_juros dados/contas.dat saida/pascal.dat
      ./pascal/bin_juros --double dados/contas.dat saida/pascal_double.dat

  ## Por que Object Pascal está num projeto de migração de legado

  Porque ele é o cliente desktop que acompanha o lote.

  O arranjo é tão comum que virou arquétipo: o processamento noturno roda em
  COBOL no mainframe, e o atendente usa um aplicativo Delphi que lê os mesmos
  arquivos. Quando o COBOL é migrado, o cliente Delphi tem de continuar
  concordando com ele — e é essa a verificação que este arquivo faz.

  Delphi é proprietário; o **Free Pascal** é livre (GPL/LGPL) e compila o
  mesmo dialeto Object Pascal. Este arquivo roda nos dois.

  ## A simetria com o C#, e o que ela mostra

  O C# ao lado tem `decimal` para dinheiro, e o projeto mede o que acontece
  quando alguém usa `double` no lugar.

  Object Pascal tem o **mesmo par**, e com nomes ainda mais explícitos:

    Currency   ponto fixo, 4 casas decimais, armazenado como Int64 escalado
               por 10000. Projetado para dinheiro, e o nome diz.

    Double     IEEE 754 binário, como em qualquer outra linguagem.

  Então a mesma demonstração cabe aqui, e o resultado é o mesmo: `Currency`
  bate byte a byte com o COBOL, e `Double` perde o centavo nas contas 13 e 14.

  **Três linguagens de três épocas — COBOL de 1959, Object Pascal de 1986, C#
  de 2000 — e as três acertam com o tipo decimal e erram com o binário.** Não
  é característica de linguagem: é característica do tipo.

  ## As quatro casas do `Currency`, e por que isso importa

  `Currency` guarda **4** decimais, e a regra deste projeto trabalha com 2.
  Isso é vantagem e armadilha ao mesmo tempo:

    * vantagem: o resultado intermediário de `saldo * taxa / 10000 / 12` tem
      duas casas de folga antes do arredondamento final, então não há perda
      por truncamento no meio da expressão;

    * armadilha: o valor NÃO está arredondado a 2 casas sozinho. Gravá-lo no
      arquivo exige arredondamento explícito — e o `RoundTo` da unidade `Math`
      do FPC usa arredondamento **bancário** (meio para o par), que é o mesmo
      padrão do C# e o oposto do `ROUNDED` do COBOL.

  Por isso este arquivo tem `ArredondaMeioLonge`, escrito à mão. Usar o
  `RoundTo` da biblioteca produziria o mesmo erro que o `Math.Round` sem
  `MidpointRounding.AwayFromZero` produz em C#.
}

program Juros;

{$MODE OBJFPC}
{$H+}

uses
  SysUtils, Math;

const
  { As constantes como `Currency`, pelo mesmo motivo do sufixo `m` no C#:
    `1000.00` sem tipo é ponto flutuante, e a comparação de faixa passaria
    por conversão. }

  { ## E as duas constantes Double com TIPO EXPLÍCITO, que não são decoração

    O FPC avalia `Integer / <literal real>` em **precisão simples**, e não em
    Double. Medido por `pascal/sonda_precisao.pas`:

        Taxa / 10000.0      ->  0.00030000001424923539   (Single)
        Taxa / DivisorD     ->  0.00029999999999999997   (Double correto)

    O erro relativo da primeira forma é **4,7e-08** — cinco ordens de
    grandeza pior que o 1,1e-16 do Double.

    E isso teve uma consequência que vale mais que o número: a primeira
    versão do modo `--double` deste programa **concordava com o COBOL**, e
    concordava **por acidente**. O erro de precisão empurrou o valor para o
    outro lado do meio centavo, e dois defeitos se cancelaram.

    Dois defeitos que se cancelam é o pior caso de correção que existe: o
    teste passa, a demonstração parece funcionar, e o programa está errado
    por dois motivos ao mesmo tempo. }
  DIVISOR_TAXA: Double = 10000.0;
  DIVISOR_MES: Double = 12.0;
  DIVISOR_MIL: Double = 1000.0;
  FAIXA_CORRENTE: Currency = 1000.00;
  TARIFA_ALTA: Currency = 15.00;
  TARIFA_BAIXA: Currency = 5.00;
  TARIFA_MIN: Currency = 2.00;
  TARIFA_MAX: Currency = 50.00;

{ Arredondamento meio-para-longe-de-zero, à mão.

  O `RoundTo` da unidade `Math` usa arredondamento BANCÁRIO (meio para o par),
  que é o padrão do IEEE 754 e o oposto do `ROUNDED` do COBOL. Usá-lo faria
  a conta 00000003 — juros de exatamente meio centavo — sair como 0,00 em vez
  de 0,01.

  `Int()` trunca para zero, e somar 0,005 antes do truncamento é a construção
  clássica. Em `Currency` ela é exata, porque 0,005 tem representação exata
  em ponto fixo de 4 casas. Em `Double` ela NÃO é, e é justamente aí que o
  modo --double deste programa perde o centavo. }
function ArredondaMeioLonge(V: Currency): Currency;
begin
  if V >= 0 then
    Result := Int(V * 100 + 0.5) / 100
  else
    Result := -Int(-V * 100 + 0.5) / 100;
end;

function ArredondaMeioLongeD(V: Double): Double;
begin
  if V >= 0 then
    Result := Int(V * 100 + 0.5) / 100
  else
    Result := -Int(-V * 100 + 0.5) / 100;
end;

{ Formata um valor como campo de largura fixa: dígitos, sem ponto, com zeros
  à esquerda e sinal separado opcional.

  `Round` sobre o valor já escalado por 100: em `Currency` o produto é exato,
  então o `Round` aqui não decide nada — ele só converte para inteiro. É em
  `FormataD` que ele decide, e erra. }
function Formata(V: Currency; Digitos: Integer; ComSinal: Boolean): string;
var
  Q: Currency;
  Escalado: Int64;
  Corpo: string;
begin
  Q := ArredondaMeioLonge(V);
  Escalado := Round(Abs(Q) * 100);
  Corpo := Format('%.*d', [Digitos, Escalado]);

  if Length(Corpo) > Digitos then
    raise Exception.CreateFmt('%s nao cabe em %d digitos',
      [CurrToStr(V), Digitos]);

  if not ComSinal then
    Result := Corpo
  else if Q < 0 then
    Result := '-' + Corpo
  else
    Result := '+' + Corpo;
end;

function FormataD(V: Double; Digitos: Integer; ComSinal: Boolean): string;
var
  Q: Double;
  Escalado: Int64;
  Corpo: string;
begin
  Q := ArredondaMeioLongeD(V);
  { `Trunc`, e não `Round`: é o mesmo caminho do `(long)` no C#, e é onde o
    `double` perde. Um valor que deveria ser exatamente 0,04 pode estar
    representado como 0,039999999999999994, e truncar dá 3 em vez de 4. }
  Escalado := Trunc(Abs(Q) * 100);
  Corpo := Format('%.*d', [Digitos, Escalado]);

  if not ComSinal then
    Result := Corpo
  else if Q < 0 then
    Result := '-' + Corpo
  else
    Result := '+' + Corpo;
end;

{ Lê o campo numérico de ponto decimal implícito.

  `StrToInt64` sobre os 12 dígitos e divisão por 100 em `Currency`: exato.
  Fazer a divisão em `Double` introduziria erro antes da primeira conta. }
function LeValor(const S: string; Sinal: Char): Currency;
var
  Magnitude: Currency;
begin
  Magnitude := StrToInt64(S) / 100;
  if Sinal = '-' then
    Result := -Magnitude
  else
    Result := Magnitude;
end;

function Processa(const Linha: string; out Saida: string): Boolean;
var
  Numero: string;
  Sinal, Tipo: Char;
  Saldo, JurosV, Tarifa, Novo, Bruta: Currency;
  Taxa: Integer;
begin
  Result := False;

  Numero := Copy(Linha, 1, 8);
  Sinal := Linha[9];
  Saldo := LeValor(Copy(Linha, 10, 12), Sinal);
  Taxa := StrToInt(Copy(Linha, 22, 4));
  Tipo := Linha[26];

  JurosV := ArredondaMeioLonge(Saldo * (Taxa / 10000) / 12);

  case Tipo of
    'C':
      { `<` estrito, como no COBOL: saldo de exatamente 1000,00 cai na tarifa
        BAIXA. A conta 00000008 fixa essa decisão. }
      if Saldo < FAIXA_CORRENTE then
        Tarifa := TARIFA_ALTA
      else
        Tarifa := TARIFA_BAIXA;

    'P':
      Tarifa := 0;

    'I':
      begin
        if Saldo > 0 then
          Bruta := ArredondaMeioLonge(Saldo * 1 / 1000)
        else
          Bruta := 0;

        if Bruta < TARIFA_MIN then
          Tarifa := TARIFA_MIN
        else if Bruta > TARIFA_MAX then
          Tarifa := TARIFA_MAX
        else
          Tarifa := Bruta;
      end;
  else
    WriteLn(StdErr, 'tipo invalido na conta ', Numero, ': ', Tipo);
    Exit;
  end;

  Novo := Saldo + JurosV - Tarifa;

  Saida := Numero
         + Formata(Saldo, 12, True)
         + Formata(JurosV, 9, True)
         + Formata(Tarifa, 8, False)
         + Formata(Novo, 12, True);

  Result := True;
end;

function ProcessaD(const Linha: string; out Saida: string): Boolean;
var
  Numero: string;
  Sinal, Tipo: Char;
  Saldo, JurosV, Tarifa, Novo, Bruta: Double;
  Taxa: Integer;
begin
  Result := False;

  Numero := Copy(Linha, 1, 8);
  Sinal := Linha[9];
  Saldo := StrToInt64(Copy(Linha, 10, 12)) / 100.0;
  if Sinal = '-' then
    Saldo := -Saldo;
  Taxa := StrToInt(Copy(Linha, 22, 4));
  Tipo := Linha[26];

  { Os divisores vêm de constantes com tipo Double declarado. Com literais,
    o FPC avaliaria em Single -- ver o comentário na seção `const`. }
  JurosV := ArredondaMeioLongeD(Saldo * (Taxa / DIVISOR_TAXA) / DIVISOR_MES);

  case Tipo of
    'C':
      if Saldo < 1000.00 then Tarifa := 15.00 else Tarifa := 5.00;
    'P':
      Tarifa := 0.0;
    'I':
      begin
        if Saldo > 0 then
          Bruta := ArredondaMeioLongeD(Saldo * 1.0 / DIVISOR_MIL)
        else
          Bruta := 0.0;
        if Bruta < 2.00 then Tarifa := 2.00
        else if Bruta > 50.00 then Tarifa := 50.00
        else Tarifa := Bruta;
      end;
  else
    WriteLn(StdErr, 'tipo invalido na conta ', Numero, ': ', Tipo);
    Exit;
  end;

  Novo := Saldo + JurosV - Tarifa;

  Saida := Numero
         + FormataD(Saldo, 12, True)
         + FormataD(JurosV, 9, True)
         + FormataD(Tarifa, 8, False)
         + FormataD(Novo, 12, True);

  Result := True;
end;

var
  UsarDouble: Boolean = False;
  Entrada, SaidaArq: string;
  Linha, Res: string;
  Ent, Sai: TextFile;
  Lidos: Integer = 0;
  I, Livres: Integer;
  Arg: string;
begin
  { Os argumentos. `--double` em qualquer posição, como no C#. }
  Entrada := '';
  SaidaArq := '';
  Livres := 0;

  for I := 1 to ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--double' then
      UsarDouble := True
    else
    begin
      Inc(Livres);
      if Livres = 1 then
        Entrada := Arg
      else if Livres = 2 then
        SaidaArq := Arg;
    end;
  end;

  if Livres <> 2 then
  begin
    WriteLn(StdErr, 'uso: bin_juros [--double] <entrada> <saida>');
    Halt(64);
  end;

  if not FileExists(Entrada) then
  begin
    WriteLn(StdErr, 'nao achei ', Entrada);
    Halt(66);
  end;

  AssignFile(Ent, Entrada);
  Reset(Ent);
  AssignFile(Sai, SaidaArq);
  Rewrite(Sai);

  while not Eof(Ent) do
  begin
    ReadLn(Ent, Linha);
    if Length(Linha) = 0 then
      Continue;

    if Length(Linha) <> 26 then
    begin
      { Falha ALTO. Um registro de largura errada lido como se estivesse certo
        produz números plausíveis e errados, que é o pior resultado possível
        num lote financeiro. }
      WriteLn(StdErr, 'registro ', Lidos + 1, ' tem ', Length(Linha),
              ' chars, esperado 26');
      CloseFile(Ent);
      CloseFile(Sai);
      Halt(65);
    end;

    if UsarDouble then
    begin
      if not ProcessaD(Linha, Res) then
      begin
        CloseFile(Ent); CloseFile(Sai); Halt(65);
      end;
    end
    else
    begin
      if not Processa(Linha, Res) then
      begin
        CloseFile(Ent); CloseFile(Sai); Halt(65);
      end;
    end;

    { `WriteLn` em TextFile no FPC usa LF em Unix e CRLF em Windows. Num
      projeto cuja prova é `cmp`, isso é problema -- e a defesa aqui é o
      `.gitattributes` com `eol=lf` mais o fato de a suíte rodar em Linux.
      O C# e o VB.NET forçam `NewLine` explicitamente porque podem; o
      `TextFile` do Pascal não expõe essa configuração. }
    WriteLn(Sai, Res);
    Inc(Lidos);
  end;

  CloseFile(Ent);
  CloseFile(Sai);

  if Lidos = 0 then
  begin
    WriteLn(StdErr, 'nenhum registro processado');
    Halt(65);
  end;

  WriteLn(StdErr, Format('registros: %.8d', [Lidos]));
end.
