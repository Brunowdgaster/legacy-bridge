{ sonda_precisao.pas — qual precisão o FPC usa na divisão por constante real?

      fpc -O2 -Mobjfpc -obin_sonda pascal/sonda_precisao.pas
      ./pascal/bin_sonda

  ## Por que esta sonda existe

  O modo `--double` do `juros.pas` NÃO divergiu do COBOL, enquanto o modo
  `--double` do `Juros.cs` divergiu. As duas usam a mesma regra, a mesma
  construção de arredondamento e um tipo de 64 bits.

  Emulando a aritmética em IEEE 754 de 64 bits puro, o resultado para a conta
  13 é `0,0349999999999999963…` — **abaixo** de 0,035 — e a construção
  `Int(v*100 + 0.5)` sobre ele devolve 3, como o C# fez.

  O binário do FPC devolveu 4. Então o valor que ele calculou não é o mesmo
  double, e esta sonda mede qual é.
}

program SondaPrecisao;

{$MODE OBJFPC}
{$H+}

uses
  SysUtils;

const
  { As três referências, calculadas fora e escritas como texto:

      exato      0.0003
      em Double  0.000299999999999999973718939338951...
      em Single  0.000300000014249235391616821289...

    Se o FPC devolver o terceiro, ele usou precisão SIMPLES numa expressão
    cujo destino é Double. }
  REF = '  (Double seria 0.00029999999999999997, Single 0.00030000001424923539)';

var
  Saldo: Double = 1400.0;
  Taxa: Integer = 3;

  SemTipo, ComDouble, ComSingle: Double;
  DivisorD: Double = 10000.0;
  DivisorS: Single = 10000.0;

  JurosSemTipo, JurosComDouble: Double;

begin
  WriteLn('tamanhos, em bytes:   Double=', SizeOf(Double),
          '  Single=', SizeOf(Single),
          '  Extended=', SizeOf(Extended),
          '  Currency=', SizeOf(Currency));
  WriteLn;
  WriteLn('conta 13: saldo 1400,00  taxa 3 pontos-base, valor exato 0.035');
  WriteLn;

  { 1. Como `juros.pas` escreve: divisor como constante literal sem tipo. }
  SemTipo := Taxa / 10000.0;

  { 2. Com o divisor numa variável Double declarada. }
  ComDouble := Taxa / DivisorD;

  { 3. Com o divisor numa variável Single, para comparação. }
  ComSingle := Taxa / DivisorS;

  WriteLn('a fracao taxa/10000, em tres formas:');
  WriteLn('  constante literal : ', FormatFloat('0.00000000000000000000', SemTipo));
  WriteLn('  variavel Double   : ', FormatFloat('0.00000000000000000000', ComDouble));
  WriteLn('  variavel Single   : ', FormatFloat('0.00000000000000000000', ComSingle));
  WriteLn(REF);
  WriteLn;

  JurosSemTipo := Saldo * SemTipo / 12.0;
  JurosComDouble := Saldo * ComDouble / 12.0;

  WriteLn('os juros, e o centavo que cada um grava:');
  WriteLn('  com constante literal: ',
          FormatFloat('0.00000000000000000000', JurosSemTipo),
          '  -> ', Trunc(JurosSemTipo * 100.0 + 0.5));
  WriteLn('  com variavel Double  : ',
          FormatFloat('0.00000000000000000000', JurosComDouble),
          '  -> ', Trunc(JurosComDouble * 100.0 + 0.5));
  WriteLn;

  if SemTipo <> ComDouble then
  begin
    WriteLn('VEREDITO: a constante literal NAO foi avaliada em Double.');
    WriteLn('  O erro relativo contra o Double correto e ',
            FormatFloat('0.0000000000E+00',
                        Abs(SemTipo - ComDouble) / ComDouble));
    WriteLn('  Se os dois centavos gravados diferem, o modo --double do');
    WriteLn('  juros.pas acerta o COBOL POR ACIDENTE: o erro de precisao');
    WriteLn('  empurrou o valor para o outro lado do meio centavo.');
  end
  else
    WriteLn('VEREDITO: a constante literal foi avaliada em Double.');
end.
