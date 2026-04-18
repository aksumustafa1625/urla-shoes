// Set FLS for Nationalized_Country__c - make visible and editable for all profiles
List<PermissionSet> adminPS = [SELECT Id FROM PermissionSet WHERE IsOwnedByProfile = true AND Profile.Name = 'System Administrator'];
if (!adminPS.isEmpty()) {
    try {
        insert new FieldPermissions(
            ParentId = adminPS[0].Id,
            SobjectType = 'Contact',
            Field = 'Contact.Nationalized_Country__c',
            PermissionsRead = true,
            PermissionsEdit = true
        );
        System.debug('FLS set successfully for System Administrator');
    } catch (DmlException e) {
        System.debug('FLS might already exist: ' + e.getMessage());
    }
}
