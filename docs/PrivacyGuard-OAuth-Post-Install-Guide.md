# PrivacyGuard — OAuth and Named Credential post-install guide

Version: 1.0 · 3 November 2026 (Sydney)

Applies to managed package 0.2.0.1, subscriber version `04tQE00000jQRU5YAO`, namespace `privacyguard`. Target for current testing: Pguard sandbox.

## Purpose and boundaries

This configuration allows approved users to read and change supported Apex trigger metadata through Salesforce APIs in the **same sandbox**. PrivacyGuard authenticates each user separately. Installing the package alone does not populate OAuth secrets or authenticate users.

Production masking/deletion and cross-org Tooling calls are blocked by the application. Do not point a sandbox credential at production. Trigger metadata management is privileged; grant it only to approved administrators. Flow and validation-rule metadata toggling is outside this feature's scope.

## What is installed versus configured by the customer

| Component | Installed API name / value | Post-install action |
|---|---|---|
| External Auth Identity Provider | `privacyguard__PrivacyGuard_Tooling_OAuth` | Supply the customer's OAuth app client ID/secret; verify endpoints and generated callback. |
| External Credential | `privacyguard__PrivacyGuard_Tooling_OAuth` | Verify Browser Flow, provider link, scopes and principal. |
| Principal parameter name | `PrivacyGuard_User` | Keep Per User Principal, sequence 1. Do not create a duplicate. |
| OAuth permission set | `privacyguard__PrivacyGuard_Tooling_Access` | Assign to each approved user. |
| Admin permission set | `privacyguard__PrivacyGuard_Admin` | Assign to administrators who need the packaged functionality. |
| External Client App | Customer-owned; suggested name `PrivacyGuard Tooling` | Create/configure in the target sandbox. Not included by this package design. |
| Named Credential | Customer-owned, API name **`PrivacyGuard_Tooling`** | Create in target sandbox and link to installed External Credential. |
| Per-user access/refresh tokens | Not packaged | Each approved user authenticates after setup. |

Labels may omit namespace prefixes. Confirm API names and package origin, especially if similarly named unmanaged components already exist. The customer-owned Named Credential must retain its unprefixed API name because Apex uses `callout:PrivacyGuard_Tooling`.

## 1. Record the target sandbox domain

Use Setup → My Domain to obtain the target sandbox's Salesforce My Domain URL. Use the `my.salesforce.com` domain, not `lightning.force.com`.

Record these values privately:

| Value | Target-specific entry |
|---|---|
| Target org / sandbox | Pguard |
| My Domain base URL | `https://<company>--<sandbox>.sandbox.my.salesforce.com` |
| OAuth authorize URL | `<My Domain base URL>/services/oauth2/authorize` |
| OAuth token URL | `<My Domain base URL>/services/oauth2/token` |
| Callback URL | Copy from the **installed provider's detail page**; do not construct it. |

Do not reuse PGTEST's domain. Domain examples here are placeholders, not values to paste unchanged.

## 2. Inspect the installed provider and copy its callback

1. Open Setup → Named Credentials and locate **External Auth Identity Providers** (the section/tab name can vary by Salesforce release).
2. Open the installed PrivacyGuard Tooling OAuth provider. Check the API name/package origin.
3. Copy its generated **Callback URL** exactly for the External Client App.
4. Verify protocol **OAuth 2.0**, flow **Authorization Code (Browser Flow)**, and **PKCE enabled**.

Managed-package callbacks can include namespace information. The callback seen during unmanaged PGTEST development is not authoritative for this installation. Always use the callback displayed by the installed provider. If a required field is not editable in your installed version, stop and capture the screen; do not create a parallel unmanaged provider as a workaround.

## 3. Create the target sandbox's External Client App

1. Setup → External Client App Manager → New External Client App.
2. Set name **PrivacyGuard Tooling**, API name `PrivacyGuard_Tooling` (or another customer-owned app name), an administrator contact email and distribution **Local** for this sandbox-specific setup.
3. Enable OAuth.
4. Enter the exact callback copied in step 2.
5. Select scopes:
   - **Manage user data via APIs (`api`)**.
   - **Perform requests at any time (`refresh_token`, `offline_access`)**.
