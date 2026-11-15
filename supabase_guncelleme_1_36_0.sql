-- DEPO YÖNETİM SİSTEMİ 1.36.0: roller, yetkiler ve kullanıcı yönetimi
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır (yöneticinin değiştirdiği yetkiler korunur).
--
-- * kullanicilar: aktif / pasif, unvan, "şifre değiştirmesi bekleniyor",
--   geçici şifrenin bitişi. Rol, aktiflik ve şifre bilgileri YALNIZ sunucu
--   fonksiyonuyla (hesap) değişir; telefondan gönderilen değerler yok sayılır.
-- * Roller: admin (Yönetici) · depoSorumlusu · sahaKullanicisi (Saha) ·
--   gozlemci (Gözlemci) · amir (Amir).
-- * yetkiler: yöneticinin düzenleyebildiği yetki tablosu (varsayılanlarla).
-- * bildirim_alicilari: hangi bildirimi hangi roller / kişiler alır.
-- * hesap_islemleri: şifre talebi, sıfırlama, kullanıcı ekleme, rol, pasif /
--   aktif kayıtları (yalnız yönetici okur; kimse değiştiremez / silemez).
--   Şifre ya da kodun kendisi asla yazılmaz.
-- * Pasif kullanıcı ve şifresini henüz değiştirmemiş kullanıcı hiçbir
--   kayda erişemez (her zaman).
-- * Ayrıntılı yetki denetimi (ör. Saha depoya giriş yapamaz): kurum
--   ayarlarındaki "yetki_denetimi" değerine göre:
--     kayit (varsayılan): işlem yapılır, yetkisiz işlem yetki_ihlalleri
--                         tablosuna yazılır (yönetici uygulamada görür)
--     engel             : yetkisiz işlem sunucuda reddedilir
--   Uygulamada yetkisi olmayan düğme zaten görünmez; "kayit" ile birkaç gün
--   izlenip ihlal görülmezse uygulamadan "engel"e geçilir.
--
-- !!! EN ALTTAKİ "İLK YÖNETİCİ" SATIRINA KENDİ GİRİŞ E-POSTANIZI YAZIN !!!

-- ------------------------------------------------------------------
-- 1) Kullanıcılar: yeni sütunlar
-- ------------------------------------------------------------------
alter table kullanicilar add column if not exists aktif integer not null default 1;
alter table kullanicilar add column if not exists unvan text;
alter table kullanicilar add column if not exists sifre_degistirmeli integer not null default 0;
alter table kullanicilar add column if not exists gecici_bitis bigint;

-- ------------------------------------------------------------------
-- 2) Yetki tablosu ve bildirim alıcıları (senkronlanır)
-- ------------------------------------------------------------------
create table if not exists yetkiler (
  id text primary key, rol text not null, yetki text not null,
  izin integer not null default 0);
create table if not exists bildirim_alicilari (
  id text primary key, roller text, kisiler text);

do $$
declare t text;
begin
  foreach t in array array['yetkiler', 'bildirim_alicilari'] loop
    execute format('alter table %I add column if not exists updated_at bigint not null default 0', t);
    execute format('alter table %I add column if not exists deleted integer not null default 0', t);
    execute format('alter table %I add column if not exists synced_at bigint not null default 0', t);
    execute format('create index if not exists %I on %I (synced_at)', t || '_synced_idx', t);
    execute format('drop trigger if exists senk_tetik on %I', t);
    execute format('create trigger senk_tetik before insert or update on %I for each row execute function senk_tetik()', t);
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- ------------------------------------------------------------------
-- 3) Sunucu kayıtları (uygulamadan değiştirilemez / silinemez)
-- ------------------------------------------------------------------
create table if not exists hesap_islemleri (
  id bigint generated always as identity primary key,
  tarih timestamptz not null default now(),
  tur text not null,           -- sifre_talebi | sifre_sifirlama | gecici_giris |
                               -- sifre_degisti | gecici_suresi_doldu | kullanici_ekleme |
                               -- rol_degisti | pasif | aktif | ad_degisti
  yapan_id text, yapan_email text,
  hedef_id text, hedef_email text, hedef_ad text,
  aciklama text, ip text);
