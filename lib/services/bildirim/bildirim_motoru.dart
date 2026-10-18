import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../database/app_database.dart';
import '../giris_kaydi_servisi.dart';
import 'bildirim_ayarlari.dart';
import 'bildirim_gosterici.dart';

class _Atla implements Exception {
  const _Atla();
}

class _Yeni {
  _Yeni(this.tur, this.baslik, this.govde);
  final BildirimTuru tur;
  final String baslik;
  final String govde;
}

/// Bildirim olaylarını yerel veritabanından (senkron sonrası) hesaplar.
/// Hem uygulama açıkken (her senkrondan sonra) hem de arka plan görevinde
/// çalışır. Aynı olay için ikinci kez bildirim yapılmaz.
class BildirimMotoru {
  static bool _calisiyor = false;
  static final _saat = DateFormat('dd.MM HH:mm');

  /// Yeni bildirim sayısını döndürür.
  static Future<int> calistir(AppDatabase db, {String? benimId}) async {
    if (_calisiyor) return 0;
    _calisiyor = true;
    try {
      return await _calistir(db, benimId);
    } catch (e, st) {
      debugPrint('Bildirim motoru hatası: $e\n$st');
      return 0;
    } finally {
      _calisiyor = false;
    }
  }

  static Future<int> _calistir(AppDatabase db, String? benimId) async {
    final ayar = await BildirimAyarlari.yukle();
    final simdi = DateTime.now();
    final ms = simdi.millisecondsSinceEpoch;
    final yeni = <_Yeni>[];

    // --------------------------------------------------------------
    // Hareket olayları (başkalarının yaptığı işlemler)
    // --------------------------------------------------------------
    final ilk = !(await db.bildirimGoruldu('baslangic'));
    final pencere = simdi.subtract(const Duration(days: 3));
    final hareketler =
        await db.bildirimHareketleri(pencere.millisecondsSinceEpoch);
    final gorulen = (await db.bildirimGorulenler('h:')).toSet();
    final islenecek = <Map<String, Object?>>[];
    for (final h in hareketler) {
      final anahtar = 'h:${h['id']}';
      if (gorulen.contains(anahtar)) continue;
      await db.bildirimGorulduIsaretle(anahtar, (h['tarih'] as num).toInt());
      if (ilk) continue; // ilk çalıştırmada geçmiş için bildirim yapılmaz
      if (benimId != null && h['kullanici_id'] == benimId) continue;
      islenecek.add(h);
    }
    if (ilk) await db.bildirimGorulduIsaretle('baslangic');
    await db.bildirimGorulenEskileriSil(
        simdi.subtract(const Duration(days: 4)).millisecondsSinceEpoch);

    String kim(Map<String, Object?> h) => (h['kullanici'] as String?) ?? '';
    String seri(Map<String, Object?> h) => (h['seri_no'] as String?) ?? '-';
    String urun(Map<String, Object?> h) => (h['urun_adi'] as String?) ?? '-';
    String sebep(Map<String, Object?> h) => (h['sebep'] as String?) ?? '';

    // Ürün adlarını "NVR ×3, Kamera ×2" biçiminde özetler
    String urunOzeti(List<Map<String, Object?>> l) {
      final say = <String, int>{};
      for (final h in l) {
        say[urun(h)] = (say[urun(h)] ?? 0) + 1;
      }
      final p = say.entries.map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key);
      return p.take(4).join(', ') + (say.length > 4 ? ' ...' : '');
    }

    String kimler(List<Map<String, Object?>> l) {
      final k = {for (final h in l) kim(h)}..remove('');
      return k.isEmpty ? '' : ' · ${k.take(2).join(', ')}';
    }

    // Araca / depoya cihaz geldi
    if (ayar.acikMi(BildirimTuru.cihazGeldi)) {
      final gruplar = <String, List<Map<String, Object?>>>{};
      for (final h in islenecek) {
        final tip = h['tip'];
        final hedef = h['hedef_depo_id'] as String?;
        if (hedef == null ||
            !(tip == 'transfer' || tip == 'kullanim' || tip == 'iade')) {
          continue;
        }
        if (ayar.izlenenDepolar.isNotEmpty &&
            !ayar.izlenenDepolar.contains(hedef)) {
          continue;
        }
        gruplar.putIfAbsent(hedef, () => []).add(h);
      }
      for (final l in gruplar.values) {
        final ad = (l.first['hedef_adi'] as String?) ?? '-';
        final arac = l.first['hedef_tur'] == 'arac';
        yeni.add(_Yeni(
          BildirimTuru.cihazGeldi,
          '${arac ? 'Araca' : 'Depoya'} cihaz geldi: $ad (${l.length})',
          '${urunOzeti(l)}${kimler(l)}',
        ));
      }
    }

