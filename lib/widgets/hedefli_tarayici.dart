import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cihaz_tercihleri.dart';
import '../services/etiket/etiket_kodu.dart';
import '../services/kurum_barkodu.dart';
import '../services/ses_servisi.dart';
import '../services/sn_metni.dart';
import '../services/tarayici.dart';
import 'kod_yardimci.dart';

/// Hedef çerçevenin şekli: ince-uzun (çizgi barkod) veya kare (karekod).
enum TaramaModu { barkod, karekod }

/// Kamera görüntüsünde yalnızca ortadaki hedef çerçevenin İÇİNDEKİ kodu
/// okur. Etikette seri no barkodunun yanında başka barkodlar ve karekodlar
/// olsa bile, sadece çerçeveye alınan kod dikkate alınır.
///
/// - Çerçeve yana kaydırınca "Barkod" (ince-uzun) ⇄ "Karekod" (kare) olur;
///   üstte hangi yöne geçileceği yazar, seçim telefonda hatırlanır. İki
///   modda da her kod okunur, fark yalnız çerçevenin şekli (1.29.2: düğme
///   kalktı).
/// - Görüntüye dokununca kamera çerçevenin ortasına yeniden netler; kod
///   okunmadığı sürece birkaç saniyede bir kendiliğinden de netler.
/// - İki parmakla yakınlaştırılabilir (telefonu çok yaklaştırınca kamera
///   netleyemez; uzaktan yakınlaştırmak daha iyi sonuç verir).
/// - Uygulama arka plana gidince kamera durur; dönünce, ekran hâlâ öndeyse
///   yeniden açılır.
/// - Yanlış okumayı önlemek için:
///   * kamera açılınca ilk 0,5 sn hiçbir şey okunmaz (telefon kaldırılırken
///     etraftaki kodlar okunmasın),
///   * çerçevede birden çok kod varsa ortaya en yakın olanı alınır,
///   * web adresi, Wi-Fi, MAC adresi, sipariş no, kutu üstündeki ürün
///     barkodu (EAN/UPC) gibi seri no olamayacak kodlar yok sayılır ve
///     çerçevenin üstünde kısa bir ipucuyla gösterilir,
///   * kurum etiketi, koli karekodu ve kayıtlı kod ilk okumada; bilinmeyen
///     kod 1,5 sn içinde ikinci kez okununca kabul edilir,
///   * "S/N:" öneki ve sondaki ek bilgi ("EU/3.0") atılıp seri no ayıklanır,
///   * tek parmakla yana kaydırınca Barkod ⇄ Karekod değişir.
/// - Pil (1.29.0): 15 sn hiçbir kod görülmezse okuma seyrekleşir (saniyede
///   ~3), kod görülünce normale döner; 30 sn olmazsa kamera (ve fener) durur,
///   dokununca yeniden açılır.
/// - Yazıdan okuma (1.29.0, Android, Ayarlar → "Yazıdan da oku"): 3 sn
///   barkod okunmazsa çerçevedeki "S/N" satırı yazıdan okunur; iki kez aynı
///   okununca, yarım saniye içinde barkod okunmazsa kabul edilir (barkod
///   önceliği). Kayıtlı cihazla eşleşmezse "Doğru mu?" sorulur.
/// - Düzen (1.29.2), yukarıdan aşağıya: sol üstte sayaç, ortada kaydırma
///   ipucu; pembe "Yazı da okunuyor" şeridi; çerçeve (küçülmez); altta
///   "15-25 cm uzakta tutun" (sığmazsa gizlenir); en altta 1x · 2x · 3x.
class HedefliTarayici extends StatefulWidget {
  const HedefliTarayici({
    super.key,
    required this.controller,
    required this.onDetect,
    this.mod,
    this.urunBarkodu = false,
    this.bilinenMi,
    this.sayac,
    this.yazidanOku = true,
  });

  /// false: bu ekranda yazıdan okuma yapılmaz (ör. etiket doğrulama).
  final bool yazidanOku;

  /// Kameranın sol üstünde gösterilecek sayaç (ör. "100/98").
  final Widget? sayac;

  final MobileScannerController controller;
  final void Function(BarcodeCapture capture) onDetect;

  /// Verilirse çerçeve bu modda açılır (ör. etiket doğrulamada önce karekod,
  /// sonra çizgi barkod). Kullanıcı yine de değiştirebilir.
  final TaramaModu? mod;

