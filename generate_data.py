"""
Sentetik tedarik ve kalite verisi üretici.

Tüm tedarikçi adları, parçalar, siparişler ve sonuçlar KURGUSALDIR; gerçek bir firmayı
veya gerçek tedarik verisini temsil etmez. Amaç, SQL analiz yöntemini göstermektir.

Kullanım:
    python generate_data.py --out data
"""
import argparse
import os

import numpy as np
import pandas as pd

SEED = 42
START = pd.Timestamp("2024-01-01")
LAST_ORDER = pd.Timestamp("2026-09-20")
CUTOFF = pd.Timestamp("2026-09-30")  # veri kesim tarihi: sonrasında teslim edilenler henüz "açık sipariş"
N_ORDERS = 3200

# kategori: (kod, ortalama termin günü, birim maliyet aralığı USD, red çarpanı, tipik sipariş adedi, parça adları)
CATEGORIES = {
    "Metal Parça": ("MTL", 21, (15, 400), 1.0, 120, ["Braket", "Mil", "Flanş", "Gövde", "Burç"]),
    "Elektronik Kart": ("ELK", 45, (60, 1500), 1.6, 60, ["Güç Kartı", "Kontrol Kartı", "Sensör Kartı", "Arayüz Kartı", "Röle Kartı"]),
    "Kablaj": ("KBL", 28, (20, 600), 1.1, 80, ["Ana Kablo Demeti", "Sensör Kablosu", "Güç Kablosu", "Veri Kablosu", "Topraklama Seti"]),
    "Hidrolik": ("HDR", 35, (80, 2500), 1.2, 25, ["Pompa", "Valf", "Silindir", "Hortum Grubu", "Akümülatör"]),
    "Kompozit": ("KMP", 40, (100, 3000), 1.4, 20, ["Panel", "Kaporta", "Takviye Plakası", "Kanat Kaplaması", "Muhafaza"]),
    "Optik": ("OPT", 50, (200, 5000), 1.3, 15, ["Lens Grubu", "Prizma", "Koruyucu Cam", "Filtre", "Sensör Penceresi"]),
    "Bağlantı Elemanı": ("BGL", 14, (1, 40), 0.7, 1500, ["Cıvata", "Somun", "Pul", "Perçin", "Kelepçe"]),
    "Isıl İşlem/Kaplama": ("ISL", 10, (5, 120), 0.9, 200, ["Sertleştirme", "Anodizasyon", "Boya Kaplama", "Nitrürleme", "Kadmiyumsuz Kaplama"]),
}
VARIANTS = ["A", "B", "C"]

REGIONS = ["Kuzey", "Marmara", "Ege", "Toros", "Akdeniz", "Karadeniz", "Anadolu", "Trakya",
           "Yıldız", "Çınar", "Bozkır", "Kızılırmak", "Fırat", "Sakarya", "Meriç", "Zirve",
           "Ova", "Pınar", "Doruk", "Ufuk", "Bereket", "Güney", "Batı", "Altın"]
SECTOR_WORDS = {
    "Metal Parça": "Metal Sanayi", "Elektronik Kart": "Elektronik", "Kablaj": "Kablaj Sistemleri",
    "Hidrolik": "Hidrolik", "Kompozit": "Kompozit", "Optik": "Optik Sistemler",
    "Bağlantı Elemanı": "Bağlantı Elemanları", "Isıl İşlem/Kaplama": "Yüzey İşlemleri",
}
LOCATIONS = [("Türkiye", c) for c in ["Ankara", "İstanbul", "Kocaeli", "Bursa", "İzmir", "Eskişehir", "Konya", "Kayseri", "Sakarya"]]
FOREIGN = [("Almanya", "Stuttgart"), ("İtalya", "Torino"), ("Fransa", "Toulouse"), ("Polonya", "Rzeszów")]

REASONS = ["Boyutsal sapma", "Yüzey kusuru", "Malzeme uygunsuzluğu", "Dokümantasyon eksikliği", "Fonksiyon testi başarısız"]
REASON_W_DEFAULT = np.array([0.30, 0.25, 0.20, 0.15, 0.10])
REASON_W_ELEC = np.array([0.10, 0.10, 0.15, 0.20, 0.45])


def make_suppliers(rng):
    cats = list(CATEGORIES)
    # 3 tedarikçi/kategori, karışık sırada
    primary = rng.permutation([c for c in cats for _ in range(3)])
    # davranış profilleri: (gecikme olasılığı, ort. gecikme günü, temel red oranı)
    profiles = []
    for _ in range(3):   # hem geç hem kalitesiz
        profiles.append((rng.uniform(0.38, 0.45), 12, rng.uniform(0.06, 0.08)))
    for _ in range(2):   # geç ama kaliteli
        profiles.append((rng.uniform(0.35, 0.40), 9, rng.uniform(0.008, 0.015)))
    for _ in range(2):   # zamanında ama kalite zayıf
        profiles.append((rng.uniform(0.05, 0.08), 4, rng.uniform(0.06, 0.07)))
    while len(profiles) < 24:
        profiles.append((rng.uniform(0.05, 0.20), rng.uniform(3, 8), rng.uniform(0.008, 0.03)))
    profiles = [profiles[i] for i in rng.permutation(24)]

    regions = rng.permutation(REGIONS)[:24]
    rows, traits = [], {}
    for i in range(24):
        cat = primary[i]
        if i < 4:
            country, city = FOREIGN[i]
        else:
            country, city = LOCATIONS[int(rng.integers(len(LOCATIONS)))]
        name = f"{regions[i]} {SECTOR_WORDS[cat]}"
        sid = i + 1
        rows.append((sid, name, country, city, cat))
        secondary = [c for c in cats if c != cat]
        cat_list = [cat] + ([secondary[int(rng.integers(len(secondary)))]] if rng.random() < 0.4 else [])
        late_p, mean_delay, reject = profiles[i]
        traits[sid] = dict(cats=cat_list, late_p=late_p, mean_delay=mean_delay, reject=reject)
    df = pd.DataFrame(rows, columns=["supplier_id", "supplier_name", "country", "city", "primary_category"])
    return df, traits


