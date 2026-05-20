/**
 * @description : Sibling helper for FileHubController. Declared `without sharing` so it
 *                can perform DML on records the running user only has Read access to
 *                (specifically: a recipient marking an entry as read).
 *
 *                Every public method MUST enforce its own auth check before touching
 *                the record — otherwise we'd be leaking write privileges that the
 *                sharing model is supposed to gate.
 * @author      : Mustafa Aksu
 * @date        : 2026-05-13
 * @group       : File Hub
 */
public without sharing class FileHubSharingHelper {

    /**
     * @description Updates Read__c = true on an entry, bypassing sharing.
     *              Safety net: refuses unless the running user is the entry's Recipient.
     */
    public static void markAsReadInternal(Id entryId) {
        if (entryId == null) return;

        File_Hub_Entry__c entry = [
            SELECT Id, Recipient__c, Read__c
            FROM File_Hub_Entry__c
            WHERE Id = :entryId
            LIMIT 1
        ];

        // Explicit auth check — without this, the without-sharing context would let
        // anyone with knowledge of the Id flip the flag. We re-enforce here that only
        // the named Recipient can mark as read.
        if (entry.Recipient__c != UserInfo.getUserId()) {
            return;
        }
        if (entry.Read__c) {
            return;  // Already read — no-op, no wasted DML
        }

        entry.Read__c = true;
        update entry;
    }
}
