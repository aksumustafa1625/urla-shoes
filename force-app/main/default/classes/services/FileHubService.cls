/**
 * Service layer for File Hub data-integrity operations that must run regardless of
 * the entry point (LWC, Data Loader, Flow, standard Files UI).
 *
 * Ghost-record prevention: a File_Hub_Entry__c is a wrapper that points at a native
 * ContentDocument via ContentDocument_Id__c. If that ContentDocument is deleted
 * outside the File Hub UI (e.g. the standard Files page or Data Loader), the wrapper
 * is left orphaned — it renders but its file no longer exists. ContentDocumentTrigger
 * calls deleteOrphanedEntries on before-delete so the wrapper is removed in lock-step.
 *
 * `inherited sharing`: when invoked from a trigger there is no established sharing
 * context, so it runs system-mode and can clean up every orphan (including entries
 * owned by other users) — which is the correct behaviour for a maintenance cleanup.
 */
public inherited sharing class FileHubService {

    /**
     * Deletes File_Hub_Entry__c wrappers whose ContentDocument_Id__c points at any of
     * the supplied (about-to-be-deleted) ContentDocument ids. Bulk-safe.
     */
    public static void deleteOrphanedEntries(Set<Id> deletedDocumentIds) {
        if (deletedDocumentIds == null || deletedDocumentIds.isEmpty()) {
            return;
        }
        // ContentDocument_Id__c is a Text field, so compare against String ids.
        Set<String> docIdStrings = new Set<String>();
        for (Id docId : deletedDocumentIds) {
            docIdStrings.add(String.valueOf(docId));
        }

        List<File_Hub_Entry__c> orphans = [
            SELECT Id
            FROM File_Hub_Entry__c
            WHERE ContentDocument_Id__c IN :docIdStrings
        ];
        if (!orphans.isEmpty()) {
            delete orphans;
        }
    }
}
