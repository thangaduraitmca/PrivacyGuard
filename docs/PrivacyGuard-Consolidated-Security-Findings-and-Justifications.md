# PrivacyGuard — Consolidated Security Findings and Proposed False-Positive Justifications

**Version:** 1.0  
**Prepared:** 4 November 2026  
**Status:** Draft for security-review submission; evidence completion and owner sign-off pending.

## Declaration and scope

PrivacyGuard Engineering proposes the finding-specific dispositions below based on the inspected implementation and available evidence. The scanner results remain unchanged. A proposed false positive means the specific reported vulnerability does not match the inspected use, or the scanner does not recognize an existing protection. It does not mean all related access, integrity or lifecycle risks have been eliminated.

**This is not a blanket declaration that all 23 findings are false positives or that the application is security-cleared.** Intentional privileged operations are identified separately and require justification of their authorization boundary. Outstanding tests and implementation concerns remain visible. Salesforce determines acceptance.

This is the consolidated working register for the 23 findings in `CodeAnalyzerReport(3).csv`; it incorporates the earlier security review, Custom Metadata/sandbox review and sensitive-data assessment. Older document identifiers are not reused: CF-01 through CF-23 map to the latest CSV order.

## Baseline and traceability

- Latest reviewed report: `CodeAnalyzerReport(3).csv` — 12 ApexCRUDViolation, three ApexSOQLInjection and eight ProtectSensitiveData findings; 15 high and eight moderate.
- Reviewed source archive: `force-app(20261104-045327).zip`, plus the query-hardening patch and additive authorization-test patch. The query patch's Contact Describe expression was corrected to `Contact.SObjectType.getDescribe().getName()` after a compilation error.
- Test evidence inspected: `apex-07L9r00000WZzmGEAT.log` for PrivacyGuardInternalAuthorizationTest.
- Candidate package discussed: 0.2.0.1, subscriber ID `04tQE00000jQRU5YAO`. Later local patches are not proven to be included in that already-created version. Final released package/source/scan matching remains pending.
- Deployment and testing were performed by the project owner on their laptop/org. No Salesforce CLI execution was performed in the document-preparation environment.

## Disposition summary

| Group | Count | Proposed classification | Remaining condition |
| --- | ---: | --- | --- |
| Schema-constrained dynamic SOQL | 3 | False-positive candidates after hardening | Retain executed malicious-input and CRUD/FLS denial results |
| Custom Metadata reads | 6 | Configuration-read false-positive candidates | Match metadata content and endpoint authorization to final release |
| Organization sandbox indicator | 1 | Intentional narrow system-context safety read | Retain environment-blocking and installed-environment evidence |
| Internal bypass/tracker queries | 5 | Intentional privileged-operation justifications | Service denial evidence obtained; direct setting access and lifecycle concerns remain |
| Potential auth-token storage | 8 | Rule-specific false-positive candidates | Verify actual contents and separate direct-edit/CRUD/FLS boundaries |
| **Total** | **23** | **Proposed dispositions, not approved closures** | **No scanner findings suppressed by this document** |

## Complete finding register

Locations below match the latest CSV; source lines may shift in later releases.