    // Depoya giriş (yeni cihaz)
    if (ayar.acikMi(BildirimTuru.depoyaGiris)) {
      final gruplar = <String, List<Map<String, Object?>>>{};
      for (final h in islenecek) {
        if (h['tip'] != 'girisi' || h['sebep'] != null) continue;
        gruplar.putIfAbsent('${h['depo_id']}', () => []).add(h);
      }
      for (final l in gruplar.values) {
        yeni.add(_Yeni(
          BildirimTuru.depoyaGiris,
          'Depoya giriş: ${(l.first['depo_adi'] as String?) ?? '-'} (${l.length})',
          '${urunOzeti(l)}${kimler(l)}',
        ));
      }
    }

    // Hurda ve silme
    if (ayar.acikMi(BildirimTuru.hurdaSilme)) {
      final l = islenecek
          .where((h) => h['tip'] == 'hurda' || h['tip'] == 'silme')
          .toList();
      if (l.length == 1) {
        final h = l.first;
        yeni.add(_Yeni(
          BildirimTuru.hurdaSilme,
          '${h['tip'] == 'hurda' ? 'Hurdaya ayrıldı' : 'Silindi'}: ${seri(h)}',
          [urun(h), if (sebep(h).isNotEmpty) sebep(h), if (kim(h).isNotEmpty) kim(h)]
              .join(' · '),
        ));
      } else if (l.length > 1) {
        final hurda = l.where((h) => h['tip'] == 'hurda').length;
        yeni.add(_Yeni(
          BildirimTuru.hurdaSilme,
          '${l.length} cihaz: $hurda hurda, ${l.length - hurda} silme',
          l.take(4).map((h) => '${seri(h)} (${urun(h)})').join(', '),
        ));
      }
    }

    // Yeni arıza ve servisten dönüş
    final arizalar = islenecek
        .where((h) => h['tip'] == 'servis' && sebep(h).startsWith('Arıza kaydı'))
        .toList();
    if (ayar.acikMi(BildirimTuru.yeniAriza) && arizalar.isNotEmpty) {
      yeni.add(_Yeni(
        BildirimTuru.yeniAriza,
        arizalar.length == 1
            ? 'Yeni arıza: ${seri(arizalar.first)}'
            : '${arizalar.length} yeni arıza kaydı',
        arizalar.length == 1
            ? [
                urun(arizalar.first),
                sebep(arizalar.first).replaceFirst('Arıza kaydı: ', ''),
                if ((arizalar.first['not_'] as String?) != null)
                  arizalar.first['not_'] as String,
              ].join(' · ')
            : arizalar.take(4).map((h) => '${seri(h)} (${urun(h)})').join(', '),
      ));
    }
    final donusler = islenecek
        .where((h) =>
            h['tip'] == 'servis' &&
            (sebep(h).startsWith('Onarıldı') ||
                sebep(h).startsWith('Değiştirildi') ||
                sebep(h).startsWith('Servisten döndü')))
        .toList();
    if (ayar.acikMi(BildirimTuru.servisDonus)) {
      for (final h in donusler.take(5)) {
        yeni.add(_Yeni(
          BildirimTuru.servisDonus,
          'Servisten döndü: ${seri(h)}',
          [urun(h), sebep(h), if ((h['not_'] as String?) != null) h['not_'] as String]
              .join(' · '),
        ));
      }
    }

    // --------------------------------------------------------------
    // Durum olayları
    // --------------------------------------------------------------

    // Kritik stok / tükendi
    if (ayar.acikMi(BildirimTuru.kritikStok)) {
      final liste = await db.kritikStoklar();
      final simdiki = {
        for (final k in liste)
          'kritik:${k.urunId}:${k.toplam == 0 ? 'tukendi' : 'kritik'}': k,
      };
      final onceki = (await db.bildirimGorulenler('kritik:')).toSet();
      // Kritikten çıkan (veya durumu değişen) ürünün işareti kalkar;
      // tekrar düşerse yeniden bildirilir.
      for (final a in onceki.difference(simdiki.keys.toSet())) {
        await db.bildirimGorulenSil(a);
      }
      final yeniKritik = [
        for (final e in simdiki.entries)
          if (!onceki.contains(e.key)) e.value,
      ];
      for (final e in simdiki.keys) {
        if (!onceki.contains(e)) await db.bildirimGorulduIsaretle(e);
      }
      if (yeniKritik.length == 1) {
        final k = yeniKritik.first;
        yeni.add(_Yeni(
          BildirimTuru.kritikStok,
          k.toplam == 0 ? 'Tükendi: ${k.urunAdi}' : 'Kritik stok: ${k.urunAdi}',
          'Depolar ${k.depoda} + araçlar ${k.aracta} = ${k.toplam} · '
              'minimum ${k.minStok}',
        ));
      } else if (yeniKritik.length > 1) {
        final biten = yeniKritik.where((k) => k.toplam == 0).length;
        yeni.add(_Yeni(
          BildirimTuru.kritikStok,
          '${yeniKritik.length} ürün kritik stokta'
              '${biten > 0 ? ' ($biten tükendi)' : ''}',
          yeniKritik
              .take(5)
              .map((k) => '${k.urunAdi} (${k.toplam}/${k.minStok})')
              .join(', '),
        ));
      }
    }

