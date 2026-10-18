import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import 'rapor_modeli.dart';

/// Veritabanından [Rapor] nesneleri üretir. Önizleme, PDF ve Excel aynı
/// nesneyi kullanır.
class RaporOlusturucu {
  static final _tarih = DateFormat('dd.MM.yyyy HH:mm');
  static final _gun = DateFormat('dd.MM.yyyy');

  static String _aralik(DateTime? bas, DateTime? bit) {
    if (bas == null && bit == null) return 'Tüm zamanlar';
    return '${bas == null ? '...' : _gun.format(bas)} - '
        '${bit == null ? 'bugün' : _gun.format(bit)}';
  }

  static String _olusturma() => 'Oluşturma: ${_tarih.format(DateTime.now())}';

  static String _tarihMs(Object? ms) => ms == null
      ? ''
      : _tarih.format(DateTime.fromMillisecondsSinceEpoch((ms as num).toInt()));

  /// Cihazın durumu, bulunduğu yerin türüyle birlikte.
  static String durumEtiketi(String? durum, String? depoTur) {
    switch (durum) {
      case 'depoda':
        return depoTur == 'arac' ? 'Araçta' : 'Depoda';
      case 'kullanimda':
        return 'Sahada kullanıldı';
      case 'cikti':
        return 'Çıkış yapıldı';
      default:
        return durum ?? '';
    }
  }

  static const _tipAdlari = {
    'girisi': 'Giriş',
    'cikis': 'Çıkış',
    'transfer': 'Transfer',
    'kullanim': 'Kullanım',
    'iade': 'İade',
  };

  // Cihaz satırları için ortak sütunlar
  static const _cihazSutunlari = [
    'Seri No', 'Durum', 'Konum', 'Kullanım yeri', 'Son değişiklik'
  ];
  static const _cihazGenislik = [22.0, 16.0, 22.0, 26.0, 17.0];

  static List<Object?> _cihazSatiri(Map<String, Object?> r) => [
        r['seri_no'] ?? '',
        durumEtiketi(r['durum'] as String?, r['depo_tur'] as String?),
        r['depo_adi'] ?? '',
        r['kullanim_yeri'] ?? '',
        _tarihMs(r['guncelleme']),
      ];