| ID | Severity / rule | Source location | Rationale group | Proposed disposition |
| --- | --- | --- | --- | --- |
| CF-01 | High / ApexCRUDViolation | `AutomationManagerService.cls:70` | D — internal coordination | Intentional privileged read; residual controls pending |
| CF-02 | High / ApexCRUDViolation | `EnvironmentSafetyService.cls:52` | C — environment guard | Intentional narrow system read |
| CF-03 | High / ApexSOQLInjection | `FileAttachmentPurgeController.cls:115` | A — schema-constrained query | False-positive candidate; validation evidence pending |
| CF-04 | High / ApexSOQLInjection | `FileAttachmentPurgeController.cls:117` | A — schema-constrained query | False-positive candidate; validation evidence pending |
| CF-05 | High / ApexCRUDViolation | `MaskingConfigService.cls:55` | B — Custom Metadata | Configuration-read false-positive candidate |
| CF-06 | High / ApexCRUDViolation | `MaskingConfigService.cls:94` | B — Custom Metadata | Configuration-read false-positive candidate |
| CF-07 | High / ApexCRUDViolation | `MaskingJobOrchestrator.cls:184` | D — internal coordination | Intentional privileged read; residual controls pending |
| CF-08 | High / ApexCRUDViolation | `MaskingJobOrchestrator.cls:197` | D — internal coordination | Intentional privileged read; residual controls pending |
| CF-09 | High / ApexCRUDViolation | `MaskingJobOrchestrator.cls:217` | D — internal coordination | Intentional privileged read; residual controls pending |
| CF-10 | High / ApexCRUDViolation | `MaskingJobOrchestrator.cls:229` | D — internal coordination | Intentional privileged read; residual controls pending |
| CF-11 | High / ApexSOQLInjection | `MaskingPreviewService.cls:58` | A — schema-constrained query | False-positive candidate; validation evidence pending |
| CF-12 | High / ApexCRUDViolation | `PIIFieldScannerService.cls:152` | B — Custom Metadata | Configuration-read false-positive candidate |
| CF-13 | High / ApexCRUDViolation | `PIIFieldScannerService.cls:169` | B — Custom Metadata | Configuration-read false-positive candidate |
| CF-14 | High / ApexCRUDViolation | `PrivacyGuardConfigurationController.cls:195` | B — Custom Metadata | Configuration-read false-positive candidate |
| CF-15 | High / ApexCRUDViolation | `PrivacyGuardConfigurationController.cls:219` | B — Custom Metadata | Configuration-read false-positive candidate |
| CF-16 | Moderate / ProtectSensitiveData | `Automation_Bypass__c.Bypass_All_Automations__c:1` | E — noncredential field | Auth-token classification false-positive candidate |
| CF-17 | Moderate / ProtectSensitiveData | `Automation_Bypass__c.Bypass_Flows__c:1` | E — noncredential field | Auth-token classification false-positive candidate |
| CF-18 | Moderate / ProtectSensitiveData | `Automation_Bypass__c.Bypass_Owner__c:1` | E — noncredential field | Auth-token classification false-positive candidate |
| CF-19 | Moderate / ProtectSensitiveData | `Automation_Bypass__c.Bypass_Snapshot__c:1` | E — noncredential field | Auth-token classification false-positive candidate |
| CF-20 | Moderate / ProtectSensitiveData | `Automation_Bypass__c.Bypass_Triggers__c:1` | E — noncredential field | Auth-token classification false-positive candidate |
| CF-21 | Moderate / ProtectSensitiveData | `Automation_Bypass__c.Bypass_Validation_Rules__c:1` | E — noncredential field | Auth-token classification false-positive candidate |
| CF-22 | Moderate / ProtectSensitiveData | `PII_Keyword_Config__c.Keyword__c:1` | E — noncredential field | Auth-token classification false-positive candidate |
| CF-23 | Moderate / ProtectSensitiveData | `PII_Keyword__mdt.Keyword__c:1` | E — noncredential field | Auth-token classification false-positive candidate |

## A. Dynamic SOQL — three findings

**FileAttachmentPurgeController, two counts:** The object name is checked against the real schema and purge eligibility. The concatenated name comes from Describe.getName(), with the new identifier grammar guard. The remaining count-query syntax is fixed. Both queries retain WITH USER_MODE. There is no arbitrary user-supplied WHERE/ORDER fragment.

**MaskingPreviewService, one query:** The selected object must belong to the job and resolve through SchemaValidationUtil. Selected fields are validated and retrieved from Describe; the Once completion checkbox is validated and canonicalized. The patch adds identifier grammar checks to object, selected fields and completion-field identifiers. Fixed WHERE/ORDER/LIMIT syntax restricts the preview to five records, and WITH USER_MODE enforces record/object/field access. The preview performs no DML.

