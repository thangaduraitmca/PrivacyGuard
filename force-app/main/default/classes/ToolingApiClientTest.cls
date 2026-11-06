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
            System.assert(req.getEndpoint().startsWith('callout:privacyguard__PrivacyGuard_Tooling/'), 'Use only the fixed OAuth Named Credential endpoint.');
            System.assertEquals(null,req.getHeader('Authorization'),'Apex must not construct an authorization header.');
            if (req.getEndpoint().contains('/query/?q=') && !req.getEndpoint().contains('/tooling/')) {
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String,Object>{'records'=>new List<Object>{
                    new Map<String,Object>{'Id'=>UserInfo.getOrganizationId(),'IsSandbox'=>true}}}));
                return res;
            }

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
            System.assert(req.getEndpoint().startsWith('callout:privacyguard__PrivacyGuard_Tooling/'), 'Use only the fixed OAuth Named Credential endpoint.');
            System.assertEquals(null,req.getHeader('Authorization'),'Apex must not construct an authorization header.');
            if (req.getEndpoint().contains('/query/?q=') && !req.getEndpoint().contains('/tooling/')) {
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String,Object>{'records'=>new List<Object>{
                    new Map<String,Object>{'Id'=>UserInfo.getOrganizationId(),'IsSandbox'=>true}}}));
                return res;
            }

            res.setStatusCode(500);
            res.setBody('{"error":"boom"}');
            return res;
        }
    }

    @isTest
    static void testQuerySucceeds() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Test.setMock(HttpCalloutMock.class, new SuccessQueryMock());
        Test.startTest();
        Map<String, Object> result = ToolingApiClient.query('SELECT Id FROM ApexTrigger');
        Test.stopTest();
        System.assertEquals(1, ((List<Object>) result.get('records')).size());
    }

    @isTest
    static void testQueryThrowsOnNon200() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        Boolean threw = false;
        Test.startTest();
        try {
            ToolingApiClient.query('SELECT Id FROM ApexTrigger');
        } catch (ToolingApiClient.ToolingApiException e) {
            threw = true;
            System.assert(!e.getMessage().contains('boom'),'HTTP errors must not expose the raw response body.');
        }
        Test.stopTest();
        System.assert(threw);
    }

    @IsTest static void directPatchIsBlockedWithoutCallouts() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Integer beforeCallouts=Limits.getCallouts();
        Boolean blocked=false;
        try { ToolingApiClient.patch('FlowDefinition','0300000000001','{}'); }
        catch (ToolingApiClient.ToolingApiException ex) { blocked=true; }
        System.assert(blocked,'Retired Flow/Validation Rule PATCH must fail closed.');
        System.assertEquals(beforeCallouts,Limits.getCallouts(),'A blocked PATCH must make no callout.');
    }
    @isTest
    static void testPatchThrowsOnNon204() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
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
    private class IdentityMock implements HttpCalloutMock {
        String remoteOrg; Boolean sandbox; Integer status; Boolean malformed;
        Integer calls=0;Integer toolingCalls=0;
        IdentityMock(String remoteOrg, Boolean sandbox, Integer status, Boolean malformed) {
            this.remoteOrg=remoteOrg;this.sandbox=sandbox;this.status=status;this.malformed=malformed;
        }
        public HttpResponse respond(HttpRequest req) {
            calls++;
            System.assert(req.getEndpoint().startsWith('callout:privacyguard__PrivacyGuard_Tooling/'),'Use the fixed Named Credential.');
            System.assertEquals(null,req.getHeader('Authorization'),'Apex must never set a bearer token.');
            HttpResponse response=new HttpResponse();
            if (req.getEndpoint().contains('/tooling/')) {
                toolingCalls++;
                response.setStatusCode(req.getMethod()=='POST'?201:200);
                response.setBody(req.getMethod()=='POST'?'{'+'"id":"1dc000000000001AAA"}':'{'+'"records":[]}');
                return response;
            }
            response.setStatusCode(status);
            response.setBody(malformed?'untrusted-body':JSON.serialize(new Map<String,Object>{
                'records'=>new List<Object>{new Map<String,Object>{'Id'=>remoteOrg,'IsSandbox'=>sandbox}}}));
            return response;
        }
    }
    private static void assertTargetBlocked(String remoteOrg, Boolean sandbox, Integer status, Boolean malformed) {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        IdentityMock mock=new IdentityMock(remoteOrg,sandbox,status,malformed);
        Test.setMock(HttpCalloutMock.class,mock);
        Boolean blocked=false;
        try { ToolingApiClient.post('MetadataContainer','{}'); }
        catch (ToolingApiClient.ToolingApiException ex) { blocked=true; }
        System.assert(blocked,'An unverified target must block trigger metadata operations.');
        System.assertEquals(0,mock.toolingCalls,'Only the identity lookup may reach an unverified endpoint.');
    }
    @IsTest static void foreignSandboxIsBlocked() {
        assertTargetBlocked('00D000000000000',true,200,false);
    }
    @IsTest static void productionTargetIsBlocked() {
        assertTargetBlocked(UserInfo.getOrganizationId(),false,200,false);
    }
    @IsTest static void invalidIdentityResponseIsBlocked() {
        assertTargetBlocked(UserInfo.getOrganizationId(),true,200,true);
    }
    @IsTest static void expiredOrDeniedOAuthIsBlocked() {
        assertTargetBlocked(UserInfo.getOrganizationId(),true,401,false);
    }
    @IsTest static void sameSandboxIsVerifiedOncePerTransaction() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        IdentityMock mock=new IdentityMock(UserInfo.getOrganizationId(),true,200,false);
        Test.setMock(HttpCalloutMock.class,mock);
        ToolingApiClient.query('SELECT Id FROM ApexTrigger');
        ToolingApiClient.post('MetadataContainer','{}');
        System.assertEquals(3,mock.calls,'Two Tooling calls share one identity preflight within the transaction.');
        System.assertEquals(2,mock.toolingCalls,'Verified operations must continue using the Named Credential.');
    }
    @IsTest static void diagnosticVerifiesIdentityWithoutToolingMutation() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        IdentityMock mock=new IdentityMock(UserInfo.getOrganizationId(),true,200,false);
        Test.setMock(HttpCalloutMock.class,mock);
        System.assertEquals('HTTP 200: same sandbox verified',ToolingApiClient.diagnoseConnection(),
            'Diagnostic must report a verified same-sandbox connection.');
        System.assertEquals(0,mock.toolingCalls,'Diagnostic must not access Tooling mutation endpoints.');
    }
}