create index if not exists hesap_islemleri_tarih_idx on hesap_islemleri (tarih desc);
alter table hesap_islemleri enable row level security;
revoke all on hesap_islemleri from anon, authenticated;
grant select on hesap_islemleri to authenticated;

create table if not exists yetki_ihlalleri (
  id bigint generated always as identity primary key,
  tarih timestamptz not null default now(),
  kullanici_id text, tablo text, kayit_id text, gereken text, engellendi boolean);
create index if not exists yetki_ihlalleri_tarih_idx on yetki_ihlalleri (tarih desc);
alter table yetki_ihlalleri enable row level security;
revoke all on yetki_ihlalleri from anon, authenticated;
grant select on yetki_ihlalleri to authenticated;

-- ------------------------------------------------------------------
-- 4) Yardımcı fonksiyonlar
-- ------------------------------------------------------------------
create or replace function simdi_ms() returns bigint
language sql stable as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;

-- Giriş yapanın rolü; pasif, silinmiş ya da şifresini değiştirmesi
-- gereken kullanıcı için null.
create or replace function ben_rol() returns text
language sql stable security definer set search_path = public as $$
  select k.rol from kullanicilar k
  where k.id = auth.uid()::text and k.aktif = 1 and k.deleted = 0
    and k.sifre_degistirmeli = 0
  limit 1
$$;

create or replace function aktifim() returns boolean
language sql stable security definer set search_path = public as $$
  select ben_rol() is not null
$$;

create or replace function yetkim(p_yetki text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select y.izin = 1 from yetkiler y
    where y.rol = ben_rol() and y.yetki = p_yetki and y.deleted = 0
    limit 1), false)
$$;

-- Uygulamanın girişte sorduğu durum (RLS'den bağımsız)
create or replace function benim_durumum() returns json
language sql stable security definer set search_path = public as $$
  select coalesce((
    select json_build_object(
      'var', true, 'rol', k.rol, 'aktif', k.aktif, 'unvan', k.unvan, 'ad', k.ad,
      'sifre_degistirmeli', k.sifre_degistirmeli, 'gecici_bitis', k.gecici_bitis)
    from kullanicilar k where k.id = auth.uid()::text limit 1),
    json_build_object('var', false))
$$;

-- ------------------------------------------------------------------
-- 5) Varsayılan yetkiler (var olanlar korunur)
-- ------------------------------------------------------------------
do $$
declare
  r record;
  roller text[] := array['admin', 'depoSorumlusu', 'sahaKullanicisi', 'gozlemci', 'amir'];
  i int;
begin
  for r in select * from (values
    -- yetki,              Y, D, S, G, A
    ('okut',               1, 1, 1, 1, 1),
    ('ara',                1, 1, 1, 1, 1),
    ('depo_giris',         1, 1, 0, 0, 0),
    ('transfer',           1, 1, 0, 0, 0),
    ('araca_yukle',        1, 1, 1, 0, 0),
    ('iade',               1, 1, 1, 0, 0),
    ('montaj',             1, 1, 1, 0, 0),
    ('geri_alma',          1, 1, 1, 0, 0),
    ('ariza',              1, 1, 1, 0, 0),
    ('servis',             1, 1, 0, 0, 0),
    ('cihaz_duzenle',      1, 1, 0, 0, 0),
    ('hurda',              1, 0, 0, 0, 0),
    ('cihaz_sil',          1, 0, 0, 0, 0),
    ('malzeme_giris',      1, 1, 0, 0, 0),
    ('malzeme_araca',      1, 1, 1, 0, 0),
    ('malzeme_iade',       1, 1, 1, 0, 0),
    ('malzeme_transfer',   1, 1, 0, 0, 0),
    ('malzeme_kullanim',   1, 1, 1, 0, 0),
    ('urun_tanim',         1, 1, 0, 0, 0),
    ('urun_birlestir',     1, 1, 0, 0, 0),
    ('urun_sil',           1, 0, 0, 0, 0),
    ('depo_tanim',         1, 1, 0, 0, 0),
    ('depo_sil',           1, 0, 0, 0, 0),
    ('sayim',              1, 1, 0, 0, 0),
    ('kurum_kodu',         1, 1, 0, 0, 0),
    ('etiket_bas',         1, 1, 0, 0, 0),
    ('etiket_dogrula',     1, 1, 1, 0, 0),
    ('etiket_ayar',        1, 0, 0, 0, 0),
    ('rapor',              1, 1, 0, 1, 1),
    ('giris_kayitlari',    1, 0, 0, 0, 0),
    ('okuma_istatistik',   1, 1, 0, 0, 0),
    ('kullanici_yonetimi', 1, 0, 0, 0, 0),
    ('bildirim_ayar',      1, 1, 1, 1, 1),
    ('hareket_silme',      0, 0, 0, 0, 0)
  ) as v(yetki, y, d, s, g, a) loop
    for i in 1..5 loop
      insert into yetkiler (id, rol, yetki, izin, updated_at)
      values (roller[i] || ':' || r.yetki, roller[i], r.yetki,
              case i when 1 then r.y when 2 then r.d when 3 then r.s
                     when 4 then r.g else r.a end,
              simdi_ms())
      on conflict (id) do nothing;
    end loop;
  end loop;
