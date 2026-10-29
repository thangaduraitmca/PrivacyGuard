/**
 * @class         FileAttachmentDeletionBatch
 * @description   Apex class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
 * @package       PrivacyGuard
 * @namespace     privacyguard
 * @apiVersion    66.0
 * @owner         PrivacyGuard Engineering
 * @changeControl Changes to this class must be peer reviewed, linked to an approved work item, validated by automated tests, and promoted through the managed-package release process.
 *
 * CHANGE HISTORY
 * Version     Date         Change Ref         Author/Owner               Description
 * 1.0.0       2026-09-16   PG-BASELINE-001    PrivacyGuard Engineering   Established managed-package audit and change-control baseline.
 */
/**
 * Deletes legacy Attachment records or modern Files (ContentDocument, via
 * ContentDocumentLink) related to every record of a given object. Plugs into the same
 * job framework as MaskingBatch - same finish()/MaskingJobOrchestrator hookup, so it
 * gets Serial/Parallel sequencing, scheduling, automation bypass, and logging for free.
 *
 * SECURITY NOTES:
 * - Declared `without sharing`, deliberately, for the same reason as MaskingBatch: a
 *   purge job must delete every related Attachment/File regardless of the running
 *   user's record-level sharing visibility, or it would silently leave real data
 *   behind. Access control lives upstream (Permission Set + Sandbox-only safety gate).
 * - objectApiName is validated against the org's real schema via SchemaValidationUtil
 *   before being concatenated into dynamic SOQL - this matters especially here since
 *   FileAttachmentPurgeService accepts object names typed directly into an LWC text
 *   field, so this is real user input, not just admin-configured metadata.
 *
 * MODE_ATTACHMENTS deletes Attachment rows directly.
 * MODE_FILES deletes the ContentDocument (which cascades to ContentVersion and every
 * ContentDocumentLink) rather than just unlinking it, since the goal is removing the
 * underlying file/content, not just its association to this record. Note: if a file is
 * shared across multiple records (linked to more than one parent), deleting the
 * ContentDocument removes it everywhere, not just from the object being purged.
 */
public without sharing class FileAttachmentDeletionBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final String MODE_ATTACHMENTS = 'ATTACHMENT_DELETION';
    public static final String MODE_FILES = 'FILE_DELETION';

    private String jobName;
    private String objectApiName;
    private String mode;
    private Integer recordsDeleted = 0;
    private Integer recordsFailed = 0;
    private Set<Id> processedContentDocumentIds = new Set<Id>();

    public FileAttachmentDeletionBatch(String jobName, String objectApiName, String mode) {
        this.jobName = jobName;
        this.objectApiName = objectApiName;
        this.mode = mode;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requirePurgePermission();

        // Validates objectApiName against the real org schema before it's concatenated
        // into SOQL below - closes the injection surface for the LWC's free-text input.
        SchemaValidationUtil.requireValidObject(objectApiName);

        String query;
        if (mode == MODE_ATTACHMENTS) {
            query = 'SELECT Id FROM Attachment WHERE ParentId IN (SELECT Id FROM ' + objectApiName + ')';
        } else {
            query = 'SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN (SELECT Id FROM ' + objectApiName + ')';
        }
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requirePurgePermission();
        if (mode == MODE_ATTACHMENTS) {
            deleteAndLog(scope);
            return;
        }

        // MODE_FILES: dedupe ContentDocumentIds (a doc can appear via multiple links,
        // possibly across chunks - processedContentDocumentIds persists via Stateful).
        List<ContentDocument> docsToDelete = new List<ContentDocument>();
        for (SObject link : scope) {
            Id docId = (Id) link.get('ContentDocumentId');
            if (docId != null && !processedContentDocumentIds.contains(docId)) {
                processedContentDocumentIds.add(docId);
                docsToDelete.add(new ContentDocument(Id = docId));
            }
        }
        deleteAndLog(docsToDelete);
    }

    private void deleteAndLog(List<SObject> records) {
        if (records.isEmpty()) return;
        List<Database.DeleteResult> results = Database.delete(records, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                recordsDeleted++;
            } else {
                recordsFailed++;
                String errors = '';
                for (Database.Error err : results[i].getErrors()) {
                    errors += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                }
                MaskingLogger.queueActivity('Files',jobName,objectApiName,records[i].Id,'Delete failed: '+errors,'Failed');
            }
        }
        MaskingLogger.flush();
    }

    public void finish(Database.BatchableContext bc) {
        String kind = (mode == MODE_ATTACHMENTS) ? 'Attachment' : 'File';
        String summary=jobName+': '+kind+' deletion finished for '+objectApiName+'. Deleted: '+recordsDeleted+', Failed: '+recordsFailed;
        if(recordsFailed>0)PrivacyGuardAuditService.recordFailure('Files','Deletion finished',null,summary);
        else PrivacyGuardAuditService.record('Files','Deletion finished',null,summary);
        MaskingJobOrchestrator.handleJobCompletion(jobName);
    }
}
