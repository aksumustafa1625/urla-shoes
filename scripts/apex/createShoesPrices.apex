// ----------------------------
// STEP 1: CREATE PRODUCTS
// ----------------------------

List<Product2> products = new List<Product2>{

    // BRONZE
    new Product2(Name='Urban Basic',      ProductCode='URB-001', Family='Bronze', IsActive=true,
        Description='Comfortable everyday sneaker for urban use'),
    new Product2(Name='City Walker',      ProductCode='URB-002', Family='Bronze', IsActive=true,
        Description='Lightweight walking shoe for daily commute'),
    new Product2(Name='Street Step',      ProductCode='URB-003', Family='Bronze', IsActive=true,
        Description='Durable street shoe with classic design'),

    // SILVER
    new Product2(Name='Sport Pro',        ProductCode='SLV-001', Family='Silver', IsActive=true,
        Description='Performance sport shoe for active lifestyle'),
    new Product2(Name='Comfort Elite',    ProductCode='SLV-002', Family='Silver', IsActive=true,
        Description='Premium comfort shoe with memory foam sole'),
    new Product2(Name='Urban Flex',       ProductCode='SLV-003', Family='Silver', IsActive=true,
        Description='Flexible hybrid shoe for work and casual'),

    // GOLD
    new Product2(Name='Prestige Run',     ProductCode='GLD-001', Family='Gold', IsActive=true,
        Description='High-performance running shoe with carbon plate'),
    new Product2(Name='Executive Walk',   ProductCode='GLD-002', Family='Gold', IsActive=true,
        Description='Luxury leather shoe for business professionals'),
    new Product2(Name='Luxe Stride',      ProductCode='GLD-003', Family='Gold', IsActive=true,
        Description='Premium stride shoe with Italian leather'),

    // PLATINUM
    new Product2(Name='Signature Edition',   ProductCode='PLT-001', Family='Platinum', IsActive=true,
        Description='Limited edition hand-crafted signature shoe'),
    new Product2(Name='Master Collection',   ProductCode='PLT-002', Family='Platinum', IsActive=true,
        Description='Exclusive collection with custom embroidery'),
    new Product2(Name='Icon Series',         ProductCode='PLT-003', Family='Platinum', IsActive=true,
        Description='Ultra-premium icon series with gold detailing')
};

insert products;
System.debug('✅ Products inserted: ' + products.size());

// ----------------------------
// STEP 2: STANDARD PRICE BOOK ENTRIES
// ----------------------------

Id standardPbId = Test.isRunningTest()
    ? Test.getStandardPricebookId()
    : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

Map<String, Decimal> standardPrices = new Map<String, Decimal>{
    'URB-001' => 49.99,  'URB-002' => 54.99,  'URB-003' => 44.99,
    'SLV-001' => 89.99,  'SLV-002' => 94.99,  'SLV-003' => 84.99,
    'GLD-001' => 149.99, 'GLD-002' => 169.99, 'GLD-003' => 159.99,
    'PLT-001' => 249.99, 'PLT-002' => 279.99, 'PLT-003' => 299.99
};

List<PricebookEntry> standardEntries = new List<PricebookEntry>();
for (Product2 p : products) {
    standardEntries.add(new PricebookEntry(
        Pricebook2Id  = standardPbId,
        Product2Id    = p.Id,
        UnitPrice     = standardPrices.get(p.ProductCode),
        IsActive      = true
    ));
}
insert standardEntries;
System.debug('✅ Standard Price Book Entries: ' + standardEntries.size());

// ----------------------------
// STEP 3: CREATE PRICE BOOKS
// ----------------------------

Pricebook2 bronzePb   = new Pricebook2(Name='Bronze Price Book',   IsActive=true);
Pricebook2 silverPb   = new Pricebook2(Name='Silver Price Book',   IsActive=true);
Pricebook2 goldPb     = new Pricebook2(Name='Gold Price Book',     IsActive=true);
Pricebook2 platinumPb = new Pricebook2(Name='Platinum Price Book', IsActive=true);
insert new List<Pricebook2>{ bronzePb, silverPb, goldPb, platinumPb };
System.debug('✅ Price Books inserted: 4');

// ----------------------------
// STEP 4: TIERED PRICE BOOK ENTRIES
// ----------------------------

Map<String, Decimal> discounts = new Map<String, Decimal>{
    'Bronze'   => 0.10,
    'Silver'   => 0.20,
    'Gold'     => 0.30,
    'Platinum' => 0.35
};

Map<String, Id> pbIds = new Map<String, Id>{
    'Bronze'   => bronzePb.Id,
    'Silver'   => silverPb.Id,
    'Gold'     => goldPb.Id,
    'Platinum' => platinumPb.Id
};

List<PricebookEntry> tieredEntries = new List<PricebookEntry>();

for (Product2 p : products) {
    Decimal basePrice = standardPrices.get(p.ProductCode);
    for (String tier : new List<String>{'Bronze','Silver','Gold','Platinum'}) {
        Decimal discounted = (basePrice * (1 - discounts.get(tier))).setScale(2);
        tieredEntries.add(new PricebookEntry(
            Pricebook2Id = pbIds.get(tier),
            Product2Id   = p.Id,
            UnitPrice    = discounted,
            IsActive     = true
        ));
    }
}

insert tieredEntries;
System.debug('✅ Tiered Price Book Entries: ' + tieredEntries.size());
System.debug('🎉 ALL DONE!');