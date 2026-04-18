/**
 * ContactTrigger
 *
 * Purpose:
 * - Executes post-insert logic for Contact records.
 * - Delegates business logic to ContactTriggerHandler to keep trigger lean and maintainable.
 *
 * Context:
 * - Events: after insert
 * - Bulkification: Handler must be bulk-safe. This trigger performs no per-record work.
 */
trigger ContactTrigger on Contact (after insert) {
    new ContactTriggerHandler().run();
}
