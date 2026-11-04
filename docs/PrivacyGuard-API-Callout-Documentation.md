# PrivacyGuard API Callout Documentation

**Document version:** 1.0  
**Prepared:** 4 November 2026  
**Product:** PrivacyGuard, namespace `privacyguard`  
**Purpose:** API integration register and data-flow evidence for installation, administration and Salesforce security review.

## 1. Scope and evidence baseline

This document describes the implementation in the supplied `force-app(20261103-052010).zip`, together with the packaged OAuth credential configuration discussed during release preparation. It is not an independent verification of the current GitHub head or the contents of an installed package.

The candidate package version is **0.2.0.1**, subscriber package version ID **04tQE00000jQRU5YAO**. Installation was reported successful. The last supplied package report showed `Released=false`; promotion and security-review approval are not established by that report. Before submission, reconcile this register with the exact released source and installed review environment.

The production Apex HTTP inventory in the supplied source resolves to `ToolingApiClient.cls`. Test mocks are excluded. This register covers the active Apex callouts and the OAuth service endpoints needed to authorize them.

## 2. Integration overview

PrivacyGuard calls Salesforce in the **same executing sandbox** to inspect and change the status of eligible, non-namespaced Apex triggers. It uses Salesforce REST API and Tooling API version **v66.0** through a customer-configured Named Credential.

| Property | Implementation |
| --- | --- |
| Apex endpoint alias | `callout:PrivacyGuard_Tooling` |
| Named Credential API name | `PrivacyGuard_Tooling` |
| Base URL | Exact executing sandbox My Domain, for example `https://<company>--<sandbox>.sandbox.my.salesforce.com` |
| Transport | HTTPS |
| Authentication | OAuth 2.0 authorization code browser flow with PKCE; per-user principal |
| Recipient | Customer's Salesforce sandbox; no third-party analytics or masking service identified in this HTTP inventory |
| HTTP timeout | 20,000 milliseconds per request |
| Response format | JSON |
| General-purpose API proxy | Not provided; resource names are restricted in the adapter |

Do not use the Lightning UI hostname as the API base URL. The destination is administrator configured, but PrivacyGuard verifies the remote organization before allowing Tooling operations.

## 3. Callout register

All paths below are relative to the Named Credential base URL. `q` contains URL-encoded SOQL. Each transaction verifies the destination before its first Tooling operation; subsequent operations in that transaction reuse the successful check.

| ID | Method and path | Purpose and request | Response used | Expected HTTP status |
| --- | --- | --- | --- | --- |
| API-01 | `GET /services/data/v66.0/query/?q={SOQL}` | Preflight: `SELECT Id, IsSandbox FROM Organization LIMIT 1` | Exactly one organization; matching org ID and `IsSandbox=true` | 200 |
| API-02 | `GET /services/data/v66.0/tooling/query/?q={SOQL}` | Fetch selected trigger: `SELECT Id, Name, Body, ApiVersion, NamespacePrefix FROM ApexTrigger WHERE Id = '{triggerId}' LIMIT 1` | Trigger identity, source body, API version and namespace | 200 |
| API-03 | `POST /services/data/v66.0/tooling/sobjects/MetadataContainer` | Create a deployment container with a generated `PG_...` name | Created container `id` | 201 |
| API-04 | `POST /services/data/v66.0/tooling/sobjects/ApexTriggerMember` | Stage original trigger body with requested status and API version | Created member `id` | 201 |
| API-05 | `POST /services/data/v66.0/tooling/sobjects/ContainerAsyncRequest` | Submit deployment with `IsCheckOnly=false` | Deployment request `id` | 201 |
| API-06 | `GET /services/data/v66.0/tooling/query/?q={SOQL}` | Poll: `SELECT Id, State, ErrorMsg, DeployDetails FROM ContainerAsyncRequest WHERE Id = '{requestId}'` | Deployment state and diagnostic details | 200 |
| API-07 | `GET /services/data/v66.0/tooling/query/?q={SOQL}` | Verify: `SELECT Id, Status FROM ApexTrigger WHERE Id = '{triggerId}'` | Actual final trigger status | 200 |

IDs in these queries are escaped with `String.escapeSingleQuotes` by the queueable caller. The adapter permits query resources `ApexTrigger`, `ContainerAsyncRequest` and `ApexClass`. The inspected trigger-toggle path does not use an `ApexClass` query. The adapter's resource regular expression is not a complete SOQL parser and must not be treated as proof that every possible caller is injection safe.

The POST allowlist contains only `MetadataContainer`, `ApexTriggerMember` and `ContainerAsyncRequest`. The adapter's direct `patch` method rejects the operation. Retired Flow/validation-rule metadata mutation is not part of this supported callout path.

## 4. Representative payloads

These examples are structural and contain placeholders, not customer credentials or live deployment IDs.

### API-03: Create container

```json
{
  "Name": "PG_<generated-identifier>"
}
```

### API-04: Stage trigger member

```json
{
  "MetadataContainerId": "<container-id>",
  "ContentEntityId": "<trigger-id>",
  "Body": "<existing-trigger-Apex-source>",
  "Metadata": {
    "status": "Inactive",
    "apiVersion": 66.0
  }
}
```

