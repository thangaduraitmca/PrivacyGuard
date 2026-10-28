/**
 * @class         AutomationMetadataToggleServiceTest
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
private with sharing class AutomationMetadataToggleServiceTest {

    private class DeactivateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                if (req.getEndpoint().contains('FlowDefinition')) {
                    res.setBody('{"records":[{"Id":"3000000000001AAA","DeveloperName":"Test_Flow","ActiveVersion":{"VersionNumber":3}}]}');
                } else {
                    res.setBody('{"records":[{"Id":"03d000000000001AAA","ValidationName":"Test_Validation_Rule"}]}');
                }
            } else {
                // PATCH
                res.setStatusCode(204);
            }
            return res;
        }
    }

    private class AllFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"boom"}');
            return res;
        }
    }

    @isTest
    static void testDeactivateRecordsFlowAndValidationRule() {
        Test.setMock(HttpCalloutMock.class, new DeactivateMock());

        Test.startTest();
        Integer count = AutomationMetadataToggleService.deactivateAllFlowsAndValidationRules('run-123');
        Test.stopTest();

        System.assertEquals(2, count);

        List<Deactivated_Automation__c> records = [
            SELECT Component_Type__c, Component_Name__c, Original_State_Json__c, Reactivated__c
            FROM Deactivated_Automation__c WHERE Run_Id__c = 'run-123'
        ];
        System.assertEquals(2, records.size());

        Map<String, Deactivated_Automation__c> byType = new Map<String, Deactivated_Automation__c>();
        for (Deactivated_Automation__c r : records) byType.put(r.Component_Type__c, r);

        System.assertEquals('Test_Flow', byType.get('FLOW').Component_Name__c);
        System.assertEquals('3', byType.get('FLOW').Original_State_Json__c);
        System.assertEquals(false, byType.get('FLOW').Reactivated__c);
        System.assertEquals('Test_Validation_Rule', byType.get('VALIDATION_RULE').Component_Name__c);
    }

    @isTest
    static void testReactivateMarksRecordsReactivated() {
        Test.setMock(HttpCalloutMock.class, new DeactivateMock());
        AutomationMetadataToggleService.deactivateAllFlowsAndValidationRules('run-456');

        Test.startTest();
        Integer count = AutomationMetadataToggleService.reactivateAll('run-456');
        Test.stopTest();

        System.assertEquals(2, count);
        List<Deactivated_Automation__c> records = [SELECT Reactivated__c, Reactivated_Date__c FROM Deactivated_Automation__c WHERE Run_Id__c = 'run-456'];
        for (Deactivated_Automation__c r : records) {
            System.assertEquals(true, r.Reactivated__c);
            System.assertNotEquals(null, r.Reactivated_Date__c);
        }
    }

    @isTest
    static void testDeactivateDegradesGracefullyOnTotalFailure() {
        Test.setMock(HttpCalloutMock.class, new AllFailMock());

        Test.startTest();
        Integer count = AutomationMetadataToggleService.deactivateAllFlowsAndValidationRules('run-789');
        Test.stopTest();

        System.assertEquals(0, count, 'A total Tooling API failure should degrade to zero, not throw');
        System.assertEquals(0, [SELECT COUNT() FROM Deactivated_Automation__c WHERE Run_Id__c = 'run-789']);
    }

    @isTest
    static void testReactivateWithNoDeactivationRecordsIsANoOp() {
        Test.startTest();
        Integer count = AutomationMetadataToggleService.reactivateAll('run-does-not-exist');
        Test.stopTest();
        System.assertEquals(0, count);
    }
}
