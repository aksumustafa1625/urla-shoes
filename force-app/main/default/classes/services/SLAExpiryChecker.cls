global class SLAExpiryChecker implements Schedulable {
    global void execute(SchedulableContext sc) {
        LeadQueueProcessor.processExpiredLeads();
    }
}