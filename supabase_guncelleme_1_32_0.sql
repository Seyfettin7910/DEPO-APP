-- DEPO YÖNETİM SİSTEMİ 1.32.0: belediye zimmeti için Başkanlık onayı
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * kullanim_kayitlari.zimmet_yeri      : hizmet | kirsal (yalnız BELEDİYE ZİMMETİ
--                                          deposundan yapılan montajlarda dolu)
-- * kullanim_kayitlari.onay_evrak_sayisi: kırsal mahallede kullanımda Başkanlık
--                                          onayının evrak sayısı (zorunlu)
-- * zimmet_girisimleri: onay olmadan kırsal mahallede kullanma girişimleri
--   (kaydedilmeyen montajlar). Bildirim ve rapor için; değiştirilemez, silinemez.
-- * Bu SQL çalıştırılana kadar uygulama çalışır: yeni bilgiler telefonda
--   bekler, SQL çalıştırılınca kendiliğinden gönderilir.

alter table kullanim_kayitlari add column if not exists zimmet_yeri text;
alter table kullanim_kayitlari add column if not exists onay_evrak_sayisi text;

create table if not exists zimmet_girisimleri (
  id text primary key, kullanici_id text, tarih bigint not null,
  depo_id text, icerik text, kullanim_yeri text,
  il text, ilce text, mahalle text,
  enlem double precision, boylam double precision);
create index if not exists zimmet_girisimleri_tarih_idx on zimmet_girisimleri (tarih);

-- Ortak senkron sütunları, tetikleyici ve güvenlik (yalnızca giriş yapmış kullanıcılar)
do $$
declare t text;
begin
  foreach t in array array['zimmet_girisimleri'] loop
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

-- Girişim kayıtları değiştirilemez ve silinemez. (Aynı kaydın telefondan
-- tekrar gönderilmesi hata vermez; kayıt olduğu gibi kalır.)
create or replace function zimmet_girisim_koru() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    return null;
  end if;
  return old;
end $$;
drop trigger if exists a_koru on zimmet_girisimleri;
create trigger a_koru before update or delete on zimmet_girisimleri
  for each row execute function zimmet_girisim_koru();

-- Anlık senkron (Realtime "zili")
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime'
                       and schemaname = 'public' and tablename = 'zimmet_girisimleri') then
    alter publication supabase_realtime add table public.zimmet_girisimleri;
  end if;
end $$;

-- Sunucunun tablo ve sütun listesini hemen yenile
notify pgrst, 'reload schema';
