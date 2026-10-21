/// Okut ekranında arka arkaya okutmanın kuralları (ekrandan bağımsız; testleri
/// test/okut_listesi_test.dart'ta).
///
/// - İşlem seçilmeden: kayıtlı cihaz → kart açılır. 1. kayıtsız → bugünkü gibi
///   uyarı. Hemen ardından 2. kayıtsız → arka arkaya okutma başlar (Depoya
///   giriş listesi, ikisi de girer). 1. kayıtsızdan sonra kayıtlı okutulursa
///   sorulur (Atla / Kartı aç).
/// - Hızlı işlem seçiliyse: Depoya giriş yalnız kayıtsız, Transfer / Araca
///   Yükle / Montaj yalnız kayıtlı alır; diğeri "liste dışı" atlanır.
/// - En fazla [sinir] kayıt; aynı seri no iki kez girmez.
library;

enum OkutIslemi { giris, transfer, yukle, montaj }

enum OkutSonucu {
  /// İşlem yok, kayıtlı cihaz: kartı açılsın.
  kartAc,

  /// İşlem yok, 1. kayıtsız: bugünkü uyarı ("Depoya ekle").
  ilkKayitsiz,

  /// 2. kayıtsız: arka arkaya okutma başladı (liste = Depoya giriş).
  topluBasladi,

  /// 1. kayıtsızdan sonra kayıtlı: Atla / Kartı aç diye sorulsun.
  sor,

  eklendi,
  zatenListede,

  /// Depoya giriş listesinde kayıtlı cihaz: liste dışı.
  atlandiKayitli,

  /// Transfer / Araca Yükle / Montaj listesinde kayıtsız seri no: liste dışı.
  atlandiKayitsiz,

  /// Liste dolu (0/[OkutListesi.sinir]).
  dolu,
}

/// Koli karekodu ya da çoklu ekleme sonucu.
class KoliSonucu {
  int eklendi = 0;
  int zatenListede = 0;
  int disari = 0; // moda uymayan (kayıtlı / kayıtsız)
  int sigmadi = 0;

  int get toplam => eklendi + zatenListede + disari + sigmadi;

  String ozet({required bool girisListesi}) => [
        'Koli: $toplam seri no',
        '$eklendi eklendi',
        if (zatenListede > 0) '$zatenListede zaten listede',
        if (disari > 0)
          '$disari liste dışı (${girisListesi ? 'kayıtlı' : 'kayıtsız'})',
        if (sigmadi > 0) '$sigmadi sığmadı',
      ].join(' · ');
}

class OkutListesi {
  OkutListesi({this.sinir = 100});

  final int sinir;

  /// Seçili hızlı işlem; null = normal okutma.
  OkutIslemi? islem;

  /// Listedeki seri numaraları (kayıtlı cihazlarda cihazın kendi seri nosu).
  final List<String> seriler = [];

  /// İşlem yokken okutulan 1. kayıtsız seri no (2.si gelince liste başlar).
  String? ilkKayitsiz;

  /// Malzemeler (kablo, adaptör…): ürün id → miktar. 100 sınırına sayılmaz.
  final Map<String, int> malzemeler = {};

  /// Malzeme barkodu okutuldu ya da listeden eklendi: miktar eklenir
  /// (aynı barkod iki kez → 2 kutu). Yalnız hızlı işlem seçiliyken.
  bool malzemeEkle(String urunId, int miktar) {
    if (islem == null || miktar <= 0) return false;
    malzemeler[urunId] = (malzemeler[urunId] ?? 0) + miktar;
    return true;
  }

  void malzemeAyarla(String urunId, int miktar) {
    if (miktar <= 0) {
      malzemeler.remove(urunId);
    } else {
      malzemeler[urunId] = miktar;
    }
  }

  /// İşlem düğmesindeki sayı: cihazlar + malzeme kalemleri.
  int get kalemSayisi => seriler.length + malzemeler.length;

