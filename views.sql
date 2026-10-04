-- Power BI için görünümler (PostgreSQL)
-- Çalıştırma: psql -U postgres -d tedarik_kalite -f views.sql

DROP VIEW IF EXISTS v_supplier_scorecard;
DROP VIEW IF EXISTS v_order_facts;

-- Sipariş başına tek satır: sipariş + tedarikçi + parça + teslimat + kalite
CREATE VIEW v_order_facts AS
SELECT o.order_id,
       o.order_date,
       SUBSTR(CAST(o.order_date AS TEXT), 1, 7) AS siparis_ayi,
       o.promised_date,
       d.delivery_date,
       s.supplier_id,
       s.supplier_name,
       s.country,
       s.primary_category AS tedarikci_kategori,
       p.part_code,
       p.part_name,
       p.category AS parca_kategori,
       o.quantity,
       o.unit_price_usd,
       o.quantity * o.unit_price_usd AS siparis_tutar_usd,
       d.delivered_qty,
       CASE WHEN d.delivery_id IS NULL THEN 'Açık sipariş' ELSE 'Teslim edildi' END AS durum,
       d.delivery_date - o.promised_date AS gecikme_gun,
       CASE WHEN d.delivery_id IS NULL THEN NULL
            WHEN d.delivery_date > o.promised_date THEN 1
            ELSE 0 END AS gec_mi,
       q.inspected_qty,
       q.rejected_qty,
       q.reject_reason
FROM orders o
JOIN suppliers s ON s.supplier_id = o.supplier_id
JOIN parts p ON p.part_id = o.part_id
LEFT JOIN deliveries d ON d.order_id = o.order_id
LEFT JOIN quality_inspections q ON q.delivery_id = d.delivery_id;

-- Tedarikçi başına tek satır: karne
CREATE VIEW v_supplier_scorecard AS
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
       s.country,
       s.primary_category,
       t.siparis,
       ROUND(t.gec_yuzde, 1) AS gec_yuzde,
       ROUND(k.red_yuzde, 2) AS red_yuzde,
       ROUND(t.harcama_usd, 0) AS harcama_usd,
       CASE WHEN t.siparis < 30 THEN 'Yetersiz veri'
            WHEN t.gec_yuzde >= 30 AND k.red_yuzde >= 5 THEN 'Yüksek risk'
            WHEN t.gec_yuzde >= 30 OR k.red_yuzde >= 5 THEN 'İzlenmeli'
            ELSE 'Normal' END AS risk_sinifi
FROM suppliers s
JOIN teslimat t ON t.supplier_id = s.supplier_id
JOIN kalite k ON k.supplier_id = s.supplier_id;
