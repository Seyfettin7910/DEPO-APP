import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/models.dart';
import '../../providers/app_providers.dart';
import '../../services/ses_servisi.dart';
import '../../services/taslak_servisi.dart';
import '../../widgets/barkod_okuyucu_sayfasi.dart';
import '../../widgets/depo_secici.dart';
import '../../widgets/kod_yardimci.dart';

/// Seri numarası olmayan, miktarla takip edilen malzemeler (kablo, adaptör…)
/// için giriş, Araca Yükle, transfer, iade ve Montaj / Kullanıldı.
///
/// Malzeme listeden seçilir ya da fabrika barkodu okutulur; miktar +/- ile
/// ya da sayıya dokunup yazarak girilir.
class MalzemeIslemScreen extends ConsumerStatefulWidget {
  const MalzemeIslemScreen({
    super.key,
    required this.islem,
    this.onceKaynakId,
    this.onceHedefId,
    this.onceUrunId,
    this.taslaktan = false,
  });

  final MalzemeIslemi islem;
  final String? onceKaynakId;
  final String? onceHedefId;
  final String? onceUrunId;
  final bool taslaktan;

  @override
  ConsumerState<MalzemeIslemScreen> createState() => _MalzemeIslemScreenState();
}

class _MalzemeIslemScreenState extends ConsumerState<MalzemeIslemScreen>
    with YarimIsKorumasi<MalzemeIslemScreen> {
  final _notCtrl = TextEditingController();
  final _yerCtrl = TextEditingController();
  final _barkodCtrl = TextEditingController();

  /// urunId -> miktar (ekleme sırası korunur).
  final _satirlar = <String, int>{};
  String? _kaynakId;
  String? _hedefId;
  bool _kaydediliyor = false;

  MalzemeIslemi get _islem => widget.islem;

  @override
  void initState() {
    super.initState();
    _kaynakId = widget.onceKaynakId;
    _hedefId = widget.onceHedefId;
    if (widget.onceUrunId != null) _satirlar[widget.onceUrunId!] = 0;
    taslakKorumasiniBaslat(dinlenecekler: [_notCtrl, _yerCtrl]);
  }

  @override
  void dispose() {
    taslakKorumasiniBitir(dinlenecekler: [_notCtrl, _yerCtrl]);
    _notCtrl.dispose();
    _yerCtrl.dispose();
    _barkodCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Yarım iş (taslak)
  // ---------------------------------------------------------------

  @override
  String get taslakTuru => 'malzeme_${_islem.name}';

  @override
  bool get taslaktanAcildi => widget.taslaktan;

  @override
  Taslak? taslakOlustur() {
    final dolu = _satirlar.values.where((m) => m > 0).length;
    if (dolu == 0) return null;
    return Taslak(
      tur: taslakTuru,
      baslik: _islem.baslik,
      ozet: '$dolu kalem malzeme',
      veri: {
        'kaynak': _kaynakId,
        'hedef': _hedefId,
        'satirlar': Map.of(_satirlar),
        'yer': _yerCtrl.text,
        'not': _notCtrl.text,
      },
    );
  }

  @override
  Future<void> taslagiYukle(Taslak t) async {
    final v = t.veri;
    setState(() {
      _kaynakId = v['kaynak'] as String? ?? _kaynakId;
      _hedefId = v['hedef'] as String? ?? _hedefId;
      _satirlar.clear();
      final m = (v['satirlar'] as Map?) ?? const {};
      for (final e in m.entries) {
        final n = (e.value as num?)?.toInt() ?? 0;
        if (n > 0) _satirlar['${e.key}'] = n;
      }
    });
    _yerCtrl.text = v['yer'] as String? ?? '';
    _notCtrl.text = v['not'] as String? ?? '';
  }

  // ---------------------------------------------------------------

  void _mesaj(String metin, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(metin),
        backgroundColor: hata ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 3),
      ));
  }

  /// Kaynaktaki miktar (girişte sınır yok).
  int? _mevcut(Map<String, Map<String, int>> stok, String urunId) =>
      _islem.kaynakli
          ? (_kaynakId == null ? 0 : (stok[urunId]?[_kaynakId] ?? 0))
          : null;

  void _ekle(Urun u, {int adet = 1}) {
    final stok = ref.read(malzemeStoklariProvider).value ?? const {};
    final mevcut = _mevcut(stok, u.id);
    final yeni = (_satirlar[u.id] ?? 0) + adet;
    if (mevcut != null && yeni > mevcut) {
      SesServisi.hata();
      _mesaj('${u.ad}: burada ${u.miktarMetni(mevcut)} var', hata: true);
      if (!_satirlar.containsKey(u.id)) setState(() => _satirlar[u.id] = 0);
      return;
    }
    SesServisi.basari();
    setState(() => _satirlar[u.id] = yeni);
  }

  Future<void> _malzemeSec(List<Urun> malzemeler,
      Map<String, Map<String, int>> stok) async {
    if (_islem.kaynakli && _kaynakId == null) {
      _mesaj('Önce nereden alınacağını seçin', hata: true);
      return;
    }
    final secenekler = [
      for (final u in malzemeler)
        if (!_islem.kaynakli || (_mevcut(stok, u.id) ?? 0) > 0) u
    ];
    if (secenekler.isEmpty) {
      _mesaj(
          malzemeler.isEmpty
              ? 'Tanımlı malzeme yok. Ürünler sekmesinde takip türü '
                  '"Miktar" olan ürün ekleyin.'
              : 'Burada malzeme yok',
          hata: true);
      return;
    }
    final secilen = await showDialog<Urun>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Malzeme seç'),
        children: [
          for (final u in secenekler)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, u),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cable_outlined),
                title: Text(u.ad),
                subtitle: Text([
                  if (u.kategori != null) u.kategori!,
                  if (_islem.kaynakli)
                    'Burada: ${u.miktarMetni(_mevcut(stok, u.id) ?? 0)}'
                  else
                    'Birim: ${u.birim}',
                ].join(' · ')),
              ),
            ),
        ],
      ),
    );
    if (secilen == null || !mounted) return;
    if (_satirlar.containsKey(secilen.id)) {
      _ekle(secilen);
    } else {
      setState(() => _satirlar[secilen.id] = 0);
      _ekle(secilen);
    }
  }

  /// Fabrika barkodu: tanımlı malzemeyse 1 eklenir; tanımlı değilse hangi
  /// malzemeye ait olduğu sorulur ve kaydedilir.
  Future<void> _barkodIsle(String ham, List<Urun> malzemeler) async {
    final kod = ham.trim();
    if (kod.isEmpty) return;
    _barkodCtrl.clear();
    final db = ref.read(appDatabaseProvider);
    final urun = await db.barkodIleUrunBul(kod);
    if (!mounted) return;
    if (urun != null && !urun.deleted) {
      if (!urun.miktarli) {
        SesServisi.hata();
        _mesaj('${urun.ad} seri numarasıyla takip ediliyor; bu ekranda '
            'kullanılamaz', hata: true);
        return;
      }
      _ekle(urun);
      return;
    }
    if (malzemeler.isEmpty) {
      SesServisi.hata();
      _mesaj('Barkod tanımsız ve hiç malzeme yok', hata: true);
      return;
    }
    SesServisi.hata();
    final secilen = await showDialog<Urun>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Barkod tanımsız: $kod'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Bu barkod hangi malzemenin? Seçerseniz kaydedilir; '
                'bir dahaki okutmada doğrudan eklenir.'),
          ),
          for (final u in malzemeler)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, u),
              child: Text(u.barkod == null
                  ? u.ad
                  : '${u.ad} (şu anki barkod: ${u.barkod})'),
            ),
        ],
      ),
    );
    if (secilen == null || !mounted) return;
    await db.urunGuncelle(
      id: secilen.id,
      ad: secilen.ad,
      barkod: kod,
      birim: secilen.birim,
      kategori: secilen.kategori,
      minStokSeviyesi: secilen.minStokSeviyesi,
    );
    if (!mounted) return;
    _mesaj('Barkod ${secilen.ad} için kaydedildi');
    _ekle(secilen);
  }

  Future<void> _kameraIleOkut(List<Urun> malzemeler) async {
    final kod = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BarkodOkuyucuSayfasi()));
    if (kod != null && mounted) await _barkodIsle(kod, malzemeler);
  }

  Future<void> _miktarYaz(Urun u, int? mevcut) async {
    final ctrl = TextEditingController(text: '${_satirlar[u.id] ?? 0}');
    final yeni = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(u.ad),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Miktar (${u.birim})',
            helperText:
                mevcut == null ? null : 'Burada: ${u.miktarMetni(mevcut)}',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: const Text('Tamam')),
        ],
      ),
    );
    ctrl.dispose();
    if (yeni == null || yeni < 0) return;
    if (mevcut != null && yeni > mevcut) {
      _mesaj('${u.ad}: burada ${u.miktarMetni(mevcut)} var', hata: true);
      return;
    }
    setState(() => _satirlar[u.id] = yeni);
  }

  Future<void> _kaydet() async {
    final miktarlar = {
      for (final e in _satirlar.entries)
        if (e.value > 0) e.key: e.value
    };
    if (miktarlar.isEmpty) {
      _mesaj('Miktar girin', hata: true);
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      await ref.read(appDatabaseProvider).malzemeHareketiKaydet(
            islem: _islem,
            kaynakDepoId: _islem.kaynakli ? _kaynakId : null,
            hedefDepoId: _islem.hedefli ? _hedefId : null,
            miktarlar: miktarlar,
            kullaniciId:
                ref.read(aktifKullaniciIdProvider) ?? 'demo-kullanici',
            not_: _notCtrl.text,
            kullanimYeri: _yerCtrl.text,
          );
      SesServisi.basari();
      await taslakTamamlandi();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_islem.baslik}: ${miktarlar.length} kalem '
              'kaydedildi')));
      Navigator.pop(context);
    } catch (e) {
      SesServisi.hata();
      _mesaj(e is StateError ? e.message : 'Kaydedilemedi: $e', hata: true);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  // ---------------------------------------------------------------

  List<Depo> _kaynaklar(List<Depo> tumu) => switch (_islem) {
        MalzemeIslemi.iade => [
            ...tumu.where((d) => d.arac),
            ...tumu.where((d) => !d.arac),
          ],
        MalzemeIslemi.kullanim => [
            ...tumu.where((d) => d.arac),
            ...tumu.where((d) => !d.arac),
          ],
        _ => tumu,
      };

  List<Depo> _hedefler(List<Depo> tumu) {
    final l = tumu.where((d) => d.id != _kaynakId).toList();
    return switch (_islem) {
      MalzemeIslemi.yukle => [
          ...l.where((d) => d.arac),
          ...l.where((d) => !d.arac),
        ],
      MalzemeIslemi.iade => l.where((d) => !d.arac).toList(),
      _ => l,
    };
  }

  @override
  Widget build(BuildContext context) {
    final depolar = ref.watch(depolarStreamProvider).value ?? <Depo>[];
    final urunler = ref.watch(urunlerStreamProvider).value ?? <Urun>[];
    final stok = ref.watch(malzemeStoklariProvider).value ??
        const <String, Map<String, int>>{};
    final malzemeler = urunler.where((u) => u.miktarli).toList();
    final urunMap = {for (final u in urunler) u.id: u};
    final kaynaklar = _kaynaklar(depolar);
    final hedefler = _hedefler(depolar);

    return yarimIsKapsayici(
      child: Scaffold(
        appBar: AppBar(title: Text(_islem.baslik)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  if (_islem.kaynakli)
                    DropdownButtonFormField<String>(
                      value: kaynaklar.any((d) => d.id == _kaynakId)
                          ? _kaynakId
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: _islem == MalzemeIslemi.kullanim
                              ? 'Hangi araçtan / depodan düşülecek?'
                              : 'Nereden?'),
                      items: depoDropdownOgeleri(kaynaklar),
                      onChanged: (v) => setState(() {
                        _kaynakId = v;
                        if (_hedefId == v) _hedefId = null;
                      }),
                    ),
                  if (_islem.hedefli)
                    DropdownButtonFormField<String>(
                      value: hedefler.any((d) => d.id == _hedefId)
                          ? _hedefId
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: switch (_islem) {
                        MalzemeIslemi.giris => 'Hangi depo / araca girilecek?',
                        MalzemeIslemi.yukle => 'Hangi araca yüklenecek?',
                        MalzemeIslemi.iade => 'Hangi depoya iade edilecek?',
                        _ => 'Nereye?',
                      }),
                      items: depoDropdownOgeleri(hedefler),
                      onChanged: (v) => setState(() => _hedefId = v),
                    ),
                  if (_islem == MalzemeIslemi.kullanim)
                    TextField(
                      controller: _yerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nerede kullanıldı?',
                        hintText: 'Örn: Zabıta Müdürlüğü, Park Cad. 12',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: bilgisayarTarayicisi
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _barkodCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Fabrika barkodu (okuyucuyla okutun)',
                              prefixIcon: Icon(Icons.qr_code_scanner),
                            ),
                            onSubmitted: (v) => _barkodIsle(v, malzemeler),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => _malzemeSec(malzemeler, stok),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Malzeme seç'),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _kameraIleOkut(malzemeler),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Barkod okut'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _malzemeSec(malzemeler, stok),
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Malzeme seç'),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _satirlar.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          malzemeler.isEmpty
                              ? 'Henüz miktarla takip edilen malzeme yok.\n\n'
                                  'Ürünler sekmesinde yeni ürün eklerken takip '
                                  'türünü "Miktar" seçin (kablo, adaptör…).'
                              : 'Malzemenin fabrika barkodunu okutun ya da '
                                  '"Malzeme seç" ile listeden seçin. Miktarı '
                                  '+/- ile ya da sayıya dokunup yazarak girin.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final e in _satirlar.entries)
                          if (urunMap[e.key] != null)
                            _MalzemeSatiri(
                              urun: urunMap[e.key]!,
                              miktar: e.value,
                              mevcut: _mevcut(stok, e.key),
                              azalt: e.value > 0
                                  ? () => setState(
                                      () => _satirlar[e.key] = e.value - 1)
                                  : null,
                              artir: () => _ekle(urunMap[e.key]!),
                              yaz: () => _miktarYaz(
                                  urunMap[e.key]!, _mevcut(stok, e.key)),
                              sil: () =>
                                  setState(() => _satirlar.remove(e.key)),
                            ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _notCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Not (opsiyonel)'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _kaydediliyor ? null : _kaydet,
                        icon: const Icon(Icons.save),
                        label: Text(_kaydediliyor
                            ? 'Kaydediliyor...'
                            : 'Kaydet (${_satirlar.values.where((m) => m > 0).length} kalem)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MalzemeSatiri extends StatelessWidget {
  const _MalzemeSatiri({
    required this.urun,
    required this.miktar,
    required this.mevcut,
    required this.azalt,
    required this.artir,
    required this.yaz,
    required this.sil,
  });

  final Urun urun;
  final int miktar;
  final int? mevcut;
  final VoidCallback? azalt;
  final VoidCallback artir;
  final VoidCallback yaz;
  final VoidCallback sil;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(urun.ad),
      subtitle: Text(mevcut == null
          ? urun.birim
          : 'Burada: ${urun.miktarMetni(mevcut!)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: azalt,
          ),
          InkWell(
            onTap: yaz,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              alignment: Alignment.center,
              child: Text('$miktar',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: artir,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Kaldır',
            onPressed: sil,
          ),
        ],
      ),
    );
  }
}