The requested status is restricted to `Active` or `Inactive`. The API version is read from the existing trigger; the example does not mean all triggers are rewritten to version 66.0. The source body is read from Salesforce and sent back unchanged by this caller.

### API-05: Submit deployment

```json
{
  "MetadataContainerId": "<container-id>",
  "IsCheckOnly": false
}
```

This is an actual metadata deployment, not validation only. A successful submission response means Salesforce accepted the request; it does not prove the trigger changed state.

## 5. OAuth endpoints and credential ownership

OAuth authorization and token exchange are handled by Salesforce credential infrastructure, separately from the Apex business callouts above.

| Item | Configuration and use |
| --- | --- |
| External Credential | Installed `privacyguard__PrivacyGuard_Tooling_OAuth` |
| Principal | `PrivacyGuard_User`, per-user principal, sequence 1 |
| External Auth Identity Provider | Installed `privacyguard__PrivacyGuard_Tooling_OAuth` |
| OAuth scopes | `api refresh_token` |
| Authorization endpoint | `/services/oauth2/authorize` on the configured Salesforce authorization host; browser authorization |
| Token endpoint | `/services/oauth2/token` on that host; authorization code exchange and refresh handled by Salesforce |
| Packaged provider endpoint defaults | `https://test.salesforce.com/services/oauth2/authorize` and `https://test.salesforce.com/services/oauth2/token` |
| Environment-specific configuration | Configure the provider for the intended sandbox, using its exact My Domain endpoints where required by the installation design |
| Callback | Copy the exact callback URL displayed by the installed provider into the customer's External Client App; do not reconstruct it or reuse an unmanaged provider callback |
| Client authentication | `ClientSecretBasic`; client credentials in request body disabled |
| PKCE | Enabled |
| Client ID and secret | Customer supplies the External Client App values to the installed provider using supported configuration actions |

No client secret, access token or refresh token is embedded in Apex source. Apex does not retrieve a session ID or build a bearer header. The Named Credential generates the Authorization header; Salesforce manages the per-user credential material. Do not include secrets or tokens in screenshots, support attachments or review documents.

The Named Credential must enable callouts and authorization-header generation, reference the installed External Credential, and allow namespace `privacyguard`. Header/body formula options are not required. A separate Remote Site Setting is not required for this Named Credential route.

The broad `api` scope does not itself grant every operation: the authenticated Salesforce user's platform permissions, app policies and package authorization also apply. Each authorized operator completes their own OAuth authentication. A shared named principal is not the implementation described here.

## 6. Authorization and target validation

Before the adapter sends a request, it checks the package metadata-deactivation custom permission and the local environment safety guard. The trigger queueable independently checks that permission and sandbox status.

| Control | Required behavior |
| --- | --- |
| Package operation permission | `Use_PrivacyGuard_Metadata_Deactivation` |
| Packaged permission set for operation | `privacyguard__PrivacyGuard_Metadata_Deactivation_Break_Glass` |
| Principal access permission set | `privacyguard__PrivacyGuard_Tooling_Access`; principal reference `privacyguard__PrivacyGuard_Tooling_OAuth-PrivacyGuard_User` |
| Platform permissions | Authenticated user must have the Salesforce API and metadata capabilities required for the intended operation; package permission sets do not establish all platform rights |
| Per-user credential access | Ensure effective User External Credentials access as required for the user's profile/permission sets |
| Local guard | Execution allowed only in a sandbox |
| Remote guard | One returned organization, ID length 15 or 18, first 15 characters matching `UserInfo.getOrganizationId()`, and `IsSandbox=true` |
| Failed or malformed preflight | No subsequent Tooling operation |
| Trigger eligibility | Namespaced triggers rejected; protected PrivacyGuard audit triggers rejected |

The remote check is cached only within an Apex transaction. Each subsequent queueable transaction performs its own check. Production installation does not authorize production trigger changes, and a sandbox configured to point to production or another sandbox must fail the identity check.

## 7. Execution and state handling

1. User requests an eligible trigger state change; the workflow requires a restoration-tracking record.
2. Queueable checks authorization, local sandbox status and requested status.
3. Adapter verifies the remote organization.
4. Queueable reads the trigger, checks namespace/protected identity, creates a container and member, and submits a deployment request.
5. After the submission callouts, it persists the request ID and progress to `Deactivated_Automation__c` and schedules a status check.
6. Later queueables poll the saved request. A completed deployment is followed by a separate actual-status query.
7. `Succeeded` is recorded only when the actual status matches the requested state. Successful activation updates restoration tracking.

Pending deployment states remain queued/in progress. Terminal Salesforce states `Failed`, `Error`, `Aborted` and `Invalidated` are recorded as failures. Polling is scheduled with a one-minute delay request; actual timing depends on Salesforce scheduling. The code caps automatic checks at 60, then records `Check required`. An operator can resume checking through **Check Deployment Status**.

