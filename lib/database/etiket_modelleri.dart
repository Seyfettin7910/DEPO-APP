/// Kurum etiketi (barkod / karekod) ile ilgili modeller (şema sürümü 11).

/// Ayarlardan tanımlanan kurum kodu (ör. BLD-BIM · Bilgi İşlem).
class KurumKodu {
  const KurumKodu({
    required this.id,
    required this.kod,
    required this.ad,
    this.aktif = true,
    this.sira = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String kod;
  final String ad;
  final bool aktif;
  final int sira;
  final DateTime updatedAt;
  final bool deleted;

  String get gorunen => ad.trim().isEmpty ? kod : '$kod · $ad';

  factory KurumKodu.fromMap(Map<String, Object?> m) => KurumKodu(
        id: m['id'] as String,
        kod: m['kod'] as String,
        ad: (m['ad'] as String?) ?? '',
        aktif: ((m['aktif'] as num?) ?? 1).toInt() == 1,
        sira: ((m['sira'] as num?) ?? 0).toInt(),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as num).toInt()),
        deleted: ((m['deleted'] as num?) ?? 0).toInt() == 1,
      );
}

/// Etiketin yaşam döngüsü.
enum EtiketDurumu {
  /// Kod üretildi, sistemde kayıtlı; basım istenmedi.
  kayitli('Kodu var, basılmadı'),

  /// Basım kuyruğunda (bilgisayardan basılacak).
  kuyrukta('Basım kuyruğunda'),

  /// Basıldı; cihaza yapıştırılıp doğrulanması bekleniyor.
  basildi('Yapıştırma bekliyor'),

  /// Etiket ile cihazın seri numarası eşleşti.
  dogrulandi('Doğrulandı'),

  /// Etiket başka bir cihaza yapıştırılmış.
  uyusmazlik('Uyuşmazlık');

  const EtiketDurumu(this.etiket);
  final String etiket;
}

EtiketDurumu etiketDurumuCoz(Object? ad) => EtiketDurumu.values
    .firstWhere((d) => d.name == ad, orElse: () => EtiketDurumu.kayitli);

/// Etiket geçmişindeki işlem türleri (kayıtlar silinemez).
enum EtiketIslemi {
  uretildi('Kod üretildi'),
  kuyruga('Basım kuyruğuna alındı'),
  basildi('Basıldı'),
  dogrulandi('Yapıştırma doğrulandı'),
  uyusmazlik('Uyuşmazlık'),
  yenidenBasim('Yeniden basım istendi');

  const EtiketIslemi(this.etiket);
  final String etiket;
}

EtiketIslemi etiketIslemiCoz(Object? ad) => EtiketIslemi.values
    .firstWhere((d) => d.name == ad, orElse: () => EtiketIslemi.uretildi);

/// Bir cihazın kurum etiketi ve cihaz / ürün / depo bilgileri.
class EtiketBilgi {
  const EtiketBilgi({
    required this.id,
    required this.cihazId,
    required this.kod,
    required this.surum,
    required this.durum,
    required this.seriNosuz,
    required this.olusturma,
    required this.seriNo,
    required this.urunAdi,
    this.depoAdi,
    this.kurumKoduId,
  });

  final String id;
  final String cihazId;
  final String kod;
  final int surum;
  final EtiketDurumu durum;

  /// Cihazın üretici seri numarası yok; kurum kodu seri no yerine geçer.
  final bool seriNosuz;
  final DateTime olusturma;
  final String seriNo;
  final String urunAdi;
  final String? depoAdi;
  final String? kurumKoduId;

  /// Basılmış ama doğrulanmamış (veya uyuşmazlık kaydı olan) etiket.
  bool get dogrulanmadi =>
      durum == EtiketDurumu.basildi || durum == EtiketDurumu.uyusmazlik;

  factory EtiketBilgi.fromRow(Map<String, Object?> r) => EtiketBilgi(
        id: r['e_id'] as String,
        cihazId: r['cihaz_id'] as String,
        kod: r['kod'] as String,
        surum: ((r['surum'] as num?) ?? 1).toInt(),
        durum: etiketDurumuCoz(r['e_durum']),
        seriNosuz: ((r['seri_nosuz'] as num?) ?? 0).toInt() == 1,
        olusturma: DateTime.fromMillisecondsSinceEpoch(
            ((r['olusturma'] as num?) ?? 0).toInt()),
        seriNo: (r['seri_no'] as String?) ?? '-',
        urunAdi: (r['urun_adi'] as String?) ?? '-',
        depoAdi: r['depo_adi'] as String?,
        kurumKoduId: r['kurum_kodu_id'] as String?,
      );
}

/// Etiket geçmişi satırı.
class EtiketHareketSatiri {
  const EtiketHareketSatiri({
    required this.islem,
    required this.tarih,
    this.aciklama,
    this.kullaniciAdi,
  });

  final EtiketIslemi islem;
  final DateTime tarih;
  final String? aciklama;
  final String? kullaniciAdi;
}

/// Kurum genelindeki etiket ayarları (sunucuda tutulur, herkeste aynı).
class EtiketAyarlari {
  const EtiketAyarlari({this.dogrulama = true, this.engel = false});

  /// Yapıştırma doğrulaması kullanılıyor mu?
  final bool dogrulama;

  /// Doğrulanmamış etiketli cihazın transfer / kullanıma verme / sahada
  /// kullanımı engellensin mi? (Doğrulama açıkken geçerli.)
  final bool engel;

  bool get engelEtkin => dogrulama && engel;

  static const dogrulamaAnahtari = 'etiket_dogrulama';
  static const engelAnahtari = 'etiket_engel';

  factory EtiketAyarlari.fromMap(Map<String, String> m) => EtiketAyarlari(
        dogrulama: m[dogrulamaAnahtari] != '0',
        engel: m[engelAnahtari] == '1',
      );
}
