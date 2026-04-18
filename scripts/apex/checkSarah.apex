List<Contact> contacts = [SELECT Id, FirstName, LastName, Nationalized_Country__c FROM Contact WHERE FirstName = 'Sarah' AND LastName = 'May' LIMIT 1];
for (Contact c : contacts) {
    System.debug('Contact: ' + c.FirstName + ' ' + c.LastName + ' -> Country: ' + c.Nationalized_Country__c);
}
