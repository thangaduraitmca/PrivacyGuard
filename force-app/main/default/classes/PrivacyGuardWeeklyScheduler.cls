/** Weekly scheduled execution for an existing PrivacyGuard masking job. */
public without sharing class PrivacyGuardWeeklyScheduler implements Schedulable {
    private Id jobId;
    public PrivacyGuardWeeklyScheduler(Id id) { jobId = id; }
    public void execute(SchedulableContext context) {
        // Keep the original execution guard in the orchestrator. Never run in production.
        if (jobId == null) return;
        List<Masking_Job__c> jobs = [SELECT Id, Is_Active__c FROM Masking_Job__c WHERE Id = :jobId LIMIT 1];
        if (jobs.isEmpty() || !jobs[0].Is_Active__c) return;
        // Avoid overlapping runs. A running job remains Running until its batches finish.
        List<Masking_Job_Run__c> running = [SELECT Id FROM Masking_Job_Run__c WHERE Masking_Job__c = :jobId AND Status__c = 'Running' LIMIT 1];
        if (!running.isEmpty()) return;
        MaskingJobManagerService.runJob(jobId);
    }
}
