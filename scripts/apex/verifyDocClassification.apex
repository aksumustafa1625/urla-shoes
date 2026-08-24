// Live end-to-end check of the DocumentClassification prompt template + service.
// Picks one reseller-linked File Hub entry and runs the real Einstein classification.
List<File_Hub_Entry__c> entries = [
    SELECT Id, File_Name__c, Category__c
    FROM File_Hub_Entry__c
    WHERE Related_Reseller__c != null
    ORDER BY CreatedDate DESC
    LIMIT 1
];
if (entries.isEmpty()) {
    System.debug('No reseller-linked entries to test.');
} else {
    File_Hub_Entry__c e = entries[0];
    System.debug('Testing entry: ' + e.File_Name__c + ' (current category: ' + e.Category__c + ')');
    DocumentIntelligenceService.ClassificationResult r =
        DocumentIntelligenceService.classifyAndApply(e.Id);
    System.debug('==================== AI CLASSIFICATION ====================');
    System.debug('applied      : ' + r.applied);
    System.debug('category     : ' + r.suggestedCategory);
    System.debug('confidence   : ' + r.confidence);
    System.debug('expiryDate   : ' + r.expiryDate);
    System.debug('summary      : ' + r.summary);
    System.debug('message      : ' + r.message);
    System.debug('===========================================================');
}
