public with sharing class TaskTriggerHandler {
    public static void updateOpportunityTaskCounts(Set<Id> oppIds) {
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        
        // Opportunity ID'lerine göre Taskları gruplayarak sayıyoruz
        // Hem toplam sayıyı hem de sadece 'Completed' olanları tek sorguda alıyoruz
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();
        for (Id oppId : oppIds) {
            oppMap.put(oppId, new Opportunity(Id = oppId, Score__c = 0, completed_task__c = 0));
        }

        // Toplam Task Sayısı (Score) için Query
        for (AggregateResult ar : [SELECT WhatId, COUNT(Id) total FROM Task 
                                   WHERE WhatId IN :oppIds GROUP BY WhatId]) {
            Id oppId = (Id)ar.get('WhatId');
            oppMap.get(oppId).Score__c = (Integer)ar.get('total');
        }

        // Tamamlanmış Task Sayısı için Query
        for (AggregateResult ar : [SELECT WhatId, COUNT(Id) total FROM Task 
                                   WHERE WhatId IN :oppIds AND Status = 'Completed' GROUP BY WhatId]) {
            Id oppId = (Id)ar.get('WhatId');
            oppMap.get(oppId).completed_task__c = (Integer)ar.get('total');
        }

        if (!oppMap.isEmpty()) {
            update oppMap.values();
        }
    }
}