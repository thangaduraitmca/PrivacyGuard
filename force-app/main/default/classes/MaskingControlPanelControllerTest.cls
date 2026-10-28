/**
 * @class         MaskingControlPanelControllerTest
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
private with sharing class MaskingControlPanelControllerTest {

    @testSetup
    static void setup() {
        insert new Contact(LastName = 'OriginalLastName', Email = 'original@example.com', Phone = '415-555-0100');
        insert new Lead(LastName = 'OriginalLead', Company = 'RealCompanyName');
    }

    @isTest
    static void testRunMaskingNowSucceedsWhenAllowed() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        Test.startTest();
        MaskingControlPanelController.runMaskingNow();
        Test.stopTest();

        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        System.assertNotEquals('OriginalLastName', c.LastName);
    }

    @isTest
    static void testRunMaskingNowSurfacesFriendlyErrorWhenBlocked() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;

        Boolean threw = false;
        Test.startTest();
        try {
            MaskingControlPanelController.runMaskingNow();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Sandbox'));
        }
        Test.stopTest();

        System.assert(threw);
        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        System.assertEquals('OriginalLastName', c.LastName);
    }
}
