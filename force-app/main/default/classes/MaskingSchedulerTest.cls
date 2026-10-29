/**
 * @class         MaskingSchedulerTest
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
private with sharing class MaskingSchedulerTest {

    @testSetup
    static void setup() {
        MaskingTestConfiguration.createDefaults();
        insert new Contact(LastName = 'OriginalLastName', Email = 'original@example.com', Phone = '415-555-0100');
    }

    @isTest
    static void testScheduledExecuteRunsMaskingWhenAllowed() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        Test.startTest();
        new MaskingScheduler().execute(null);
        Test.stopTest();

        Contact updated = [SELECT LastName FROM Contact LIMIT 1];
        System.assertNotEquals('OriginalLastName', updated.LastName);
    }

    @isTest
    static void testCanBeScheduledViaSystemSchedule() {
        Test.startTest();
        Id jobId = System.schedule('Masking Scheduler Test Job', '0 0 3 * * ?', new MaskingScheduler());
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        CronTrigger ct = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 3 * * ?', ct.CronExpression);
    }
}