  /// true: kutu üstündeki ürün barkodları (EAN / UPC) da okunur (malzemenin
  /// fabrika barkodunu okuturken).
  final bool urunBarkodu;

  /// Verilirse: kod sistemde kayıtlı mı (seri no / malzeme barkodu)?
  /// Kayıtlıysa kısa, değilse uzun süre sabit durması beklenir. Kayıtlı
  /// malzeme barkodu (EAN / UPC) da bu sayede okunur.
  final Future<bool> Function(String kod)? bilinenMi;

  @override
  State<HedefliTarayici> createState() => _HedefliTarayiciState();
}

class _HedefliTarayiciState extends State<HedefliTarayici>
    with WidgetsBindingObserver {
  static const _anahtar = 'tarama_modu';
  TaramaModu _mod = TaramaModu.barkod;

  Timer? _netleme;
  DateTime _sonOkuma = DateTime.fromMillisecondsSinceEpoch(0);
  double _zoom = 0;
  double _zoomBaslangic = 0;
  bool _netleniyor = false;

  // Okuma onayı: kurum etiketi, koli karekodu ve kayıtlı kod ilk okumada,
  // bilinmeyen / şüpheli kod 1,5 sn içinde 2. kez okununca kabul edilir.
  // (Küçük, sık çizgili barkodlar her karede okunamaz; sayaç aradaki
  // kaçırılan karelerde sıfırlanmaz.)
  static const _acilisBeklemesi = Duration(milliseconds: 500);
  static const _adaySuresi = Duration(milliseconds: 1500);

  DateTime _hazir = DateTime.now().add(_acilisBeklemesi);
  String? _aday; // onay bekleyen kod
  Barcode? _adayKod;
  int _adaySayi = 0;
  int _adayGereken = 1;
  String? _okunan; // en son okunan (gönderilen) kod
  DateTime _okunmaZamani = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _kayip;
  final _bilinenler = <String, bool>{};

  // Yok sayılan kod ipucu ("Yok sayıldı: … (MAC adresi)")
  String? _ipucu;
  Timer? _ipucuZamanlayici;

  // Tek parmakla yatay kaydırma: Barkod ⇄ Karekod
  double _kaydirma = 0;

  // --- Pil tasarrufu: normal → bekleme (seyrek okuma) → durdu ---
  static const _normalHiz = 120; // ms (≈ saniyede 8)
  static const _bekleHiz = 333; // ms (≈ saniyede 3)
  static const _bekleSuresi = Duration(seconds: 15);
  static const _durdurSuresi = Duration(seconds: 30);
  DateTime _sonEtkinlik = DateTime.now();
  bool _beklemede = false;
  bool _durduruldu = false;
  Timer? _pil;

  // --- Yazıdan okuma (S/N satırı) ---
  static const _metinBekleme = Duration(milliseconds: 3000);
  // Barkod önceliği: yazıdan okunan, bu süre içinde barkod okunmazsa kabul.
  static const _barkodOnceligi = Duration(milliseconds: 500);
  DateTime _sonKabul = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<List<String>>? _metinAboneligi;
  String? _metinAday;
  DateTime _metinAdayZamani = DateTime.fromMillisecondsSinceEpoch(0);
  bool _metinSoruluyor = false;
  bool _metinBekliyor = false; // barkod önceliği için yarım saniye
  bool _metinIpucu = false;

  bool get _yaziAcik =>
      MetinOkuma.destekleniyor &&
      widget.yazidanOku &&
      !widget.urunBarkodu &&
      CihazTercihleri.yazidanOku.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_kameraDinle);
    SesServisi.onay.addListener(_onayGeldi);
    if (widget.mod != null) {
      _mod = widget.mod!;
    } else {
      _moduYukle();
    }
    if (!kIsWeb) {
      // Kod okunmadığı sürece ara ara ortaya netle (bazı telefonlarda
      // sürekli otomatik netleme yakın mesafede takılı kalıyor).
      _netleme = Timer.periodic(const Duration(seconds: 4), (_) {
        if (DateTime.now().difference(_sonOkuma) > const Duration(seconds: 4)) {
          _ortayaNetle(goster: false);
        }
      });
    }
    _pil = Timer.periodic(const Duration(seconds: 1), _pilDenetle);
    _metinAboneligi = MetinOkuma.satirlar.listen(_metinGeldi);
  }

  // ------------------------------------------------------- pil tasarrufu

  /// Kod okundu / ekrana dokunuldu: normal hıza dönülür, süre baştan.
  void _etkinlik() {
    _sonEtkinlik = DateTime.now();
    if (_beklemede) {
      _beklemede = false;
      unawaited(MetinOkuma.hizAyarla(_normalHiz));
    }
    if (_metinIpucu && mounted) setState(() => _metinIpucu = false);
  }

  void _pilDenetle(Timer _) {
    if (!mounted || _durduruldu || !widget.controller.value.isRunning) return;
    if (_metinSoruluyor) {
      _sonEtkinlik = DateTime.now();
      return;
    }
    final bos = DateTime.now().difference(_sonEtkinlik);
    if (bos >= _durdurSuresi) {
      unawaited(_kameraDurdur());
      return;
    }
    if (bos >= _bekleSuresi && !_beklemede) {
      _beklemede = true;
      unawaited(MetinOkuma.hizAyarla(_bekleHiz));
    }
    final ipucu = _yaziAcik && bos >= _metinBekleme;
    if (ipucu != _metinIpucu) setState(() => _metinIpucu = ipucu);
  }

  /// 30 sn kod yok: kamera durur (fener de söner), dokununca açılır.
  Future<void> _kameraDurdur() async {
    setState(() {
      _durduruldu = true;
      _metinIpucu = false;
    });
    try {
      await widget.controller.stop();
    } catch (_) {}
  }

  Future<void> _kameraBaslat() async {
    _etkinlik();
    setState(() => _durduruldu = false);
    try {
      await widget.controller.start();
    } catch (_) {}
  }

  // ------------------------------------------------ yazıdan okuma (S/N)

  void _metinGeldi(List<String> satirlar) {
    if (!mounted || _metinSoruluyor || _metinBekliyor || _durduruldu ||
        !_yaziAcik) {
      return;
    }
    // Yalnız ekranda görünen (en üstteki) kamera.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final sn = snAyikla(satirlar);
    if (sn == null) return;
    final simdi = DateTime.now();
    if (sn == _okunan &&
        simdi.difference(_okunmaZamani) < const Duration(seconds: 3)) {
      _okunmaZamani = simdi; // hâlâ çerçevede: tekrar okunmaz
      return;
    }
    // Yanlış okumaya karşı: aynı değer arka arkaya iki kez okunmalı.
    if (sn != _metinAday ||
        simdi.difference(_metinAdayZamani) > const Duration(seconds: 3)) {
      _metinAday = sn;
      _metinAdayZamani = simdi;
      return;
    }
    _metinAday = null;
    // Barkod önceliği: yarım saniye içinde barkod / karekod okunursa
    // yazıdan okunan atılır.
    final an = DateTime.now();
    _metinBekliyor = true;
    Future.delayed(_barkodOnceligi, () {
      _metinBekliyor = false;
      if (!mounted || _sonKabul.isAfter(an) || _durduruldu) return;
      _etkinlik();
      unawaited(_metinOnayla(sn));
    });
  }

  Future<void> _metinOnayla(String sn) async {
    _metinSoruluyor = true;
    try {
      var kayitli = false;
      final kontrol = widget.bilinenMi;
      if (kontrol != null) {
        try {
          kayitli = await kontrol(sn);
        } catch (_) {}
      }
      if (!mounted) return;
      if (!kayitli) {
        final evet = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.document_scanner_outlined),
            title: const Text('Yazıdan okundu'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  sn,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
                const SizedBox(height: 12),
                const Text('Seri numarası doğru mu? Etiketteki ile '
                    'karşılaştırın (0 / O, 1 / I, 8 / B karışabilir).'),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hayır')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Evet, doğru')),
            ],
          ),
        );
        // "Hayır" da olsa aynı yazı çerçevede kaldıkça yeniden sorulmaz.
        _okunan = sn;
        _okunmaZamani = DateTime.now();
        if (evet != true || !mounted) return;
      }
      _okunan = sn;
      _okunmaZamani = DateTime.now();
      widget.onDetect(BarcodeCapture(barcodes: [
        Barcode(rawValue: sn, format: BarcodeFormat.unknown),
      ]));
    } finally {
      _metinSoruluyor = false;
      _sonEtkinlik = DateTime.now();
    }
  }

  // Görsel onay: okutma sonucu çerçeve kısa süre yeşil / kırmızı yanar
  // (iPhone'da titreşim olmadığı için; sessizdeki telefonda da görünür).
  Color? _yanma;
  Timer? _yanmaZamanlayici;

  void _onayGeldi() {
    final o = SesServisi.onay.value;
    if (o == null || !mounted) return;
    // Yalnızca ekranda görünen (en üstteki) kamera yansın.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    setState(() =>
        _yanma = o.$1 ? const Color(0xFF2E7D32) : const Color(0xFFC62828));
    _yanmaZamanlayici?.cancel();
    _yanmaZamanlayici = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _yanma = null);
    });
  }

  @override
  void didUpdateWidget(HedefliTarayici eski) {
    super.didUpdateWidget(eski);
    if (widget.mod != null && widget.mod != eski.mod) {
      setState(() => _mod = widget.mod!);
    }
    if (widget.controller != eski.controller) {
      eski.controller.removeListener(_kameraDinle);
      widget.controller.addListener(_kameraDinle);
    }
  }

  @override
  void dispose() {
    _netleme?.cancel();
    _pil?.cancel();
    unawaited(_metinAboneligi?.cancel());
    if (MetinOkuma.destekleniyor) unawaited(MetinOkuma.ayarla(acik: false));
    _kayip?.cancel();
    _ipucuZamanlayici?.cancel();
    _yanmaZamanlayici?.cancel();
    SesServisi.onay.removeListener(_onayGeldi);
    widget.controller.removeListener(_kameraDinle);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = widget.controller;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(c.stop().catchError((_) {}));
    } else if (state == AppLifecycleState.resumed) {
      // Üstte başka bir sayfa açıksa kamera o sayfanındır; burası açılmaz.
      final onde = ModalRoute.of(context)?.isCurrent ?? true;
      if (onde && mounted) {
        _hazir = DateTime.now().add(_acilisBeklemesi);
        unawaited(c.start().catchError((_) {}));
      }
    }
  }

  Future<void> _moduYukle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kayitli = prefs.getString(_anahtar);
      if (kayitli == TaramaModu.karekod.name && mounted) {
        setState(() => _mod = TaramaModu.karekod);
      }
    } catch (_) {}
  }

  Future<void> _modDegistir() async {
    final yeni =
        _mod == TaramaModu.barkod ? TaramaModu.karekod : TaramaModu.barkod;
    setState(() => _mod = yeni);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_anahtar, yeni.name);
    } catch (_) {}
  }

  Future<void> _ortayaNetle({bool goster = true}) async {
    if (kIsWeb || !widget.controller.value.isRunning) return;
    if (goster && mounted) setState(() => _netleniyor = true);
    try {
      await widget.controller.setFocusPoint(const Offset(0.5, 0.5));
    } catch (_) {}
    if (goster) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _netleniyor = false);
    }
  }

  // Yakınlık seçici (1x · 2x · 3x): kamera 2x açılır. Android'de
  // yakınlaştırma 0-1 arası "doğrusal" değerle verilir; 2x / 3x'in karşılığı
  // telefonun en büyük yakınlığına göre biraz değişir (yaklaşık).
  static const _dogrusal = {1: 0.0, 2: 0.56, 3: 0.75};
  int _kademe = 2;

  /// Web: tarayıcı kamera yakınlaştırmasını destekliyorsa (min, max) oran.
  (double, double)? _webAralik;
  int _webDeneme = 0;

  bool get _seciciVar => !kIsWeb || _webAralik != null;

  Future<void> _kademeSec(int k) async {
    _etkinlik();
    setState(() => _kademe = k);
    await _kademeUygula();
  }

  Future<void> _kademeUygula() async {
    if (!mounted) return;
    if (kIsWeb) {
      final a = _webAralik;
      if (a != null) {
        await webZoomAyarla(_kademe.toDouble().clamp(a.$1, a.$2));
      }
      return;
    }
    await _zoomAyarla(_dogrusal[_kademe]!, zorla: true);
  }

  /// Kamera açılınca (ve arka plandan dönünce) seçili yakınlık uygulanır.
  void _acilistaYakinlik() {
    Future.delayed(const Duration(milliseconds: 450), () async {
      if (!mounted || !widget.controller.value.isRunning) return;
      if (kIsWeb) {
        // Video hazır olunca tarayıcıya sorulur (birkaç deneme).
        final a = webZoomAraligi();
        if (a == null) {
          if (++_webDeneme < 6) _acilistaYakinlik();
          return;
        }
        setState(() => _webAralik = a);
      }
      await _kademeUygula();
    });
  }

  Future<void> _zoomAyarla(double z, {bool zorla = false}) async {
    if (kIsWeb) return;
    final yeni = z.clamp(0.0, 1.0);
    if (!zorla && (yeni - _zoom).abs() < 0.01) return;
    _zoom = yeni;
    if (mounted) setState(() {});
    try {
      await widget.controller.setZoomScale(yeni);
    } catch (_) {}
  }

  // Düzen payları (1.29.2): üstte sayaç + kaydırma ipucu satırı ve pembe
  // şerit; altta "15-25 cm uzakta tutun" ve 1x · 2x · 3x seçici.
  static const _satir = 30.0; // üst satır (sayaç / ipucu)
  static const _serit = 28.0; // pembe şerit
  static const _altYazi = 20.0;
  // 1.29.3: seçici inceldi (daire 28, alt boşluk 4): karekod modunda da alt
  // yazı sığsın.
  double _seciciPay(bool kucuk) => _seciciVar ? (kucuk ? 34.0 : 38.0) : 6.0;

  /// Görüntü alanına göre hedef çerçeve ve alt yazının sığıp sığmadığı.
  /// Çerçevenin boyutu değişmez (karekod çerçevesi küçültülmez); sığdığı
  /// sürece üst yazılarla alttaki seçici arasında ortalanır.
  (Rect, bool) _pencere(Size alan) {
    final Size boyut;
    if (_mod == TaramaModu.barkod) {
      // İnce şerit: yalnızca seri no barkodu sığsın, yandakiler girmesin.
      final g = math.min(alan.width * 0.70, 440.0);
      final y = math.min(math.max(alan.height * 0.18, 56.0), 104.0);
      boyut = Size(g, y);
    } else {
      // Karekod (koli karekodu dahil) için kare.
      final k = math.min(
          math.min(alan.width * 0.62, alan.height * 0.72), 320.0);
      boyut = Size(k, k);
    }
    final kucuk = alan.height < 260;
    final ust = _satir + (_yaziAcik ? _serit : 0);
    final alt = _seciciPay(kucuk);
    Rect ortala(double ustSinir, double altSinir) => Rect.fromCenter(
        center: Offset(alan.width / 2, (ustSinir + altSinir) / 2),
        width: boyut.width,
        height: boyut.height);
    if (boyut.height + ust + alt + _altYazi <= alan.height) {
      return (ortala(ust, alan.height - alt - _altYazi), true);
    }
    if (boyut.height + ust + alt <= alan.height) {
      return (ortala(ust, alan.height - alt), false);
    }
    // Çok küçük alan: eskisi gibi tam ortada.
    return (ortala(0, alan.height), false);
  }

  /// Kodun ekrandaki merkezi (önizleme "cover" ile sığdırılır); hesaplanamazsa
  /// null.
  Offset? _merkez(Barcode b, Size goruntu, Size alan) {
    if (b.corners.isEmpty || goruntu.width <= 0 || goruntu.height <= 0) {
      return null;
    }
    final olcek = math.max(
        alan.width / goruntu.width, alan.height / goruntu.height);
    final dx = (alan.width - goruntu.width * olcek) / 2;
    final dy = (alan.height - goruntu.height * olcek) / 2;
    var sx = 0.0, sy = 0.0;
    for (final c in b.corners) {
      sx += c.dx;
      sy += c.dy;
    }
    return Offset(sx / b.corners.length * olcek + dx,
        sy / b.corners.length * olcek + dy);
  }

  /// 1.30.2: 266'lı kurum kodu tanımlı değilse bunu açıkça söyler.
  String _urunBarkoduSebebi(String v) => kurumBarkoduMu(v)
      ? 'kurum kodu, hiçbir malzemeye tanımlı değil'
      : 'ürün barkodu';

  /// Kurum etiketi ya da koli karekodu: yerelde tanınır, kısa beklenir.
  bool _taninan(String v) =>
      EtiketKodu.coz(v) != null || seriNolariAyir(v).length > 1;

  void _ipucuGoster(String metin) {
    if (_ipucu != metin && mounted) setState(() => _ipucu = metin);
    _ipucuZamanlayici?.cancel();
    _ipucuZamanlayici = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _ipucu = null);
    });
  }

  static String _kisalt(String v) =>
      v.length > 24 ? '${v.substring(0, 22)}…' : v;

  /// Ayıklanmış (S/N: öneki, sondaki ek bilgi atılmış) barkod.
  Barcode _ayikla(Barcode b) {
    final ham = b.rawValue?.trim() ?? '';
    final v = seriAyikla(ham);
    if (v == ham) return b;
    return Barcode(rawValue: v, format: b.format, corners: b.corners);
  }

  void _algilandi(BarcodeCapture capture, Size alan, Rect pencere) {
    final simdi = DateTime.now();
    _sonOkuma = simdi;
    _etkinlik();
    if (_metinSoruluyor) return;
    if (simdi.isBefore(_hazir)) return;

    final goruntu = capture.size != Size.zero
        ? capture.size
        : widget.controller.value.size;

    // 1) Seri no olamayacak kodları ayıkla; webde çerçeve dışını at.
    final adaylar = <(Barcode, Offset?)>[];
    String? yokSayilan;
    for (final ham in capture.barcodes) {
      final b = _ayikla(ham);
      final v = b.rawValue?.trim() ?? '';
      if (v.isEmpty) continue;
      final m = _merkez(b, goruntu, alan);
      if (kIsWeb && m != null && !pencere.inflate(8).contains(m)) continue;
      // Kurum etiketi ve koli karekodu her zaman okunur.
      if (!_taninan(v)) {
        final sebep = gereksizSebep(v);
        if (sebep != null) {
          yokSayilan ??= '${_kisalt(v)} ($sebep)';
          continue;
        }
        if (_kayitliOlmali(b, v)) {
          if (widget.bilinenMi == null && urunBarkoduTuru(b)) {
            yokSayilan ??= '${_kisalt(v)} (${_urunBarkoduSebebi(v)})';
            continue;
          }
          if (_bilinenler[v] == false) {
            yokSayilan ??= urunBarkoduTuru(b)
                ? '${_kisalt(v)} (${_urunBarkoduSebebi(v)})'
                : '${_kisalt(v)} (kayıtlı değil: malzeme / lot / model kodu)';
            continue;
          }
        }
      }
      adaylar.add((b, m));
    }
    if (adaylar.isEmpty) {
      if (yokSayilan != null) _ipucuGoster('Yok sayıldı: $yokSayilan');
      return;
    }

    // 2) Birden çok kod varsa ortaya en yakını
    Barcode secilen;
    if (adaylar.length == 1) {
      secilen = adaylar.first.$1;
    } else if (adaylar.every((a) => a.$2 != null)) {
      adaylar.sort((a, b) => (a.$2! - pencere.center)
          .distance
          .compareTo((b.$2! - pencere.center).distance));
      secilen = adaylar.first.$1;
    } else {
      // Konum hesaplanamıyor: eskisi gibi ekran "birden çok kod" uyarır.
      _sonKabul = DateTime.now();
      widget.onDetect(BarcodeCapture(
        barcodes: [for (final a in adaylar) a.$1],
        image: capture.image,
        size: capture.size,
      ));
      return;
    }
    final deger = secilen.rawValue!.trim();

    // 3) Onay: aynı kod gerektiği kadar okununca gönderilir.
    if (deger == _okunan &&
        simdi.difference(_okunmaZamani) < const Duration(seconds: 3)) {
      _okunmaZamani = simdi; // hâlâ çerçevede: tekrar okunmaz
      return;
    }
    _kayip?.cancel();
    _kayip = Timer(_adaySuresi, () {
      if (mounted) setState(() => _aday = null);
    });
    if (deger != _aday) {
      _aday = deger;
      _adaySayi = 1;
      _adayGereken = _gerekenBelirle(deger, secilen);
    } else {
      _adaySayi++;
    }
    _adayKod = secilen;
    _dene();
  }

  /// Aday kod onaylandıysa gönderir; değilse göstergeyi günceller.
  void _dene() {
    final deger = _aday;
    final kod = _adayKod;
    if (deger == null || kod == null || !mounted) return;
    final bekle = _adaySayi < _adayGereken ||
        // Kayıtlı olması gereken kodun cevabı henüz gelmedi
        (!_taninan(deger) &&
            _kayitliOlmali(kod, deger) &&
            _bilinenler[deger] != true);
    if (bekle) {
      setState(() {});
      return;
    }
    _okunan = deger;
    _okunmaZamani = DateTime.now();
    _sonKabul = _okunmaZamani;
    _kayip?.cancel();
    setState(() => _aday = null);
    widget.onDetect(BarcodeCapture(barcodes: [kod]));
  }

  /// Kamera (yeniden) açılınca: ilk 0,5 sn okuma yok, aynı kod yeniden
  /// okunabilir.
  bool _calisiyordu = false;
  void _kameraDinle() {
    final calisiyor = widget.controller.value.isRunning;
    if (calisiyor && !_calisiyordu) {
      _hazir = DateTime.now().add(_acilisBeklemesi);
      _okunan = null;
      _aday = null;
      _webDeneme = 0;
      _acilistaYakinlik();
      // Pil: normal hızla başlar; yazıdan okuma bu ekrana göre açılır.
      _beklemede = false;
      _sonEtkinlik = DateTime.now();
      _metinAday = null;
      if ((_durduruldu || _metinIpucu) && mounted) {
        setState(() {
          _durduruldu = false;
          _metinIpucu = false;
        });
      }
      unawaited(MetinOkuma.ayarla(acik: _yaziAcik, bekleme: _metinBekleme));
    }
    _calisiyordu = calisiyor;
  }

  /// Bu kod ancak sistemde kayıtlıysa mı okunur? Ürün barkodu (EAN/UPC) ve
  /// şüpheli kodlar (yalnız rakam, tireli model / parça no) için: Okut gibi
  /// kayıt kontrolü yapılan ekranlarda evet.
  bool _kayitliOlmali(Barcode b, String v) {
    if (widget.urunBarkodu) return false;
    if (urunBarkoduTuru(b)) return true;
    return widget.bilinenMi != null && supheliKod(v);
  }

  /// Kaç okumada kabul edilir: tanınan / kayıtlı kod 1, bilinmeyen 2.
  int _gerekenBelirle(String deger, Barcode b) {
    if (_taninan(deger) || widget.urunBarkodu) return 1;
    final kontrol = widget.bilinenMi;
    if (kontrol == null) return supheliKod(deger) ? 2 : 1;
    final bilinen = _bilinenler[deger];
    if (bilinen != null) return bilinen ? 1 : 2;
    // Sistemde kayıtlı mı? Cevap gelince (aday hâlâ buysa) yeniden denenir.
    kontrol(deger).then((v) {
      _bilinenler[deger] = v;
      if (!mounted || _aday != deger) return;
      if (!v && _kayitliOlmali(_adayKod ?? b, deger)) {
        setState(() => _aday = null);
        _ipucuGoster('Yok sayıldı: ${_kisalt(deger)} '
            '(${kurumBarkoduMu(deger) ? _urunBarkoduSebebi(deger) : 'kayıtlı değil: malzeme / lot / model kodu'})');
        return;
      }
      _adayGereken = v ? 1 : 2;
      _dene();
    }).catchError((_) {
      _bilinenler[deger] = false;
    });
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final alan = Size(c.maxWidth, c.maxHeight);
      final (pencere, altYaziSigar) = _pencere(alan);
      final kucuk = alan.height < 260;
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (_) {
              _etkinlik();
              _ortayaNetle();
            },
            onScaleStart: (_) {
              _etkinlik();
              _zoomBaslangic = _zoom;
              _kaydirma = 0;
            },
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) {
                // Tek parmak: yatay kaydırma miktarı (Barkod ⇄ Karekod)
                _kaydirma += d.focalPointDelta.dx;
                return;
              }
              _kaydirma = 0;
              _zoomAyarla(_zoomBaslangic + (d.scale - 1) * 0.35);
            },
            onScaleEnd: (d) {
              final hiz = d.velocity.pixelsPerSecond.dx.abs();
              if (_kaydirma.abs() > 60 || (hiz > 600 && _kaydirma.abs() > 20)) {
                _modDegistir();
              }
              _kaydirma = 0;
            },
            child: MobileScanner(
              controller: widget.controller,
              scanWindow: pencere,
              // Yaşam döngüsünü bu widget yönetir (üstte başka sayfa
              // açıkken kamerayı yeniden açmamak için).
              useAppLifecycleState: false,
              onDetect: (capture) => _algilandi(capture, alan, pencere),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _CerceveBoyaci(pencere, _netleniyor || _aday != null),
            ),
          ),
          // Okunuyor göstergesi (bilinmeyen kod 2. okumayı bekliyor)
          if (_aday != null)
            Positioned(
              left: pencere.left + 12,
              width: pencere.width - 24,
              top: pencere.bottom - 10,
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _adaySayi / math.max(_adayGereken, 1),
                    minHeight: 5,
                    color: const Color(0xFF4CAF50),
                    backgroundColor: const Color(0x66FFFFFF),
                  ),
                ),
              ),
            ),
          if (_yanma != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _yanma!.withOpacity(0.18),
                    border: Border.all(color: _yanma!, width: 10),
                  ),
                ),
              ),
            ),
          // Üst satır: sol üstte sayaç, ortada kaydırma ipucu (düğme yok).
          Positioned(
            top: kucuk ? 3 : 5,
            left: 8,
            right: 8,
            child: IgnorePointer(
              child: SizedBox(
                height: _satir - 6,
                child: Stack(
                  children: [
                    if (widget.sayac != null)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: widget.sayac),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: widget.sayac != null ? 80 : 0),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.swap_horiz,
                                  color: Colors.white, size: 16,
                                  shadows: [Shadow(blurRadius: 4)]),
                              const SizedBox(width: 4),
                              Text(
                                _mod == TaramaModu.barkod
                                    ? 'Karekod için yana kaydırın'
                                    : 'Barkod için yana kaydırın',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    shadows: [Shadow(blurRadius: 4)]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Çerçevenin hemen üstü: "Yok sayıldı" ipucu ya da pembe şerit.
          if (_ipucu != null)
            Positioned(
              left: 12,
              right: 12,
              top: math.max(pencere.top - 26, _satir - 2),
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _ipucu!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFBDBDBD), fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          if (_metinIpucu && _ipucu == null && !_durduruldu)
            Positioned(
              left: 12,
              right: 12,
              top: math.max(pencere.top - 26, _satir - 2),
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xCCC2185B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.document_scanner_outlined,
                            color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Yazı da okunuyor · S/N satırını çerçeveye alın',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Çerçevenin altı: tek satır (sığmazsa gösterilmez).
          if (altYaziSigar)
            Positioned(
              left: 16,
              right: 16,
              top: pencere.bottom + 2,
              child: const IgnorePointer(
                child: Text(
                  '15-25 cm uzakta tutun',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      shadows: [Shadow(blurRadius: 4)]),
                ),
              ),
            ),
          // Yakınlık seçici: görüntünün altında ortada (1x · 2x · 3x)
          if (_seciciVar)
            Positioned(
              left: 0,
              right: 0,
              bottom: kucuk ? 3 : 4,
              child: Center(
                child: _YakinlikSecici(
                  secili: kIsWeb
                      ? _kademe
                      : _dogrusal.entries
                          .where((e) => (e.value - _zoom).abs() < 0.03)
                          .map((e) => e.key)
                          .firstOrNull,
                  kucuk: kucuk,
                  onSec: _kademeSec,
                ),
              ),
            ),
          // Pil: 30 sn kod okunmadı, kamera durdu.
          if (_durduruldu)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _kameraBaslat,
                child: ColoredBox(
                  color: const Color(0xF0101418),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.no_photography_outlined,
                            color: Colors.white70, size: kucuk ? 32 : 48),
                        SizedBox(height: kucuk ? 6 : 12),
                        Text(
                          'Kamera durdu',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: kucuk ? 15 : 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Başlatmak için dokunun',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// 1x · 2x · 3x yakınlık seçici (telefonun kendi kamerasındaki gibi).
class _YakinlikSecici extends StatelessWidget {
  const _YakinlikSecici({
    required this.secili,
    required this.kucuk,
    required this.onSec,
  });

  final int? secili;
  final bool kucuk;
  final ValueChanged<int> onSec;

  @override
  Widget build(BuildContext context) {
    // 1.29.2: 44 → 34; 1.29.3: 34 → 28.
    final boyut = kucuk ? 26.0 : 28.0;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(boyut),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final k in const [1, 2, 3])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: secili == k ? Colors.white : Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onSec(k),
                  child: SizedBox(
                    width: boyut,
                    height: boyut,
                    child: Center(
                      child: Text(
                        '${k}x',
                        style: TextStyle(
                          color: secili == k ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: kucuk ? 11 : 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Çerçevenin dışını karartır, hedefi yeşil kenarla gösterir.
class _CerceveBoyaci extends CustomPainter {
  _CerceveBoyaci(this.pencere, this.netleniyor);

  final Rect pencere;
  final bool netleniyor;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(pencere, const Radius.circular(12));
    final karartma = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rr);
    canvas.drawPath(karartma, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = netleniyor ? const Color(0xFFFFC107) : const Color(0xFF4CAF50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = netleniyor ? 4 : 3,
    );
    // Ortadan geçen ince kırmızı nişan çizgisi
    canvas.drawLine(
      Offset(pencere.left + 10, pencere.center.dy),
      Offset(pencere.right - 10, pencere.center.dy),
      Paint()
        ..color = const Color(0xAAFF5252)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CerceveBoyaci eski) =>
      eski.pencere != pencere || eski.netleniyor != netleniyor;
}
