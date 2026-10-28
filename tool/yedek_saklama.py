#!/usr/bin/env python3
"""Yedek saklama kuralı (Seyfettin'in kararı, 29.10.2026).

Kalanlar:
  * son 30 günün bütün yedekleri,
  * son 12 ayın her birinde o ayın İLK yedeği,
  * ne olursa olsun en yeni yedek.
Gerisi silinir.

Kullanım:  ... | python3 tool/yedek_saklama.py --bugun 2026-10-29
  stdin : her satırda bir ad (içinde YYYY-AA-GG geçen; etiket ya da dosya yolu)
  stdout: SİLİNECEK adlar (içinde tarih olmayan adlara hiç dokunulmaz)
Deneme: python3 tool/yedek_saklama.py --test
"""
import datetime
import re
import sys

GUNLUK = 30   # gün
AYLIK = 12    # ay

_TARIH = re.compile(r'(\d{4})-(\d{2})-(\d{2})')


def tarih(ad):
    m = _TARIH.search(ad)
    if not m:
        return None
    try:
        return datetime.date(*map(int, m.groups()))
    except ValueError:
        return None


def silinecekler(adlar, bugun):
    gunler = {}
    for ad in adlar:
        t = tarih(ad)
        if t is not None:
            gunler.setdefault(t, []).append(ad)
    if not gunler:
        return []

    kalan = {t for t in gunler if (bugun - t).days < GUNLUK}

    ayin_ilki = {}
    for t in sorted(gunler):
        ayin_ilki.setdefault((t.year, t.month), t)
    for (yil, ay), t in ayin_ilki.items():
        if (bugun.year * 12 + bugun.month) - (yil * 12 + ay) < AYLIK:
            kalan.add(t)

    kalan.add(max(gunler))
    return sorted(ad for t, liste in gunler.items() if t not in kalan
                  for ad in liste)


def _test():
    g = datetime.date
    bugun = g(2026, 10, 29)

    # 30 gün: 30.09 kalır (29 gün önce), 29.09 gider (30 gün önce, ayın ilki değil)
    adlar = ['yedek-2026-09-01', 'yedek-2026-09-30', 'yedek-2026-09-29', 'yedek-2026-10-29']
    assert silinecekler(adlar, bugun) == ['yedek-2026-09-29'], silinecekler(adlar, bugun)

    # ayın ilki: eylülün ilk yedeği 03.09 ise o kalır (01.09 hiç alınamamış)
    adlar = ['yedek-2026-09-03', 'yedek-2026-09-04', 'yedek-2026-09-05', 'yedek-2026-10-29']
    assert silinecekler(adlar, bugun) == ['yedek-2026-09-04', 'yedek-2026-09-05']

    # 12 ay: Kasım 2025'in ilki kalır (11 ay önce), Ekim 2025'in ilki gider (12 ay önce)
    adlar = ['yedek-2025-10-01', 'yedek-2025-11-01', 'yedek-2026-10-29']
    assert silinecekler(adlar, bugun) == ['yedek-2025-10-01']

    # aynı gün iki dosya (elle ikinci çalıştırma) birlikte kalır / birlikte gider
    adlar = ['2026-08/depo_2026-08-10_0317.tar.gpg', '2026-08/depo_2026-08-10_1500.tar.gpg',
             '2026-08/depo_2026-08-01_0317.tar.gpg', '2026-10/depo_2026-10-29_0317.tar.gpg']
    assert silinecekler(adlar, bugun) == ['2026-08/depo_2026-08-10_0317.tar.gpg',
                                          '2026-08/depo_2026-08-10_1500.tar.gpg']

    # en yeni yedek, eski de olsa, asla silinmez (uzun süre yedek alınamazsa)
    adlar = ['yedek-2024-05-07', 'yedek-2024-05-09']
    assert silinecekler(adlar, bugun) == ['yedek-2024-05-07']

    # tarihsiz adlara dokunulmaz; boş liste sorun değil
    assert silinecekler(['README', 'v1.0'], bugun) == []
    assert silinecekler([], bugun) == []

    # bir yıl boyunca her gün yedek → 30 günlük + önceki 11 ayın ilki = 41 kalır
    gunler = [bugun - datetime.timedelta(days=i) for i in range(400)]
    adlar = ['yedek-%s' % d.isoformat() for d in gunler]
    kalan = len(adlar) - len(silinecekler(adlar, bugun))
    assert kalan == 30 + 11, kalan
    print('yedek_saklama: bütün denemeler geçti')


def main(argv):
    if '--test' in argv:
        _test()
        return 0
    if '--bugun' not in argv:
        print(__doc__, file=sys.stderr)
        return 2
    bugun = datetime.date.fromisoformat(argv[argv.index('--bugun') + 1])
    adlar = [s.strip() for s in sys.stdin if s.strip()]
    for ad in silinecekler(adlar, bugun):
        print(ad)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
