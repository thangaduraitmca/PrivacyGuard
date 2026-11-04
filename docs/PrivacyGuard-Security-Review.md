# PrivacyGuard: security review and justification register — 23 findings

Updated 3 November 2026 (Australia/Sydney).

Baseline source: force-app(20261103-052010).zip plus privacyguard-bypass-restoration-fix.zip. Latest submission scan: CodeAnalyzerReport(2).csv. The final complete packaged source has not been independently compared against this combination.

## Result

The original 20 findings were traced to the supplied source. The restoration patch introduced three further findings, assessed below. This review has not established an exploitable injection, missing business-record CRUD/FLS check, or credential stored in the eight flagged fields. These are evidence-backed justification candidates, not Salesforce-approved exceptions or a complete security audit.

The bypass restoration patch was delivered separately. The project owner reported deployment and successful manual testing. No suppression, broader permissions or field visibility change was proposed merely to reduce scanner counts. Detailed deployment/test outputs and scenario evidence have not been supplied.

## Latest scan results

| Rule | High | Moderate | Total |
|---|---:|---:|---:|
| ApexCRUDViolation | 12 | 0 | 12 |
| ApexSOQLInjection | 3 | 0 | 3 |
| ProtectSensitiveData | 0 | 8 | 8 |
| **Total** | **15** | **8** | **23** |

There are zero critical findings and no engine-error rows in CodeAnalyzerReport(2).csv. This does not independently prove complete scan coverage; retain full console/log output.

The earlier all-PMD scan reported 2,354 findings (163 high, 1,478 moderate, 713 low). The submission scan selects AppExchange and Recommended:Security rules rather than all quality rules. The omitted quality findings were not thereby fixed.

The previous clean console run executed PMD, ESLint, Regex and RetireJS. Its log stated that no Flow files were targeted, explaining why no Flow rules ran. The summary's “13 files” referred to files containing findings, not a total scanned-file count. That earlier log is not evidence for every later run.

Command used for submission reports:

```powershell
sf code-analyzer run --workspace . --target force-app --rule-selector AppExchange --rule-selector Recommended:Security --output-file CodeAnalyzerReport.html --output-file CodeAnalyzerReport.csv
```

## Disposition summary

| Category | Count | Proposed treatment |
|---|---:|---|
| Platform sandbox check | 1 | Document intentional safety query and fail-closed behavior. |
| Custom Metadata reads | 6 | Document configuration reads and separate user-mode business/configuration access. |
| Internal coordination reads | 5 | Document permission gates, bounded queries and intended system-state handling. |
| Schema-validated dynamic SOQL | 3 | Document canonical identifiers and user mode; retain malicious-input tests. |
| Fields flagged as credential storage | 8 | Document types and actual intended contents; assess integrity/access separately. |

All remain provisional until relevant test evidence is retained. A finding being a secret-storage false positive does not mean the underlying setting is safe to modify without authorization.

## Finding-by-finding evidence

### PG-SEC-01: ApexCRUDViolation

- Source: `force-app\main\default\classes\EnvironmentSafetyService.cls` at line 52.
- Classification: Platform safety-check exception candidate.
- Evidence: Static query reads only Organization.IsSandbox for an authoritative sandbox gate. No record data is returned to a client by this query. Query failure returns false and blocks execution. Keeping this gate independent of business-user CRUD is intentional. Its Apex metadata API version is 66.0; do not assume future API default-mode behavior is identical.
- Located source: `return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;`

### PG-SEC-02: ApexSOQLInjection

- Source: `force-app\main\default\classes\FileAttachmentPurgeController.cls` at line 114.
- Classification: Schema-allowlist exception candidate.
- Evidence: requireEligibleObject rejects unknown/excluded names and checks query/read/create/update eligibility. The concatenated object is subsequently resolved again from Schema.getGlobalDescribe() and getDescribe().getName(). Remaining query text is fixed, and both count queries use WITH USER_MODE. A failed count produces a warning, not an authorization bypass.
- Located source: `'SELECT count() FROM Attachment WHERE ParentId IN (SELECT Id FROM ' + canonical + ') WITH USER_MODE');`

### PG-SEC-03: ApexSOQLInjection

