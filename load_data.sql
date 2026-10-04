-- psql içinden, proje klasöründeyken çalıştırın:
--   \i load_data.sql
-- (\copy komutları yolu psql'in çalıştığı klasöre göre okur.)

\copy suppliers FROM 'data/suppliers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy parts FROM 'data/parts.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy orders FROM 'data/orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy deliveries FROM 'data/deliveries.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy quality_inspections FROM 'data/quality_inspections.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
