/**
 * @class         MaskingJobOrchestrator
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
 * 1.1.0       2026-09-16   PG-SEC-003         PrivacyGuard Engineering   Added concurrency guard and row-locked completion tracking.
 */
/**
 * Reads a list of jobs (either the active Masking_Job_Sequence__mdt records, or an
 * ad-hoc list built programmatically - see FileAttachmentPurgeService) and runs them
 * Serial or Parallel:
 *   - Serial jobs run one at a time; each batch's finish() kicks off the next.
 *   - Parallel jobs are all submitted to the batch queue at once.
 * Automations are disabled once up-front and re-enabled exactly once, after
 * every job (serial + parallel) has completed, tracked via Masking_Run_Tracker__c.
 *
 * Each job dispatches to one of three batch classes based on Job_Type__c:
 *   - FIELD_MASKING (default): MaskingBatch
 *   - ATTACHMENT_DELETION: FileAttachmentDeletionBatch (legacy Attachment records)
 *   - FILE_DELETION: FileAttachmentDeletionBatch (modern Files / ContentDocument)
 *
 * NOTE: completion tracking uses a Hierarchy Custom Setting updated from each
 * batch's finish(). Under heavy parallel load this can hit row-lock contention
 * (UNABLE_TO_LOCK_ROW) since multiple async transactions update the same
 * record concurrently. For high-volume orgs, consider swapping this counter
 * for a Platform Event or an AsyncApexJob status poll via Schedulable instead.
 *
 * NOTE: for ad-hoc job lists (not sourced from Masking_Job_Sequence__mdt), only
 * Parallel execution is meaningfully supported - handleJobCompletion() re-reads the
 * CMDT-defined serial sequence to advance the chain, so an ad-hoc job by a name not
 * present in CMDT simply won't be found there, which is a no-op rather than an error
 * (the completion counter still decrements correctly either way). FileAttachmentPurgeService
 * always builds its jobs as Parallel for this reason.
 */