Object and field names cannot be bound as ordinary literal values. The defense is schema allowlisting plus identifier validation, not String.escapeSingleQuotes on an unquoted identifier. USER_MODE enforces permissions; it does not replace injection prevention.

**Proposed reviewer statement:** “The dynamic identifiers at these sinks are resolved from validated Salesforce schema names, then checked against an identifier grammar. The caller cannot supply arbitrary SOQL expressions or query clauses. Data access is enforced in user mode. The scanner does not recognize the complete validation chain.”

**Evidence limitation:** The scan still reports all three warnings after hardening. Negative tests were added to SchemaValidationUtilTest, FileAttachmentPurgeControllerTest and MaskingPreviewServiceTest, but the supplied internal-authorization log does not establish those test results. Retain their successful execution and denial tests for real schema names without appropriate CRUD/FLS. Do not mark this group fully closed based only on deployment success.

## B. Custom Metadata — six findings

MaskingConfigService reads active Masking_Configuration__mdt and ordered Masking_Job_Sequence__mdt. PIIFieldScannerService reads the keyword dictionary and configured-field identifiers. PrivacyGuardConfigurationController reads packaged keywords for display and duplicate detection.

These three types have Public visibility. They store application configuration, not customer records being masked. Salesforce documents distinct system-context behavior for Custom Metadata; ordinary record CRUD/FLS assumptions do not apply identically to these reads. This is a narrow justification for the flagged configuration queries, not permission to expose confidential metadata.

The six packaged masking defaults inspected contain object/field names, strategy settings and execution groups; all are inactive. Five have no masking pattern and Lead Company has length 12. The archive contains two job-sequence records and 30 keyword records. Future subscriber changes must not contain secrets, real PII samples or confidential static replacement values.

PII scanning and keyword-controller methods require Manage_PrivacyGuard_PII. The scanner checks object/field accessibility. Mutable subscriber configuration reads use WITH USER_MODE and keyword writes use user-mode DML. MaskingConfigService is not an Aura endpoint and has no independent custom-permission gate; its caller authorization must be maintained when new entry points are added. Downstream target validation is still required.

**Proposed reviewer statement:** “The flagged queries read public application configuration from Custom Metadata. They do not retrieve customer record values or perform metadata DML. Exposed configuration/discovery operations are permission gated, and mutable subscriber configuration uses user-mode access.”

**Evidence limitation:** Negative PII endpoint and keyword CRUD/FLS execution evidence is not established by the supplied bypass/tracker test log.

## C. Organization sandbox check — one finding

EnvironmentSafetyService queries only `SELECT IsSandbox FROM Organization LIMIT 1`. It returns a Boolean, not an Organization record. Query exceptions return false; destructive entry paths then block. The old production override is not honored. The test override is private/test-visible and effective only during tests.

**Proposed reviewer statement:** “This narrow system-context read obtains only the environment indicator required to prevent destructive execution outside sandboxes. Failure to determine the org type blocks execution. No Organization record or business data is returned.”

EnvironmentSafetyServiceTest contains sandbox allow, non-sandbox block, former-override rejection and direct batch blocking cases. Their test source was inspected; individual passing results for this class were not supplied in the reviewed authorization log. Simulated test overrides do not establish real installed-org behavior or exercise the actual query-failure branch.

## D. Internal bypass/tracker state — five findings

AutomationManagerService.lockSettings queries the current org's hierarchy setting using a bound SetupOwnerId and FOR UPDATE. Public disable and restore methods check Run_PrivacyGuard_Masking and sandbox status before the private helper. Owner matching and typed Boolean snapshots protect restoration. State writes explicitly use system mode.

MaskingJobOrchestrator's four queries lock the org-default tracker by bound ID. Its public run/completion entry points require masking authorization and sandbox execution; deletion jobs additionally require purge permission. These queries coordinate internal lifecycle state rather than expose arbitrary customer records.

