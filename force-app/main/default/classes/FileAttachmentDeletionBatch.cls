/** Deprecated object-wide purge. Existing scheduled/direct invocations fail closed. */
public with sharing class FileAttachmentDeletionBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String MODE_ATTACHMENTS = 'ATTACHMENT_DELETION';
    public static final String MODE_FILES = 'FILE_DELETION';
    public FileAttachmentDeletionBatch(String jobName, String objectApiName, String mode) {}
    public Database.QueryLocator start(Database.BatchableContext bc) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requirePurgePermission();
        FileAttachmentPurgeService.assertObjectPurgeEnabled();
        return null;
    }
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requirePurgePermission();
        FileAttachmentPurgeService.assertObjectPurgeEnabled();
    }
    public void finish(Database.BatchableContext bc) {
        // No completion or deletion is claimed for retired object-wide jobs.
    }
}
