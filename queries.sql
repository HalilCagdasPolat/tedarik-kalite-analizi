-- Tedarik ve kalite analizi: SQL sorguları (PostgreSQL)
-- Veri kurgusaldır; sonuçlar bu veri setine aittir, gerçek bir firmayı yansıtmaz.
-- Veri kesim tarihi: 2026-09-30 (bu tarihten sonra teslim edilecek siparişler "açık sipariş" sayılır).
-- Eşikler (%30 gecikme, %5 red, en az 30 teslimat) örnek amaçlı seçilmiştir.

-- Q1. Veri kontrolü: tablo satır sayıları
SELECT 'suppliers' AS tablo, COUNT(*) AS satir FROM suppliers
UNION ALL SELECT 'parts', COUNT(*) FROM parts
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'deliveries', COUNT(*) FROM deliveries
UNION ALL SELECT 'quality_inspections', COUNT(*) FROM quality_inspections;

-- Q2. Hangi tedarikçiler en çok geç teslim ediyor? (JOIN + FILTER + HAVING)
SELECT s.supplier_id,
       s.supplier_name,
       COUNT(*) AS teslim_edilen_siparis,
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.delivery_date > o.promised_date) / COUNT(*), 1) AS gec_teslim_yuzde,
       ROUND(AVG(d.delivery_date - o.promised_date) FILTER (WHERE d.delivery_date > o.promised_date), 1) AS ort_gecikme_gun
FROM suppliers s
JOIN orders o ON o.supplier_id = s.supplier_id
JOIN deliveries d ON d.order_id = o.order_id
GROUP BY s.supplier_id, s.supplier_name
HAVING COUNT(*) >= 30
ORDER BY gec_teslim_yuzde DESC;

-- Q3. Tedarikçi bazında red oranı
SELECT s.supplier_id,
       s.supplier_name,
       COUNT(*) AS teslimat,
       SUM(q.inspected_qty) AS kontrol_edilen_adet,
       SUM(q.rejected_qty) AS reddedilen_adet,
       ROUND(100.0 * SUM(q.rejected_qty) / SUM(q.inspected_qty), 2) AS red_yuzde
FROM suppliers s
JOIN orders o ON o.supplier_id = s.supplier_id
JOIN deliveries d ON d.order_id = o.order_id
JOIN quality_inspections q ON q.delivery_id = d.delivery_id
GROUP BY s.supplier_id, s.supplier_name
HAVING COUNT(*) >= 30
ORDER BY red_yuzde DESC;

-- Q4. Tedarikçi karnesi: gecikme ve kalite birlikte (CTE)
WITH teslimat AS (
    SELECT o.supplier_id,
           COUNT(*) AS siparis,
           100.0 * COUNT(*) FILTER (WHERE d.delivery_date > o.promised_date) / COUNT(*) AS gec_yuzde,
           SUM(o.quantity * o.unit_price_usd) AS harcama_usd
    FROM orders o
    JOIN deliveries d ON d.order_id = o.order_id
    GROUP BY o.supplier_id
), kalite AS (
    SELECT o.supplier_id,
           100.0 * SUM(q.rejected_qty) / SUM(q.inspected_qty) AS red_yuzde
    FROM orders o
    JOIN deliveries d ON d.order_id = o.order_id
    JOIN quality_inspections q ON q.delivery_id = d.delivery_id
    GROUP BY o.supplier_id
)
SELECT s.supplier_id,
       s.supplier_name,
       s.primary_category,
       t.siparis,
       ROUND(t.gec_yuzde, 1) AS gec_yuzde,
       ROUND(k.red_yuzde, 2) AS red_yuzde,
       ROUND(t.harcama_usd, 0) AS harcama_usd,
       CASE WHEN t.gec_yuzde >= 30 AND k.red_yuzde >= 5 THEN 'Yüksek risk'
            WHEN t.gec_yuzde >= 30 OR k.red_yuzde >= 5 THEN 'İzlenmeli'
            ELSE 'Normal' END AS risk_sinifi
FROM suppliers s
JOIN teslimat t ON t.supplier_id = s.supplier_id
JOIN kalite k ON k.supplier_id = s.supplier_id
WHERE t.siparis >= 30
ORDER BY t.gec_yuzde DESC, k.red_yuzde DESC;

-- Q5. Parça kategorisine göre red oranı ve en sık red nedeni (CTE + ROW_NUMBER)
WITH neden AS (
    SELECT p.category,
           q.reject_reason,
           SUM(q.rejected_qty) AS adet,
           ROW_NUMBER() OVER (PARTITION BY p.category ORDER BY SUM(q.rejected_qty) DESC) AS sira
    FROM quality_inspections q
    JOIN deliveries d ON d.delivery_id = q.delivery_id
    JOIN orders o ON o.order_id = d.order_id
    JOIN parts p ON p.part_id = o.part_id
    WHERE q.rejected_qty > 0
    GROUP BY p.category, q.reject_reason
), kategori AS (
    SELECT p.category,
           100.0 * SUM(q.rejected_qty) / SUM(q.inspected_qty) AS red_yuzde
    FROM quality_inspections q
    JOIN deliveries d ON d.delivery_id = q.delivery_id
    JOIN orders o ON o.order_id = d.order_id
    JOIN parts p ON p.part_id = o.part_id
    GROUP BY p.category
)
SELECT k.category,
       ROUND(k.red_yuzde, 2) AS red_yuzde,
       n.reject_reason AS en_sik_red_nedeni
FROM kategori k
JOIN neden n ON n.category = k.category AND n.sira = 1
ORDER BY k.red_yuzde DESC;