- Source: `force-app\main\default\classes\FileAttachmentPurgeController.cls` at line 116.
- Classification: Schema-allowlist exception candidate.
- Evidence: requireEligibleObject rejects unknown/excluded names and checks query/read/create/update eligibility. The concatenated object is subsequently resolved again from Schema.getGlobalDescribe() and getDescribe().getName(). Remaining query text is fixed, and both count queries use WITH USER_MODE. A failed count produces a warning, not an authorization bypass.
- Located source: `'SELECT count() FROM ContentDocumentLink WHERE LinkedEntityId IN (SELECT Id FROM ' + canonical + ') WITH USER_MODE');`

### PG-SEC-04: ApexCRUDViolation

- Source: `force-app\main\default\classes\MaskingConfigService.cls` at line 55.
- Classification: Custom-metadata read exception candidate.
- Evidence: Flagged query reads packaged custom metadata (Masking_Configuration__mdt, Masking_Job_Sequence__mdt or PII_Keyword__mdt), not mutable business records. Nearby runtime custom-object configuration queries use WITH USER_MODE. Masking targets are separately schema/FLS validated. CMDT access is part of the Apex configuration design; document the precise read rather than granting extra object/FLS permissions to silence PMD.
- Located source: `for (Masking_Configuration__mdt cfg : [`

### PG-SEC-05: ApexCRUDViolation

- Source: `force-app\main\default\classes\MaskingConfigService.cls` at line 94.
- Classification: Custom-metadata read exception candidate.
- Evidence: Flagged query reads packaged custom metadata (Masking_Configuration__mdt, Masking_Job_Sequence__mdt or PII_Keyword__mdt), not mutable business records. Nearby runtime custom-object configuration queries use WITH USER_MODE. Masking targets are separately schema/FLS validated. CMDT access is part of the Apex configuration design; document the precise read rather than granting extra object/FLS permissions to silence PMD.
- Located source: `for (Masking_Job_Sequence__mdt job : [`

### PG-SEC-06: ApexCRUDViolation

- Source: `force-app\main\default\classes\MaskingJobOrchestrator.cls` at line 184.
- Classification: Privileged internal-state read exception candidate.
- Evidence: Private helper queries the single org-default Masking_Run_Tracker__c record by bound Id using FOR UPDATE. This is internal execution coordination, not business-record access. Public run/completion entry points require Run_PrivacyGuard_Masking and sandbox checks. Writes already explicitly use as system. Granting operators broad tracker edit access or enforcing their FLS here would change the internal control model. Public custom-setting visibility and concurrency/restoration caveats remain relevant.
- Located source: `Masking_Run_Tracker__c tracker = [SELECT Id, Total_Jobs__c, Completed_Jobs__c, Run_In_Progress__c, Run_Started_At__c`

### PG-SEC-07: ApexCRUDViolation

- Source: `force-app\main\default\classes\MaskingJobOrchestrator.cls` at line 197.
- Classification: Privileged internal-state read exception candidate.
- Evidence: Private helper queries the single org-default Masking_Run_Tracker__c record by bound Id using FOR UPDATE. This is internal execution coordination, not business-record access. Public run/completion entry points require Run_PrivacyGuard_Masking and sandbox checks. Writes already explicitly use as system. Granting operators broad tracker edit access or enforcing their FLS here would change the internal control model. Public custom-setting visibility and concurrency/restoration caveats remain relevant.
- Located source: `Masking_Run_Tracker__c tracker = [SELECT Id, Total_Jobs__c, Completed_Jobs__c, Run_In_Progress__c`

### PG-SEC-08: ApexCRUDViolation

- Source: `force-app\main\default\classes\MaskingJobOrchestrator.cls` at line 217.
- Classification: Privileged internal-state read exception candidate.
- Evidence: Private helper queries the single org-default Masking_Run_Tracker__c record by bound Id using FOR UPDATE. This is internal execution coordination, not business-record access. Public run/completion entry points require Run_PrivacyGuard_Masking and sandbox checks. Writes already explicitly use as system. Granting operators broad tracker edit access or enforcing their FLS here would change the internal control model. Public custom-setting visibility and concurrency/restoration caveats remain relevant.
- Located source: `Masking_Run_Tracker__c tracker = [SELECT Id, Run_In_Progress__c, Run_Started_At__c`

