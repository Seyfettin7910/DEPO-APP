-- DEPO OTOMASYON SİSTEMİ 1.29.0: anlık senkron (Realtime "zili")
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * Tablolar Supabase'in "supabase_realtime" yayınına eklenir: bir telefonda
--   kayıt yapılınca sunucu diğer telefonlara "şu tabloda değişiklik var" der,
--   onlar yalnız o tabloyu kaldığı yerden çeker.
-- * Herkes yalnızca görme yetkisi olan kayıtların haberini alır (RLS).
-- * Bu SQL çalıştırılana kadar uygulama çalışır; telefonlar değişiklikleri
--   5 dakikada bir (ve uygulama açılınca / internet gelince) alır.

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array[
    'depolar', 'urunler', 'araclar', 'kullanicilar', 'kurum_kodlari',
    'kurum_ayarlari', 'cihazlar', 'stok_hareketleri', 'kullanim_kayitlari',
    'servis_kayitlari', 'etiketler', 'etiket_hareketleri'
  ] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t)
       and not exists (select 1 from pg_publication_tables
                       where pubname = 'supabase_realtime'
                         and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Kontrol: aşağıdaki sorgu 12 tabloyu listelemeli.
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'
order by tablename;
