/**
 * @class         MaskingSchedulerUtilTest
 * @description   Apex test class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
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
@isTest
private with sharing class MaskingSchedulerUtilTest {

    @isTest
    static void testScheduleDailyCreatesCronJob() {
        Test.startTest();
        Id jobId = MaskingSchedulerUtil.scheduleDaily('Daily Mask Test', 2);
        Test.stopTest();

        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 2 * * ?', ct.CronExpression);
    }

    @isTest
    static void testScheduleWeeklyCreatesCronJob() {
        Test.startTest();
        Id jobId = MaskingSchedulerUtil.scheduleWeekly('Weekly Mask Test', 'SUN', 2);
        Test.stopTest();

        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 2 ? * SUN', ct.CronExpression);
    }

    @isTest
    static void testAbortScheduledJobsByNameAbortsMatchingJobs() {
        MaskingSchedulerUtil.scheduleDaily('Daily Mask Prefix Test', 3);
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Daily Mask Prefix Test%']);

        Test.startTest();
        MaskingSchedulerUtil.abortScheduledJobsByName('Daily Mask Prefix Test');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Daily Mask Prefix Test%']);
    }
}