6. For this confidential server-side Browser Flow, enable **Require Secret for Web Server Flow** and **Require Secret for Refresh Token Flow**. Keep PKCE enabled. Keep platform-required refresh-token rotation enabled.
7. Do not enable Client Credentials, JWT, Device, Token Exchange or Headless Code and Credentials flows merely for this setup. Standard authorization-code Browser Flow is the intended design.
8. Create/save the app. Open its consumer/client details and copy the **client ID (consumer key)** and **client secret** privately.
9. Review OAuth policies. If **Admin approved users are pre-authorized** is selected, explicitly grant the app to the intended users through the appropriate profile/permission-set policy; the packaged principal-access permission set does not automatically provide this separate app approval.

Never put the client secret in Git, Apex, Custom Metadata, screenshots or this guide. Preserve existing organization session/IP policies; do not disable them to make authentication work.

## 4. Populate the installed External Auth Identity Provider

Edit the installed provider using its supported credential-edit action:

| Setting | Value |
|---|---|
| Client ID | Target sandbox External Client App's consumer key |
| Client Secret | Target sandbox app's secret |
| Authorize Endpoint URL | Target sandbox My Domain + `/services/oauth2/authorize` |
| Token Endpoint URL | Target sandbox My Domain + `/services/oauth2/token` |
| User Info Endpoint URL | Leave blank for this implementation |
| Use PKCE | Enabled |
| Pass client credentials in request body | Unchecked — package uses `ClientSecretBasic` |

The package defaults OAuth endpoints to `test.salesforce.com`. Target-specific My Domain endpoints make the intended sandbox explicit; verify editable settings in the installed component. Save and confirm the callback still exactly matches the External Client App.

## 5. Verify the installed External Credential

Setup → Named Credentials → External Credentials → installed PrivacyGuard Tooling OAuth.

| Setting | Expected value |
|---|---|
| Authentication Protocol | OAuth 2.0 |
| Authentication Flow Type | Browser Flow |
| Identity Provider | Installed PrivacyGuard Tooling OAuth provider |
| Scope | `api refresh_token` |
| Additional Status Codes for Token Refresh | Blank unless a separately justified HTTP status is required |
| Principal parameter name | `PrivacyGuard_User` |
| Identity type | Per User Principal |
| Sequence | 1 |
| Principal-level scope | Blank; use credential-level scope |

**Do not put `api refresh_token` in Additional Status Codes.** That field is for HTTP response status codes.

## 6. Create the customer-owned Named Credential

Setup → Named Credentials → Named Credentials → New.

| Setting | Value |
|---|---|
| Label | PrivacyGuard Tooling |
| Name / API name | **`PrivacyGuard_Tooling`** |
| URL | Exact target sandbox My Domain base URL |
| Enabled for Callouts | On |
| External Credential | Installed `privacyguard__PrivacyGuard_Tooling_OAuth` |
| Generate Authorization Header | Checked |
| Allow Formulas in HTTP Header | Unchecked |
| Allow Formulas in HTTP Body | Unchecked |
| Client Certificate | None for this OAuth design |
| Outbound Network Connection | None unless organization networking requires one |
| Allowed Namespaces for Callouts | **`privacyguard`** |

Save. If this unprefixed Named Credential already exists, inspect it and deliberately update its provider link/URL rather than creating a duplicate. Do not delete working PGTEST components in another org. A Remote Site Setting is not needed for the named-credential callout route.

## 7. Assign access to approved users

For the authenticated CLI user in Pguard, run in PowerShell:

```powershell
sf org assign permset --name privacyguard__PrivacyGuard_Admin --target-org Pguard
sf org assign permset --name privacyguard__PrivacyGuard_Tooling_Access --target-org Pguard
```

For other users use Setup → Permission Sets → relevant set → Manage Assignments.

Verify the installed Tooling Access permission set grants the installed credential's `PrivacyGuard_User` principal. Also verify the users have the existing PrivacyGuard permission for metadata deactivation and the Salesforce API/metadata permissions required for the supported trigger operation. Do not grant broader permissions solely to silence a scanner warning.

For **Per User OAuth**, custom user permission sets may also need **Read, Create, Edit and Delete** on **User External Credentials**, as documented by Salesforce. Verify effective access; do not assume the small packaged principal-mapping permission set grants these object permissions. Standard profiles may already supply them.

## 8. Authenticate each user

1. Sign in to Lightning as the actual approved user.
2. Open avatar → Settings → search **External Credentials** in personal settings.
3. Locate the installed PrivacyGuard credential and choose **Authenticate** (or its equivalent action).
4. Authenticate as that same user in the **target sandbox** and approve the app if prompted.
5. Return and confirm authentication completed.

Each user must perform this step. An admin's successful authentication does not authenticate another user's principal. Do not change to Named Principal as a shortcut. Async work needs the initiating/executing user's valid credential and effective access.

