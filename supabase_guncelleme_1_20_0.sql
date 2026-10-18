-- DEPO OTOMASYON SİSTEMİ 1.20.0: iPhone ve bilgisayar tarayıcısına bildirim (web push)
-- Supabase > SQL Editor'da bir kez çalıştırın. Tekrar çalıştırmak zararsızdır.
--
-- Hiçbir gizli anahtar elle girilmez: bildirim anahtarları ilk çalışmada
-- sunucudaki fonksiyon tarafından üretilip bu tablolarda saklanır. Tablolar
-- uygulamadan okunamaz (yalnızca aşağıdaki fonksiyonlar üzerinden).

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Sunucu ayarları (bildirim anahtarları, imleçler, zamanlayıcı anahtarı)
create table if not exists push_ayar (
  ad text primary key,
  deger text not null
);
alter table push_ayar enable row level security;
revoke all on push_ayar from anon, authenticated;

-- Zamanlayıcının fonksiyonu çağırırken kullandığı rastgele anahtar
insert into push_ayar (ad, deger)
values ('cron_anahtar', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (ad) do nothing;

-- Bildirim abonelikleri (her tarayıcı / iPhone bir kayıt)
create table if not exists push_abonelikleri (
  id bigint generated always as identity primary key,
  kullanici_id uuid not null,
  email text,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  ayarlar jsonb not null default '{}'::jsonb,
  platform text,
  olusturma timestamptz not null default now(),
  guncelleme timestamptz not null default now()
);
alter table push_abonelikleri enable row level security;
revoke all on push_abonelikleri from anon, authenticated;

-- Abone başına "bu olay bildirildi" işaretleri
create table if not exists push_gorulen (
  abonelik_id bigint not null references push_abonelikleri(id) on delete cascade,
  anahtar text not null,
  tarih timestamptz not null default now(),
  primary key (abonelik_id, anahtar)
);
alter table push_gorulen enable row level security;
revoke all on push_gorulen from anon, authenticated;

-- İşlenmiş hareketler (aynı hareket iki kez bildirilmesin)
create table if not exists push_islenen (
  anahtar text primary key,
  tarih timestamptz not null default now()
);
alter table push_islenen enable row level security;
revoke all on push_islenen from anon, authenticated;

-- Uygulamanın abone olurken kullandığı genel (gizli olmayan) anahtar
create or replace function push_genel_anahtar() returns text
language sql stable security definer set search_path = public as $$
  select deger from push_ayar where ad = 'vapid_genel'
$$;

create or replace function push_abone_ol(
  p_endpoint text, p_p256dh text, p_auth text, p_ayarlar jsonb, p_platform text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Giriş gerekli'; end if;
  insert into push_abonelikleri (kullanici_id, email, endpoint, p256dh, auth, ayarlar, platform)
  values (auth.uid(), auth.jwt()->>'email', p_endpoint, p_p256dh, p_auth,
          coalesce(p_ayarlar, '{}'::jsonb), left(p_platform, 80))
  on conflict (endpoint) do update set
    kullanici_id = excluded.kullanici_id, email = excluded.email,
    p256dh = excluded.p256dh, auth = excluded.auth, ayarlar = excluded.ayarlar,
    platform = excluded.platform, guncelleme = now();
end $$;

create or replace function push_abonelik_sil(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  delete from push_abonelikleri where endpoint = p_endpoint and kullanici_id = auth.uid()
$$;

revoke all on function push_genel_anahtar() from public;
revoke all on function push_abone_ol(text, text, text, jsonb, text) from public;
revoke all on function push_abonelik_sil(text) from public;
grant execute on function push_genel_anahtar() to authenticated;
grant execute on function push_abone_ol(text, text, text, jsonb, text) to authenticated;
grant execute on function push_abonelik_sil(text) to authenticated;

-- 2 dakikada bir bildirim fonksiyonunu çalıştır
select cron.schedule('bildirim-gonder', '*/2 * * * *', $$
  select net.http_post(
    url := 'https://xxnzfqtwtfzltjkjteco.supabase.co/functions/v1/bildirim-gonder',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-anahtar', (select deger from public.push_ayar where ad = 'cron_anahtar')),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  )
$$);