end $$;

-- Varsayılan bildirim alıcıları (var olanlar korunur; Kullanıcılar →
-- Roller ve yetkiler → Bildirim alıcıları'ndan değiştirilir). Seçilen kişi
-- bildirimi kendi telefonunda yalnızca kapatabilir.
insert into bildirim_alicilari (id, roller, kisiler, updated_at) values
  ('kritikStok',       'admin,depoSorumlusu', '', simdi_ms()),
  ('yeniAriza',        'admin,depoSorumlusu', '', simdi_ms()),
  ('servisGecikmesi',  'admin,depoSorumlusu', '', simdi_ms()),
  ('garantiBitiyor',   'admin,depoSorumlusu', '', simdi_ms()),
  ('cihazGeldi',       'admin,depoSorumlusu,sahaKullanicisi', '', simdi_ms()),
  ('depoyaGiris',      'admin,depoSorumlusu', '', simdi_ms()),
  ('hurdaSilme',       'admin,depoSorumlusu,amir', '', simdi_ms()),
  ('servisDonus',      'admin,depoSorumlusu', '', simdi_ms()),
  ('hataliSifre',      'admin', '', simdi_ms()),
  ('yeniIpGiris',      'admin', '', simdi_ms()),
  ('sifreTalebi',      'admin', '', simdi_ms()),
  ('gunlukOzet',       'admin,depoSorumlusu,amir', '', simdi_ms()),
  ('etiketBasim',      'admin,depoSorumlusu', '', simdi_ms()),
  ('etiketUyusmazlik', 'admin,depoSorumlusu', '', simdi_ms()),
  ('zimmetOnaysiz',    'admin,amir', '', simdi_ms())
on conflict (id) do nothing;

-- Kilitler: yöneticinin kullanıcı yönetimi kapatılamaz, hareket silme
-- kimseye açılamaz (yöneticinin kendini dışarıda bırakmasına karşı).
create or replace function yetki_kilit() returns trigger
language plpgsql as $$
begin
  if new.yetki = 'hareket_silme' then new.izin := 0; end if;
  if new.yetki = 'kullanici_yonetimi' and new.rol = 'admin' then new.izin := 1; end if;
  return new;
end $$;
drop trigger if exists b_kilit on yetkiler;
create trigger b_kilit before insert or update on yetkiler
  for each row execute function yetki_kilit();

-- ------------------------------------------------------------------
-- 6) Kullanıcı satırı koruması (her zaman): rol, aktiflik ve şifre
--    bilgileri yalnız sunucu fonksiyonuyla değişir. Görünen adı yalnız
--    kişinin kendisi ya da kullanıcı yönetimi yetkisi olan değiştirir.
--    Kendi satırı yoksa yalnız Saha rolüyle eklenebilir.
-- ------------------------------------------------------------------
create or replace function kullanici_koru() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;  -- sunucu fonksiyonu / SQL
  if tg_op = 'INSERT' then
    if exists (select 1 from kullanicilar where id = new.id) then
      return new;  -- upsert: güncelleme yolunda denetlenir
    end if;
    if new.id <> auth.uid()::text and not yetkim('kullanici_yonetimi') then
      return null;  -- başkası adına kullanıcı eklenemez (sessizce yok sayılır)
    end if;
    new.rol := 'sahaKullanicisi';
    new.aktif := 1;
    new.sifre_degistirmeli := 0;
    new.gecici_bitis := null;
    return new;
  end if;
  new.rol := old.rol;
  new.aktif := old.aktif;
  new.unvan := old.unvan;
  new.sifre_degistirmeli := old.sifre_degistirmeli;
  new.gecici_bitis := old.gecici_bitis;
  new.email := old.email;
  new.deleted := old.deleted;
  if new.ad is distinct from old.ad
     and new.id <> auth.uid()::text and not yetkim('kullanici_yonetimi') then
    new.ad := old.ad;
  end if;
  return new;
