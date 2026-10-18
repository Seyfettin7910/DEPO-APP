-- DEPO OTOMASYON SİSTEMİ 1.18.0: giriş kayıtları (kullanıcı + IP)
-- Supabase > SQL Editor'da bir kez çalıştırın. Tekrar çalıştırmak zararsızdır.
--
-- IP adresi telefondan değil, sunucunun gördüğü bağlantıdan alınır
-- (uygulama tarafından değiştirilemez). Kayıtlar uygulamadan okunabilir ama
-- kimse (yönetici dahil) uygulamadan değiştiremez veya silemez.

create table if not exists giris_kayitlari (
  id bigint generated always as identity primary key,
  tarih timestamptz not null default now(),
  kullanici_id uuid,
  email text,
  basarili boolean not null default true,
  ip text,
  platform text,
  surum text,
  tarayici text
);
create index if not exists giris_kayitlari_tarih_idx on giris_kayitlari (tarih desc);

alter table giris_kayitlari enable row level security;
revoke all on giris_kayitlari from anon, authenticated;
grant select on giris_kayitlari to authenticated;
drop policy if exists okuma on giris_kayitlari;
create policy okuma on giris_kayitlari for select to authenticated using (true);

-- İsteği yapanın IP adresi (Supabase'in ilettiği başlıklardan)
create or replace function istek_ip() returns text
language sql stable as $$
  select nullif(coalesce(
    current_setting('request.headers', true)::json->>'cf-connecting-ip',
    split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
    current_setting('request.headers', true)::json->>'x-real-ip'
  ), '')
$$;

-- Başarılı giriş: kullanıcı bilgisi oturumdan alınır
create or replace function giris_kaydet(p_platform text, p_surum text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into giris_kayitlari (kullanici_id, email, basarili, ip, platform, surum, tarayici)
  values (auth.uid(), auth.jwt()->>'email', true, istek_ip(),
          left(p_platform, 60), left(p_surum, 20),
          left(current_setting('request.headers', true)::json->>'user-agent', 300));
end $$;

-- Hatalı şifre denemesi (giriş yapılmadan çağrılır; aynı IP'den
-- 10 dakikada en fazla 20 kayıt alınır)
create or replace function hatali_giris_kaydet(p_email text, p_platform text, p_surum text)
returns void language plpgsql security definer set search_path = public as $$
declare v_ip text := istek_ip();
begin
  if (select count(*) from giris_kayitlari
      where basarili = false and ip is not distinct from v_ip
        and tarih > now() - interval '10 minutes') >= 20 then
    return;
  end if;
  insert into giris_kayitlari (email, basarili, ip, platform, surum, tarayici)
  values (left(lower(trim(p_email)), 120), false, v_ip,
          left(p_platform, 60), left(p_surum, 20),
          left(current_setting('request.headers', true)::json->>'user-agent', 300));
end $$;

revoke all on function giris_kaydet(text, text) from public;
revoke all on function hatali_giris_kaydet(text, text, text) from public;
grant execute on function giris_kaydet(text, text) to authenticated;
grant execute on function hatali_giris_kaydet(text, text, text) to anon, authenticated;
