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
 * Minimal Tooling API HTTP client for self-org callouts (query + single-record PATCH).
 * Shared by AutomationMetadataToggleService and ComplianceCategorizationService-style
 * integrations.
 *
 * PREREQUISITE: requires a Remote Site Setting authorizing callouts to this org's own
 * My Domain URL (Setup > Remote Site Settings > New, URL = your My Domain). Uses
 * UserInfo.getSessionId() as the bearer token, which works from Anonymous Apex, Batch
 * Apex, and Scheduled Apex, but is blocked by Salesforce from being reused for
 * callouts when the session originates from a Visualforce/LWC page request - by
 * design, every caller in this framework only invokes Tooling API operations from
 * synchronous Apex triggered by a button click's server round-trip (not the session
 * itself), which works fine in practice, but keep this restriction in mind if you
 * extend this class.
 */
public with sharing class ToolingApiClient {

    private static final String API_VERSION = 'v66.0';

    public class ToolingApiException extends Exception {}

    // Read-only diagnostic. Never returns or logs an API session token.
    public static String diagnoseConnection() {
        String sid = UserInfo.getSessionId();
        if (String.isBlank(sid)) return 'NO_SESSION';
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(Url.getOrgDomainUrl().toExternalForm() +
                '/services/data/' + API_VERSION + '/tooling/query/?q=' +
                EncodingUtil.urlEncode('SELECT Id FROM ApexClass LIMIT 1', 'UTF-8'));
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + sid);
            req.setHeader('Accept', 'application/json');
            req.setTimeout(20000);
            HttpResponse res = new Http().send(req);
            return 'HTTP ' + res.getStatusCode();
        } catch (Exception ex) {
            // Avoid exposing exception contents, which can contain endpoint details.
            return 'CALLOUT_ERROR';
        }
    }



    public static Map<String, Object> query(String soql) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(Url.getOrgDomainUrl().toExternalForm() +
            '/services/data/' + API_VERSION + '/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new ToolingApiException('Tooling API query failed (HTTP ' + res.getStatusCode() + '): ' + res.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /** Create a Tooling API record and return its Id. */
    public static String post(String sobjectType, String jsonBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(Url.getOrgDomainUrl().toExternalForm() + '/services/data/' + API_VERSION + '/tooling/sobjects/' + sobjectType);
        req.setMethod('POST'); req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId()); req.setHeader('Content-Type', 'application/json'); req.setBody(jsonBody); req.setTimeout(20000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 201) throw new ToolingApiException('Tooling API create failed for ' + sobjectType + ' (HTTP ' + res.getStatusCode() + '): ' + res.getBody());
        return (String)((Map<String,Object>)JSON.deserializeUntyped(res.getBody())).get('id');
    }

    /** PATCH a single Tooling API sobject record. jsonBody is the raw request body, e.g. {"Metadata":{"active":false}}. */
    public static void patch(String sobjectType, String recordId, String jsonBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(Url.getOrgDomainUrl().toExternalForm() +
            '/services/data/' + API_VERSION + '/tooling/sobjects/' + sobjectType + '/' + recordId);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonBody);
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        // Tooling API PATCH returns 204 No Content on success.
        if (res.getStatusCode() != 204) {
            throw new ToolingApiException('Tooling API update failed for ' + sobjectType + '/' + recordId +
                ' (HTTP ' + res.getStatusCode() + '): ' + res.getBody());
        }
    }
}
