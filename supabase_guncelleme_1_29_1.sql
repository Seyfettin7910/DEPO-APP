-- DEPO OTOMASYON SİSTEMİ 1.29.1: eski kayıtlardaki yazılar BÜYÜK HARF
-- Supabase > SQL Editor'da çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır: yalnız küçük harf kalan kayıtlar değişir.
-- Bütün telefonlar 1.29.1'e geçtikten sonra bir kez daha çalıştırmak iyi olur
-- (eski sürümle küçük harf yazılmış olabilir).
--
-- * Yalnız kullanıcıların yazdığı / otomatik dolan metinler: ad, konum,
--   açıklama, not, nerede kullanıldı, il / ilçe / mahalle, firma, ihale,
--   kategori, plaka. Türkçe kural: i → İ, ı → I (plakada i → I).
-- * Seri no, barkod, kurum kodu, e-posta ve uygulamanın iç kodları
--   (tip, durum, tutanak, birim…) DEĞİŞMEZ. Hiçbir kayıt silinmez.
-- * Değişen kayıtların güncellenme zamanı ilerletilir; telefonlar yeni
--   yazılışı kendiliğinden alır.

create or replace function depo_tr_buyuk(t text) returns text
language sql immutable as $$
  select translate(t,
    'abcçdefgğhıijklmnoöprsştuüvyzqwxâîûéèêëäå',
    'ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZQWXÂÎÛÉÈÊËÄÅ')
$$;

create or replace function depo_latin_buyuk(t text) returns text
language sql immutable as $$
  select translate(t,
    'abcçdefgğhıijklmnoöprsştuüvyzqwx',
    'ABCÇDEFGĞHIIJKLMNOÖPRSŞTUÜVYZQWX')
$$;

do $$
declare
  -- tablo -> Türkçe kurallı sütunlar
  liste text[][] := array[
    array['depolar', 'ad'], array['depolar', 'konum'],
    array['urunler', 'ad'], array['urunler', 'kategori'],
    array['araclar', 'ad'], array['araclar', 'aciklama'],
    array['kullanicilar', 'ad'],
    array['cihazlar', 'kullanim_yeri'], array['cihazlar', 'firma'],
    array['cihazlar', 'ihale'],
    array['stok_hareketleri', 'not_'],
    array['kullanim_kayitlari', 'kullanim_yeri'],
    array['kullanim_kayitlari', 'not_'], array['kullanim_kayitlari', 'il'],
    array['kullanim_kayitlari', 'ilce'], array['kullanim_kayitlari', 'mahalle'],
    array['servis_kayitlari', 'ariza_aciklama'],
    array['servis_kayitlari', 'firma'],
    array['servis_kayitlari', 'sonuc_aciklama'],
    array['kurum_kodlari', 'ad']
  ];
  i int;
  n int;
  toplam int := 0;
begin
  for i in 1 .. array_length(liste, 1) loop
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = liste[i][1]
                 and column_name = liste[i][2]) then
      execute format(
        'update public.%1$I set %2$I = depo_tr_buyuk(%2$I), '
        'updated_at = greatest(updated_at + 1, '
        '(extract(epoch from clock_timestamp()) * 1000)::bigint) '
        'where %2$I is distinct from depo_tr_buyuk(%2$I)',
        liste[i][1], liste[i][2]);
      get diagnostics n = row_count;
      toplam := toplam + n;
    end if;
  end loop;

  -- Plaka: Latin kuralı (i → I)
  update public.araclar set plaka = depo_latin_buyuk(plaka),
    updated_at = greatest(updated_at + 1,
      (extract(epoch from clock_timestamp()) * 1000)::bigint)
  where plaka is distinct from depo_latin_buyuk(plaka);
  get diagnostics n = row_count;
  toplam := toplam + n;

  raise notice 'Büyük harfe çevrilen alan: %', toplam;
end $$;

drop function if exists depo_tr_buyuk(text);
drop function if exists depo_latin_buyuk(text);

select 'Tamam: yazılar büyük harfe çevrildi' as sonuc;
