/**
 * Computes Reseller document-compliance status for the Partner Compliance Cockpit
 * and the per-Reseller checklist.
 *
 * A "requirement" is a Compliance_Requirement__mdt record naming a document
 * category every reseller must have on file. A reseller satisfies it by having a
 * File_Hub_Entry__c in that category linked via Related_Reseller__c. When the
 * requirement Has_Expiry, the linked file's Expiry_Date__c is evaluated:
 *
 *   MISSING   — no file in this category for the reseller        (gray)
 *   EXPIRED   — file exists but Expiry_Date__c is in the past    (red)
 *   EXPIRING  — file valid but expires within Warning_Days        (amber)
 *   OK        — file present and valid                            (green)
 *
 * Compliance score = (# requirements that are OK or EXPIRING) / (# requirements) * 100.
 * EXPIRING still counts as valid-today but is surfaced as a warning.
 *
 * All queries run WITH USER_MODE so FLS/CRUD is enforced for the running user.
 */
public with sharing class ComplianceService {

    private static final String STATUS_OK = 'OK';
    private static final String STATUS_EXPIRING = 'EXPIRING';
    private static final String STATUS_EXPIRED = 'EXPIRED';
    private static final String STATUS_MISSING = 'MISSING';
    private static final Integer DEFAULT_WARNING_DAYS = 30;

    /* ─── DTOs ──────────────────────────────────────────────────────────── */

    public class RequirementDef {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String category;
        @AuraEnabled public Boolean hasExpiry;
        @AuraEnabled public Integer warningDays;
        @AuraEnabled public Integer sortOrder;
    }

    public class CellStatus {
        @AuraEnabled public String category;
        @AuraEnabled public String label;
        @AuraEnabled public String status;        // OK | EXPIRING | EXPIRED | MISSING
        @AuraEnabled public String color;         // hex for the cell
        @AuraEnabled public String icon;          // SLDS utility icon
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public Integer daysUntilExpiry;
        @AuraEnabled public String contentDocumentId; // for preview link, null if missing
        @AuraEnabled public String fileName;
    }

    public class ResellerComplianceRow {
        @AuraEnabled public Id resellerId;
        @AuraEnabled public String resellerName;
        @AuraEnabled public String tier;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
        @AuraEnabled public Integer score;
        @AuraEnabled public String scoreColor;
        @AuraEnabled public Integer missingCount;
        @AuraEnabled public Integer expiringCount;
        @AuraEnabled public Integer expiredCount;
        @AuraEnabled public List<CellStatus> cells;
    }

    public class ComplianceMatrix {
        @AuraEnabled public List<RequirementDef> requirements;
        @AuraEnabled public List<ResellerComplianceRow> rows;
        @AuraEnabled public Integer totalResellers;
        @AuraEnabled public Integer avgScore;
        @AuraEnabled public Integer fullyCompliantCount;
        @AuraEnabled public Integer atRiskCount;       // any EXPIRED or MISSING
        @AuraEnabled public Integer expiringSoonCount; // any EXPIRING (and not at risk)
    }

    /* ─── PUBLIC API ────────────────────────────────────────────────────── */

    @AuraEnabled(cacheable=true)
    public static List<RequirementDef> getRequirements() {
        return loadRequirements();
    }

    @AuraEnabled(cacheable=true)
    public static ComplianceMatrix getMatrix() {
        List<RequirementDef> requirements = loadRequirements();

        List<Reseller__c> resellers = [
            SELECT Id, Name, Tier__c, City__c, Country__c
            FROM Reseller__c
            WITH USER_MODE
            ORDER BY Name
        ];

        Map<Id, Map<String, File_Hub_Entry__c>> bestByReseller =
            loadBestEntries(new Map<Id, Reseller__c>(resellers).keySet(), requirements);

        ComplianceMatrix matrix = new ComplianceMatrix();
        matrix.requirements = requirements;
        matrix.rows = new List<ResellerComplianceRow>();
        matrix.totalResellers = resellers.size();
        matrix.fullyCompliantCount = 0;
        matrix.atRiskCount = 0;
        matrix.expiringSoonCount = 0;

        Integer scoreSum = 0;
        for (Reseller__c r : resellers) {
            ResellerComplianceRow row = buildRow(r, requirements, bestByReseller.get(r.Id));
            matrix.rows.add(row);
            scoreSum += row.score;

            if (row.missingCount > 0 || row.expiredCount > 0) {
                matrix.atRiskCount++;
            } else if (row.expiringCount > 0) {
                matrix.expiringSoonCount++;
            } else {
                matrix.fullyCompliantCount++;
            }
        }
        matrix.avgScore = resellers.isEmpty() ? 0 : Math.round((Decimal) scoreSum / resellers.size());
        return matrix;
    }

    @AuraEnabled(cacheable=true)
    public static ResellerComplianceRow getResellerCompliance(Id resellerId) {
        if (resellerId == null) {
            throw new AuraHandledException('A reseller id is required');
        }
        List<RequirementDef> requirements = loadRequirements();

        List<Reseller__c> resellers = [
            SELECT Id, Name, Tier__c, City__c, Country__c
            FROM Reseller__c
            WHERE Id = :resellerId
            WITH USER_MODE
            LIMIT 1
        ];
        if (resellers.isEmpty()) {
            throw new AuraHandledException('Reseller not found or not accessible');
        }

        Map<Id, Map<String, File_Hub_Entry__c>> bestByReseller =
            loadBestEntries(new Set<Id>{ resellerId }, requirements);

        return buildRow(resellers[0], requirements, bestByReseller.get(resellerId));
    }

    /* ─── INTERNALS ─────────────────────────────────────────────────────── */

    private static List<RequirementDef> loadRequirements() {
        List<RequirementDef> defs = new List<RequirementDef>();
        for (Compliance_Requirement__mdt mdt : [
            SELECT DeveloperName, Requirement_Label__c, Document_Category__c,
                   Has_Expiry__c, Warning_Days__c, Sort_Order__c
            FROM Compliance_Requirement__mdt
            WHERE Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, Requirement_Label__c ASC
        ]) {
            RequirementDef def = new RequirementDef();
            def.developerName = mdt.DeveloperName;
            def.label = mdt.Requirement_Label__c;
            def.category = mdt.Document_Category__c;
            def.hasExpiry = mdt.Has_Expiry__c;
            def.warningDays = mdt.Warning_Days__c == null
                ? DEFAULT_WARNING_DAYS
                : Integer.valueOf(mdt.Warning_Days__c);
            def.sortOrder = mdt.Sort_Order__c == null ? 999 : Integer.valueOf(mdt.Sort_Order__c);
            defs.add(def);
        }
        return defs;
    }

    /**
     * Returns reseller id → (category → best matching entry). "Best" = furthest
     * future expiry (ORDER BY Expiry_Date__c DESC NULLS LAST → first seen wins).
     */
    private static Map<Id, Map<String, File_Hub_Entry__c>> loadBestEntries(
        Set<Id> resellerIds, List<RequirementDef> requirements
    ) {
        Set<String> categories = new Set<String>();
        for (RequirementDef def : requirements) {
            categories.add(def.category);
        }

        Map<Id, Map<String, File_Hub_Entry__c>> bestByReseller =
            new Map<Id, Map<String, File_Hub_Entry__c>>();

        if (resellerIds.isEmpty() || categories.isEmpty()) {
            return bestByReseller;
        }

        for (File_Hub_Entry__c entry : [
            SELECT Related_Reseller__c, Category__c, Expiry_Date__c,
                   ContentDocument_Id__c, File_Name__c
            FROM File_Hub_Entry__c
            WHERE Related_Reseller__c IN :resellerIds
              AND Category__c IN :categories
            WITH USER_MODE
            ORDER BY Expiry_Date__c DESC NULLS LAST
        ]) {
            Map<String, File_Hub_Entry__c> byCat = bestByReseller.get(entry.Related_Reseller__c);
            if (byCat == null) {
                byCat = new Map<String, File_Hub_Entry__c>();
                bestByReseller.put(entry.Related_Reseller__c, byCat);
            }
            // First seen for a (reseller, category) is the furthest-future expiry — keep it.
            if (!byCat.containsKey(entry.Category__c)) {
                byCat.put(entry.Category__c, entry);
            }
        }
        return bestByReseller;
    }

    private static ResellerComplianceRow buildRow(
        Reseller__c r, List<RequirementDef> requirements, Map<String, File_Hub_Entry__c> byCat
    ) {
        ResellerComplianceRow row = new ResellerComplianceRow();
        row.resellerId = r.Id;
        row.resellerName = r.Name;
        row.tier = r.Tier__c;
        row.city = r.City__c;
        row.country = r.Country__c;
        row.cells = new List<CellStatus>();
        row.missingCount = 0;
        row.expiringCount = 0;
        row.expiredCount = 0;

        Integer compliant = 0;
        for (RequirementDef def : requirements) {
            File_Hub_Entry__c entry = (byCat == null) ? null : byCat.get(def.category);
            CellStatus cell = evaluate(def, entry);
            row.cells.add(cell);

            if (cell.status == STATUS_MISSING) {
                row.missingCount++;
            } else if (cell.status == STATUS_EXPIRED) {
                row.expiredCount++;
            } else if (cell.status == STATUS_EXPIRING) {
                row.expiringCount++;
                compliant++; // expiring is still valid today
            } else {
                compliant++;
            }
        }

        row.score = requirements.isEmpty()
            ? 100
            : Math.round((Decimal) compliant / requirements.size() * 100);
        row.scoreColor = scoreColor(row.score);
        return row;
    }

    private static CellStatus evaluate(RequirementDef def, File_Hub_Entry__c entry) {
        CellStatus cell = new CellStatus();
        cell.category = def.category;
        cell.label = def.label;

        if (entry == null) {
            cell.status = STATUS_MISSING;
            cell.color = '#c9c7c5';
            cell.icon = 'utility:dash';
            return cell;
        }

        cell.contentDocumentId = entry.ContentDocument_Id__c;
        cell.fileName = entry.File_Name__c;
        cell.expiryDate = entry.Expiry_Date__c;

        if (def.hasExpiry && entry.Expiry_Date__c != null) {
            Integer daysLeft = Date.today().daysBetween(entry.Expiry_Date__c);
            cell.daysUntilExpiry = daysLeft;
            if (daysLeft < 0) {
                cell.status = STATUS_EXPIRED;
                cell.color = '#ea001e';
                cell.icon = 'utility:error';
                return cell;
            }
            if (daysLeft <= def.warningDays) {
                cell.status = STATUS_EXPIRING;
                cell.color = '#fe9339';
                cell.icon = 'utility:clock';
                return cell;
            }
        }

        cell.status = STATUS_OK;
        cell.color = '#2e844a';
        cell.icon = 'utility:check';
        return cell;
    }

    private static String scoreColor(Integer score) {
        if (score >= 100) { return '#2e844a'; } // green
        if (score >= 67)  { return '#5cb85c'; } // light green
        if (score >= 34)  { return '#fe9339'; } // amber
        return '#ea001e';                        // red
    }
}