  // ------------------------------------------------------------------
  // Kullanım raporu
  // ------------------------------------------------------------------
  static Future<Rapor> kullanim(AppDatabase db,
      {DateTime? baslangic, DateTime? bitis}) async {
    final satirlar =
        await db.kullanimRaporu(baslangic: baslangic, bitis: bitis);

    final urunSayilari = <String, int>{};
    for (final s in satirlar) {
      urunSayilari[s.urunAdi] = (urunSayilari[s.urunAdi] ?? 0) + s.miktar;
    }
    final urunler = urunSayilari.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Rapor(
      baslik: 'Kullanım Raporu',
      altBaslik: '${_aralik(baslangic, bitis)} · ${_olusturma()}',
      dosyaOn: 'kullanim_raporu',
      ozet: [
        MapEntry('Toplam kullanım', '${satirlar.length}'),
        MapEntry('Ürün çeşidi', '${urunler.length}'),
      ],
      sutunlar: const [
        'Tarih', 'Seri No', 'Ürün', 'Çıktığı yer', 'Kullanım yeri / Araç'
      ],
      genislikler: const [17, 22, 26, 20, 28],
      bolumler: [
        if (urunler.isNotEmpty)
          RaporBolumu(
            baslik: 'Ürün bazlı özet',
            sutunlar: const ['Ürün', 'Adet'],
            genislikler: const [40, 10],
            satirlar: [
              for (final u in urunler) [u, urunSayilari[u]],
            ],
          ),
        RaporBolumu(
          baslik: 'Kullanım detayları',
          satirlar: [
            for (final s in satirlar)
              [
                _tarih.format(s.tarih),
                s.seriNo ?? '',
                s.urunAdi,
                s.depoAdi,
                s.aracPlaka ?? s.kullanimYeri ?? 'Belirtilmedi',
              ],
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Ürünler raporu (ürün çeşidine göre ayrılmış)
  // ------------------------------------------------------------------
  static Future<Rapor> urunler(AppDatabase db) async {
    final rows = await db.cihazListesiRaporu();

    // Ürüne göre grupla (sorgu ürün adına göre sıralı gelir)
    final gruplar = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      gruplar.putIfAbsent(r['urun_id'] as String, () => []).add(r);
    }

    final sayac = _Sayac();
    final ozetSatirlari = <List<Object?>>[];
    final detaylar = <RaporBolumu>[];

    for (final liste in gruplar.values) {
      final s = _Sayac()..ekle(liste);
      sayac.topla(s);
      final ad = liste.first['urun_adi'] as String;
      final kategori = (liste.first['kategori'] as String?) ?? '';
      ozetSatirlari.add([
        ad, kategori, s.toplam, s.depoda, s.aracta, s.sahada, s.cikti
      ]);
      detaylar.add(RaporBolumu(
        baslik: ad,
        aciklama: [
          if (kategori.isNotEmpty) 'Kategori: $kategori',
          'Toplam ${s.toplam}',
          'Depoda ${s.depoda}',
          'Araçta ${s.aracta}',
          'Sahada ${s.sahada}',
          'Çıkış ${s.cikti}',
        ].join(' · '),
        satirlar: [for (final r in liste) _cihazSatiri(r)],
      ));
    }

    return Rapor(
      baslik: 'Ürünler Raporu',
      altBaslik: 'Ürün çeşidine göre · ${_olusturma()}',
      dosyaOn: 'urunler_raporu',
      ozet: [
        MapEntry('Ürün çeşidi', '${gruplar.length}'),
        MapEntry('Toplam cihaz', '${sayac.toplam}'),
        MapEntry('Depoda', '${sayac.depoda}'),
        MapEntry('Araçta', '${sayac.aracta}'),
        MapEntry('Sahada kullanıldı', '${sayac.sahada}'),
        MapEntry('Çıkış yapıldı', '${sayac.cikti}'),
      ],
      sutunlar: _cihazSutunlari,
      genislikler: _cihazGenislik,
      bolumler: [
        if (ozetSatirlari.isNotEmpty)
          RaporBolumu(
            baslik: 'Ürün özeti',
            sutunlar: const [
              'Ürün', 'Kategori', 'Toplam', 'Depoda', 'Araçta', 'Sahada',
              'Çıkış'
            ],
            genislikler: const [28, 16, 9, 9, 9, 9, 9],
            satirlar: ozetSatirlari,
          ),
        ...detaylar,
      ],
    );
  }

  // ------------------------------------------------------------------
  // Seçili ürünün stok durumu
  // ------------------------------------------------------------------
  static Future<Rapor> urunStokDurumu(AppDatabase db, Urun urun) async {
    final rows = await db.cihazListesiRaporu(urunId: urun.id);
    final s = _Sayac()..ekle(rows);

    List<Map<String, Object?>> filtre(String durum, {String? tur}) => rows
        .where((r) =>
            r['durum'] == durum &&
            (tur == null ||
                (tur == 'arac') == (r['depo_tur'] == 'arac')))
        .toList();

    final depolarda = filtre('depoda', tur: 'sabit');
    final araclarda = filtre('depoda', tur: 'arac');
    final sahada = filtre('kullanimda');
    final cikti = filtre('cikti');

    // Konumlara göre dağılım (depo ve araçlar)
    final dagilim = <String, List<Object?>>{};
    for (final r in [...depolarda, ...araclarda]) {
      final ad = (r['depo_adi'] as String?) ?? '-';
      final tur = r['depo_tur'] == 'arac' ? 'Araç' : 'Depo';
      final mevcut = dagilim['$tur|$ad'];
      dagilim['$tur|$ad'] =
          mevcut == null ? [ad, tur, 1] : [ad, tur, (mevcut[2] as int) + 1];
    }

    RaporBolumu? bolum(String baslik, List<Map<String, Object?>> liste) =>
        liste.isEmpty
            ? null
            : RaporBolumu(
                baslik: '$baslik (${liste.length})',
                satirlar: [for (final r in liste) _cihazSatiri(r)],
              );

    return Rapor(
      baslik: 'Stok Durumu: ${urun.ad}',
      altBaslik: [
        if ((urun.kategori ?? '').isNotEmpty) 'Kategori: ${urun.kategori}',
        _olusturma(),
      ].join(' · '),
      dosyaOn: 'stok_durumu',
      ozet: [
        MapEntry('Toplam', '${s.toplam}'),
        MapEntry('Depolarda', '${s.depoda}'),
        MapEntry('Araçlarda', '${s.aracta}'),
        MapEntry('Sahada kullanıldı', '${s.sahada}'),
        MapEntry('Çıkış yapıldı', '${s.cikti}'),
      ],
      sutunlar: _cihazSutunlari,
      genislikler: _cihazGenislik,
      bolumler: [
        if (dagilim.isNotEmpty)
          RaporBolumu(
            baslik: 'Konumlara göre dağılım',
            sutunlar: const ['Konum', 'Tür', 'Adet'],
            genislikler: const [30, 10, 10],
            satirlar: dagilim.values.toList()
              ..sort((a, b) => (b[2] as int).compareTo(a[2] as int)),
          ),
        ...[
          bolum('Depolarda', depolarda),
          bolum('Araçlarda', araclarda),
          bolum('Sahada kullanıldı', sahada),
          bolum('Çıkış yapıldı', cikti),
        ].whereType<RaporBolumu>(),
        if (rows.isEmpty)
          const RaporBolumu(
            baslik: 'Bu ürüne ait kayıtlı cihaz yok',
            satirlar: [],
          ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Hareket geçmişi
  // ------------------------------------------------------------------
  static Future<Rapor> hareketler(AppDatabase db,
      {DateTime? baslangic, DateTime? bitis}) async {
    final rows = await db.hareketRaporu(baslangic: baslangic, bitis: bitis);

    final tipSayilari = <String, int>{};
    for (final r in rows) {
      final t = _tipAdlari[r['tip']] ?? '${r['tip']}';
      tipSayilari[t] = (tipSayilari[t] ?? 0) + 1;
    }

    return Rapor(
      baslik: 'Hareket Geçmişi',
      altBaslik: '${_aralik(baslangic, bitis)} · ${_olusturma()}',
      dosyaOn: 'hareket_gecmisi',
      ozet: [
        MapEntry('Toplam hareket', '${rows.length}'),
        for (final e in tipSayilari.entries) MapEntry(e.key, '${e.value}'),
      ],
      sutunlar: const [
        'Tarih', 'İşlem', 'Seri No', 'Ürün', 'Nereden', 'Nereye',
        'Kullanım yeri', 'Kullanıcı', 'Not'
      ],
      genislikler: const [16, 10, 18, 22, 16, 16, 20, 14, 20],
      bolumler: [
        RaporBolumu(
          satirlar: [
            for (final r in rows)
              [
                _tarihMs(r['tarih']),
                _tipAdlari[r['tip']] ?? (r['tip'] ?? ''),
                r['seri_no'] ?? '',
                r['urun_adi'] ?? '',
                r['kaynak'] ?? '',
                r['hedef'] ?? '',
                r['kullanim_yeri'] ?? '',
                r['kullanici'] ?? '',
                r['not_'] ?? '',
              ],
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Sayım sonucu
  // ------------------------------------------------------------------
  static Rapor sayim({
    required String depoAdi,
    required List<CihazBilgi> beklenen,
    required Map<String, CihazBilgi?> okunanlar,
    required DateTime baslangic,
  }) {
    final beklenenSeriler = {for (final c in beklenen) c.cihaz.seriNo};
    final bulunan =
        beklenen.where((c) => okunanlar.containsKey(c.cihaz.seriNo)).toList();
    final eksik =
        beklenen.where((c) => !okunanlar.containsKey(c.cihaz.seriNo)).toList();
    final fazla = okunanlar.entries
        .where((e) => !beklenenSeriler.contains(e.key))
        .toList();

    return Rapor(
      baslik: 'Sayım Raporu: $depoAdi',
      altBaslik: 'Sayım: ${_tarih.format(baslangic)} · ${_olusturma()}',
      dosyaOn: 'sayim_raporu',
      ozet: [
        MapEntry('Sistemde olması gereken', '${beklenen.length}'),
        MapEntry('Bulunan', '${bulunan.length}'),
        MapEntry('Eksik', '${eksik.length}'),
        MapEntry('Fazla', '${fazla.length}'),
      ],
      sutunlar: const ['Seri No', 'Ürün', 'Açıklama'],
      genislikler: const [24, 30, 36],
      bolumler: [
        RaporBolumu(
          baslik: 'Eksik (${eksik.length})',
          aciklama: 'Sistemde bu konumda görünüyor ama sayımda okutulmadı.',
          satirlar: [
            for (final c in eksik) [c.cihaz.seriNo, c.urunAdi, ''],
          ],
        ),
        RaporBolumu(
          baslik: 'Fazla (${fazla.length})',
          aciklama: 'Sayımda okutuldu ama sistemde bu konumda değil.',
          satirlar: [
            for (final e in fazla)
              [e.key, e.value?.urunAdi ?? '-', sistemdekiYer(e.value)],
          ],
        ),
        RaporBolumu(
          baslik: 'Bulunan (${bulunan.length})',
          satirlar: [
            for (final c in bulunan) [c.cihaz.seriNo, c.urunAdi, ''],
          ],
        ),
      ],
    );
  }

  /// Sayımda "fazla" çıkan cihazın sistemde nerede göründüğü.
  static String sistemdekiYer(CihazBilgi? b) {
    if (b == null) return 'Sistemde kayıtlı değil';
    switch (b.cihaz.durum) {
      case CihazDurumu.depoda:
        return 'Sistemde: ${b.depoAdi ?? '-'}'
            '${b.depoArac ? ' (araç)' : ''}';
      case CihazDurumu.kullanimda:
        return 'Sistemde: sahada kullanıldı'
            '${b.cihaz.kullanimYeri == null ? '' : ' (${b.cihaz.kullanimYeri})'}';
      case CihazDurumu.cikti:
        return 'Sistemde: çıkış yapılmış';
    }
  }
}

class _Sayac {
  int toplam = 0, depoda = 0, aracta = 0, sahada = 0, cikti = 0;

  void ekle(List<Map<String, Object?>> rows) {
    for (final r in rows) {
      toplam++;
      switch (r['durum']) {
        case 'depoda':
          if (r['depo_tur'] == 'arac') {
            aracta++;
          } else {
            depoda++;
          }
          break;
        case 'kullanimda':
          sahada++;
          break;
        case 'cikti':
          cikti++;
          break;
      }
    }
  }

  void topla(_Sayac s) {
    toplam += s.toplam;
    depoda += s.depoda;
    aracta += s.aracta;
    sahada += s.sahada;
    cikti += s.cikti;
  }
}