## 9. Validate the managed installation

Use the installed PrivacyGuard UI. Do not rely on calling a package-internal public Apex class from subscriber Execute Anonymous; public is not the same as global.

| Check | Expected result |
|---|---|
| Read/list supported trigger metadata | Completes without credential errors |
| Namespaced trigger row | Protected/not selectable for changes |
| Approved test trigger deactivate | Operation completes and verified state is Inactive |
| Same test trigger reactivate | Operation completes and verified state is Active |
| User without required PrivacyGuard access | Operation denied |
| NC accidentally targets a different org or production | Application fails closed; no metadata change |
| Masking completion / cancellation | Original cooperative bypass flags restored |

Use an appropriate test trigger in the sandbox. Preserve before/after results. Confirm the target remains the same sandbox throughout. A successful request alone does not prove refresh-token renewal; verify renewal separately under your organization's approved token/session policy.

## 10. Production installation and sandbox refresh

Installing metadata in production does not authorize destructive execution there. For a production-to-sandbox refresh lifecycle:

1. Treat copied OAuth configuration as needing reconciliation, not automatically ready.
2. Confirm the refreshed sandbox domain and installed package version.
3. Inspect the External Client App; verify/recreate its sandbox-local configuration and credentials as necessary.
4. Copy the refreshed installed provider callback and update the app to match.
5. Recheck authorize/token URLs and the Named Credential URL; no production URL should remain.
6. Confirm the installed provider/credential links, `privacyguard` namespace allowance and permission-set assignments.
7. Populate missing credentials through supported setup actions and reauthenticate each operator.
8. Repeat same-sandbox read and test-trigger checks before enabling real jobs.

Do not assume refresh tokens, secrets or authenticated per-user state survive installation, sandbox copy or refresh in a usable form. Do not hard-code sandbox names into package Apex. This release still needs these manual environment-specific setup steps; it has no automatic OAuth bootstrap/refresh repair.

## Troubleshooting

| Symptom | Check / action |
|---|---|
| Named Credential not found | Exact unprefixed API name `PrivacyGuard_Tooling`; enabled for callouts. |
| Principal/credential permission error | Installed credential selected, packaged principal access assigned, User External Credentials effective permissions, and user authenticated. |
| Works in source org but not managed install | Named Credential allowed namespace `privacyguard`; installed namespaced credential selected. |
| Redirect URI mismatch | Exact callback from installed provider; namespace, domain and case must match app registration. |
| Invalid client | Correct target app key/secret and ClientSecretBasic; confirm saved secret and app policy. |
| Authentication succeeds but access later expires | `api refresh_token` scope, app refresh policy, per-user credential permissions and token status; reauthenticate after fixing. |
| 401/403 during API operation | Credential/token state, API permission and least-privilege metadata rights. Do not log tokens. |
| Same-org / sandbox validation error | NC base URL and identity must resolve to the executing sandbox. |
| Trigger remains queued/failed | Inspect operation status and safe error details; authentication success alone is not proof of deployment permission. |
| No provider credential-edit action | Capture installed component details and supported actions for review; do not invent an alternate unmanaged chain. |

## Handover record

Record package version, org ID, sandbox domain, setup date/operator, selected installed provider/credential, callback, permission-set assignments and validation results. Store secrets only in approved secret storage. Keep authentication evidence separate from application/security-review claims.

## Official references

- Named Credential packaging and customer-owned namespace allowance: https://developer.salesforce.com/docs/platform/named-credentials/guide/nc-package-credentials.html
- Post-install external credential population: https://developer.salesforce.com/docs/platform/named-credentials/guide/nc-populate-external-credentials.html
- OAuth credential Browser Flow: https://help.salesforce.com/s/articleView?id=xcloud.nc_create_edit_oath_browser_ext_cred.htm&language=en_US&type=5
- OAuth web server flow: https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_web_server_flow.htm&language=en_US&type=5
- Principal access: https://help.salesforce.com/s/articleView?id=sf.nc_enable_ext_cred_principal.htm&language=en_US&type=5
- User External Credentials permissions: https://help.salesforce.com/s/articleView?id=sf.nc_user_external_credentials_permissions.htm&language=en_US&type=5
- My Domain / managed callback behavior: https://help.salesforce.com/s/articleView?id=release-notes.rn_security_named_credentials.htm&language=en_US&release=262&type=5

This guide is based on the delivered metadata and the successful unmanaged PGTEST setup. The installed managed Pguard credential chain still requires the validation above; screen labels and editable actions may differ by Salesforce release.
