// Seeds an active Price Book + 15 Urla Shoes products + price book entries.
// Idempotent: safe to re-run (skips products/entries that already exist).

// 1) Activate the standard price book
Pricebook2 std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
if (!std.IsActive) { std.IsActive = true; update std; }

// 2) Custom price book
List<Pricebook2> customs = [SELECT Id FROM Pricebook2 WHERE Name = 'Urla Shoes Price Book' LIMIT 1];
Pricebook2 custom = customs.isEmpty()
    ? new Pricebook2(Name = 'Urla Shoes Price Book', IsActive = true, Description = 'Urla Shoes wholesale catalogue')
    : customs[0];
if (custom.Id == null) { insert custom; }

// 3) Catalog: code -> {name, price}
Map<String, String> names = new Map<String, String>{
    'URLA-1001' => 'Classic Leather Derby',      'URLA-1002' => 'Chelsea Boot Waterproof',
    'URLA-2005' => 'Urban Running Sneaker',      'URLA-2011' => 'Trail Hiking Boot',
    'URLA-3007' => 'Kids School Shoe',           'URLA-4002' => 'Safety Work Shoe S3',
    'URLA-1015' => 'Suede Loafer',               'URLA-2020' => 'Canvas Slip-On',
    'URLA-5003' => 'Winter Snow Boot',           'URLA-6001' => 'Ballerina Flat',
    'URLA-1030' => 'Oxford Business Shoe',        'URLA-7004' => 'Comfort Sandal',
    'URLA-2033' => 'High-Top Basketball Shoe',   'URLA-8002' => 'Summer Espadrille',
    'URLA-9005' => 'Orthopedic Walking Shoe'
};
Map<String, Decimal> prices = new Map<String, Decimal>{
    'URLA-1001' => 89.90,  'URLA-1002' => 119.90, 'URLA-2005' => 74.90,  'URLA-2011' => 139.90,
    'URLA-3007' => 49.90,  'URLA-4002' => 99.90,  'URLA-1015' => 84.90,  'URLA-2020' => 39.90,
    'URLA-5003' => 129.90, 'URLA-6001' => 59.90,  'URLA-1030' => 109.90, 'URLA-7004' => 44.90,
    'URLA-2033' => 94.90,  'URLA-8002' => 34.90,  'URLA-9005' => 114.90
};

// 4) Create missing products
Set<String> existing = new Set<String>();
for (Product2 p : [SELECT ProductCode FROM Product2 WHERE ProductCode IN :names.keySet()]) existing.add(p.ProductCode);
List<Product2> toCreate = new List<Product2>();
for (String code : names.keySet()) {
    if (!existing.contains(code)) {
        toCreate.add(new Product2(Name = names.get(code), ProductCode = code, IsActive = true, Family = 'Footwear'));
    }
}
if (!toCreate.isEmpty()) insert toCreate;

// 5) Map products by code
Map<String, Product2> prodByCode = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :names.keySet()]) prodByCode.put(p.ProductCode, p);

// 6) Standard price book entries (required before custom entries)
Set<Id> hasStd = new Set<Id>();
for (PricebookEntry e : [SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :std.Id AND Product2Id IN :prodByCode.values()]) hasStd.add(e.Product2Id);
List<PricebookEntry> stdEntries = new List<PricebookEntry>();
for (String code : prodByCode.keySet()) {
    Product2 p = prodByCode.get(code);
    if (!hasStd.contains(p.Id)) stdEntries.add(new PricebookEntry(Pricebook2Id = std.Id, Product2Id = p.Id, UnitPrice = prices.get(code), IsActive = true));
}
if (!stdEntries.isEmpty()) insert stdEntries;

// 7) Custom price book entries
Set<Id> hasCustom = new Set<Id>();
for (PricebookEntry e : [SELECT Product2Id FROM PricebookEntry WHERE Pricebook2Id = :custom.Id]) hasCustom.add(e.Product2Id);
List<PricebookEntry> custEntries = new List<PricebookEntry>();
for (String code : prodByCode.keySet()) {
    Product2 p = prodByCode.get(code);
    if (!hasCustom.contains(p.Id)) custEntries.add(new PricebookEntry(Pricebook2Id = custom.Id, Product2Id = p.Id, UnitPrice = prices.get(code), IsActive = true));
}
if (!custEntries.isEmpty()) insert custEntries;

System.debug('DIAG standardActive=' + std.IsActive + ' customPbId=' + custom.Id
    + ' products=' + prodByCode.size() + ' newProducts=' + toCreate.size()
    + ' newStdEntries=' + stdEntries.size() + ' newCustomEntries=' + custEntries.size());
