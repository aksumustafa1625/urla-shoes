List<Contact> contacts = [SELECT Id, FirstName, LastName, Nationalized_Country__c FROM Contact WHERE FirstName = 'Mustafa' AND LastName = 'Aksu' LIMIT 5];
for (Contact c : contacts) {
    System.debug('Contact: ' + c.FirstName + ' ' + c.LastName + ' -> Country: ' + c.Nationalized_Country__c);
}
