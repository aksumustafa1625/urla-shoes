Schema.DescribeFieldResult dfr = Contact.Nationalized_Country__c.getDescribe();
System.debug('Field found: ' + dfr.getName() + ' | Label: ' + dfr.getLabel());
