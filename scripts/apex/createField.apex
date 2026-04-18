// List all custom fields on Contact to see what exists
Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Contact.fields.getMap();
for (String fieldName : fieldMap.keySet()) {
    if (fieldName.endsWith('__c')) {
        System.debug('Custom field: ' + fieldName);
    }
}
System.debug('Total fields: ' + fieldMap.size());
