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

    private class AllFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"boom"}');
            return res;
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
