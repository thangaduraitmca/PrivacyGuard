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

    private class DeactivateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                if (req.getEndpoint().contains('FlowDefinition')) {
                    res.setBody('{"records":[{"Id":"3000000000001AAA","DeveloperName":"Test_Flow","ActiveVersion":{"VersionNumber":1}}]}');
                } else {
                    res.setBody('{"records":[]}');
                }
            } else {
                res.setStatusCode(204);
            }
            return res;
        }
    }

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

    @isTest
    static void testMetadataDeactivationRunsAndReactivatesWhenEnabled() {
        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        if (settings.Id == null) settings = new Automation_Bypass__c();
        settings.Use_Metadata_Deactivation__c = true;
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new DeactivateMock());

        Test.startTest();
        AutomationManagerService.disableAllAutomations();
        Test.stopTest();

        List<Deactivated_Automation__c> deactivated = [SELECT Component_Name__c, Run_Id__c, Reactivated__c FROM Deactivated_Automation__c];
        System.assertEquals(1, deactivated.size());
        System.assertEquals('Test_Flow', deactivated[0].Component_Name__c);
        System.assertEquals(false, deactivated[0].Reactivated__c);

        String runId = Masking_Run_Tracker__c.getOrgDefaults().Current_Run_Id__c;
        System.assertNotEquals(null, runId, 'Run Id should be persisted so enableAllAutomations() can find it later');

        AutomationManagerService.enableAllAutomations();

        Deactivated_Automation__c afterEnable = [SELECT Reactivated__c FROM Deactivated_Automation__c LIMIT 1];
        System.assertEquals(true, afterEnable.Reactivated__c, 'The Flow should be reactivated when enableAllAutomations() runs');
    }
}