def make_parts(rng):
    rows, pid = [], 1
    for cat, (code, _lead, (lo, hi), _m, _q, names) in CATEGORIES.items():
        i = 1
        for n in names:
            for v in VARIANTS:
                cost = round(float(np.exp(rng.uniform(np.log(lo), np.log(hi)))), 2)
                rows.append((pid, f"{code}-{i:03d}", f"{n} {v}", cat, cost))
                pid += 1
                i += 1
    return pd.DataFrame(rows, columns=["part_id", "part_code", "part_name", "category", "std_cost_usd"])


def main(out_dir):
    rng = np.random.default_rng(SEED)
    os.makedirs(out_dir, exist_ok=True)
    suppliers, traits = make_suppliers(rng)
    parts = make_parts(rng)
    parts_by_cat = {c: parts[parts.category == c] for c in CATEGORIES}

    # tedarikçi hacimleri eşit değil
    weights = rng.dirichlet(np.ones(24) * 2.0)
    sup_ids = suppliers.supplier_id.to_numpy()

    span = (LAST_ORDER - START).days
    orders = []
    for _ in range(N_ORDERS):
        sid = int(rng.choice(sup_ids, p=weights))
        cat = traits[sid]["cats"][int(rng.integers(len(traits[sid]["cats"])))]
        part = parts_by_cat[cat].iloc[int(rng.integers(len(parts_by_cat[cat])))]
        _code, lead, _c, _m, qmed, _n = CATEGORIES[cat]
        order_date = START + pd.Timedelta(days=int(rng.integers(0, span + 1)))
        promised = order_date + pd.Timedelta(days=max(5, lead + int(rng.normal(0, 3))))
        qty = max(1, int(rng.lognormal(np.log(qmed), 0.8)))
        price = round(float(part.std_cost_usd) * rng.uniform(0.95, 1.08), 2)
        orders.append((sid, int(part.part_id), order_date, promised, qty, price, cat))
    orders = pd.DataFrame(orders, columns=["supplier_id", "part_id", "order_date", "promised_date",
                                           "quantity", "unit_price_usd", "cat_name"])
    orders = orders.sort_values(["order_date", "supplier_id"]).reset_index(drop=True)
    orders.insert(0, "order_id", orders.index + 1)

    deliveries, inspections = [], []
    for o in orders.itertuples():
        t = traits[o.supplier_id]
        if rng.random() < t["late_p"]:
            delay = 1 + int(rng.exponential(t["mean_delay"]))
        else:
            delay = -int(rng.integers(0, 6))
        d_date = o.promised_date + pd.Timedelta(days=delay)
        if d_date > CUTOFF:
            continue  # açık sipariş: henüz teslim yok
        qty = o.quantity
        if qty > 1 and rng.random() < 0.06:
            qty = max(1, int(qty * rng.uniform(0.6, 0.95)))
        did = len(deliveries) + 1
        deliveries.append((did, o.order_id, d_date, qty))

        mult = CATEGORIES[o.cat_name][3]
        p = t["reject"] * mult * rng.lognormal(0, 0.25)
        if delay > 10:
            p *= 1.3
        p = min(p, 0.25)
        inspected = qty if qty <= 50 else max(50, int(np.ceil(0.2 * qty)))
        rejected = int(rng.binomial(inspected, p))
        reason = None
        if rejected > 0:
            w = REASON_W_ELEC if o.cat_name == "Elektronik Kart" else REASON_W_DEFAULT
            reason = str(rng.choice(REASONS, p=w))
        insp_date = d_date + pd.Timedelta(days=int(rng.integers(1, 4)))
        inspections.append((len(inspections) + 1, did, insp_date, inspected, rejected, reason))

    deliveries = pd.DataFrame(deliveries, columns=["delivery_id", "order_id", "delivery_date", "delivered_qty"])
    inspections = pd.DataFrame(inspections, columns=["inspection_id", "delivery_id", "inspection_date",
                                                     "inspected_qty", "rejected_qty", "reject_reason"])
    orders = orders.drop(columns="cat_name")

    for df, cols in ((orders, ["order_date", "promised_date"]), (deliveries, ["delivery_date"]),
                     (inspections, ["inspection_date"])):
        for c in cols:
            df[c] = df[c].dt.strftime("%Y-%m-%d")

    for name, df in (("suppliers", suppliers), ("parts", parts), ("orders", orders),
                     ("deliveries", deliveries), ("quality_inspections", inspections)):
        df.to_csv(os.path.join(out_dir, f"{name}.csv"), index=False, encoding="utf-8")
        print(f"{name}: {len(df)} satır")
    print(f"Açık sipariş (teslim edilmemiş): {len(orders) - len(deliveries)}")
    print(f"CSV dosyaları '{out_dir}' klasörüne yazıldı.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data")
    main(ap.parse_args().out)