An API/polling error after a request ID exists means the outcome is unknown; it is not evidence the deployment failed. Reconcile the existing request before starting another change. The queueable ignores obsolete polls whose request ID no longer matches the tracking record. There is no general automatic retry policy for failed POST requests and no automatic rollback guarantee. Bypass-flag restoration and trigger metadata restoration are separate concerns.

## 8. Data transmitted, received and retained

| Data category | Movement and purpose | Exposure/retention consideration |
| --- | --- | --- |
| Organization ID and sandbox indicator | Salesforce to Apex during target verification | Organization identity metadata |
| Trigger ID, name, namespace, API version and status | Salesforce to Apex for eligibility and verification | Customer configuration metadata |
| Trigger Apex body | Salesforce to Apex, then back to same sandbox in `ApexTriggerMember` | Source code may contain sensitive embedded literals; this is not merely status-only traffic |
| Container/member/request IDs | Salesforce to Apex | Request ID persisted for reconciliation; container/member IDs used during submission |
| Deployment errors and details | Salesforce to Apex, tracking and logs | May expose source references, component names or sensitive diagnostic content |
| OAuth code/client credentials/tokens | Browser and Salesforce OAuth infrastructure | Not handled as business payloads by `ToolingApiClient`; keep out of application logs and support exports |

This trigger-toggle path does not intentionally send masking-record field values, file bodies or attachments as API payloads. This statement is limited to the inspected path and does not assert that trigger source or diagnostic text is free of sensitive information.

`Deployment_Message__c` and queueable logging receive bounded diagnostic strings, clipped to 32,000 characters by this caller. Clipping is not redaction. Audit/log access and retention must follow the customer's data-handling policy. No automatic deletion of deployment containers or universal log-retention period is established by the inspected implementation.

## 9. Failure handling and operational limits

| Condition | Behavior / operator response |
| --- | --- |
| HTTP response other than expected 200/201 | Adapter throws an exception containing operation/resource and status rather than intentionally returning the raw response body |
| Callout exception | Adapter returns a bounded OAuth/configuration error; check authorization, principal access, namespace and URL |
| Missing/wrong target organization | Fail closed; correct the Named Credential URL and authorization |
| Missing per-user authorization or insufficient platform rights | Authenticate/authorize the correct user and review least-privilege platform access |
| Completed request but wrong/unreadable trigger status | `Check required`; inspect and reconcile actual status |
| Poll limit reached or transient polling error | Keep saved request ID; resume checking instead of assuming failure |
| Malformed JSON or unexpected response shape | Can raise processing exceptions; do not claim every parser error is sanitized |
| Salesforce limits | HTTP timeouts, callout/queueable limits, API allocation and metadata-deployment restrictions still apply |

There is no external network proxy or custom certificate pinning implemented in this client. HTTPS and Named Credential behavior rely on the Salesforce platform. API version upgrades require code/release validation; the client's version is fixed at `v66.0`.

## 10. Reviewer verification checklist

Record actual results and evidence references for the exact submitted package. These are acceptance tests, not claims of completed testing.

| Test | Expected result |
| --- | --- |
| Authenticate authorized per-user operator in installed sandbox | Same-sandbox connection succeeds without exposing tokens |
| User lacks operation custom permission | Operation denied before business callouts |
| User lacks principal access or OAuth authorization | Callout cannot proceed; configuration guidance available |
| Local production execution attempt | Blocked |
| Destination is another sandbox or production | Identity/sandbox preflight blocks Tooling operations |
| Non-namespaced sample trigger inactive then active | Request IDs persisted; actual status verified for both operations |
| Namespaced or protected audit trigger selected | Rejected before mutation |
| Pending request / interrupted status check | Never reported successful merely because submission/job execution succeeded |
| Resume status checking | Existing request reconciled; no unnecessary duplicate submission |
| Review logs and tracking exports | No OAuth secrets; diagnostic sensitivity assessed and access restricted |

Source test classes include `ToolingApiClientTest.cls` and `AutomationTriggerProgressTest.cls`. Mock tests do not replace installed-package OAuth and real deployment evidence. Earlier positive PGTEST testing does not by itself establish that the managed installation in Pguard has passed every case above.

## 11. Source references and maintenance

| Source | Responsibility |
| --- | --- |
| `force-app/main/default/classes/ToolingApiClient.cls` | HTTP transport, fixed alias/version, resource allowlists, permissions and same-sandbox preflight |
| `force-app/main/default/classes/AutomationTriggerToggleQueueable.cls` | Trigger payloads, deployment submission, polling, final-state verification and tracking |
| `force-app/main/default/classes/PrivacyGuardSecurityService.cls` | Custom-permission authorization |
| `force-app/main/default/classes/EnvironmentSafetyService.cls` | Sandbox execution guard |
| Packaged External Credential / External Auth Identity Provider / Tooling Access permission set | OAuth configuration, principal and principal access |
| PrivacyGuard OAuth Post-Install Guide | Detailed customer configuration procedure |

Update this register whenever endpoints, API version, scopes, principal type, payloads, allowlists, error handling or remote services change. Attach package-matched test evidence and complete the separate Salesforce submission requirements; this document alone is not a security approval or a replacement for scan reports.
