// Seeds a realistic compliance mix across the existing resellers so the
// Partner Compliance Cockpit renders a green / amber-red / mostly-red spread.
// Safe to re-run: deletes prior demo entries (File_Name__c ending '(demo)') first.

List<Reseller__c> resellers = [SELECT Id, Name FROM Reseller__c ORDER BY Name LIMIT 3];
if (resellers.size() < 3) {
    System.debug('Need at least 3 resellers; found ' + resellers.size());
}

// Clean previous demo rows
delete [SELECT Id FROM File_Hub_Entry__c WHERE File_Name__c LIKE '%(demo)'];

Id me = UserInfo.getUserId();
Date today = Date.today();
List<File_Hub_Entry__c> rows = new List<File_Hub_Entry__c>();

// Helper inline via list building
// Reseller 0 → fully compliant (all 4, valid)
if (resellers.size() >= 1) {
    Id r = resellers[0].Id;
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Contract',     File_Name__c='Distribution Contract (demo)', ContentDocument_Id__c='Demo00000000000001'));
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Tax Document',  File_Name__c='Tax Certificate (demo)',      ContentDocument_Id__c='Demo00000000000002', Expiry_Date__c=today.addDays(220)));
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Insurance',     File_Name__c='Liability Insurance (demo)',   ContentDocument_Id__c='Demo00000000000003', Expiry_Date__c=today.addDays(180)));
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Bank Details',  File_Name__c='Bank Details (demo)',          ContentDocument_Id__c='Demo00000000000004'));
}
// Reseller 1 → mixed: contract ok, tax expiring soon, insurance expired, bank missing
if (resellers.size() >= 2) {
    Id r = resellers[1].Id;
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Contract',     File_Name__c='Distribution Contract (demo)', ContentDocument_Id__c='Demo00000000000011'));
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Tax Document',  File_Name__c='Tax Certificate (demo)',      ContentDocument_Id__c='Demo00000000000012', Expiry_Date__c=today.addDays(12)));
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Insurance',     File_Name__c='Liability Insurance (demo)',   ContentDocument_Id__c='Demo00000000000013', Expiry_Date__c=today.addDays(-8)));
    // Bank Details intentionally omitted → MISSING
}
// Reseller 2 → mostly red: only contract on file
if (resellers.size() >= 3) {
    Id r = resellers[2].Id;
    rows.add(new File_Hub_Entry__c(Sender__c=me, Related_Reseller__c=r, Category__c='Contract',     File_Name__c='Distribution Contract (demo)', ContentDocument_Id__c='Demo00000000000021'));
}

insert rows;
System.debug('Seeded ' + rows.size() + ' demo File Hub entries across ' + resellers.size() + ' resellers.');
