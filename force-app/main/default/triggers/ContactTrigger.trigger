/**
 * @description : Trigger on Contact. Uses the thin-trigger pattern: no business logic here,
 *                all work is delegated to ContactTriggerHandler (which extends TriggerHandler).
 *                This keeps the trigger easy to read, handlers unit-testable, and allows
 *                bypass / loop-count control from TriggerHandler at a framework level.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @events      : after insert
 * @group       : Contact Nationalization
 *
 * Design notes:
 * - Only `after insert` is subscribed; we need the Contact.Id for the async job, which
 *   is not available in `before insert`.
 * - If new events are needed in the future (e.g. after update on FirstName change),
 *   extend the events clause below AND override the matching method on the handler.
 * - Do NOT add logic directly in this file — anything added here is not unit-testable.
 */
trigger ContactTrigger on Contact (after insert) {
    // Single entry point. TriggerHandler.run() dispatches to the correct context method
    // (afterInsert, afterUpdate, etc.) on the handler subclass.
    new ContactTriggerHandler().run();
}
