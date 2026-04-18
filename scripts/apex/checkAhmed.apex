Contact c = [SELECT Id, FirstName, LastName, Nationalized_Country__c FROM Contact WHERE Id = '003g500000DifEnAAJ'];
System.debug('Contact: ' + c.FirstName + ' ' + c.LastName + ' -> Country: ' + c.Nationalized_Country__c);
