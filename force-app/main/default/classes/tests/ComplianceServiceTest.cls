@isTest
private class ComplianceServiceTest {

    // Relies on the 4 deployed Compliance_Requirement__mdt records
    // (Signed Contract, Tax Certificate, Insurance, Bank Details).

    private static Reseller__c makeReseller(String name) {
        // Tier__c is a read-only/formula field — not set here.
        return new Reseller__c(
            Name = name,
            Company_Email__c = name.deleteWhitespace().toLowerCase() + '@test.com',
            City__c = 'Munich',
            Country__c = 'Germany'
        );
    }

    /**
     * Creates one File_Hub_Entry__c per active requirement category for the reseller,
     * using the supplied expiry per category. Categories present in skipCategories are
     * left out (→ MISSING).
     */
    private static void seedDocs(Id resellerId, Map<String, Date> expiryByCat, Set<String> skipCategories) {
        List<File_Hub_Entry__c> entries = new List<File_Hub_Entry__c>();
        for (ComplianceService.RequirementDef def : ComplianceService.getRequirements()) {
            if (skipCategories != null && skipCategories.contains(def.category)) {
                continue;
            }
            entries.add(new File_Hub_Entry__c(
                Sender__c = UserInfo.getUserId(),
                Related_Reseller__c = resellerId,
                Category__c = def.category,
                ContentDocument_Id__c = 'ConDoc' + String.valueOf(Math.abs(Crypto.getRandomLong())).left(12),
                File_Name__c = def.label + '.pdf',
                Expiry_Date__c = expiryByCat == null ? null : expiryByCat.get(def.category)
            ));
        }
        if (!entries.isEmpty()) {
            insert entries;
        }
    }

    @isTest
    static void requirementsAreLoaded() {
        List<ComplianceService.RequirementDef> reqs = ComplianceService.getRequirements();
        System.assert(reqs.size() >= 1, 'expected at least one active requirement deployed');
        for (ComplianceService.RequirementDef def : reqs) {
            System.assertNotEquals(null, def.category, 'requirement must have a category');
            System.assertNotEquals(null, def.label, 'requirement must have a label');
        }
    }

    @isTest
    static void fullyCompliantResellerScores100() {
        Reseller__c r = makeReseller('Acme Full');
        insert r;

        // All categories present; expiry-bearing ones set far in the future
        Map<String, Date> farFuture = new Map<String, Date>();
        for (ComplianceService.RequirementDef def : ComplianceService.getRequirements()) {
            farFuture.put(def.category, Date.today().addDays(200));
        }
        seedDocs(r.Id, farFuture, null);

        Test.startTest();
        ComplianceService.ResellerComplianceRow row = ComplianceService.getResellerCompliance(r.Id);
        Test.stopTest();

        System.assertEquals(100, row.score, 'all valid docs → 100');
        System.assertEquals(0, row.missingCount);
        System.assertEquals(0, row.expiredCount);
        System.assertEquals(0, row.expiringCount);
    }

    @isTest
    static void missingAllDocsScores0() {
        Reseller__c r = makeReseller('Acme Empty');
        insert r;
        // no docs seeded

        Test.startTest();
        ComplianceService.ResellerComplianceRow row = ComplianceService.getResellerCompliance(r.Id);
        Test.stopTest();

        System.assertEquals(0, row.score, 'no docs → 0');
        System.assertEquals(row.cells.size(), row.missingCount, 'every cell missing');
        for (ComplianceService.CellStatus cell : row.cells) {
            System.assertEquals('MISSING', cell.status);
            System.assertEquals('#c9c7c5', cell.color);
        }
    }

    @isTest
    static void expiredDocIsFlagged() {
        Reseller__c r = makeReseller('Acme Expired');
        insert r;

        // Find an expiry-bearing requirement; expire it, keep the rest valid
        String expiryCat;
        Map<String, Date> expiry = new Map<String, Date>();
        for (ComplianceService.RequirementDef def : ComplianceService.getRequirements()) {
            if (def.hasExpiry && expiryCat == null) {
                expiryCat = def.category;
                expiry.put(def.category, Date.today().addDays(-5)); // expired
            } else {
                expiry.put(def.category, Date.today().addDays(200));
            }
        }
        seedDocs(r.Id, expiry, null);

        Test.startTest();
        ComplianceService.ResellerComplianceRow row = ComplianceService.getResellerCompliance(r.Id);
        Test.stopTest();

        System.assertEquals(1, row.expiredCount, 'one expired doc');
        System.assert(row.score < 100, 'expired reduces score');
        Boolean foundExpired = false;
        for (ComplianceService.CellStatus cell : row.cells) {
            if (cell.category == expiryCat) {
                System.assertEquals('EXPIRED', cell.status);
                System.assertEquals('#ea001e', cell.color);
                foundExpired = true;
            }
        }
        System.assert(foundExpired, 'expired cell present');
    }

    @isTest
    static void expiringSoonCountsAsValidButWarns() {
        Reseller__c r = makeReseller('Acme Expiring');
        insert r;

        String expiryCat;
        Map<String, Date> expiry = new Map<String, Date>();
        for (ComplianceService.RequirementDef def : ComplianceService.getRequirements()) {
            if (def.hasExpiry && expiryCat == null) {
                expiryCat = def.category;
                expiry.put(def.category, Date.today().addDays(10)); // within default 30-day warning
            } else {
                expiry.put(def.category, Date.today().addDays(200));
            }
        }
        seedDocs(r.Id, expiry, null);

        Test.startTest();
        ComplianceService.ResellerComplianceRow row = ComplianceService.getResellerCompliance(r.Id);
        Test.stopTest();

        System.assertEquals(1, row.expiringCount, 'one expiring doc');
        System.assertEquals(100, row.score, 'expiring still counts as valid today');
        for (ComplianceService.CellStatus cell : row.cells) {
            if (cell.category == expiryCat) {
                System.assertEquals('EXPIRING', cell.status);
                System.assertEquals('#fe9339', cell.color);
            }
        }
    }

    @isTest
    static void matrixAggregatesAcrossResellers() {
        Reseller__c full = makeReseller('Matrix Full');
        Reseller__c empty = makeReseller('Matrix Empty');
        insert new List<Reseller__c>{ full, empty };

        Map<String, Date> farFuture = new Map<String, Date>();
        for (ComplianceService.RequirementDef def : ComplianceService.getRequirements()) {
            farFuture.put(def.category, Date.today().addDays(200));
        }
        seedDocs(full.Id, farFuture, null);
        // empty gets nothing

        Test.startTest();
        ComplianceService.ComplianceMatrix matrix = ComplianceService.getMatrix();
        Test.stopTest();

        System.assert(matrix.totalResellers >= 2, 'both resellers counted');
        System.assert(matrix.fullyCompliantCount >= 1, 'full reseller fully compliant');
        System.assert(matrix.atRiskCount >= 1, 'empty reseller at risk');
        System.assert(matrix.avgScore >= 0 && matrix.avgScore <= 100, 'avg score in range');
        System.assertEquals(matrix.rows.size(), matrix.totalResellers, 'one row per reseller');
    }

    @isTest
    static void nullResellerThrows() {
        Boolean threw = false;
        try {
            ComplianceService.getResellerCompliance(null);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'null reseller id should throw');
    }
}