-- Q6. Aylık gecikme trendi: önceki aya göre fark ve 3 aylık hareketli ortalama (LAG + pencere)
WITH aylik AS (
    SELECT SUBSTR(CAST(o.promised_date AS TEXT), 1, 7) AS ay,
           COUNT(*) AS teslimat,
           100.0 * COUNT(*) FILTER (WHERE d.delivery_date > o.promised_date) / COUNT(*) AS gec_yuzde
    FROM orders o
    JOIN deliveries d ON d.order_id = o.order_id
    GROUP BY SUBSTR(CAST(o.promised_date AS TEXT), 1, 7)
)
SELECT ay,
       teslimat,
       ROUND(gec_yuzde, 1) AS gec_yuzde,
       ROUND(gec_yuzde - LAG(gec_yuzde) OVER (ORDER BY ay), 1) AS onceki_aya_gore_fark,
       ROUND(AVG(gec_yuzde) OVER (ORDER BY ay ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS hareketli_ort_3ay
FROM aylik
ORDER BY ay;

-- Q7. Açık siparişler: teslimatı olmayan siparişler (LEFT JOIN + IS NULL)
SELECT s.supplier_id,
       s.supplier_name,
       COUNT(*) AS acik_siparis,
       COUNT(*) FILTER (WHERE o.promised_date < '2026-09-30') AS vadesi_gecmis,
       ROUND(SUM(o.quantity * o.unit_price_usd), 0) AS acik_tutar_usd
FROM orders o
JOIN suppliers s ON s.supplier_id = o.supplier_id
LEFT JOIN deliveries d ON d.order_id = o.order_id
WHERE d.order_id IS NULL
GROUP BY s.supplier_id, s.supplier_name
ORDER BY acik_tutar_usd DESC;

-- Q8. Kategori içinde tedarikçi sıralaması: red oranı (RANK + PARTITION BY)
WITH kalite AS (
    SELECT s.supplier_id,
           s.supplier_name,
           s.primary_category,
           COUNT(*) AS teslimat,
           100.0 * SUM(q.rejected_qty) / SUM(q.inspected_qty) AS red_yuzde
    FROM suppliers s
    JOIN orders o ON o.supplier_id = s.supplier_id
    JOIN deliveries d ON d.order_id = o.order_id
    JOIN quality_inspections q ON q.delivery_id = d.delivery_id
    GROUP BY s.supplier_id, s.supplier_name, s.primary_category
    HAVING COUNT(*) >= 30
)
SELECT primary_category,
       supplier_name,
       ROUND(red_yuzde, 2) AS red_yuzde,
       RANK() OVER (PARTITION BY primary_category ORDER BY red_yuzde DESC) AS kategori_ici_sira
FROM kalite
ORDER BY primary_category, kategori_ici_sira;

-- Q9. Harcama dağılımı ve kümülatif pay (Pareto, pencere fonksiyonu)
WITH harcama AS (
    SELECT s.supplier_id,
           s.supplier_name,
           SUM(o.quantity * o.unit_price_usd) AS tutar
    FROM orders o
    JOIN suppliers s ON s.supplier_id = o.supplier_id
    GROUP BY s.supplier_id, s.supplier_name
)
SELECT supplier_name,
       ROUND(tutar, 0) AS tutar_usd,
       ROUND(100.0 * tutar / SUM(tutar) OVER (), 1) AS pay_yuzde,
       ROUND(100.0 * SUM(tutar) OVER (ORDER BY tutar DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(tutar) OVER (), 1) AS kumulatif_pay_yuzde
FROM harcama
ORDER BY tutar DESC;

-- Q10. Gecikme ile red oranı ilişkisi (CASE ile gruplama)
SELECT CASE WHEN d.delivery_date <= o.promised_date THEN '1) Zamanında / erken'
            WHEN (d.delivery_date - o.promised_date) <= 7 THEN '2) 1-7 gün gecikme'
            WHEN (d.delivery_date - o.promised_date) <= 14 THEN '3) 8-14 gün gecikme'
            ELSE '4) 15+ gün gecikme' END AS gecikme_grubu,
       COUNT(*) AS teslimat,
       ROUND(100.0 * SUM(q.rejected_qty) / SUM(q.inspected_qty), 2) AS red_yuzde
FROM orders o
JOIN deliveries d ON d.order_id = o.order_id
JOIN quality_inspections q ON q.delivery_id = d.delivery_id
GROUP BY 1
ORDER BY 1;

-- Q11. En yüksek red oranlı parçalar (en az 15 teslimat)
SELECT p.part_code,
       p.part_name,
       p.category,
       COUNT(*) AS teslimat,
       SUM(q.rejected_qty) AS reddedilen_adet,
       ROUND(100.0 * SUM(q.rejected_qty) / SUM(q.inspected_qty), 2) AS red_yuzde
FROM parts p
JOIN orders o ON o.part_id = p.part_id
JOIN deliveries d ON d.order_id = o.order_id
JOIN quality_inspections q ON q.delivery_id = d.delivery_id
GROUP BY p.part_id, p.part_code, p.part_name, p.category
HAVING COUNT(*) >= 15
ORDER BY red_yuzde DESC
LIMIT 10;

-- Q12. Eksik teslimat ve karşılama oranı (sipariş edilen adedin ne kadarı geldi)
SELECT s.supplier_id,
       s.supplier_name,
       COUNT(*) AS teslimat,
       COUNT(*) FILTER (WHERE d.delivered_qty < o.quantity) AS eksik_teslimat,
       ROUND(100.0 * SUM(d.delivered_qty) / SUM(o.quantity), 1) AS karsilama_yuzde
FROM suppliers s
JOIN orders o ON o.supplier_id = s.supplier_id
JOIN deliveries d ON d.order_id = o.order_id
GROUP BY s.supplier_id, s.supplier_name
HAVING COUNT(*) >= 30
ORDER BY karsilama_yuzde ASC;