**Proposed reviewer statement:** “These private, tightly scoped queries coordinate authorized sandbox jobs and safe automation restoration. Public entry paths enforce custom-permission and sandbox gates before the queries. System state access is intentional; granting operators broad direct tracker-edit privileges is not necessary to execute the workflow.”

### Executed negative authorization evidence

The supplied log shows both PrivacyGuardInternalAuthorizationTest scenarios completing without assertion or fatal errors:

- deniedCallsDoNotCreateInternalState.
- deniedCallsPreserveExistingState.

Each covers seven entry paths: disable/enable with legacy and explicit-owner overloads, runMaskingJobs, runJobs with a nonempty job list, and handleJobCompletion. The tests disable the test permission bypass and assert the fixture user lacks masking permission. Expected authorization exceptions are caught. Assertions check no SOQL/DML after denied calls, no state changes, and no newly queued work. The sandbox override is true to isolate authorization.

This supports service-entry denial, not every direct state-edit route. Retain formal test results in addition to the debug log. Existing positive-path/restoration tests are also necessary.

### Residual implementation concerns

1. Public hierarchy settings remain subject to subscriber administrative/API permissions. Service authorization does not protect every direct-edit path.
2. Legacy completion uses a fixed owner and lacks a per-generation completion token. Duplicate/stale callbacks can affect counter accounting; do not claim universal exactly-once completion.
3. A tracker row does not exist to lock on first use. The shared bypass ownership boundary adds protection, but this is not a full concurrency rewrite.
4. Restoration cannot distinguish an administrator deliberately re-saving true from PrivacyGuard's own true value. False edits are preserved.
5. Abandoned runtime runs depend on reconciliation; no autonomous recovery watchdog was added.

These concerns are not declared false positives by this register and need explicit release assessment.

## E. Potential auth-token fields — eight findings

| Field | Actual contents | Why token classification is disputed |
| --- | --- | --- |
| Bypass_All_Automations__c | Checkbox, default false | Cooperative control flag, not credential |
| Bypass_Flows__c | Checkbox, default false | Cooperative control flag, not credential |
| Bypass_Triggers__c | Checkbox, default false | Cooperative control flag, not credential |
| Bypass_Validation_Rules__c | Checkbox, default false | Cooperative control flag, not credential |
| Bypass_Owner__c | Text(80): run ID or fixed legacy owner | Identifier; knowing it does not bypass permission checks |
| Bypass_Snapshot__c | Text(255): four original Boolean values in JSON | Not a customer-data snapshot or credential |
| PII_Keyword_Config__c.Keyword__c | Text(100): subscriber discovery category term | Used for field-name/label matching, not authentication |
| PII_Keyword__mdt.Keyword__c | Text(100): packaged dictionary term | Public nonsecret dictionary configuration |

**Proposed reviewer statement:** “The eight fields are not used to store authentication tokens. They hold Boolean automation flags, a run identifier, prior Boolean state and discovery dictionary terms. OAuth is handled through Salesforce credential infrastructure rather than these fields. The auth-token classification is disputed on this basis; configuration integrity and actual access rights are assessed separately.”

Automation_Bypass__c is public so subscriber automation can consult cooperative flags. Public visibility is not an anonymous endpoint, but is not a confidentiality/integrity guarantee either. Do not change the entire setting to protected solely to silence a warning; that can break subscriber automation. If direct mutation is unacceptable, assess protected owner/snapshot storage as a separate migration/design change.

PII_Keyword_Config__c has ReadWrite sharing. Its admin permission set grants CRUD/FLS; controller gates do not prevent direct CRUD granted elsewhere. Keyword inputs accept arbitrary text, so guidance must prohibit secrets and real PII. Text fields are not intrinsically safe merely because their intended use is nonsecret. Keyword values appear in the UI and can appear in duplicate-validation errors.

