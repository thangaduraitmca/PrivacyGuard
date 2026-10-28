/**
 * @class         FileAttachmentPurgeService
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
 * Direct entry point: give it a list of object API names and it deletes every
 * Attachment and/or File related to every record of those objects. No CMDT setup
 * required - use this for one-off cleanups; use Masking_Job_Sequence__mdt records
 * with Job_Type__c = ATTACHMENT_DELETION / FILE_DELETION instead if you want this to
 * run on the same schedule/sequence as your field masking jobs.
 *
 * Jobs built here always run Parallel (see MaskingJobOrchestrator note on why serial
 * chaining isn't meaningful for ad-hoc, non-CMDT-defined job lists).
 *
 * SECURITY NOTE: objectApiNames here is real user input (typed directly into the
 * attachmentFilePurge LWC's text field), not admin-configured metadata like the rest
 * of the framework. Every name is validated against the org's actual schema via
 * SchemaValidationUtil before any job is built, so a typo or malicious string can't
 * reach dynamic SOQL - invalid names are skipped and logged individually rather than
 * failing the whole request, so "Cotnact, Lead" still purges Lead correctly.
 */
public with sharing class FileAttachmentPurgeService {

    public static void purgeForObjects(List<String> objectApiNames, Boolean deleteAttachments, Boolean deleteFiles) {
        if (objectApiNames == null || objectApiNames.isEmpty()) {
            MaskingLogger.logInfo('FileAttachmentPurgeService', 'No objects supplied - nothing to purge.');
            return;
        }
        if (deleteAttachments != true && deleteFiles != true) {
            MaskingLogger.logInfo('FileAttachmentPurgeService', 'Neither deleteAttachments nor deleteFiles was true - nothing to purge.');
            return;
        }

        List<MaskingConfigService.JobConfig> jobs = new List<MaskingConfigService.JobConfig>();
        Integer seq = 1;
        for (String objectApiName : objectApiNames) {
            String cleanName = objectApiName.trim();
            if (String.isBlank(cleanName)) continue;

            try {
                FileAttachmentPurgeController.requireEligibleObject(cleanName);
            } catch (Exception e) {
                MaskingLogger.logError('FileAttachmentPurgeService', cleanName, null, null,
                    'Skipped "' + cleanName + '": ' + e.getMessage());
                continue;
            }

            if (deleteAttachments) {
                jobs.add(buildJob('Purge_Attachments_' + cleanName, cleanName, FileAttachmentDeletionBatch.MODE_ATTACHMENTS, seq++));
            }
            if (deleteFiles) {
                jobs.add(buildJob('Purge_Files_' + cleanName, cleanName, FileAttachmentDeletionBatch.MODE_FILES, seq++));
            }
        }

        if (jobs.isEmpty()) {
            MaskingLogger.logInfo('FileAttachmentPurgeService', 'No valid objects to purge after validation - nothing was queued.');
            return;
        }

        MaskingJobOrchestrator.runJobs(jobs);
    }

    private static MaskingConfigService.JobConfig buildJob(String jobName, String objectApiName, String jobType, Integer seq) {
        MaskingConfigService.JobConfig jc = new MaskingConfigService.JobConfig();
        jc.jobName = jobName;
        jc.objectApiName = objectApiName;
        jc.executionMode = 'Parallel';
        jc.sequenceOrder = seq;
        jc.batchSize = 200;
        jc.runMode = 'Full';
        jc.jobType = jobType;
        return jc;
    }
}