  /// Ekranda "sınır/kalan" olarak gösterilir (100/100, 100/99…; 1.29.2).
  int get kalan => sinir - seriler.length;
  bool get bos => seriler.isEmpty && malzemeler.isEmpty;
  bool get aktif => islem != null;
  bool get girisListesi => islem == OkutIslemi.giris;

  /// Hızlı işleme dokunuldu. Bekleyen 1. kayıtsız, Depoya girişte listeye
  /// alınır.
  void islemSec(OkutIslemi i) {
    if (islem != i) {
      seriler.clear();
      malzemeler.clear();
    }
    islem = i;
    final ilk = ilkKayitsiz;
    ilkKayitsiz = null;
    if (i == OkutIslemi.giris && ilk != null && !seriler.contains(ilk)) {
      seriler.add(ilk);
    }
  }

  /// Liste işlendi ya da Temizle / ✕: normal okutmaya dönülür.
  void temizle() {
    islem = null;
    seriler.clear();
    malzemeler.clear();
    ilkKayitsiz = null;
  }

  void cikar(String seri) => seriler.remove(seri);

  /// "Kartı aç" seçildi: bekleyen 1. kayıtsız unutulur, sayma baştan.
  void saymayiSifirla() => ilkKayitsiz = null;

  /// Bir okutma. [seri]: kayıtlıysa cihazın seri nosu, değilse okunan kod.
  OkutSonucu okut(String seri, {required bool kayitli}) {
    final i = islem;
    if (i == null) {
      if (kayitli) {
        return ilkKayitsiz == null ? OkutSonucu.kartAc : OkutSonucu.sor;
      }
      final ilk = ilkKayitsiz;
      if (ilk == null || ilk == seri) {
        ilkKayitsiz = seri;
        return OkutSonucu.ilkKayitsiz;
      }
      islem = OkutIslemi.giris;
      ilkKayitsiz = null;
      seriler
        ..clear()
        ..addAll([ilk, seri]);
      return OkutSonucu.topluBasladi;
    }
    final giris = i == OkutIslemi.giris;
    if (giris && kayitli) return OkutSonucu.atlandiKayitli;
    if (!giris && !kayitli) return OkutSonucu.atlandiKayitsiz;
    if (seriler.contains(seri)) return OkutSonucu.zatenListede;
    if (kalan <= 0) return OkutSonucu.dolu;
    seriler.add(seri);
    return OkutSonucu.eklendi;
  }

  /// Koli karekodu (işlem seçiliyken): hepsi tek seferde, pencere açılmadan.
  KoliSonucu koliOkut(List<(String seri, bool kayitli)> kodlar) {
    final s = KoliSonucu();
    for (final (seri, kayitli) in kodlar) {
      switch (okut(seri, kayitli: kayitli)) {
        case OkutSonucu.eklendi:
          s.eklendi++;
        case OkutSonucu.zatenListede:
          s.zatenListede++;
        case OkutSonucu.dolu:
          s.sigmadi++;
        default:
          s.disari++;
      }
    }
    return s;
  }

  Map<String, Object?> toJson() => {
        'islem': islem?.name,
        'seriler': List.of(seriler),
        'malzemeler': Map.of(malzemeler),
      };

  void fromJson(Map<String, Object?> j) {
    temizle();
    final ad = j['islem'];
    islem = OkutIslemi.values.where((e) => e.name == ad).firstOrNull;
    for (final s in (j['seriler'] as List? ?? const [])) {
      if (seriler.length >= sinir) break;
      if (!seriler.contains('$s')) seriler.add('$s');
    }
    for (final e in ((j['malzemeler'] as Map?) ?? const {}).entries) {
      final m = (e.value as num?)?.toInt() ?? 0;
      if (m > 0) malzemeler['${e.key}'] = m;
    }
    if (islem == null) {
      seriler.clear();
      malzemeler.clear();
    }
  }
}
