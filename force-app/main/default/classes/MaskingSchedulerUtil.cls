/**
 * @class         MaskingSchedulerUtil
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
 * Convenience wrappers around System.schedule() for the common "run this daily/weekly"
 * asks. Uses MaskingScheduler under the hood, which just calls
 * MaskingFrameworkService.executeMaskingRun() - the same run that reads every active
 * Masking_Job_Sequence__mdt record and respects each job's Full/Delta setting.
 */
public with sharing class MaskingSchedulerUtil {

    /**
     * Schedules a daily run at the given hour (0-23), org time.
     * Example: MaskingSchedulerUtil.scheduleDaily('Daily Sandbox Mask', 2); // 2 AM daily
     */
    public static Id scheduleDaily(String jobName, Integer hourOfDay) {
        String cron = '0 0 ' + hourOfDay + ' * * ?';
        return System.schedule(jobName, cron, new MaskingScheduler());
    }

    /**
     * Schedules a weekly run on the given day at the given hour (0-23), org time.
     * dayOfWeek: SUN, MON, TUE, WED, THU, FRI, SAT.
     * Example: MaskingSchedulerUtil.scheduleWeekly('Weekly Sandbox Mask', 'SUN', 2); // 2 AM every Sunday
     */
    public static Id scheduleWeekly(String jobName, String dayOfWeek, Integer hourOfDay) {
        String cron = '0 0 ' + hourOfDay + ' ? * ' + dayOfWeek;
        return System.schedule(jobName, cron, new MaskingScheduler());
    }

    /** Aborts any currently scheduled masking jobs (matched by CronTrigger job name prefix). */
    public static void abortScheduledJobsByName(String jobNamePrefix) {
        String likePattern = jobNamePrefix + '%';
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :likePattern
        ]) {
            System.abortJob(ct.Id);
        }
    }
}