    // Servis gecikmesi
    if (ayar.acikMi(BildirimTuru.servisGecikmesi)) {
      final esik = Duration(days: ayar.servisGecikmeGun);
      final geciken = <String>[];
      for (final s in await db.acikServisDosyalari()) {
        final gonderim = s['gonderim_tarihi'] as num?;
        final acilis = (s['acilis_tarihi'] as num).toInt();
        final baz = gonderim?.toInt() ?? acilis;
        if (ms - baz < esik.inMilliseconds) continue;
        final anahtar = '${gonderim == null ? 'bekleme' : 'gecikme'}:${s['id']}';
        if (await db.bildirimGoruldu(anahtar)) continue;
        await db.bildirimGorulduIsaretle(anahtar);
        final gun = Duration(milliseconds: ms - baz).inDays;
        geciken.add(gonderim == null
            ? '${s['seri_no'] ?? '-'}: $gun gündür arızalı bekliyor (servise gönderilmedi)'
            : '${s['seri_no'] ?? '-'}: $gun gündür serviste'
                '${s['firma'] == null ? '' : ' (${s['firma']})'}');
      }
      if (geciken.isNotEmpty) {
        yeni.add(_Yeni(
          BildirimTuru.servisGecikmesi,
          geciken.length == 1
              ? 'Servis gecikmesi'
              : '${geciken.length} cihaz serviste gecikti',
          geciken.take(4).join('\n'),
        ));
      }
    }

    // Garanti bitiyor
    if (ayar.acikMi(BildirimTuru.garantiBitiyor)) {
      final gun = DateFormat('dd.MM.yyyy');
      final l = <String>[];
      for (final c in await db.garantisiBitecekler(ayar.garantiGun)) {
        final anahtar = 'garanti:${c['id']}:${c['garanti_bitis']}';
        if (await db.bildirimGoruldu(anahtar)) continue;
        await db.bildirimGorulduIsaretle(anahtar);
        l.add('${c['seri_no']} (${c['urun_adi']}) · '
            '${gun.format(DateTime.fromMillisecondsSinceEpoch((c['garanti_bitis'] as num).toInt()))}');
      }
      if (l.isNotEmpty) {
        yeni.add(_Yeni(
          BildirimTuru.garantiBitiyor,
          l.length == 1
              ? 'Garanti bitiyor'
              : '${l.length} cihazın garantisi ${ayar.garantiGun} gün içinde bitiyor',
          l.take(4).join('\n') + (l.length > 4 ? '\n...' : ''),
        ));
      }
    }

    // Gönderilmemiş kayıtlar (en fazla 3 saatte bir hatırlatılır)
    if (ayar.acikMi(BildirimTuru.gonderilmemis)) {
      final enEski = await db.enEskiBekleyenKayit();
      if (enEski != null && ms - enEski > const Duration(hours: 1).inMilliseconds) {
        final son = await db.bildirimGorulmeZamani('gonderilmemis');
        if (son == null || ms - son > const Duration(hours: 3).inMilliseconds) {
          await db.bildirimGorulduIsaretle('gonderilmemis');
          final adet = await db.bekleyenSayisi();
          final saat = Duration(milliseconds: ms - enEski).inHours;
          yeni.add(_Yeni(
            BildirimTuru.gonderilmemis,
            'Gönderilmemiş kayıtlar var ($adet)',
            'Bu telefondaki işlemler $saat saattir sunucuya gönderilemedi. '
                'İnternet bağlantısını kontrol edip uygulamayı açın.',
          ));
        }
      }
    }

