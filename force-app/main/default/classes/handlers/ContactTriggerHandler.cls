/**
 * @description : Handles Contact trigger events. On after insert, collects the Ids of
 *                contacts that have a FirstName and enqueues a single NationalizeService
 *                Queueable job to enrich them asynchronously with country data.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Contact Nationalization
 *
 * Design notes:
 * - Extends the project's shared TriggerHandler framework, which provides bypass control,
 *   loop-count protection, and context routing out of the box.
 * - We use `after insert` because the Contact.Id is required to later update the record
 *   inside the Queueable; in `before insert` the Id is not yet assigned.
 * - Only one Queueable is enqueued per trigger invocation (regardless of batch size),
 *   which keeps us well under the 50-jobs-per-transaction governor limit.
 */
public class ContactTriggerHandler extends TriggerHandler {

    /**
     * Runs after Contacts are inserted. Filters out contacts without a FirstName
     * (the Nationalize API requires a name) and enqueues a single async job to
     * handle the callout + update cycle.
     */
    override protected void afterInsert() {
        // Collect only the Ids we actually need to process. Filtering here avoids
        // wasting API calls and callout-per-transaction quota on rows that cannot
        // produce a result (no FirstName -> Nationalize.io has nothing to look up).
        List<Id> contactIds = new List<Id>();

        // Trigger.new is typed as List<SObject>; the cast is safe here because this
        // method only runs on Contact insert.
        for (Contact c : (List<Contact>) Trigger.new) {
            // String.isNotBlank covers null, empty, and whitespace-only strings —
            // safer than `!= null` which would still allow '' or '   '.
            if (String.isNotBlank(c.FirstName)) {
                contactIds.add(c.Id);
            }
        }

        // Guard: if no eligible contacts were inserted, skip enqueueing entirely.
        // Enqueueing an empty job would waste a Queueable slot and generate a no-op
        // Apex job log entry.
        if (!contactIds.isEmpty()) {
            // A single Queueable processes ALL contacts in this trigger batch.
            // This is the key to bulk-safety: we don't enqueue one job per contact,
            // which would quickly exhaust the 50-queueables-per-transaction limit
            // on large data loads.
            System.enqueueJob(new NationalizeService(contactIds));
        }
    }
}
