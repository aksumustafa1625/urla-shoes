/**
 * ContactTriggerHandler
 *
 * Handles after insert events on Contact.
 * Collects Contact Ids that have a FirstName and enqueues
 * NationalizeService to enrich them with country data.
 */
public class ContactTriggerHandler extends TriggerHandler {

    override protected void afterInsert() {
        List<Id> contactIds = new List<Id>();

        for (Contact c : (List<Contact>) Trigger.new) {
            if (String.isNotBlank(c.FirstName)) {
                contactIds.add(c.Id);
            }
        }

        if (!contactIds.isEmpty()) {
            System.enqueueJob(new NationalizeService(contactIds));
        }
    }
}
