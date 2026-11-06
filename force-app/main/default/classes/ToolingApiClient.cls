/**
 * @class         ToolingApiClient
 * @description   Apex class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
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
/**
 * OAuth Tooling transport through the subscriber-owned PrivacyGuard_Tooling
 * Named Credential. Salesforce manages tokens; Apex never reads session IDs or
 * builds authorization headers. Every transaction verifies the remote org identity
 * and sandbox status before accessing Tooling metadata.
 */
public with sharing class ToolingApiClient {

    private static final String API_VERSION = 'v66.0';
    private static final String ENDPOINT = 'callout:privacyguard__PrivacyGuard_Tooling';
    private static Boolean targetVerified = false;

    public class ToolingApiException extends Exception {}

    // No credentials or response bodies are exposed by this diagnostic.
    public static String diagnoseConnection() {
        authorize();
        try {
            verifyTargetOrg();
            return 'HTTP 200: same sandbox verified';
        } catch (ToolingApiException ex) {
            return 'CONFIGURATION_ERROR: Verify PrivacyGuard_Tooling OAuth authorization, principal access, allowed namespace and same-sandbox URL.';
        }
    }

    public static Map<String, Object> query(String soql) {
        authorize();
        if (String.isBlank(soql) || !Pattern.compile('(?i)^\\s*SELECT\\s+.+\\s+FROM\\s+(ApexTrigger|ContainerAsyncRequest|ApexClass)(\\s|$)').matcher(soql).find()) {
            throw new ToolingApiException('Only PrivacyGuard trigger deployment queries are supported.');
        }
        verifyTargetOrg();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT +
            '/services/data/' + API_VERSION + '/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'));
        req.setMethod('GET');
        req.setTimeout(20000);

        HttpResponse res = send(req);
        if (res.getStatusCode() != 200) {
            throw new ToolingApiException('Tooling API query failed (HTTP ' + res.getStatusCode() + ').');
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /** Create a Tooling API record and return its Id. */
    public static String post(String sobjectType, String jsonBody) {
        authorize();
        if (!new Set<String>{'MetadataContainer','ApexTriggerMember','ContainerAsyncRequest'}.contains(sobjectType)) {
            throw new ToolingApiException('Unsupported Tooling API resource.');
        }
        verifyTargetOrg();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT + '/services/data/' + API_VERSION + '/tooling/sobjects/' + sobjectType);
        req.setMethod('POST'); req.setHeader('Content-Type', 'application/json'); req.setBody(jsonBody); req.setTimeout(20000);
        HttpResponse res = send(req);
        if (res.getStatusCode() != 201) throw new ToolingApiException('Tooling API create failed for ' + sobjectType + ' (HTTP ' + res.getStatusCode() + ').');
        return (String)((Map<String,Object>)JSON.deserializeUntyped(res.getBody())).get('id');
    }

    /** Compatibility endpoint: direct metadata PATCH operations are retired. */
    public static void patch(String sobjectType, String recordId, String jsonBody) {
        authorize();
        throw new ToolingApiException('Direct metadata PATCH is not supported. Use controlled Apex trigger deployment.');
    }
    private static void authorize() {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) {
            throw new PrivacyGuardSecurityService.PrivacyGuardAuthorizationException('You do not have permission to manage automation metadata.');
        }
        EnvironmentSafetyService.assertExecutionAllowed();
    }
    private static void verifyTargetOrg() {
        if (targetVerified) return;
        HttpRequest req=new HttpRequest();
        req.setEndpoint(ENDPOINT + '/services/data/' + API_VERSION + '/query/?q=' +
            EncodingUtil.urlEncode('SELECT Id, IsSandbox FROM Organization LIMIT 1','UTF-8'));
        req.setMethod('GET');req.setHeader('Accept','application/json');req.setTimeout(20000);
        HttpResponse res=send(req);
        if (res.getStatusCode()!=200) {
            throw new ToolingApiException('Could not verify the OAuth target org (HTTP '+res.getStatusCode()+').');
        }
        try {
            Map<String,Object> data=(Map<String,Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> records=(List<Object>)data.get('records');
            if (records==null || records.size()!=1) throw new ToolingApiException('Target identity unavailable.');
            Map<String,Object> org=(Map<String,Object>)records[0];
            String remoteId=(String)org.get('Id');
            String localId=UserInfo.getOrganizationId();
            if (String.isBlank(remoteId) || (remoteId.length()!=15 && remoteId.length()!=18) ||
                remoteId.left(15)!=localId.left(15) || org.get('IsSandbox')!=true) {
                throw new ToolingApiException('The Named Credential must connect to this same sandbox org.');
            }
        } catch (ToolingApiException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ToolingApiException('The OAuth target org identity could not be verified. No Tooling operation was sent.');
        }
        targetVerified=true;
    }
    private static HttpResponse send(HttpRequest req) {
        try {
            return new Http().send(req);
        } catch (CalloutException ex) {
            throw new ToolingApiException('OAuth callout unavailable. Configure and authorize the PrivacyGuard_Tooling Named Credential for the running user.');
        }
    }
}