### PG-SEC-09: ApexCRUDViolation

- Source: `force-app\main\default\classes\MaskingJobOrchestrator.cls` at line 229.
- Classification: Privileged internal-state read exception candidate.
- Evidence: Private helper queries the single org-default Masking_Run_Tracker__c record by bound Id using FOR UPDATE. This is internal execution coordination, not business-record access. Public run/completion entry points require Run_PrivacyGuard_Masking and sandbox checks. Writes already explicitly use as system. Granting operators broad tracker edit access or enforcing their FLS here would change the internal control model. Public custom-setting visibility and concurrency/restoration caveats remain relevant.
- Located source: `Masking_Run_Tracker__c tracker = [SELECT Id, Run_In_Progress__c FROM Masking_Run_Tracker__c WHERE Id = :defaults.Id FOR UPDATE];`

### PG-SEC-10: ApexSOQLInjection

- Source: `force-app\main\default\classes\MaskingPreviewService.cls` at line 58.
- Classification: Schema-allowlist exception candidate.
- Evidence: Object comes from requireValidObject(...).getName(); selected fields come from describe.getName() after validateMaskingTarget; the Once checkbox comes from requireCheckbox(...), which returns describe.getName(). Only fixed WHERE/ORDER/LIMIT syntax is added. WITH USER_MODE enforces read access. No arbitrary WHERE clause or literal is accepted.
- Located source: `List<SObject> records=Database.query(soql);`

### PG-SEC-11: ApexCRUDViolation

- Source: `force-app\main\default\classes\PIIFieldScannerService.cls` at line 152.
- Classification: Custom-metadata read exception candidate.
- Evidence: Flagged query reads packaged custom metadata (Masking_Configuration__mdt, Masking_Job_Sequence__mdt or PII_Keyword__mdt), not mutable business records. Nearby runtime custom-object configuration queries use WITH USER_MODE. Masking targets are separately schema/FLS validated. CMDT access is part of the Apex configuration design; document the precise read rather than granting extra object/FLS permissions to silence PMD.
- Located source: `if (cachedKeywords == null) cachedKeywords = [SELECT Keyword__c FROM PII_Keyword__mdt];`

### PG-SEC-12: ApexCRUDViolation

- Source: `force-app\main\default\classes\PIIFieldScannerService.cls` at line 169.
- Classification: Custom-metadata read exception candidate.
- Evidence: Flagged query reads packaged custom metadata (Masking_Configuration__mdt, Masking_Job_Sequence__mdt or PII_Keyword__mdt), not mutable business records. Nearby runtime custom-object configuration queries use WITH USER_MODE. Masking targets are separately schema/FLS validated. CMDT access is part of the Apex configuration design; document the precise read rather than granting extra object/FLS permissions to silence PMD.
- Located source: `for (Masking_Configuration__mdt cfg : [`

### PG-SEC-13: ApexCRUDViolation

- Source: `force-app\main\default\classes\PrivacyGuardConfigurationController.cls` at line 195.
- Classification: Custom-metadata read exception candidate.
- Evidence: Flagged query reads packaged custom metadata (Masking_Configuration__mdt, Masking_Job_Sequence__mdt or PII_Keyword__mdt), not mutable business records. Nearby runtime custom-object configuration queries use WITH USER_MODE. Masking targets are separately schema/FLS validated. CMDT access is part of the Apex configuration design; document the precise read rather than granting extra object/FLS permissions to silence PMD.
- Located source: `for (PII_Keyword__mdt k : [SELECT Keyword__c FROM PII_Keyword__mdt ORDER BY Keyword__c]) {`

### PG-SEC-14: ApexCRUDViolation

- Source: `force-app\main\default\classes\PrivacyGuardConfigurationController.cls` at line 219.
- Classification: Custom-metadata read exception candidate.
- Evidence: Flagged query reads packaged custom metadata (Masking_Configuration__mdt, Masking_Job_Sequence__mdt or PII_Keyword__mdt), not mutable business records. Nearby runtime custom-object configuration queries use WITH USER_MODE. Masking targets are separately schema/FLS validated. CMDT access is part of the Apex configuration design; document the precise read rather than granting extra object/FLS permissions to silence PMD.
- Located source: `for (PII_Keyword__mdt d : [SELECT Keyword__c FROM PII_Keyword__mdt]) {`

