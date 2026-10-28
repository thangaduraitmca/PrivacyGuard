/**
 * @class         ToolingApiClientTest
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
private with sharing class ToolingApiClientTest {

    private class SuccessQueryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"records":[{"Id":"1"}]}');
            } else {
                res.setStatusCode(204);
            }
            return res;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"boom"}');
            return res;
        }
    }

    @isTest
    static void testQuerySucceeds() {
        Test.setMock(HttpCalloutMock.class, new SuccessQueryMock());
        Test.startTest();
        Map<String, Object> result = ToolingApiClient.query('SELECT Id FROM FlowDefinition');
        Test.stopTest();
        System.assertEquals(1, ((List<Object>) result.get('records')).size());
    }

    @isTest
    static void testQueryThrowsOnNon200() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        Boolean threw = false;
        Test.startTest();
        try {
            ToolingApiClient.query('SELECT Id FROM FlowDefinition');
        } catch (ToolingApiClient.ToolingApiException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testPatchSucceeds() {
        Test.setMock(HttpCalloutMock.class, new SuccessQueryMock());
        Test.startTest();
        try {
            ToolingApiClient.patch('FlowDefinition', '0300000000001', '{"Metadata":{"activeVersionNumber":null}}');
        } catch (Exception e) {
            System.assert(false, 'Should not have thrown: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testPatchThrowsOnNon204() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        Boolean threw = false;
        Test.startTest();
        try {
            ToolingApiClient.patch('FlowDefinition', '0300000000001', '{"Metadata":{"activeVersionNumber":null}}');
        } catch (ToolingApiClient.ToolingApiException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }
}
