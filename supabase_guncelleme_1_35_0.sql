-- DEPO YÖNETİM SİSTEMİ 1.35.0: genel sayım
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * sayimlar: sayım ekranında "Bitir" denince kaydedilen sayım sonuçları
--   (kim, ne zaman, hangi depo / araç; bulunan / eksik / fazla seri nolar ve
--   malzeme sayımı "icerik" içinde). Raporlar → "Genel sayım" bunları
--   birleştirir. Değiştirilemez, silinemez.
-- * Bu SQL çalıştırılana kadar uygulama çalışır: sayımlar telefonda bekler,
--   SQL çalıştırılınca kendiliğinden gönderilir.

create table if not exists sayimlar (
  id text primary key, kullanici_id text, depo_id text not null, depo_adi text,
  baslangic bigint, tarih bigint not null,
  olmali integer not null default 0, bulunan integer not null default 0,
  eksik integer not null default 0, fazla integer not null default 0,
  icerik text);
create index if not exists sayimlar_tarih_idx on sayimlar (tarih);

-- Ortak senkron sütunları, tetikleyici ve güvenlik (yalnızca giriş yapmış kullanıcılar)
do $$
declare t text;
begin
  foreach t in array array['sayimlar'] loop
    execute format('alter table %I add column if not exists updated_at bigint not null default 0', t);
    execute format('alter table %I add column if not exists deleted integer not null default 0', t);
    execute format('alter table %I add column if not exists synced_at bigint not null default 0', t);
    execute format('create index if not exists %I on %I (synced_at)', t || '_synced_idx', t);
    execute format('drop trigger if exists senk_tetik on %I', t);
    execute format('create trigger senk_tetik before insert or update on %I for each row execute function senk_tetik()', t);
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists giris_yapanlar on %I', t);
    execute format('create policy giris_yapanlar on %I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- Sayım kayıtları değiştirilemez ve silinemez. (Aynı kaydın telefondan
-- tekrar gönderilmesi hata vermez; kayıt olduğu gibi kalır.)
create or replace function sayim_koru() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    return null;
  end if;
  return old;
end $$;
drop trigger if exists a_koru on sayimlar;
create trigger a_koru before update or delete on sayimlar
  for each row execute function sayim_koru();

-- Anlık senkron (Realtime "zili")
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime'
                       and schemaname = 'public' and tablename = 'sayimlar') then
    alter publication supabase_realtime add table public.sayimlar;
  end if;
end $$;

-- Sunucunun tablo ve sütun listesini hemen yenile
notify pgrst, 'reload schema';