end $$;
drop trigger if exists b_kullanici_koru on kullanicilar;
create trigger b_kullanici_koru before insert or update on kullanicilar
  for each row execute function kullanici_koru();

-- ------------------------------------------------------------------
-- 7) Ayrıntılı yetki denetimi (kayit / engel)
-- ------------------------------------------------------------------
create or replace function yetki_denetimi_modu() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select deger from kurum_ayarlari
                   where id = 'yetki_denetimi' and deleted = 0 limit 1), 'kayit')
$$;

create or replace function yetki_denetle() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g text[];
  kaynak text;
  hedef text;
  malzeme boolean;
  y text;
  mod text;
begin
  if auth.uid() is null then return new; end if;  -- sunucu fonksiyonu / SQL
  mod := yetki_denetimi_modu();
  if mod = 'kapali' then return new; end if;

  -- Upsert: kayıt zaten varsa güncelleme yolunda denetlenir.
  if tg_op = 'INSERT' then
    execute format('select exists (select 1 from %I where id = $1)', tg_table_name)
      into malzeme using new.id;
    if malzeme then return new; end if;
  end if;

  case tg_table_name
  when 'stok_hareketleri' then
    if tg_op = 'UPDATE' then return new; end if;  -- hareketler değişmez
    malzeme := new.cihaz_id is null;
    select tur into kaynak from depolar where id = new.depo_id;
    select tur into hedef from depolar where id = new.hedef_depo_id;
    kaynak := coalesce(kaynak, 'sabit');
    if new.tip = 'girisi' then
      g := case when new.sebep is not null then array['geri_alma', 'depo_giris']
                when malzeme then array['malzeme_giris']
                else array['depo_giris'] end;
    elsif new.tip in ('kullanim', 'transfer', 'iade') then
      if new.hedef_depo_id is null then
        g := case when malzeme then array['malzeme_kullanim'] else array['montaj'] end;
      elsif coalesce(hedef, 'sabit') = 'arac' then
        g := case when malzeme then array['malzeme_araca'] else array['araca_yukle'] end;
      elsif kaynak = 'arac' then
        g := case when malzeme then array['malzeme_iade'] else array['iade'] end;
      else
        g := case when malzeme then array['malzeme_transfer'] else array['transfer'] end;
      end if;
    elsif new.tip = 'servis' then g := array['ariza', 'servis'];
    elsif new.tip = 'hurda' then g := array['hurda'];
    elsif new.tip = 'silme' then g := array['cihaz_sil', 'urun_sil'];
    elsif new.tip = 'cikis' then g := array['transfer'];
    end if;

  when 'cihazlar' then
    if tg_op = 'INSERT' then
      g := array['depo_giris'];
    elsif new.deleted = 1 and old.deleted = 0 then
      g := array['cihaz_sil'];
    elsif new.deleted = 0 and old.deleted = 1 then
      g := array['depo_giris'];
    elsif new.urun_id is distinct from old.urun_id then
      g := array['urun_birlestir', 'cihaz_duzenle'];
    elsif new.servis_durumu is distinct from old.servis_durumu then
      g := case when new.servis_durumu = 'hurda' then array['hurda']
                else array['ariza', 'servis', 'geri_alma', 'depo_giris'] end;
    elsif new.durum is distinct from old.durum
          or new.depo_id is distinct from old.depo_id then
      select tur into kaynak from depolar where id = old.depo_id;
      select tur into hedef from depolar where id = new.depo_id;
      if new.durum = 'kullanimda' then
        g := array['montaj'];
      elsif old.durum = 'kullanimda' then
        g := array['geri_alma', 'depo_giris'];
      elsif new.durum = 'depoda' and old.durum = 'depoda' then
        if coalesce(hedef, 'sabit') = 'arac' then g := array['araca_yukle'];
        elsif coalesce(kaynak, 'sabit') = 'arac' then g := array['iade'];
        else g := array['transfer'];
        end if;
      elsif new.durum = 'depoda' then
        g := array['depo_giris', 'geri_alma', 'iade', 'servis'];
      else
        g := array['transfer', 'hurda', 'cihaz_sil'];
      end if;
    elsif row(new.alim_tarihi, new.firma, new.ihale, new.garanti_bitis, new.kullanim_yeri)
          is distinct from
          row(old.alim_tarihi, old.firma, old.ihale, old.garanti_bitis, old.kullanim_yeri) then
      g := array['cihaz_duzenle', 'depo_giris', 'montaj'];
    end if;

  when 'kullanim_kayitlari' then
    g := case when tg_op = 'INSERT' then array['montaj', 'malzeme_kullanim']
              else array['montaj', 'malzeme_kullanim', 'cihaz_duzenle'] end;
  when 'zimmet_girisimleri' then
    g := array['montaj', 'malzeme_kullanim'];
  when 'servis_kayitlari' then
    g := array['ariza', 'servis'];
  when 'urunler' then
    if tg_op = 'UPDATE' and new.deleted = 1 and old.deleted = 0 then
      g := array['urun_sil'];
    elsif tg_op = 'UPDATE' and new.birlesti_id is not null and old.birlesti_id is null then
      g := array['urun_birlestir'];
    else
      g := array['urun_tanim'];
    end if;
  when 'depolar', 'araclar' then
    if tg_op = 'UPDATE' and new.deleted = 1 and old.deleted = 0 then
      g := array['depo_sil'];
    else
      g := array['depo_tanim'];
    end if;
  when 'sayimlar' then
    if tg_op = 'UPDATE' then return new; end if;
    g := array['sayim'];
  when 'kurum_kodlari' then
    g := array['etiket_ayar'];
  when 'kurum_ayarlari' then
    g := case when new.id = 'yetki_denetimi' then array['kullanici_yonetimi']
              else array['etiket_ayar'] end;
  when 'etiketler' then
    g := case when tg_op = 'INSERT' then array['kurum_kodu']
              else array['kurum_kodu', 'etiket_bas', 'etiket_dogrula'] end;
  when 'etiket_hareketleri' then
    if tg_op = 'UPDATE' then return new; end if;
    g := case new.islem
           when 'uretildi' then array['kurum_kodu']
           when 'kuyruga' then array['kurum_kodu', 'etiket_bas']
           when 'yenidenBasim' then array['kurum_kodu', 'etiket_bas', 'etiket_dogrula']
           when 'basildi' then array['etiket_bas']
           else array['etiket_dogrula', 'kurum_kodu', 'etiket_bas'] end;
  else
    return new;
  end case;

  if g is null then return new; end if;
  foreach y in array g loop
    if yetkim(y) then return new; end if;
  end loop;

  insert into yetki_ihlalleri (kullanici_id, tablo, kayit_id, gereken, engellendi)
  values (auth.uid()::text, tg_table_name, new.id, array_to_string(g, ' / '), mod = 'engel');
  if mod = 'engel' then
    raise exception 'yetki_yok: %', array_to_string(g, ' / ') using errcode = '42501';
  end if;
  return new;