public with sharing class MaskingJobOrchestrator {

    public static void runMaskingJobs() {
        List<MaskingConfigService.JobConfig> jobs = MaskingConfigService.getActiveJobSequence();
        if (jobs.isEmpty()) {
            MaskingLogger.logInfo('MaskingJobOrchestrator', 'No active masking jobs configured - nothing to run.');
            return;
        }
        runJobs(jobs);
    }

    /** Entry point for both CMDT-driven runs and ad-hoc/programmatic job lists. */
    public static void runJobs(List<MaskingConfigService.JobConfig> jobs) {
        if (jobs == null || jobs.isEmpty()) {
            MaskingLogger.logInfo('MaskingJobOrchestrator', 'No jobs to run.');
            return;
        }

        PrivacyGuardSecurityService.requireRunPermission();
        EnvironmentSafetyService.assertExecutionAllowed();
        for (MaskingConfigService.JobConfig job : jobs) {
            if (job.jobType == 'ATTACHMENT_DELETION' || job.jobType == 'FILE_DELETION') {
                PrivacyGuardSecurityService.requirePurgePermission();
            }
        }
        acquireRunGuard();

        Map<String, List<MaskingConfigService.FieldConfig>> fieldConfigsByObject = MaskingConfigService.getActiveFieldConfigsByObject();

        try {
            AutomationManagerService.disableAllAutomations();
        } catch (Exception e) {
            releaseRunGuard();
            throw e;
        }

        List<MaskingConfigService.JobConfig> serialJobs = new List<MaskingConfigService.JobConfig>();
        List<MaskingConfigService.JobConfig> parallelJobs = new List<MaskingConfigService.JobConfig>();
        for (MaskingConfigService.JobConfig job : jobs) {
            if ('Parallel'.equalsIgnoreCase(job.executionMode)) {
                parallelJobs.add(job);
            } else {
                serialJobs.add(job);
            }
        }

        resetTracker(serialJobs.size() + parallelJobs.size());

        // Parallel jobs: fire them all now.
        for (MaskingConfigService.JobConfig job : parallelJobs) {
            Database.Batchable<SObject> batchable = buildBatchable(job, fieldConfigsByObject);
            if (batchable == null) {
                decrementTrackerAndMaybeEnableAutomations();
                continue;
            }
            Database.executeBatch(batchable, job.batchSize);
        }

        // Serial jobs: kick off only the first; each finish() advances the chain.
        if (!serialJobs.isEmpty()) {
            runSerialJobByIndex(serialJobs, 0, fieldConfigsByObject);
        }
    }

    private static void runSerialJobByIndex(List<MaskingConfigService.JobConfig> serialJobs, Integer index,
                                             Map<String, List<MaskingConfigService.FieldConfig>> fieldConfigsByObject) {
        if (index >= serialJobs.size()) return;

        MaskingConfigService.JobConfig job = serialJobs[index];
        Database.Batchable<SObject> batchable = buildBatchable(job, fieldConfigsByObject);
        if (batchable == null) {
            decrementTrackerAndMaybeEnableAutomations();
            runSerialJobByIndex(serialJobs, index + 1, fieldConfigsByObject);
            return;
        }
        Database.executeBatch(batchable, job.batchSize);
    }

    /** Builds the right Batchable for a job's Job_Type__c, or null (and logs) if misconfigured. */
    private static Database.Batchable<SObject> buildBatchable(MaskingConfigService.JobConfig job,
                                                                Map<String, List<MaskingConfigService.FieldConfig>> fieldConfigsByObject) {
        String jobType = String.isBlank(job.jobType) ? 'FIELD_MASKING' : job.jobType;

        if (jobType == 'ATTACHMENT_DELETION') {
            return new FileAttachmentDeletionBatch(job.jobName, job.objectApiName, FileAttachmentDeletionBatch.MODE_ATTACHMENTS);
        }
        if (jobType == 'FILE_DELETION') {
            return new FileAttachmentDeletionBatch(job.jobName, job.objectApiName, FileAttachmentDeletionBatch.MODE_FILES);
        }

        // FIELD_MASKING
        List<MaskingConfigService.FieldConfig> fields = fieldConfigsByObject.get(job.objectApiName);
        if (fields == null || fields.isEmpty()) {
            MaskingLogger.logError('MaskingJobOrchestrator', job.objectApiName, null, null,
                'Skipped job ' + job.jobName + ': no active field configuration found for ' + job.objectApiName);
            return null;
        }
        return new MaskingBatch(job.jobName, job.objectApiName, fields, job.runMode, job.deltaTrackingField);
    }

    /** Called from MaskingBatch/FileAttachmentDeletionBatch.finish(). Advances the serial chain and updates the tracker. */
    public static void handleJobCompletion(String jobName) {
        List<MaskingConfigService.JobConfig> allJobs = MaskingConfigService.getActiveJobSequence();
        List<MaskingConfigService.JobConfig> serialJobs = new List<MaskingConfigService.JobConfig>();
        for (MaskingConfigService.JobConfig j : allJobs) {
            if (!'Parallel'.equalsIgnoreCase(j.executionMode)) {
                serialJobs.add(j);
            }
        }

        Integer currentIndex = -1;
        for (Integer i = 0; i < serialJobs.size(); i++) {
            if (serialJobs[i].jobName == jobName) {
                currentIndex = i;
                break;
            }
        }
        // If jobName isn't found here (e.g. an ad-hoc job not defined in CMDT), this is a
        // no-op rather than an error - ad-hoc jobs are expected to run Parallel-only.
        if (currentIndex > -1 && currentIndex + 1 < serialJobs.size()) {
            Map<String, List<MaskingConfigService.FieldConfig>> fieldConfigsByObject = MaskingConfigService.getActiveFieldConfigsByObject();
            runSerialJobByIndex(serialJobs, currentIndex + 1, fieldConfigsByObject);
        }

        decrementTrackerAndMaybeEnableAutomations();
    }

    private static void resetTracker(Integer totalJobs) {
        Masking_Run_Tracker__c defaults = Masking_Run_Tracker__c.getOrgDefaults();
        if (defaults.Id == null) {
            defaults = new Masking_Run_Tracker__c(
                Total_Jobs__c = totalJobs, Completed_Jobs__c = 0,
                Run_In_Progress__c = true, Run_Started_At__c = System.now());
            insert defaults;
            return;
        }
        Masking_Run_Tracker__c tracker = [SELECT Id, Total_Jobs__c, Completed_Jobs__c, Run_In_Progress__c, Run_Started_At__c
                                           FROM Masking_Run_Tracker__c WHERE Id = :defaults.Id FOR UPDATE];
        tracker.Total_Jobs__c = totalJobs;
        tracker.Completed_Jobs__c = 0;
        tracker.Run_In_Progress__c = true;
        tracker.Run_Started_At__c = System.now();
        update tracker;
    }

    private static void decrementTrackerAndMaybeEnableAutomations() {
        Masking_Run_Tracker__c defaults = Masking_Run_Tracker__c.getOrgDefaults();
        if (defaults.Id == null) return;
        // Serialize parallel finish transactions to avoid lost updates on the completion counter.
        Masking_Run_Tracker__c tracker = [SELECT Id, Total_Jobs__c, Completed_Jobs__c, Run_In_Progress__c
                                           FROM Masking_Run_Tracker__c WHERE Id = :defaults.Id FOR UPDATE];
        tracker.Completed_Jobs__c = (tracker.Completed_Jobs__c == null ? 0 : tracker.Completed_Jobs__c) + 1;
        Boolean complete = tracker.Total_Jobs__c != null && tracker.Completed_Jobs__c >= tracker.Total_Jobs__c;
        if (complete) tracker.Run_In_Progress__c = false;
        update tracker;

        if (complete) {
            try {
                AutomationManagerService.enableAllAutomations();
                MaskingLogger.logInfo('MaskingJobOrchestrator', 'All masking jobs complete. Automations re-enabled.');
            } finally {
                releaseRunGuard();
            }
        }
    }

    private static void acquireRunGuard() {
        Masking_Run_Tracker__c defaults = Masking_Run_Tracker__c.getOrgDefaults();
        if (defaults.Id == null) return;
        Masking_Run_Tracker__c tracker = [SELECT Id, Run_In_Progress__c, Run_Started_At__c
                                           FROM Masking_Run_Tracker__c WHERE Id = :defaults.Id FOR UPDATE];
        if (tracker.Run_In_Progress__c == true) {
            throw new PrivacyGuardSecurityService.PrivacyGuardAuthorizationException(
                'A PrivacyGuard destructive run is already in progress. Concurrent runs are blocked to protect data and automation state.');
        }
    }

    private static void releaseRunGuard() {
        Masking_Run_Tracker__c defaults = Masking_Run_Tracker__c.getOrgDefaults();
        if (defaults.Id == null) return;
        try {
            Masking_Run_Tracker__c tracker = [SELECT Id, Run_In_Progress__c FROM Masking_Run_Tracker__c WHERE Id = :defaults.Id FOR UPDATE];
            tracker.Run_In_Progress__c = false;
            update tracker;
        } catch (Exception e) {
            MaskingLogger.logError('MaskingJobOrchestrator', null, null, null, 'Could not release run guard: ' + e.getMessage());
        }
    }
}
