trigger TaskTrigger on Task (after insert, after update, after delete, after undelete) {
    Set<Id> oppIds = new Set<Id>();
    
    // İşlem gören taskların Opportunity ile bağlantılı olup olmadığını kontrol et
    List<Task> taskList = Trigger.isDelete ? Trigger.old : Trigger.new;
    
    for (Task t : taskList) {
        if (t.WhatId != null && String.valueOf(t.WhatId).startsWith('006')) {
            oppIds.add(t.WhatId);
        }
    }
    
    // Eğer etkilenen bir Opportunity varsa hesaplamayı başlat
    if (!oppIds.isEmpty()) {
        TaskTriggerHandler.updateOpportunityTaskCounts(oppIds);
    }
}