end $$;

-- Tetikleyiciler (b_ önekli: senk_tetik'ten sonra, a_koru'dan sonra çalışır)
do $$
declare t text;
begin
  foreach t in array array['stok_hareketleri', 'cihazlar', 'kullanim_kayitlari',
                           'zimmet_girisimleri', 'servis_kayitlari', 'urunler',
                           'depolar', 'araclar', 'sayimlar', 'kurum_kodlari',
                           'kurum_ayarlari', 'etiketler', 'etiket_hareketleri'] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t) then
      execute format('drop trigger if exists b_yetki on %I', t);
      execute format('create trigger b_yetki before insert or update on %I for each row execute function yetki_denetle()', t);
    end if;
  end loop;
end $$;

-- ------------------------------------------------------------------
-- 8) Erişim kuralları (RLS): pasif / şifre bekleyen kullanıcı hiçbir
--    kayda erişemez; yetki tablosu ve bildirim alıcıları yalnız kullanıcı
--    yönetimi yetkisiyle değişir.
-- ------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['depolar', 'urunler', 'araclar', 'kullanicilar',
                           'cihazlar', 'stok_hareketleri', 'kullanim_kayitlari',
                           'servis_kayitlari', 'kurum_kodlari', 'kurum_ayarlari',
                           'etiketler', 'etiket_hareketleri', 'zimmet_girisimleri',
                           'sayimlar'] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t) then
      execute format('drop policy if exists giris_yapanlar on %I', t);
      execute format('drop policy if exists aktif_okur on %I', t);
      execute format('drop policy if exists aktif_ekler on %I', t);
      execute format('drop policy if exists aktif_gunceller on %I', t);
      execute format('create policy aktif_okur on %I for select to authenticated using ((select aktifim()))', t);
      execute format('create policy aktif_ekler on %I for insert to authenticated with check ((select aktifim()))', t);
      execute format('create policy aktif_gunceller on %I for update to authenticated using ((select aktifim())) with check ((select aktifim()))', t);
    end if;
  end loop;

  foreach t in array array['yetkiler', 'bildirim_alicilari'] loop
    execute format('drop policy if exists aktif_okur on %I', t);
    execute format('drop policy if exists yonetici_ekler on %I', t);
    execute format('drop policy if exists yonetici_gunceller on %I', t);
    execute format('create policy aktif_okur on %I for select to authenticated using ((select aktifim()))', t);
    execute format('create policy yonetici_ekler on %I for insert to authenticated with check ((select yetkim(''kullanici_yonetimi'')))', t);
    execute format('create policy yonetici_gunceller on %I for update to authenticated using ((select yetkim(''kullanici_yonetimi''))) with check ((select yetkim(''kullanici_yonetimi'')))', t);
  end loop;