### PG-SEC-15: ProtectSensitiveData

- Source: `force-app\main\default\objects\Automation_Bypass__c\fields\Bypass_All_Automations__c.field-meta.xml` at line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: The field is a Checkbox with default false. It contains a cooperative automation-bypass switch, not an OAuth token, password, encryption key or credential. Public custom-setting visibility supports subscriber automation references. This is NOT evidence that bypass governance is safe: review access and restoration risks separately (below). Do not change to Protected simply to hide the warning; subscriber formulas/code may depend on access.
- Located source: `<?xml version='1.0' encoding='UTF-8'?>`

### PG-SEC-16: ProtectSensitiveData

- Source: `force-app\main\default\objects\Automation_Bypass__c\fields\Bypass_Flows__c.field-meta.xml` at line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: The field is a Checkbox with default false. It contains a cooperative automation-bypass switch, not an OAuth token, password, encryption key or credential. Public custom-setting visibility supports subscriber automation references. This is NOT evidence that bypass governance is safe: review access and restoration risks separately (below). Do not change to Protected simply to hide the warning; subscriber formulas/code may depend on access.
- Located source: `<?xml version='1.0' encoding='UTF-8'?>`

### PG-SEC-17: ProtectSensitiveData

- Source: `force-app\main\default\objects\Automation_Bypass__c\fields\Bypass_Triggers__c.field-meta.xml` at line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: The field is a Checkbox with default false. It contains a cooperative automation-bypass switch, not an OAuth token, password, encryption key or credential. Public custom-setting visibility supports subscriber automation references. This is NOT evidence that bypass governance is safe: review access and restoration risks separately (below). Do not change to Protected simply to hide the warning; subscriber formulas/code may depend on access.
- Located source: `<?xml version='1.0' encoding='UTF-8'?>`

### PG-SEC-18: ProtectSensitiveData

- Source: `force-app\main\default\objects\Automation_Bypass__c\fields\Bypass_Validation_Rules__c.field-meta.xml` at line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: The field is a Checkbox with default false. It contains a cooperative automation-bypass switch, not an OAuth token, password, encryption key or credential. Public custom-setting visibility supports subscriber automation references. This is NOT evidence that bypass governance is safe: review access and restoration risks separately (below). Do not change to Protected simply to hide the warning; subscriber formulas/code may depend on access.
- Located source: `<?xml version='1.0' encoding='UTF-8'?>`

### PG-SEC-19: ProtectSensitiveData

- Source: `force-app\main\default\objects\PII_Keyword_Config__c\fields\Keyword__c.field-meta.xml` at line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: Keyword__c is Text(100), used for field-name/label discovery keywords such as ssn/passport/dob. It does not intentionally store credentials or record-level PII values. Runtime keyword writes use the authorized configuration controller and user-mode DML. Do not place real tokens or personal record values in keyword configuration. Review org CRUD/FLS, sharing and metadata access separately; text type alone does not prove data sensitivity.
- Located source: `<?xml version="1.0" encoding="UTF-8"?>`

### PG-SEC-20: ProtectSensitiveData

- Source: `force-app\main\default\objects\PII_Keyword__mdt\fields\Keyword__c.field-meta.xml` at line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: Keyword__c is Text(100), used for field-name/label discovery keywords such as ssn/passport/dob. It does not intentionally store credentials or record-level PII values. Runtime keyword writes use the authorized configuration controller and user-mode DML. Do not place real tokens or personal record values in keyword configuration. Review org CRUD/FLS, sharing and metadata access separately; text type alone does not prove data sensitivity.
- Located source: `<?xml version='1.0' encoding='UTF-8'?>`

### PG-SEC-21: ApexCRUDViolation

