-- DEPO OTOMASYON SİSTEMİ 1.30.0: ürün birleştirme
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * urunler.birlesti_id : bu ürün başka bir ürüne katıldıysa kalan ürünün id'si.
--   İnternetsizken eski ürünle kaydedilmiş cihaz / hareket sonradan gelirse
--   telefonlar bu bilgiyle kaydı kalan ürüne aktarır.
-- * Bu SQL çalıştırılana kadar birleştirme yine çalışır (cihazlar ve
--   hareketler taşınır); yalnız diğer telefonlar "hangi ürüne birleşti"
--   bilgisini alamaz.

alter table urunler add column if not exists birlesti_id text;

-- Sunucunun sütun listesini hemen yenile
notify pgrst, 'reload schema';