end $$;

drop policy if exists yonetici_okur on hesap_islemleri;
create policy yonetici_okur on hesap_islemleri for select to authenticated
  using ((select yetkim('kullanici_yonetimi')));
drop policy if exists yonetici_okur on yetki_ihlalleri;
create policy yonetici_okur on yetki_ihlalleri for select to authenticated
  using ((select yetkim('kullanici_yonetimi')));

-- Giriş kayıtları yalnız yetkisi olana
drop policy if exists okuma on giris_kayitlari;
create policy okuma on giris_kayitlari for select to authenticated
  using ((select yetkim('giris_kayitlari')) or kullanici_id = auth.uid());

-- ------------------------------------------------------------------
-- 9) Başarılı girişte kullanıcı satırı yoksa oluşturulur (Saha rolüyle)
-- ------------------------------------------------------------------
create or replace function giris_kaydet(p_platform text, p_surum text)
returns void language plpgsql security definer set search_path = public as $$
declare e text := auth.jwt()->>'email';
begin
  if auth.uid() is null then return; end if;
  insert into giris_kayitlari (kullanici_id, email, basarili, ip, platform, surum, tarayici)
  values (auth.uid(), e, true, istek_ip(),
          left(p_platform, 60), left(p_surum, 20),
          left(current_setting('request.headers', true)::json->>'user-agent', 300));
  insert into kullanicilar (id, ad, email, rol, aktif, updated_at)
  values (auth.uid()::text, coalesce(split_part(e, '@', 1), '-'), coalesce(e, '-'),
          'sahaKullanicisi', 1, simdi_ms())
  on conflict (id) do nothing;
end $$;

-- ------------------------------------------------------------------
-- 10) Anlık senkron (Realtime "zili")
-- ------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['yetkiler', 'bildirim_alicilari'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime'
                       and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ------------------------------------------------------------------
-- 11) İLK YÖNETİCİ: kendi giriş e-postanızı ekleyin (virgülle birden çok).
--     Diğer kullanıcıların rolünü sonra uygulamadan (Ayarlar → Kullanıcılar)
--     verirsiniz. Rol değişince updated_at artar, telefonlara geçer.
-- ------------------------------------------------------------------
update kullanicilar set rol = 'admin', updated_at = simdi_ms()
where lower(email) in ('test@test.com')
  and rol <> 'admin';

-- Sunucunun tablo ve sütun listesini hemen yenile
notify pgrst, 'reload schema';

-- Kontrol: yöneticiler
select ad, email, rol, aktif from kullanicilar order by rol, ad;
