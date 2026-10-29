/**
 * @class         AutomationManagerServiceTest
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
private with sharing class AutomationManagerServiceTest {

    @isTest
    static void testDisableAllAutomationsSetsAllFlags() {
        Test.startTest();
        AutomationManagerService.disableAllAutomations();
        Test.stopTest();

        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        System.assertEquals(true, settings.Bypass_All_Automations__c);
        System.assertEquals(true, settings.Bypass_Triggers__c);
        System.assertEquals(true, settings.Bypass_Flows__c);
        System.assertEquals(true, settings.Bypass_Validation_Rules__c);
    }

    @isTest
    static void testEnableAllAutomationsClearsAllFlags() {
        AutomationManagerService.disableAllAutomations();

        Test.startTest();
        AutomationManagerService.enableAllAutomations();
        Test.stopTest();

        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        System.assertEquals(false, settings.Bypass_All_Automations__c);
        System.assertEquals(false, settings.Bypass_Triggers__c);
        System.assertEquals(false, settings.Bypass_Flows__c);
        System.assertEquals(false, settings.Bypass_Validation_Rules__c);
    }

    @isTest
    static void testDefaultDoesNotAttemptMetadataDeactivationOrMakeCallouts() {
        // Use_Metadata_Deactivation__c defaults false - disableAllAutomations() should
        // succeed with zero callouts (no mock registered; a callout attempt here would throw).
        Test.startTest();
        AutomationManagerService.disableAllAutomations();
        AutomationManagerService.enableAllAutomations();
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Deactivated_Automation__c]);
    }

}
