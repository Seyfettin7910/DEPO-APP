-- Yedek sayımı: her tablonun satır sayısı ("şema.tablo|adet").
-- Döküm alınırken ve geri yükleme denemesinde aynı sorgu çalışır,
-- iki sonuç birebir aynı olmalı. (Kullanım: .github/workflows/yedek.yml)
select t.table_schema || '.' || t.table_name,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from %I.%I',
                                  t.table_schema, t.table_name),
                           false, true, '')))[1]::text
from information_schema.tables t
where t.table_type = 'BASE TABLE'
  and (t.table_schema = 'public'
       or (t.table_schema = 'auth' and t.table_name = 'users'))
order by 1;
