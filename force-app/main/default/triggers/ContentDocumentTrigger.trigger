/**
 * Keeps File Hub wrappers in sync with native files. When a ContentDocument is deleted
 * (from any entry point — Files UI, Data Loader, Apex), removes the File_Hub_Entry__c
 * wrappers that pointed at it so no "ghost" entries remain.
 */
trigger ContentDocumentTrigger on ContentDocument (before delete) {
    if (Trigger.isBefore && Trigger.isDelete) {
        FileHubService.deleteOrphanedEntries(Trigger.oldMap.keySet());
    }
}