- Source: `force-app/main/default/classes/AutomationManagerService.cls`, line 70 in CodeAnalyzerReport(2).csv.
- Classification: Privileged internal-state read exception candidate.
- Evidence: Private lockSettings queries the current organization's Automation_Bypass__c record using a bound SetupOwnerId and FOR UPDATE. Public disable/restore methods invoke masking-permission and sandbox checks before the helper. The query supports internal ownership and snapshot restoration, not unrestricted business-record access. Snapshot writes explicitly use system mode.
- Validation: Retain negative-permission and production-blocking test outputs. Review subscriber access to the public hierarchy setting independently. Do not grant broader setting access to silence PMD.

### PG-SEC-22: ProtectSensitiveData

- Source: `force-app/main/default/objects/Automation_Bypass__c/fields/Bypass_Owner__c.field-meta.xml`, line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: Text(80) stores a Masking_Job_Run__c ID or the fixed legacy orchestrator identifier. It is not an OAuth token, password, API key or authentication credential.
- Integrity: Owner matching governs restoration. Administrators must not edit this internal field during execution; assess who can edit the public hierarchy setting.

### PG-SEC-23: ProtectSensitiveData

- Source: `force-app/main/default/objects/Automation_Bypass__c/fields/Bypass_Snapshot__c.field-meta.xml`, line 1.
- Classification: Secret-storage false-positive candidate.
- Evidence: Text(255) stores JSON containing the original four Boolean bypass flags. It does not intentionally contain credentials or record-level PII.
- Integrity: Invalid/missing snapshot data with an active owner blocks restoration and retains state for administrator recovery. Assess write access independently of the secret-storage classification.

## Existing test evidence and limits

Source contains PrivacyGuardConsolidatedSecurityTest.directPrivilegedMethodsRejectUnassignedUser (13 privileged methods; checks no reads/writes/callouts before rejection); SchemaValidationUtilTest tests blank/unknown names; PrivacyGuardSchemaTest rejects a field-name injection string; MaskingJobEntrySecurityTest, MaskingJobCrudSecurityTest and PrivilegedBatchSecurityTest cover other permission boundaries. These tests were inspected, not executed in this environment. Some tests default the test-only permission bypass to true; negative tests must explicitly set it false. Existing helper tests do not prove every controller and branch has end-to-end injection coverage.

The user supplied a live diagnostic log showing HTTP 200 and same-sandbox verification and confirmed successful trigger deactivate/reactivate. These are positive-path OAuth/Tooling checks only. They do not prove unauthorized-user rejection, token-refresh behavior, production blocking, cross-org blocking, or clean managed subscriber installation.

## Validation still needed for exception submission

1. Run all local Apex tests on the final source and retain deploy/test output, not merely test source or screenshots.
2. For the two purge counts and preview, test malicious object names and configured field/checkbox names containing query syntax. Require rejection/no data disclosure. Test real objects/fields without CRUD/FLS and confirm denial. Keep representative valid configurations working. Do not treat a generic exception as proof unless assertions also check side effects/data access.
3. Confirm a user lacking the appropriate custom permission cannot enter run/purge/configuration paths, including async execution. Inspect package and subscriber permission assignments; do not grant extra tracker/config edit access just for scanner counts.
4. Record that the eight flagged fields contain Boolean switches, discovery keywords, a run identifier or Boolean snapshot JSON, and include field metadata plus intended data examples in the security-review explanation. Review subscriber custom-setting and object access independently.
5. Install a new managed beta version in a separate subscriber sandbox; test namespace resolution, principal assignment, per-user authentication and same-org validation. A local source deployment is not this test.
6. Inspect complete PMD console/log output for parse/processing errors and retain scanner version/config/report. PMD-only output is not full multi-engine analysis or Salesforce security-review approval.

## Open implementation risks found alongside the warning review

### Automation bypass restoration — remediation delivered

Original behavior set all four cooperative bypass flags true and later unconditionally cleared them. This could overwrite a pre-existing admin setting.

The delivered patch:

