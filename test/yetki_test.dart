import 'dart:io';

import 'package:depo_app/database/models.dart';
import 'package:depo_app/services/bildirim/bildirim_ayarlari.dart';
import 'package:depo_app/services/yetki.dart';
import 'package:flutter_test/flutter_test.dart';

/// SQL'deki varsayılan yetki satırları: yetki → [Y, D, S, G, A].
Map<String, List<int>> _sqlVarsayilanlari() {
  final sql = File('supabase_guncelleme_1_36_0.sql').readAsStringSync();
  final satir = RegExp(r"\('([a-z_]+)',\s*([01]),\s*([01]),\s*([01]),\s*([01]),\s*([01])\)");
  return {
    for (final m in satir.allMatches(sql))
      m[1]!: [for (var i = 2; i <= 6; i++) int.parse(m[i]!)]
  };
}

const _sira = [
  KullaniciRol.admin,
  KullaniciRol.depoSorumlusu,
  KullaniciRol.sahaKullanicisi,
  KullaniciRol.gozlemci,
  KullaniciRol.amir,
];

void main() {
  test('Uygulamadaki varsayılan yetkiler sunucu SQL\'i ile aynı', () {
    final sql = _sqlVarsayilanlari();
    expect(sql.keys.toSet(), {for (final y in Yetki.values) y.anahtar});
    for (final y in Yetki.values) {
      for (var i = 0; i < 5; i++) {
        expect(y.varsayilan(_sira[i]) ? 1 : 0, sql[y.anahtar]![i],
            reason: '${y.anahtar} / ${_sira[i].name}');
      }
    }
  });

  test('Anahtar adları sunucudakiyle aynı biçimde', () {
    expect(Yetki.depoGiris.anahtar, 'depo_giris');
    expect(Yetki.kullaniciYonetimi.anahtar, 'kullanici_yonetimi');
    expect(Yetki.anahtardan('malzeme_kullanim'), Yetki.malzemeKullanim);
    expect(yetkiKimligi(KullaniciRol.amir, Yetki.rapor), 'amir:rapor');
  });

  test('Kilitler: hareket silme hep kapalı, yöneticinin kullanıcı yönetimi hep açık', () {
    for (final r in KullaniciRol.values) {
      expect(kilitliDeger(r, Yetki.hareketSilme, true), isFalse);
    }
    expect(kilitliDeger(KullaniciRol.admin, Yetki.kullaniciYonetimi, false), isTrue);
    expect(kilitliDeger(KullaniciRol.depoSorumlusu, Yetki.kullaniciYonetimi, true), isTrue);
    final y = Yetkilerim(rol: KullaniciRol.admin, tablo: {
      yetkiKimligi(KullaniciRol.admin, Yetki.kullaniciYonetimi): false,
      yetkiKimligi(KullaniciRol.admin, Yetki.hareketSilme): true,
    });
    expect(y.yonetici, isTrue);
    expect(y.var_(Yetki.hareketSilme), isFalse);
  });

  test('Sunucu tablosu yoksa eski düzen: her şey açık (hareket silme hariç)', () {
    const y = Yetkilerim.eski();
    expect(y.var_(Yetki.cihazSil), isTrue);
    expect(y.var_(Yetki.kullaniciYonetimi), isTrue);
    expect(y.var_(Yetki.hareketSilme), isFalse);
  });

  test('Tablodaki değer varsayılanı ezer; tabloda yoksa varsayılan', () {
    final y = Yetkilerim(rol: KullaniciRol.sahaKullanicisi, tablo: {
      yetkiKimligi(KullaniciRol.sahaKullanicisi, Yetki.montaj): false,
    });
    expect(y.var_(Yetki.montaj), isFalse);
    expect(y.var_(Yetki.aracaYukle), isTrue); // varsayılan
    expect(y.var_(Yetki.depoGiris), isFalse); // varsayılan
  });

  test('Gözlemci ve Amir yalnızca görür', () {
    for (final r in [KullaniciRol.gozlemci, KullaniciRol.amir]) {
      final acik = {for (final y in Yetki.values) if (y.varsayilan(r)) y};
      expect(acik, {Yetki.okut, Yetki.ara, Yetki.rapor, Yetki.bildirimAyar});
    }
  });

  test('Merkezi bildirim alıcıları: alıcı alır, kişi yalnız kapatabilir', () {
    final a = BildirimAyarlari(
      acik: {BildirimTuru.kritikStok},
      kapatilan: {BildirimTuru.yeniAriza},
    );
    final g = a.merkezeGore((t) => switch (t) {
          BildirimTuru.kritikStok => false, // alıcı değil
          BildirimTuru.yeniAriza => true, // alıcı ama kendisi kapattı
          BildirimTuru.hataliSifre => true, // alıcı, varsayılanı kapalıydı
          _ => null, // merkezi seçim yok: kendi ayarı
        });
    expect(g.acikMi(BildirimTuru.kritikStok), isFalse);
    expect(g.acikMi(BildirimTuru.yeniAriza), isFalse);
    expect(g.acikMi(BildirimTuru.hataliSifre), isTrue);
    expect(g.acikMi(BildirimTuru.depoyaGiris), isFalse); // kendi ayarında kapalı
    // Gönderilmemiş kayıtlar merkezden seçilmez
    expect(BildirimTuru.gonderilmemis.merkezi, isFalse);
  });

  test('Sunucudaki varsayılan bildirim alıcıları bilinen türler', () {
    final sql = File('supabase_guncelleme_1_36_0.sql').readAsStringSync();
    final turler = {
      for (final m in RegExp(r"\('([a-zA-Z]+)',\s+'[a-zA-Z,]+', ''").allMatches(sql)) m[1]!
    };
    expect(turler, {for (final t in BildirimTuru.values) if (t.merkezi) t.name});
  });
}
