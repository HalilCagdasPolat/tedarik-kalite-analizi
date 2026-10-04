-- Tedarik ve kalite analizi: PostgreSQL şeması
-- Tüm veri kurgusaldır (generate_data.py ile üretilir).

DROP TABLE IF EXISTS quality_inspections, deliveries, orders, parts, suppliers CASCADE;

CREATE TABLE suppliers (
    supplier_id       INT PRIMARY KEY,
    supplier_name     TEXT NOT NULL,
    country           TEXT NOT NULL,
    city              TEXT NOT NULL,
    primary_category  TEXT NOT NULL
);

CREATE TABLE parts (
    part_id        INT PRIMARY KEY,
    part_code      TEXT NOT NULL UNIQUE,
    part_name      TEXT NOT NULL,
    category       TEXT NOT NULL,
    std_cost_usd   NUMERIC(10,2) NOT NULL
);

CREATE TABLE orders (
    order_id        INT PRIMARY KEY,
    supplier_id     INT NOT NULL REFERENCES suppliers (supplier_id),
    part_id         INT NOT NULL REFERENCES parts (part_id),
    order_date      DATE NOT NULL,
    promised_date   DATE NOT NULL,
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price_usd  NUMERIC(10,2) NOT NULL
);

-- Her siparişin en fazla bir teslimatı var; teslimatı olmayan sipariş "açık sipariştir".
CREATE TABLE deliveries (
    delivery_id     INT PRIMARY KEY,
    order_id        INT NOT NULL UNIQUE REFERENCES orders (order_id),
    delivery_date   DATE NOT NULL,
    delivered_qty   INT NOT NULL CHECK (delivered_qty > 0)
);

CREATE TABLE quality_inspections (
    inspection_id    INT PRIMARY KEY,
    delivery_id      INT NOT NULL UNIQUE REFERENCES deliveries (delivery_id),
    inspection_date  DATE NOT NULL,
    inspected_qty    INT NOT NULL CHECK (inspected_qty > 0),
    rejected_qty     INT NOT NULL CHECK (rejected_qty >= 0 AND rejected_qty <= inspected_qty),
    reject_reason    TEXT
);

CREATE INDEX idx_orders_supplier ON orders (supplier_id);
CREATE INDEX idx_orders_part ON orders (part_id);