**Required access check:** Confirm ordinary operators cannot directly alter bypass owner/snapshot/flags through unintended routes. Check keyword object/FLS access and unauthorized PII endpoint calls separately. None of these checks is proven by the internal service test log.

## Evidence index

| Evidence | Use | Status |
| --- | --- | --- |
| CodeAnalyzerReport(3).csv | Authoritative 23-row finding inventory | Inspected; unchanged counts |
| Earlier CodeAnalyzerReport.html | Comparison baseline | Same rule/file/message inventory; older line numbers |
| force-app(20261104-045327).zip | Source/field metadata/permission inspection | Inspected |
| PrivacyGuard-Query-Hardening-Patch.zip plus corrected Describe test expression | Additional dynamic identifier validation and negative tests | User reports deployment; retain formal test results |
| PrivacyGuard-Authorization-Test-Patch.zip | Negative service-entry tests | Supplied execution log inspected |
| apex-07L9r00000WZzmGEAT.log | Two completed negative-authorization scenarios | No assertion/fatal errors observed; expected denials |
| Final full-suite result | Regression, malicious-input, environment and permission evidence | Formal complete result not yet attached |
| Checkmarx report | Separate scanner evidence for final package | Not supplied; not waived by this register |
| Final released package/source match and clean subscriber install | Version traceability and managed behavior | Pending verification |

Debug logs may include usernames, org IDs and internal identifiers. Review/redact unnecessary information before external attachment without removing the evidence needed to assess results. Do not attach OAuth secrets or live tokens.

## Conditions before final submission

- Retain final HTML/CSV reports, complete scan logs, tool versions and configuration. Review parse/engine failures and exclusions; a findings CSV alone cannot prove full coverage.
- Run the final full Apex suite and retain results. Include the negative query tests, insufficient CRUD/FLS cases, PII endpoint denial and sandbox guards.
- Validate direct setting/keyword access using representative profiles in a managed subscriber environment.
- Fix actual defects or explicitly assess the legacy lifecycle concerns; do not hide them inside a false-positive declaration.
- Inspect public configuration for secrets and correct stale metadata help text describing retired Flow/validation-rule behavior and substring keyword matching.
- Build and validate a new package version containing the final source; confirm release promotion and installed version. An already-created package cannot incorporate later local edits.
- Complete Checkmarx and separately triage its findings. Include its report and any additional finding-specific justifications.
- Complete owner sign-off below. Submit proposed justifications with supporting evidence; acceptance remains with Salesforce.

## Owner sign-off — not completed

| Field | Value |
| --- | --- |
| Accountable product/security owner | To be completed by project owner |
| Exact submitted package version and subscriber ID | Pending final release match |
| Source commit/tag | Pending |
| Final scan date and report hash | Pending |
| Full test run/deployment ID | Pending |
| Direct access checks and lifecycle decision | Pending |
| Approval date | Not approved/signed in this document |

Suggested statement after the evidence is complete: “We submit the finding-specific explanations in this register for Salesforce review. Our assessment is limited to the stated rule, source version, controls and test evidence. Known limitations and residual risks are disclosed separately. We have not treated a scanner warning as resolved solely because it was documented or suppressed.”

## References

- [Required materials for security review](https://developer.salesforce.com/docs/platform/isvforce/guide/security-review-required-materials.html)
- [Security review preparation and false positives](https://trailhead.salesforce.com/content/learn/modules/isv_security_review/isv_security_review_prepare)
- [Secure dynamic queries](https://developer.salesforce.com/docs/platform/secure-coding/guide/secure-coding-sql-injection.html)
- [Identifier escaping caveat](https://developer.salesforce.com/docs/platform/communities-dev/guide/communities-dev-security-guest-users-soql-injection.html)
- [Custom Metadata protection and privacy](https://help.salesforce.com/s/articleView?id=platform.custommetadatatypes_protection.htm&language=en_US&type=5)

This is a documentation consolidation. It changes no source code, scanner rule or deployed configuration.