- Persists the original four values and the owner in the org-default hierarchy setting.
- Uses FOR UPDATE for existing state. A unique SetupOwnerId causes competing first inserts to fail before both can apply bypass changes; no automatic retry is included.
- Rejects a second bypass owner until the active owner restores its state. Parallel object batches within one runtime run remain supported.
- Uses the runtime run ID for ownership on start, completion, reconciled failure and cancellation.
- Restores only flags still true, preserving changes to false made during execution.
- Makes duplicate restoration without an owner a no-op and rejects a wrong owner.
- Propagates runtime restoration failures instead of silently finalising the run; transaction rollback permits retry.
- Rejects the retired Use_Metadata_Deactivation opt-in before applying bypass state. Apex trigger metadata management remains separate.

### Reported deployment and manual validation

After receiving the all-source deployment command with RunLocalTests, the project owner stated “Deployed.” Subsequently, the owner stated “i have tested and looks good.” Record this as successful deployment and manual behavior reported by the owner, not independently inspected test results.

No detailed deployment summary, test counts, before/after flags, individual cancellation/failure outcomes or genuine concurrent-start results have been supplied. Do not state that all these scenarios were verified merely from the general confirmation.

AutomationBypassRestorationTest was included in the patch. Its test source covers mixed-state restoration through a Queueable transaction, overlap rejection, wrong/stale runtime owners, preservation of an admin false edit, duplicate restoration, corrupt snapshots and restoration without a snapshot. Test source is not proof that those tests passed.

### Remaining lifecycle and coordination limitations

- A deliberate admin re-save of true is indistinguishable from PrivacyGuard's applied true without additional provenance.
- The no-argument legacy API uses a fixed legacy owner. It still lacks a per-generation token for stale/duplicate legacy callbacks. Do not claim exactly-once restoration across all legacy runs.
- The old MaskingJobOrchestrator acquireRunGuard still has no tracker row to lock on first use. The new shared bypass ownership guard adds protection at the mutation boundary; this is not a complete rewrite of legacy tracker accounting.
- Failed/abandoned runtime batches depend on existing reconciliation, including control-panel reads. No autonomous recovery watchdog was added.
- Corrupt snapshot state needs administrator recovery. Do not blindly clear flags or ownership without investigating the active run.
- Public-setting integrity/access and genuine concurrent transaction behavior require validation in the subscriber environment.

### Existing object-selection cap

FileAttachmentPurgeController still rejects more than 10 objects in scanObjects and purgeObjects. This conflicts with the earlier product requirement to remove the cap. Removing it without batching would risk synchronous governor limits; this is a separate product/scalability change, not part of these 23 PMD exception candidates.

Do not present the package as fully security-cleared while these risks and validation gaps are unresolved. This document does not change runtime source; the separately delivered restoration patch changes the baseline described above.

## Official references

- Salesforce secure dynamic query guidance (validate object/field names using allowlists, not escaping for unquoted identifiers): https://developer.salesforce.com/docs/platform/secure-coding/guide/secure-coding-sql-injection.html
- Identifier escaping caveat: https://developer.salesforce.com/docs/platform/communities-dev/guide/communities-dev-security-guest-users-soql-injection.html
- Apex security and access-mode behavior: https://developer.salesforce.com/docs/platform/lwc/guide/apex-security
- Named Credential packaging and post-install authentication: https://developer.salesforce.com/docs/platform/named-credentials/guide/nc-package-credentials.html

## Provenance

- `force-app(20261103-052010).zip` SHA-256: `d25640c60872ec25a52c16b301b61fe6b65c98e2e5eb2551278a1d9d5bae6344`
- `privacyguard-pmd-latest.csv` SHA-256: `012b49d9687f440f67d4c9a94222e880a8eeb620049515848d8173de84c9a3fb`

## Submission evidence checklist

- [ ] Retain the final HTML and CSV reports and full scan logs.
- [ ] Match the final scan to the exact source of the package version submitted; the older released 0.1.0.6 version predates these fixes.
- [ ] Retain successful deployment and Apex test results.
- [ ] Capture mixed initial flags and results for completion, failure and cancellation.
- [ ] Retain malicious-input, insufficient-permission, production-blocking and overlapping-run evidence.
- [ ] Validate a clean managed installation in a separate subscriber sandbox, including OAuth principal setup.
- [ ] Complete Checkmarx/Source Code Scanner and review its results.
- [ ] Submit this justification register with supporting evidence. Salesforce retains final authority on acceptance.

No Checkmarx result or final package-source match was reviewed for this update.
