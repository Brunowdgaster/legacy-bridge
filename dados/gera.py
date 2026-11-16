"""Gera dados/contas.dat, de largura fixa, com os casos de borda do FORMATO.md.

O arquivo NAO e aleatorio: cada registro existe para testar uma decisao da
regra, e os seis casos de borda estao nomeados no FORMATO.md.
"""
import io
import os
from decimal import Decimal, ROUND_HALF_UP

os.makedirs('dados', exist_ok=True)

# (conta, saldo, taxa_pb, tipo, por_que)
CONTAS = [
    (1, Decimal('10000.00'), 1250, 'C', 'corrente comum, saldo alto'),
    (2, Decimal('500.00'), 600, 'P', 'poupanca, tarifa zero'),

    # 0,005 exato: saldo * taxa / 10000 / 12 tem de cair em meio centavo.
    # 1.20 * 500 / 10000 / 12 = 0.005 exatamente.
    (3, Decimal('1.20'), 500, 'P', 'juros caem em MEIO CENTAVO exato'),

    (4, Decimal('250000.00'), 980, 'I', 'investimento, tarifa no meio'),
    (5, Decimal('75.50'), 1500, 'C', 'corrente com saldo baixo'),
    (6, Decimal('-1200.00'), 1250, 'C', 'saldo NEGATIVO: sinal e juros negativos'),
    (7, Decimal('999.99'), 700, 'C', 'um centavo ABAIXO da faixa de 1000'),
    (8, Decimal('1000.00'), 700, 'C', 'EXATAMENTE na faixa de 1000'),
    (9, Decimal('33333.33'), 1111, 'P', 'divisao nao exata'),
    (10, Decimal('0.00'), 1250, 'P', 'saldo zero'),
    (11, Decimal('1500.00'), 800, 'I', 'tarifa bate no MINIMO de 2,00'),
    (12, Decimal('900000.00'), 800, 'I', 'tarifa bate no MAXIMO de 50,00'),

    # As duas contas abaixo foram ACHADAS POR BUSCA, nao escolhidas a mao.
    #
    # A primeira versao deste conjunto afirmava que o caminho em `double`
    # divergiria do `decimal`, e as 12 contas acima NAO exibiam isso -- os
    # dois arquivos sairam identicos. Em vez de afrouxar a afirmacao, um
    # programa varreu saldos de 0,01 a 2000,00 contra taxas de 1 a 2500
    # pontos-base, emulando os dois caminhos, e achou onde eles divergem.
    #
    # 1400,00 a 0,03% ao ano da juros mensais de exatamente 0,035 -- meio
    # centavo. Em decimal, meio-para-longe-de-zero sobe para 0,04. Em double,
    # 0,0003 nao e representavel, o produto cai logo abaixo de 0,035, e o
    # resultado desce para 0,03: UM CENTAVO A MENOS.
    #
    # Taxas desta ordem sao realistas: 0,03% ao ano e tipico de tarifa de
    # custodia, e e justamente em valor pequeno sobre saldo grande que o
    # centavo perdido passa despercebido.
    (13, Decimal('1400.00'), 3, 'P', 'double PERDE um centavo (0,035 exato)'),
    (14, Decimal('840.00'), 5, 'P', 'double perde um centavo, outra taxa'),
]


def campo_num(valor, digitos_int, decimais=2):
    """Magnitude como digitos, sem ponto, com zeros a esquerda."""
    q = abs(valor).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
    escalado = int(q * 100)
    total = digitos_int + decimais
    s = str(escalado).rjust(total, '0')
    assert len(s) == total, f'{valor} nao cabe em {total} digitos'
    return s


linhas = []
for conta, saldo, taxa, tipo, _por_que in CONTAS:
    sinal = '-' if saldo < 0 else '+'
    linhas.append(
        f'{conta:08d}{sinal}{campo_num(saldo, 10)}{taxa:04d}{tipo}')

for l in linhas:
    assert len(l) == 26, f'registro com {len(l)} chars: {l!r}'

with io.open('dados/contas.dat', 'w', encoding='ascii', newline='\n') as fh:
    for l in linhas:
        fh.write(l + '\n')

print(f'gravado: dados/contas.dat  ({len(linhas)} registros de 26 chars)')
print()
print('  conta     saldo          taxa  tipo  por que existe')
for (conta, saldo, taxa, tipo, por_que), linha in zip(CONTAS, linhas):
    print(f'  {conta:08d}  {saldo:>13}  {taxa/100:>5.2f}%  {tipo}     {por_que}')
