global with sharing class SLAExpiryChecker implements Schedulable {
    global void execute(SchedulableContext sc) {
        LeadQueueProcessor.processExpiredLeads();
    }
}