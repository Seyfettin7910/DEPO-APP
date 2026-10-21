import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../adres_servisi.dart';
import '../giris_kaydi_servisi.dart';
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
  static String durumEtiketi(String? durum, String? depoTur, [Object? servis]) {
    final sd = servisDurumuCoz(servis);
    if (sd != null) return sd.kisa;
    switch (durum) {
      case 'depoda':
        return depoTur == 'arac' ? 'Araçta' : 'Depoda';
      case 'kullanimda':
        return montajDurumAdi;
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
    'kullanim': 'Araca Yükle / Montaj',
    'iade': 'İade',
    'silme': 'Silme',
    'servis': 'Servis',
    'hurda': 'Hurda',
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
        durumEtiketi(r['durum'] as String?, r['depo_tur'] as String?,
            r['servis_durumu']),
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

    // Ürün bazlı toplam: cihazda adet, malzemede miktar + birim
    final urunSayilari = <String, int>{};
    final birimler = <String, String>{};
    for (final s in satirlar) {
      urunSayilari[s.urunAdi] = (urunSayilari[s.urunAdi] ?? 0) + s.miktar;
      birimler[s.urunAdi] = s.malzeme ? s.birim : 'adet';
    }
    final urunler = urunSayilari.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final cihazlar = satirlar.where((s) => !s.malzeme).toList();

    return Rapor(
      baslik: 'Kullanım Raporu – Montajı Yapılanlar',
      altBaslik: '${_aralik(baslangic, bitis)} · yapılmış tüm montajlar '
          '(sonradan geri alınanlar dahil) · ${_olusturma()}',
      dosyaOn: 'kullanim_raporu',
      ozet: [
        MapEntry('Montaj (cihaz)', '${cihazlar.length}'),
        MapEntry('Malzeme kullanımı',
            '${satirlar.length - cihazlar.length}'),
        MapEntry('Tutanak alındı',
            '${cihazlar.where((s) => s.tutanak == 'alindi').length}'),
        MapEntry('Tutanak alınacak',
            '${cihazlar.where((s) => s.tutanak == 'alinacak').length}'),
        MapEntry('Kurum içi',
            '${cihazlar.where((s) => s.tutanak == 'kurum_ici').length}'),
        // Tutanak seçeneği gelmeden (1.24.0 öncesi) yapılan montajlar
        if (cihazlar.any((s) => s.tutanak == null))
          MapEntry('Tutanak belirtilmemiş',
              '${cihazlar.where((s) => s.tutanak == null).length}'),
        MapEntry('Konumu kayıtlı',
            '${satirlar.where((s) => s.enlem != null).length}'),
      ],
      sutunlar: const [
        'Tarih', 'Seri No / Miktar', 'Ürün', 'Çıktığı yer',
        'Kullanım yeri / Araç', 'Tutanak', 'Bölge (mahalle, ilçe / il)',
        'Konum (GPS)'
      ],
      genislikler: const [14, 17, 19, 14, 20, 11, 22, 19],
      bolumler: [
        if (urunler.isNotEmpty)
          RaporBolumu(
            baslik: 'Ürün bazlı özet',
            sutunlar: const ['Ürün', 'Miktar', 'Birim'],
            genislikler: const [40, 10, 10],
            satirlar: [
              for (final u in urunler) [u, urunSayilari[u], birimler[u]],
            ],
          ),
        RaporBolumu(
          baslik: 'Kullanım detayları',
          satirlar: [
            for (final s in satirlar)
              [
                _tarih.format(s.tarih),
                s.malzeme ? '${s.miktar} ${s.birim}' : (s.seriNo ?? ''),
                s.urunAdi,
                s.depoAdi,
                s.aracPlaka ?? s.kullanimYeri ?? 'Belirtilmedi',
                s.malzeme ? '-' : tutanakKisa(s.tutanak),
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
    final malzemeBolumu = await _malzemeBolumu(db);

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
        ad, kategori, s.toplam, s.depoda, s.aracta, s.sahada, s.arizali,
        s.hurda, s.cikti
      ]);
      detaylar.add(RaporBolumu(
        baslik: ad,
        aciklama: [
          if (kategori.isNotEmpty) 'Kategori: $kategori',
          'Toplam ${s.toplam}',
          'Depoda ${s.depoda}',
          'Araçta ${s.aracta}',
          'Montajlı ${s.sahada}',
          if (s.arizali > 0) 'Arızalı / serviste ${s.arizali}',
          if (s.hurda > 0) 'Hurda ${s.hurda}',
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
        MapEntry('Montaj yapıldı', '${sayac.sahada}'),
        MapEntry('Arızalı / serviste', '${sayac.arizali}'),
        MapEntry('Hurda', '${sayac.hurda}'),
        MapEntry('Çıkış yapıldı', '${sayac.cikti}'),
      ],
      sutunlar: _cihazSutunlari,
      genislikler: _cihazGenislik,
      bolumler: [
        if (ozetSatirlari.isNotEmpty)
          RaporBolumu(
            baslik: 'Ürün özeti',
            sutunlar: const [
              'Ürün', 'Kategori', 'Toplam', 'Depoda', 'Araçta', 'Montajlı',
              'Arızalı', 'Hurda', 'Çıkış'
            ],
            genislikler: const [26, 15, 8, 8, 8, 8, 8, 8, 8],
            satirlar: ozetSatirlari,
          ),
        if (malzemeBolumu != null) malzemeBolumu,
        ...detaylar,
      ],
    );
  }

  /// Miktarla takip edilen malzemelerin depolar / araçlardaki miktarları.
  static Future<RaporBolumu?> _malzemeBolumu(AppDatabase db) async {
    final malzemeler =
        (await db.tumUrunler()).where((u) => u.miktarli).toList();
    if (malzemeler.isEmpty) return null;
    final stok = await db.malzemeStoklari();
    final depolar = {for (final d in await db.tumDepolar()) d.id: d};
    return RaporBolumu(
      baslik: 'Malzemeler (miktarla takip)',
      sutunlar: const [
        'Malzeme', 'Kategori', 'Depolarda', 'Araçlarda', 'Toplam', 'Birim'
      ],
      genislikler: const [26, 15, 10, 10, 10, 9],
      satirlar: [
        for (final u in malzemeler)
          () {
            var depoda = 0, aracta = 0;
            for (final e in (stok[u.id] ?? const <String, int>{}).entries) {
              final d = depolar[e.key];
              if (d == null) continue;
              if (d.arac) {
                aracta += e.value;
              } else {
                depoda += e.value;
              }
            }
            return <Object?>[
              u.ad, u.kategori ?? '', depoda, aracta, depoda + aracta, u.birim
            ];
          }(),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Seçili ürünün stok durumu
  // ------------------------------------------------------------------
  static Future<Rapor> urunStokDurumu(AppDatabase db, Urun urun) async {
    if (urun.miktarli) return _malzemeStokDurumu(db, urun);
    final rows = await db.cihazListesiRaporu(urunId: urun.id);
    final s = _Sayac()..ekle(rows);

    ServisDurumu? sd(Map<String, Object?> r) =>
        servisDurumuCoz(r['servis_durumu']);
    List<Map<String, Object?>> filtre(String durum, {String? tur}) => rows
        .where((r) =>
            r['durum'] == durum &&
            !(sd(r)?.arizali ?? false) &&
            sd(r) != ServisDurumu.hurda &&
            (tur == null ||
                (tur == 'arac') == (r['depo_tur'] == 'arac')))
        .toList();

    final depolarda = filtre('depoda', tur: 'sabit');
    final araclarda = filtre('depoda', tur: 'arac');
    final sahada = filtre('kullanimda');
    final cikti = filtre('cikti');
    final arizalilar = rows.where((r) => sd(r)?.arizali ?? false).toList();
    final hurdalar = rows.where((r) => sd(r) == ServisDurumu.hurda).toList();

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
        MapEntry('Montaj yapıldı', '${s.sahada}'),
        MapEntry('Arızalı / serviste', '${s.arizali}'),
        MapEntry('Hurda', '${s.hurda}'),
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
          bolum('Montaj yapıldı', sahada),
          bolum('Arızalı / serviste', arizalilar),
          bolum('Hurdaya ayrılan', hurdalar),
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

  /// Miktarlı malzemenin depolar / araçlardaki miktarı ve montajlarda
  /// kullanılanlar.
  static Future<Rapor> _malzemeStokDurumu(AppDatabase db, Urun urun) async {
    final stok = (await db.malzemeStoklari())[urun.id] ?? const <String, int>{};
    final depolar = {for (final d in await db.tumDepolar()) d.id: d};
    final dagilim = <List<Object?>>[];
    var depoda = 0, aracta = 0;
    for (final e in stok.entries) {
      final d = depolar[e.key];
      if (d == null || e.value == 0) continue;
      dagilim.add([d.ad, d.arac ? 'Araç' : 'Depo', e.value, urun.birim]);
      if (d.arac) {
        aracta += e.value;
      } else {
        depoda += e.value;
      }
    }
    dagilim.sort((a, b) => (b[2] as int).compareTo(a[2] as int));
    final kullanimlar = await db.kullanimRaporu(urunId: urun.id);
    final kullanilan = kullanimlar.fold<int>(0, (t, k) => t + k.miktar);
    return Rapor(
      baslik: 'Stok Durumu: ${urun.ad}',
      altBaslik: [
        'Malzeme (${urun.birim})',
        if ((urun.kategori ?? '').isNotEmpty) 'Kategori: ${urun.kategori}',
        _olusturma(),
      ].join(' · '),
      dosyaOn: 'stok_durumu',
      ozet: [
        MapEntry('Toplam', urun.miktarMetni(depoda + aracta)),
        MapEntry('Depolarda', urun.miktarMetni(depoda)),
        MapEntry('Araçlarda', urun.miktarMetni(aracta)),
        MapEntry('Montajda kullanılan', urun.miktarMetni(kullanilan)),
      ],
      sutunlar: const ['Konum', 'Tür', 'Miktar', 'Birim'],
      genislikler: const [30, 10, 10, 10],
      bolumler: [
        RaporBolumu(
          baslik: 'Konumlara göre miktar',
          satirlar: dagilim,
        ),
        if (kullanimlar.isNotEmpty)
          RaporBolumu(
            baslik: 'Montajda kullanılan (${kullanimlar.length})',
            sutunlar: const ['Tarih', 'Miktar', 'Çıktığı yer', 'Kullanım yeri'],
            genislikler: const [16, 12, 20, 30],
            satirlar: [
              for (final k in kullanimlar)
                [
                  _tarih.format(k.tarih),
                  '${k.miktar} ${k.birim}',
                  k.depoAdi,
                  k.kullanimYeri ?? '',
                ],
            ],
          ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Kritik stok
  // ------------------------------------------------------------------
  static Future<Rapor> kritikStok(AppDatabase db) async {
    final liste = await db.kritikStoklar();
    return Rapor(
      baslik: 'Kritik Stok',
      altBaslik: 'Depolar ve araçlardaki sağlam cihaz adedi (malzemede miktar), '
          'ürünün minimumuyla karşılaştırılır · ${_olusturma()}',
      dosyaOn: 'kritik_stok',
      ozet: [
        MapEntry('Kritik ürün', '${liste.length}'),
        MapEntry('Tükenen', '${liste.where((k) => k.toplam == 0).length}'),
        MapEntry('Toplam eksik',
            '${liste.fold<int>(0, (t, k) => t + (k.eksik > 0 ? k.eksik : 0))}'),
      ],
      sutunlar: const [
        'Ürün', 'Kategori', 'Minimum', 'Depolarda', 'Araçlarda', 'Toplam',
        'Eksik', 'Durum'
      ],
      genislikler: const [28, 16, 9, 9, 9, 9, 8, 10],
      bolumler: [
        RaporBolumu(
          aciklama: liste.isEmpty
              ? 'Minimum adedin altına inmiş ürün yok.'
              : '"Eksik": minimumun üstüne çıkmak için alınması gereken adet.',
          satirlar: [
            for (final k in liste)
              [
                k.birim == null ? k.urunAdi : '${k.urunAdi} (${k.birim})',
                k.kategori ?? '',
                k.minStok,
                k.depoda,
                k.aracta,
                k.toplam,
                k.eksik,
                k.durum,
              ],
          ],
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
          durumEtiketi(r['durum'] as String?, r['depo_tur'] as String?,
            r['servis_durumu']),
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
          'Montajlı ${s.sahada}',
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
              durumEtiketi(r['durum'] as String?, r['depo_tur'] as String?,
            r['servis_durumu']),
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
        'Stokta', 'Montajlı'
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

    // Aynı yer farklı yazılmış olabilir ("KULAT" / "Kulat", "Sakarya
    // Mahallesi" / "Sakarya Mah."): ekler atılır, büyük / küçük harf yok
    // sayılır, ekranda düzgün yazılır ("Kulat").
    String deger(Object? v) {
      final t = bolgeAdiDuzelt(v as String?);
      return t.isEmpty ? 'Belirsiz' : t;
    }

    // il|ilçe|mahalle -> kayıtlar
    final gruplar = <String, List<Map<String, Object?>>>{};
    final adlar = <String, List<String>>{};
    for (final r in rows) {
      final p = [deger(r['il']), deger(r['ilce']), deger(r['mahalle'])];
      final k = p.map(trKucuk).join('|');
      gruplar.putIfAbsent(k, () => []).add(r);
      adlar.putIfAbsent(k, () => p);
    }

    final iller = <String>{};
    final ilceler = <String>{};
    var belirsiz = 0;
    for (final r in rows) {
      final il = bolgeAdiDuzelt(r['il'] as String?);
      final ilce = bolgeAdiDuzelt(r['ilce'] as String?);
      if (il.isNotEmpty) iller.add(trKucuk(il));
      if (ilce.isNotEmpty) ilceler.add('${trKucuk(il)}|${trKucuk(ilce)}');
      if (bolgeAdiDuzelt(r['mahalle'] as String?).isEmpty) belirsiz++;
    }
    // "Belirsiz" mahalle sayılmaz.
    final mahalleSayisi = gruplar.keys.where((k) => !k.endsWith('|belirsiz')).length;
    // Kurulum noktası = farklı konum (aynı yere toplu takılanlar tek nokta);
    // konumu olmayan her montaj ayrı sayılır.
    final noktalar = <String>{};
    var konumsuz = 0;
    for (final r in rows) {
      final en = (r['enlem'] as num?)?.toDouble();
      final boy = (r['boylam'] as num?)?.toDouble();
      if (en == null || boy == null) {
        konumsuz++;
      } else {
        noktalar.add('${en.toStringAsFixed(5)},${boy.toStringAsFixed(5)}');
      }
    }

    final ozetSatirlari = <List<Object?>>[];
    final detaylar = <RaporBolumu>[];
    for (final e in gruplar.entries) {
      final p = adlar[e.key]!;
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
        'Şu an takılı cihazlar (geri alınanlar hariç)',
        _olusturma(),
      ].join(' · '),
      dosyaOn: 'bolge_raporu',
      ozet: [
        MapEntry('Montajlı cihaz', '${rows.length}'),
        MapEntry('Kurulum noktası', '${noktalar.length + konumsuz}'),
        MapEntry('İl', '${iller.length}'),
        MapEntry('İlçe', '${ilceler.length}'),
        MapEntry('Mahalle / köy', '$mahalleSayisi'),
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
              baslik: 'Kayıtlı montaj yok', satirlar: []),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Arıza / servis
  // ------------------------------------------------------------------
  static Future<Rapor> servis(AppDatabase db,
      {DateTime? baslangic, DateTime? bitis}) async {
    final rows = await db.servisRaporu(baslangic: baslangic, bitis: bitis);

    DateTime? t(Object? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
    Duration? sure(Map<String, Object?> r) {
      final g = t(r['gonderim_tarihi']);
      if (g == null) return null;
      return (t(r['donus_tarihi']) ?? DateTime.now()).difference(g);
    }

    String yer(Object? v) => onarimYeriAdlari[v] ?? '';
    String karar(Object? v) => servisKararAdlari[v] ?? '${v ?? ''}';

    final acik = rows.where((r) => r['kapanis'] == null).toList();
    final kapanan = rows.where((r) => r['kapanis'] != null).toList();
    final serviste = acik.where((r) => r['gonderim_tarihi'] != null).length;
    int sonucSay(String s) => kapanan.where((r) => r['sonuc'] == s).length;

    // Tamamlanan onarımların ortalama süresi
    final sureler = [
      for (final r in kapanan)
        if (r['gonderim_tarihi'] != null && r['donus_tarihi'] != null) sure(r)!
    ];
    final ortalama = sureler.isEmpty
        ? null
        : Duration(
            milliseconds: sureler.fold<int>(0, (a, d) => a + d.inMilliseconds) ~/
                sureler.length);

    // Firma bazlı özet (garanti ve iç onarım ayrı)
    final firmalar = <String, List<Map<String, Object?>>>{};
    for (final r in rows.where((r) => r['gonderim_tarihi'] != null)) {
      final f = (r['firma'] as String?)?.trim();
      final ad = '${yer(r['onarim_yeri'])}|${(f == null || f.isEmpty) ? '-' : f}';
      firmalar.putIfAbsent(ad, () => []).add(r);
    }
    final firmaSatirlari = <List<Object?>>[];
    for (final e in firmalar.entries) {
      final p = e.key.split('|');
      final liste = e.value;
      final biten = liste
          .where((r) => r['donus_tarihi'] != null)
          .map((r) => sure(r)!)
          .toList();
      firmaSatirlari.add([
        p[1],
        p[0],
        liste.length,
        liste.where((r) => r['kapanis'] == null).length,
        liste.where((r) => r['sonuc'] == 'onarildi').length,
        liste.where((r) => r['sonuc'] == 'degistirildi').length,
        liste.where((r) => r['sonuc'] == 'onarilamadi').length,
        biten.isEmpty
            ? ''
            : sureMetni(Duration(
                milliseconds:
                    biten.fold<int>(0, (a, d) => a + d.inMilliseconds) ~/
                        biten.length)),
      ]);
    }
    firmaSatirlari.sort((a, b) => (b[2] as int).compareTo(a[2] as int));

    return Rapor(
      baslik: 'Arıza / Servis Raporu',
      altBaslik: '${_aralik(baslangic, bitis)} (arıza kaydı tarihine göre) · '
          '${_olusturma()}',
      dosyaOn: 'ariza_servis_raporu',
      ozet: [
        MapEntry('Toplam arıza', '${rows.length}'),
        MapEntry('Açık', '${acik.length}'),
        MapEntry('Serviste', '$serviste'),
        MapEntry('Onarıldı', '${sonucSay('onarildi')}'),
        MapEntry('Değiştirildi', '${sonucSay('degistirildi')}'),
        MapEntry('Hurdaya ayrıldı',
            '${kapanan.where((r) => r['kapanis'] == 'hurda').length}'),
        if (ortalama != null) MapEntry('Ort. onarım süresi', sureMetni(ortalama)),
      ],
      sutunlar: const [
        'Seri No', 'Ürün', 'Arıza kaydı', 'Karar', 'Onarım yeri', 'Firma',
        'Gönderim', 'Dönüş', 'Onarım süresi', 'Sonuç', 'Kapanış', 'Açıklama'
      ],
      genislikler: const [15, 16, 12, 14, 13, 14, 12, 12, 10, 12, 13, 20],
      bolumler: [
        RaporBolumu(
          baslik: 'Açık dosyalar (${acik.length})',
          aciklama: 'Arızalı bekleyen veya serviste olan cihazlar. '
              'Süre: gönderimden bugüne.',
          sutunlar: const [
            'Seri No', 'Ürün', 'Arıza kaydı', 'Karar', 'Durum', 'Onarım yeri',
            'Firma', 'Gönderim', 'Geçen süre', 'Depo', 'Arıza açıklaması'
          ],
          genislikler: const [15, 16, 12, 16, 13, 13, 14, 12, 10, 12, 20],
          satirlar: [
            for (final r in acik)
              [
                r['seri_no'] ?? '',
                r['urun_adi'] ?? '',
                _tarihMs(r['acilis_tarihi']),
                karar(r['karar']),
                servisDurumuCoz(r['servis_durumu'])?.kisa ?? '',
                yer(r['onarim_yeri']),
                r['firma'] ?? '',
                _tarihMs(r['gonderim_tarihi']),
                sure(r) == null ? '' : sureMetni(sure(r)!),
                r['depo_adi'] ?? '',
                r['ariza_aciklama'] ?? '',
              ],
          ],
        ),
        RaporBolumu(
          baslik: 'Kapanan dosyalar (${kapanan.length})',
          satirlar: [
            for (final r in kapanan)
              [
                r['seri_no'] ?? '',
                r['urun_adi'] ?? '',
                _tarihMs(r['acilis_tarihi']),
                karar(r['karar']),
                yer(r['onarim_yeri']),
                r['firma'] ?? '',
                _tarihMs(r['gonderim_tarihi']),
                _tarihMs(r['donus_tarihi']),
                (r['gonderim_tarihi'] != null && r['donus_tarihi'] != null)
                    ? sureMetni(sure(r)!)
                    : '',
                servisSonucAdlari[r['sonuc']] ?? '',
                [
                  servisKapanisAdlari[r['kapanis']] ?? '${r['kapanis']}',
                  if (r['yeni_seri_no'] != null) 'Yeni SN: ${r['yeni_seri_no']}',
                ].join(' · '),
                [
                  if (r['ariza_aciklama'] != null) 'Arıza: ${r['ariza_aciklama']}',
                  if (r['sonuc_aciklama'] != null) '${r['sonuc_aciklama']}',
                ].join(' · '),
              ],
          ],
        ),
        if (firmaSatirlari.isNotEmpty)
          RaporBolumu(
            baslik: 'Firma / onarım yeri bazında',
            aciklama: 'Ortalama süre yalnızca dönüşü girilen dosyalardan hesaplanır.',
            sutunlar: const [
              'Firma / onaran', 'Onarım yeri', 'Gönderilen', 'Hâlâ serviste',
              'Onarıldı', 'Değiştirildi', 'Onarılamadı', 'Ort. süre'
            ],
            genislikler: const [24, 18, 10, 10, 10, 10, 10, 12],
            satirlar: firmaSatirlari,
          ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Hurda
  // ------------------------------------------------------------------
  static Future<Rapor> hurda(AppDatabase db,
      {DateTime? baslangic, DateTime? bitis}) async {
    final rows = await db.hurdaRaporu(baslangic: baslangic, bitis: bitis);

    final nedenler = <String, int>{};
    final urunler = <String, int>{};
    for (final r in rows) {
      final n = (r['sebep'] as String?) ?? 'Belirtilmedi';
      nedenler[n] = (nedenler[n] ?? 0) + 1;
      final u = (r['urun_adi'] as String?) ?? '-';
      urunler[u] = (urunler[u] ?? 0) + 1;
    }
    final urunSatirlari = [
      for (final e in urunler.entries) [e.key, e.value],
    ]..sort((a, b) => (b[1] as int).compareTo(a[1] as int));

    return Rapor(
      baslik: 'Hurda Raporu',
      altBaslik: '${_aralik(baslangic, bitis)} · ${_olusturma()}',
      dosyaOn: 'hurda_raporu',
      ozet: [
        MapEntry('Hurdaya ayrılan', '${rows.length}'),
        for (final e in nedenler.entries) MapEntry(e.key, '${e.value}'),
      ],
      sutunlar: const [
        'Tarih', 'Seri No', 'Ürün', 'Ayrıldığı depo', 'Neden', 'Alım tarihi',
        'Firma', 'İhale', 'Kullanıcı', 'Açıklama'
      ],
      genislikler: const [14, 17, 20, 15, 18, 11, 15, 14, 12, 20],
      bolumler: [
        if (urunSatirlari.isNotEmpty)
          RaporBolumu(
            baslik: 'Ürün bazında',
            sutunlar: const ['Ürün', 'Adet'],
            genislikler: const [40, 10],
            satirlar: urunSatirlari,
          ),
        RaporBolumu(
          baslik: 'Hurdaya ayrılan cihazlar (${rows.length})',
          satirlar: [
            for (final r in rows)
              [
                _tarihMs(r['tarih']),
                r['seri_no'] ?? '',
                r['urun_adi'] ?? '',
                r['depo_adi'] ?? '',
                r['sebep'] ?? '',
                _gunMs(r['alim_tarihi']),
                r['firma'] ?? '',
                r['ihale'] ?? '',
                r['kullanici'] ?? '',
                r['not_'] ?? '',
              ],
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Kurum etiketi durumu
  // ------------------------------------------------------------------
  static Future<Rapor> etiketDurumu(AppDatabase db) async {
    final rows = await db.etiketDurumRaporu();
    final say = <EtiketDurumu, int>{};
    for (final r in rows) {
      final d = etiketDurumuCoz(r['durum']);
      say[d] = (say[d] ?? 0) + 1;
    }
    List<Object?> satir(Map<String, Object?> r) => [
          r['kod'] ?? '',
          ((r['seri_nosuz'] as num?) ?? 0).toInt() == 1
              ? '(seri nosuz)'
              : (r['seri_no'] ?? ''),
          r['urun_adi'] ?? '',
          durumEtiketi(r['cihaz_durum'] as String?, r['depo_tur'] as String?,
              r['servis_durumu']),
          r['depo_adi'] ?? '',
          (r['surum'] as num?)?.toInt() ?? 1,
          _gunMs(r['olusturma']),
          _tarihMs(r['son_islem']),
          r['son_kullanici'] ?? '',
          r['uyusmazlik'] ?? '',
        ];
    final sirali = [
      EtiketDurumu.uyusmazlik,
      EtiketDurumu.basildi,
      EtiketDurumu.kuyrukta,
      EtiketDurumu.kayitli,
      EtiketDurumu.dogrulandi,
    ];
    return Rapor(
      baslik: 'Etiket Durumu Raporu',
      altBaslik: _olusturma(),
      dosyaOn: 'etiket_durumu_raporu',
      ozet: [
        MapEntry('Toplam etiket', '${rows.length}'),
        for (final d in sirali)
          if ((say[d] ?? 0) > 0) MapEntry(d.etiket, '${say[d]}'),
      ],
      sutunlar: const [
        'Kurum kodu', 'Seri No', 'Ürün', 'Cihaz durumu', 'Depo / araç',
        'Sürüm', 'Üretim', 'Son işlem', 'Son işlemi yapan', 'Uyuşmazlık'
      ],
      genislikler: const [20, 16, 18, 12, 14, 7, 10, 14, 12, 24],
      bolumler: [
        for (final d in sirali)
          if ((say[d] ?? 0) > 0)
            RaporBolumu(
              baslik: '${d.etiket} (${say[d]})',
              satirlar: [
                for (final r in rows)
                  if (etiketDurumuCoz(r['durum']) == d) satir(r),
              ],
            ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Giriş kayıtları (sunucudan okunur, internet gerekir)
  // ------------------------------------------------------------------
  static Future<Rapor> girisKayitlari(
      {DateTime? baslangic, DateTime? bitis}) async {
    final rows =
        await GirisKaydiServisi.kayitlar(baslangic: baslangic, bitis: bitis);

    DateTime? zaman(Object? v) =>
        v == null ? null : DateTime.tryParse('$v')?.toLocal();
    String tarih(Object? v) {
      final t = zaman(v);
      return t == null ? '' : _tarih.format(t);
    }

    final basarili = rows.where((r) => r['basarili'] != false).toList();
    final hatali = rows.where((r) => r['basarili'] == false).toList();

    // Kullanıcı bazında özet (sorgu yeniden eskiye sıralı gelir)
    final kullanicilar = <String, List<Map<String, dynamic>>>{};
    for (final r in basarili) {
      kullanicilar
          .putIfAbsent((r['email'] as String?) ?? '-', () => [])
          .add(r);
    }
    final ozetSatirlari = [
      for (final e in kullanicilar.entries)
        [
          e.key,
          e.value.length,
          tarih(e.value.first['tarih']),
          e.value.first['ip'] ?? '',
          e.value.first['platform'] ?? '',
          {for (final r in e.value) r['ip']}.whereType<String>().length,
        ],
    ]..sort((a, b) => (b[1] as int).compareTo(a[1] as int));

    List<Object?> satir(Map<String, dynamic> r) => [
          tarih(r['tarih']),
          r['email'] ?? '',
          r['basarili'] == false ? 'Hatalı şifre' : 'Başarılı',
          r['ip'] ?? '',
          r['platform'] ?? '',
          r['surum'] ?? '',
          r['tarayici'] ?? '',
        ];

    return Rapor(
      baslik: 'Giriş Kayıtları',
      altBaslik: '${_aralik(baslangic, bitis)} · ${_olusturma()}',
      dosyaOn: 'giris_kayitlari',
      ozet: [
        MapEntry('Başarılı giriş', '${basarili.length}'),
        MapEntry('Hatalı şifre', '${hatali.length}'),
        MapEntry('Kullanıcı', '${kullanicilar.length}'),
        MapEntry('Farklı IP',
            '${{for (final r in rows) r['ip']}.whereType<String>().length}'),
      ],
      sutunlar: const [
        'Tarih', 'Kullanıcı', 'Sonuç', 'IP adresi', 'Platform', 'Sürüm',
        'Tarayıcı / cihaz'
      ],
      genislikler: const [14, 24, 11, 15, 16, 8, 32],
      bolumler: [
        if (ozetSatirlari.isNotEmpty)
          RaporBolumu(
            baslik: 'Kullanıcı bazında',
            sutunlar: const [
              'Kullanıcı', 'Giriş sayısı', 'Son giriş', 'Son IP',
              'Son platform', 'Farklı IP'
            ],
            genislikler: const [26, 10, 14, 15, 18, 9],
            satirlar: ozetSatirlari,
          ),
        if (hatali.isNotEmpty)
          RaporBolumu(
            baslik: 'Hatalı şifre denemeleri (${hatali.length})',
            satirlar: [for (final r in hatali) satir(r)],
          ),
        RaporBolumu(
          baslik: 'Tüm girişler (${rows.length})',
          satirlar: [for (final r in rows) satir(r)],
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
    final sebepSayilari = <String, int>{};
    for (final r in rows) {
      final t = _tipAdlari[r['tip']] ?? '${r['tip']}';
      tipSayilari[t] = (tipSayilari[t] ?? 0) + 1;
      final sb = r['sebep'] as String?;
      if (sb != null && r['tip'] == 'girisi') {
        sebepSayilari[sb] = (sebepSayilari[sb] ?? 0) + 1;
      }
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
        'Tarih', 'İşlem', 'Seri No / Miktar', 'Ürün', 'Nereden', 'Nereye',
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
                    : r['tip'] == 'kullanim'
                        ? (r['hedef'] != null ? 'Araca Yükle' : 'Montaj')
                        : (_tipAdlari[r['tip']] ?? (r['tip'] ?? '')),
                r['seri_no'] ??
                    (r['seri_takipli'] == 0
                        ? '${r['miktar']} ${r['birim'] ?? ''}'
                        : ''),
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
    // Miktarlı malzemeler: (ad, birim, sistemde, sayılan / sayılmadıysa null)
    List<(String, String, int, int?)> malzemeler = const [],
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
        if (malzemeler.isNotEmpty)
          RaporBolumu(
            baslik: 'Malzemeler (${malzemeler.length})',
            aciklama: 'Miktarla takip edilen malzemeler: sistemdeki ve '
                'sayılan miktar. Sayılmayanlar boş.',
            sutunlar: const ['Malzeme', 'Sistemde', 'Sayılan', 'Fark', 'Birim'],
            genislikler: const [30, 12, 12, 12, 10],
            satirlar: [
              for (final (ad, birim, sistemde, sayilan) in malzemeler)
                [
                  ad,
                  sistemde,
                  sayilan ?? '',
                  sayilan == null ? '' : sayilan - sistemde,
                  birim,
                ],
            ],
          ),
      ],
    );
  }

  /// Sayımda "fazla" çıkan cihazın sistemde nerede göründüğü.
  static String sistemdekiYer(CihazBilgi? b) {
    if (b == null) return 'Sistemde kayıtlı değil';
    final sd = b.cihaz.servisDurumu;
    switch (b.cihaz.durum) {
      case CihazDurumu.depoda:
        if (sd == ServisDurumu.garantide) {
          return 'Sistemde: garanti servisinde (${b.depoAdi ?? '-'})';
        }
        return 'Sistemde: ${b.depoAdi ?? '-'}'
            '${b.depoArac ? ' (araç)' : ''}'
            '${sd == null ? '' : ' · ${sd.kisa.toLowerCase()}'}';
      case CihazDurumu.kullanimda:
        return 'Sistemde: montaj yapıldı'
            '${b.cihaz.kullanimYeri == null ? '' : ' (${b.cihaz.kullanimYeri})'}';
      case CihazDurumu.cikti:
        if (sd == ServisDurumu.hurda) return 'Sistemde: hurdaya ayrılmış';
        if (sd == ServisDurumu.degistirildi) {
          return 'Sistemde: değiştirildi (firmaya teslim)';
        }
        return 'Sistemde: çıkış yapılmış';
    }
  }
}

class _Sayac {
  int toplam = 0, depoda = 0, aracta = 0, sahada = 0, cikti = 0;
  int arizali = 0, hurda = 0;

  void ekle(List<Map<String, Object?>> rows) {
    for (final r in rows) {
      toplam++;
      final sd = servisDurumuCoz(r['servis_durumu']);
      if (sd != null && sd.arizali) {
        arizali++;
        continue;
      }
      if (sd == ServisDurumu.hurda) {
        hurda++;
        continue;
      }
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
    arizali += s.arizali;
    hurda += s.hurda;
  }
}


/// Türkçe küçük harf (I → ı, İ → i).
String trKucuk(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Türkçe büyük harf (i → İ, ı → I).
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Bölge adını düzeltir: "KULAT" → "Kulat", "Sakarya Mahallesi" / "Sakarya
/// Mah." → "Sakarya", "Kayalar Köyü" → "Kayalar". Boşsa ''.
String bolgeAdiDuzelt(String? ad) {
  var t = (ad ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '';
  t = t.replaceAll(
      RegExp(r'\s+(mahallesi|mahalle|mah\.?|köyü|köy|koyu|koy)$',
          caseSensitive: false),
      '');
  // "MAHALLESİ" gibi Türkçe büyük harfli ekler de (İ / I) atılsın.
  final kucuk = trKucuk(t);
  for (final ek in [' mahallesi', ' mahalle', ' mah.', ' mah', ' köyü', ' köy']) {
    if (kucuk.endsWith(ek)) {
      t = t.substring(0, t.length - ek.length).trimRight();
      break;
    }
  }
  return t
      .split(' ')
      .map((k) => k.isEmpty
          ? k
          : trBuyuk(k.substring(0, 1)) + trKucuk(k.substring(1)))
      .join(' ');
}
