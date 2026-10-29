/**
 * @class         MaskingRunInvocableTest
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
private with sharing class MaskingRunInvocableTest {

    @testSetup
    static void setup() {
        MaskingTestConfiguration.createDefaults();
        insert new Contact(LastName = 'OriginalLastName', Email = 'original@example.com', Phone = '415-555-0100');
        insert new Lead(LastName = 'OriginalLead', Company = 'RealCompanyName');
    }

    @isTest
    static void testReturnsSuccessWhenAllowed() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        Test.startTest();
        List<MaskingRunInvocable.Result> results = MaskingRunInvocable.runMaskingJobs();
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);

        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        System.assertNotEquals('OriginalLastName', c.LastName);
    }

    @isTest
    static void testReturnsFriendlyFailureWhenBlocked() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;

        Test.startTest();
        List<MaskingRunInvocable.Result> results = MaskingRunInvocable.runMaskingJobs();
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Sandbox'));

        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        System.assertEquals('OriginalLastName', c.LastName, 'Nothing should have been masked when blocked');
    }
}