    // Günlük özet
    if (ayar.acikMi(BildirimTuru.gunlukOzet)) {
      final bugun = DateTime(simdi.year, simdi.month, simdi.day);
      final saat = bugun.add(Duration(hours: ayar.ozetSaat, minutes: ayar.ozetDakika));
      final anahtar = 'ozet:${DateFormat('yyyyMMdd').format(bugun)}';
      if (!simdi.isBefore(saat) && !(await db.bildirimGoruldu(anahtar))) {
        await db.bildirimGorulduIsaretle(anahtar);
        final kritik = await db.kritikStoklar();
        final servis = await db.acikServisDosyalari();
        final serviste = servis.where((s) => s['gonderim_tarihi'] != null).length;
        final dun = await db.hareketSayilari(
            bugun.subtract(const Duration(days: 1)), bugun);
        final garanti = await db.garantisiBitecekler(ayar.garantiGun);
        int t(String k) => dun[k] ?? 0;
        yeni.add(_Yeni(
          BildirimTuru.gunlukOzet,
          'Günlük özet · ${DateFormat('dd.MM.yyyy').format(bugun)}',
          [
            'Kritik stok: ${kritik.length} ürün'
                '${kritik.any((k) => k.toplam == 0) ? ' (${kritik.where((k) => k.toplam == 0).length} tükendi)' : ''}',
            'Arızalı bekleyen: ${servis.length - serviste} · serviste: $serviste',
            if (garanti.isNotEmpty)
              'Garantisi ${ayar.garantiGun} gün içinde bitecek: ${garanti.length}',
            'Dün: giriş ${t('girisi')}, transfer/kullanıma verme '
                '${t('transfer') + t('kullanim') + t('iade')}, sahada ${t('kullanim')}, '
                'hurda ${t('hurda')}',
          ].join('\n'),
        ));
      }
    }

    // --------------------------------------------------------------
    // Güvenlik (sunucudaki giriş kayıtları; internet gerekir)
    // --------------------------------------------------------------
    if (ayar.acikMi(BildirimTuru.hataliSifre) ||
        ayar.acikMi(BildirimTuru.yeniIpGiris)) {
      try {
        final son = await db.bildirimGorulmeZamani('giris_son') ??
            ms - const Duration(hours: 1).inMilliseconds;
        // Sunucuya en fazla 5 dakikada bir sorulur.
        if (ms - son < const Duration(minutes: 5).inMilliseconds) {
          throw const _Atla();
        }
        final kayitlar = await GirisKaydiServisi.kayitlar(
            baslangic: DateTime.fromMillisecondsSinceEpoch(son), limit: 500);
        await db.bildirimGorulduIsaretle('giris_son', ms);

        if (ayar.acikMi(BildirimTuru.hataliSifre)) {
          final hatali = <String, List<Map<String, dynamic>>>{};
          for (final r in kayitlar.where((r) => r['basarili'] == false)) {
            hatali.putIfAbsent('${r['email'] ?? '-'}', () => []).add(r);
          }
          for (final e in hatali.entries) {
            if (e.value.length < 3) continue;
            final ipler = {for (final r in e.value) r['ip']}.whereType<String>();
            yeni.add(_Yeni(
              BildirimTuru.hataliSifre,
              'Hatalı şifre denemesi: ${e.key}',
              '${e.value.length} deneme · IP: ${ipler.take(3).join(', ')}',
            ));
          }
        }

        if (ayar.acikMi(BildirimTuru.yeniIpGiris)) {
          final bakilan = <String>{};
          for (final r in kayitlar.where((r) => r['basarili'] != false)) {
            if (benimId != null && r['kullanici_id'] == benimId) continue;
            final email = r['email'] as String?;
            final ip = r['ip'] as String?;
            if (email == null || ip == null || !bakilan.add('$email|$ip')) {
              continue;
            }
            final tarih = DateTime.tryParse('${r['tarih']}');
            if (tarih == null) continue;
            if (await GirisKaydiServisi.oncedenVarMi(email, ip, tarih)) continue;
            yeni.add(_Yeni(
              BildirimTuru.yeniIpGiris,
              "Yeni IP'den giriş: $email",
              '$ip · ${r['platform'] ?? ''} · ${_saat.format(tarih.toLocal())}',
            ));
          }
        }
      } on _Atla {
        // bu turda sorulmaz
      } catch (e) {
        debugPrint('Giriş kayıtları okunamadı: $e');
      }
    }

    // --------------------------------------------------------------
    // Kaydet ve göster
    // --------------------------------------------------------------
    var sira = 0;
    for (final b in yeni) {
      await db.bildirimEkle(tur: b.tur.name, baslik: b.baslik, govde: b.govde);
      if (sira < 6) {
        await bildirimGoster(
            (ms ~/ 1000) % 1000000 * 10 + sira, b.baslik, b.govde);
      }
      sira++;
    }
    return yeni.length;
  }

  /// Ayarlar ekranındaki "Test bildirimi" düğmesi.
  static Future<void> test(AppDatabase db) async {
    const baslik = 'Test bildirimi';
    final govde = 'Bildirimler çalışıyor · ${_saat.format(DateTime.now())}';
    await db.bildirimEkle(tur: 'test', baslik: baslik, govde: govde);
    await bildirimGoster(999999, baslik, govde);
  }
}

/// Türün ikonu ve rengi için kısa ad (bildirim listesinde).
BildirimTuru? bildirimTuruCoz(Object? ad) {
  for (final t in BildirimTuru.values) {
    if (t.name == ad) return t;
  }
  return null;
}
