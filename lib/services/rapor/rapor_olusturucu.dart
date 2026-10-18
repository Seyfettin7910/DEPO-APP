import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../adres_servisi.dart';
import '../konum_servisi.dart';
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
    'silme': 'Silme',
  };

  static String _gunMs(Object? ms) => ms == null
      ? ''
      : _gun.format(DateTime.fromMillisecondsSinceEpoch((ms as num).toInt()));

  /// Garanti bitişine kalan gün (geçmişse negatif); bilgi yoksa null.
  static int? _kalanGun(Object? ms) {
    if (ms == null) return null;
    final bitis = DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
    final bugun = DateTime.now();
    return DateTime(bitis.year, bitis.month, bitis.day)
        .difference(DateTime(bugun.year, bugun.month, bugun.day))
        .inDays;
  }

  static String _konum(Map<String, Object?> r) => r['durum'] == 'depoda'
      ? (r['depo_adi'] as String? ?? '')
      : (r['kullanim_yeri'] as String? ?? '');

  // Cihaz satırları için ortak sütunlar
  static const _cihazSutunlari = [
    'Seri No', 'Durum', 'Konum', 'Kullanım yeri', 'Firma', 'İhale',
    'Alım tarihi', 'Garanti bitiş'
  ];
  static const _cihazGenislik = [
    20.0, 13.0, 18.0, 20.0, 18.0, 15.0, 11.0, 11.0
  ];

  /// GPS konumu olan hücre için tıklanabilir harita bağlantısı.
  static Object? konumHucresi(double? enlem, double? boylam, {String? on}) {
    if (enlem == null || boylam == null) return on ?? '';
    final k = KonumServisi.koordinat(enlem, boylam);
    return RaporLink(
      on == null || on.isEmpty ? k : '$on ($k)',
      KonumServisi.haritaLinki(enlem, boylam),
    );
  }

  static Object? _kullanimYeriHucresi(Map<String, Object?> r) {
    final yer = r['kullanim_yeri'] as String?;
    final konum = r['son_konum'] as String?;
    if (r['durum'] != 'kullanimda' || konum == null) return yer ?? '';
    final p = konum.split(',');
    final e = p.isNotEmpty ? double.tryParse(p[0]) : null;
    final b = p.length > 1 ? double.tryParse(p[1]) : null;
    return konumHucresi(e, b, on: yer);
  }

  static List<Object?> _cihazSatiri(Map<String, Object?> r) => [
        r['seri_no'] ?? '',
        durumEtiketi(r['durum'] as String?, r['depo_tur'] as String?),
        r['depo_adi'] ?? '',
        _kullanimYeriHucresi(r),
        r['firma'] ?? '',
        r['ihale'] ?? '',
        _gunMs(r['alim_tarihi']),
        _gunMs(r['garanti_bitis']),
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
        MapEntry('Konumu kayıtlı',
            '${satirlar.where((s) => s.enlem != null).length}'),
        MapEntry('Ürün çeşidi', '${urunler.length}'),
      ],
      sutunlar: const [
        'Tarih', 'Seri No', 'Ürün', 'Çıktığı yer', 'Kullanım yeri / Araç',
        'Bölge (mahalle, ilçe / il)', 'Konum (GPS)'
      ],
      genislikler: const [14, 17, 19, 15, 21, 24, 20],
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
                Adres(il: s.il, ilce: s.ilce, mahalle: s.mahalle).ozet,
                konumHucresi(s.enlem, s.boylam),
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
  // Garanti durumu
  // ------------------------------------------------------------------
  static Future<Rapor> garanti(AppDatabase db, {int yakinGun = 90}) async {
    final rows = (await db.cihazListesiRaporu())
        .where((r) => r['durum'] != 'cikti') // çıkışı yapılanlar hariç
        .toList();

    final biten = <Map<String, Object?>>[];
    final yakin = <Map<String, Object?>>[];
    final devam = <Map<String, Object?>>[];
    final bilgisiz = <Map<String, Object?>>[];
    for (final r in rows) {
      final k = _kalanGun(r['garanti_bitis']);
      if (k == null) {
        bilgisiz.add(r);
      } else if (k < 0) {
        biten.add(r);
      } else if (k <= yakinGun) {
        yakin.add(r);
      } else {
        devam.add(r);
      }
    }
    int kalan(Map<String, Object?> r) => _kalanGun(r['garanti_bitis']) ?? 0;
    yakin.sort((a, b) => kalan(a).compareTo(kalan(b)));
    biten.sort((a, b) => kalan(b).compareTo(kalan(a)));
    devam.sort((a, b) => kalan(a).compareTo(kalan(b)));

    List<Object?> satir(Map<String, Object?> r) => [
          r['seri_no'] ?? '',
          r['urun_adi'] ?? '',
          r['firma'] ?? '',
          r['ihale'] ?? '',
          _gunMs(r['alim_tarihi']),
          _gunMs(r['garanti_bitis']),
          _kalanGun(r['garanti_bitis']) ?? '',
          durumEtiketi(r['durum'] as String?, r['depo_tur'] as String?),
          _konum(r),
        ];

    RaporBolumu? bolum(String baslik, String aciklama,
            List<Map<String, Object?>> liste) =>
        liste.isEmpty
            ? null
            : RaporBolumu(
                baslik: '$baslik (${liste.length})',
                aciklama: aciklama,
                satirlar: [for (final r in liste) satir(r)],
              );

    return Rapor(
      baslik: 'Garanti Durumu',
      altBaslik: 'Çıkışı yapılmamış cihazlar · ${_olusturma()}',
      dosyaOn: 'garanti_durumu',
      ozet: [
        MapEntry('Garantisi bitmiş', '${biten.length}'),
        MapEntry('$yakinGun gün içinde bitecek', '${yakin.length}'),
        MapEntry('Garantide', '${devam.length}'),
        MapEntry('Garanti bilgisi yok', '${bilgisiz.length}'),
      ],
      sutunlar: const [
        'Seri No', 'Ürün', 'Firma', 'İhale', 'Alım tarihi', 'Garanti bitiş',
        'Kalan gün', 'Durum', 'Konum / kullanım yeri'
      ],
      genislikler: const [18, 22, 16, 14, 11, 11, 8, 12, 18],
      bolumler: [
        ...[
          bolum('$yakinGun gün içinde bitecek',
              'En yakın tarihli üstte.', yakin),
          bolum('Garantisi bitmiş', 'En yeni biten üstte.', biten),
          bolum('Garantide', 'Bitiş tarihine göre.', devam),
          bolum('Garanti bilgisi yok',
              'Cihaz kartından veya girişte garanti eklenebilir.', bilgisiz),
        ].whereType<RaporBolumu>(),
        if (rows.isEmpty)
          const RaporBolumu(baslik: 'Kayıtlı cihaz yok', satirlar: []),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Alımlar: ihale / firma bazlı
  // ------------------------------------------------------------------
  static Future<Rapor> alimlar(AppDatabase db) async {
    final rows = await db.cihazListesiRaporu();

    final gruplar = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      final ihale = (r['ihale'] as String?)?.trim() ?? '';
      final firma = (r['firma'] as String?)?.trim() ?? '';
      gruplar.putIfAbsent('$ihale|$firma', () => []).add(r);
    }
    final anahtarlar = gruplar.keys.toList()
      ..sort((a, b) {
        // Bilgisi olmayanlar en sona
        if (a == '|') return 1;
        if (b == '|') return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final firmalar = <String>{};
    final ihaleler = <String>{};
    final ozetSatirlari = <List<Object?>>[];
    final detaylar = <RaporBolumu>[];

    for (final k in anahtarlar) {
      final liste = gruplar[k]!;
      final parca = k.split('|');
      final ihale = parca[0];
      final firma = parca.length > 1 ? parca[1] : '';
      if (ihale.isNotEmpty) ihaleler.add(ihale);
      if (firma.isNotEmpty) firmalar.add(firma);

      final tarihler = liste
          .map((r) => r['alim_tarihi'])
          .whereType<num>()
          .map((n) => n.toInt())
          .toList()
        ..sort();
      final s = _Sayac()..ekle(liste);
      final urunSayisi = {for (final r in liste) r['urun_id']}.length;

      final baslik = ihale.isEmpty && firma.isEmpty
          ? 'Alım bilgisi girilmemiş'
          : [
              if (ihale.isNotEmpty) 'İhale: $ihale',
              if (firma.isNotEmpty) 'Firma: $firma',
            ].join(' · ');
      ozetSatirlari.add([
        ihale.isEmpty ? '-' : ihale,
        firma.isEmpty ? '-' : firma,
        tarihler.isEmpty ? '' : _gunMs(tarihler.first),
        urunSayisi,
        s.toplam,
        s.depoda + s.aracta,
        s.sahada,
      ]);
      detaylar.add(RaporBolumu(
        baslik: baslik,
        aciklama: [
          if (tarihler.isNotEmpty) 'Alım: ${_gunMs(tarihler.first)}'
              '${tarihler.last != tarihler.first ? ' - ${_gunMs(tarihler.last)}' : ''}',
          'Toplam ${s.toplam}',
          'Stokta ${s.depoda + s.aracta}',
          'Sahada ${s.sahada}',
          'Çıkış ${s.cikti}',
        ].join(' · '),
        sutunlar: const [
          'Seri No', 'Ürün', 'Alım tarihi', 'Garanti bitiş', 'Durum',
          'Konum / kullanım yeri'
        ],
        genislikler: const [20, 26, 11, 11, 14, 22],
        satirlar: [
          for (final r in liste)
            [
              r['seri_no'] ?? '',
              r['urun_adi'] ?? '',
              _gunMs(r['alim_tarihi']),
              _gunMs(r['garanti_bitis']),
              durumEtiketi(r['durum'] as String?, r['depo_tur'] as String?),
              _konum(r),
            ],
        ],
      ));
    }

    return Rapor(
      baslik: 'Alımlar (İhale / Firma)',
      altBaslik: _olusturma(),
      dosyaOn: 'alimlar_raporu',
      ozet: [
        MapEntry('İhale', '${ihaleler.length}'),
        MapEntry('Firma', '${firmalar.length}'),
        MapEntry('Toplam cihaz', '${rows.length}'),
      ],
      sutunlar: const [
        'İhale / sipariş', 'Firma', 'İlk alım', 'Ürün çeşidi', 'Cihaz',
        'Stokta', 'Sahada'
      ],
      genislikler: const [20, 22, 11, 9, 8, 8, 8],
      bolumler: [
        if (ozetSatirlari.isNotEmpty)
          RaporBolumu(baslik: 'Özet', satirlar: ozetSatirlari),
        ...detaylar,
      ],
    );
  }

  // ------------------------------------------------------------------
  // Bölge raporu: il / ilçe / mahalle bazında kurulum noktaları
  // ------------------------------------------------------------------
  static Future<Rapor> bolge(AppDatabase db, {String? filtre}) async {
    var rows = await db.bolgeRaporu();
    final f = (filtre ?? '').trim().toLowerCase();
    if (f.isNotEmpty) {
      rows = rows
          .where((r) => [r['il'], r['ilce'], r['mahalle'], r['kullanim_yeri']]
              .whereType<String>()
              .any((v) => v.toLowerCase().contains(f)))
          .toList();
    }

    String deger(Object? v) {
      final t = (v as String?)?.trim() ?? '';
      return t.isEmpty ? 'Belirsiz' : t;
    }

    // il|ilçe|mahalle -> kayıtlar (sorgu zaten bu sırayla gelir)
    final gruplar = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      final k = '${deger(r['il'])}|${deger(r['ilce'])}|${deger(r['mahalle'])}';
      gruplar.putIfAbsent(k, () => []).add(r);
    }

    final iller = <String>{};
    final ilceler = <String>{};
    var belirsiz = 0;
    for (final r in rows) {
      if ((r['il'] as String?)?.isNotEmpty ?? false) iller.add(r['il'] as String);
      if ((r['ilce'] as String?)?.isNotEmpty ?? false) {
        ilceler.add('${r['il']}|${r['ilce']}');
      }
      if (((r['mahalle'] as String?) ?? '').isEmpty) belirsiz++;
    }

    final ozetSatirlari = <List<Object?>>[];
    final detaylar = <RaporBolumu>[];
    for (final e in gruplar.entries) {
      final p = e.key.split('|');
      final konumlu = e.value.where((r) => r['enlem'] != null).length;
      ozetSatirlari.add([p[0], p[1], p[2], e.value.length, konumlu]);
      detaylar.add(RaporBolumu(
        baslik: '${p[2]} · ${p[1]} / ${p[0]} (${e.value.length})',
        satirlar: [
          for (final r in e.value)
            [
              r['seri_no'] ?? '',
              r['urun_adi'] ?? '',
              r['kullanim_yeri'] ?? '',
              _tarihMs(r['tarih']),
              konumHucresi((r['enlem'] as num?)?.toDouble(),
                  (r['boylam'] as num?)?.toDouble()),
            ],
        ],
      ));
    }
    // Özet: en çok kurulum olan bölge üstte
    ozetSatirlari.sort((a, b) => (b[3] as int).compareTo(a[3] as int));

    return Rapor(
      baslik: 'Bölge Raporu (Kurulum Noktaları)',
      altBaslik: [
        if (f.isNotEmpty) 'Filtre: "$filtre"',
        'Sahada olan cihazlar',
        _olusturma(),
      ].join(' · '),
      dosyaOn: 'bolge_raporu',
      ozet: [
        MapEntry('Kurulum noktası', '${rows.length}'),
        MapEntry('İl', '${iller.length}'),
        MapEntry('İlçe', '${ilceler.length}'),
        MapEntry('Mahalle / köy', '${gruplar.length}'),
        if (belirsiz > 0) MapEntry('Mahallesi belirsiz', '$belirsiz'),
      ],
      sutunlar: const [
        'Seri No', 'Ürün', 'Kullanım yeri', 'Kurulum tarihi', 'Konum (GPS)'
      ],
      genislikler: const [20, 24, 26, 15, 24],
      bolumler: [
        if (ozetSatirlari.isNotEmpty)
          RaporBolumu(
            baslik: 'Mahalle / köy bazında kurulum sayıları',
            sutunlar: const [
              'İl', 'İlçe', 'Mahalle / köy', 'Kurulum', 'Konumu kayıtlı'
            ],
            genislikler: const [16, 18, 26, 10, 12],
            satirlar: ozetSatirlari,
          ),
        ...detaylar,
        if (rows.isEmpty)
          const RaporBolumu(
              baslik: 'Sahada kayıtlı kurulum yok', satirlar: []),
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
    final sebepSayilari = <String, int>{};
    for (final r in rows) {
      final t = _tipAdlari[r['tip']] ?? '${r['tip']}';
      tipSayilari[t] = (tipSayilari[t] ?? 0) + 1;
      final sb = r['sebep'] as String?;
      if (sb != null) sebepSayilari[sb] = (sebepSayilari[sb] ?? 0) + 1;
    }

    return Rapor(
      baslik: 'Hareket Geçmişi',
      altBaslik: '${_aralik(baslangic, bitis)} · ${_olusturma()}',
      dosyaOn: 'hareket_gecmisi',
      ozet: [
        MapEntry('Toplam hareket', '${rows.length}'),
        for (final e in tipSayilari.entries) MapEntry(e.key, '${e.value}'),
        for (final e in sebepSayilari.entries)
          MapEntry('Geri alma: ${e.key}', '${e.value}'),
      ],
      sutunlar: const [
        'Tarih', 'İşlem', 'Seri No', 'Ürün', 'Nereden', 'Nereye',
        'Kullanım yeri', 'Sebep', 'Kullanıcı', 'Not'
      ],
      genislikler: const [15, 10, 17, 20, 15, 15, 18, 13, 13, 18],
      bolumler: [
        RaporBolumu(
          satirlar: [
            for (final r in rows)
              [
                _tarihMs(r['tarih']),
                r['tip'] == 'girisi' && r['sebep'] != null
                    ? 'Geri alma'
                    : (_tipAdlari[r['tip']] ?? (r['tip'] ?? '')),
                r['seri_no'] ?? '',
                r['urun_adi'] ?? '',
                r['kaynak'] ?? '',
                r['hedef'] ?? '',
                r['kullanim_yeri'] ?? '',
                r['sebep'] ?? '',
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
