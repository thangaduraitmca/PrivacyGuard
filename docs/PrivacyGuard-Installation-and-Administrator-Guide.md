# PrivacyGuard: Installation and Administrator Guide

| Document control | Value |
|---|---|
| Version | 1.0 |
| Date | 4 November 2026, Australia/Sydney |
| Product | PrivacyGuard / SandboxShield |
| Namespace | `privacyguard` |
| Baseline package | 0.2.0.1 — `04tQE00000jQRU5YAO` |
| Audience | Subscriber Salesforce administrators and security reviewers |
| Status | Operating guide based on supplied source and delivered patches; verify against the installed version |

## 1. Read before installing

PrivacyGuard discovers potentially sensitive fields and runs configured data masking and file cleanup in Salesforce sandboxes. It also supports controlled management of eligible Apex triggers through per-user OAuth.

**Masking and file deletion are destructive.** Masked values are not automatically recoverable. Cancellation does not undo batches that have already committed. Use synthetic test records for initial validation and follow your organization's approved backup/recovery policy before larger runs.

- Production masking/deletion is blocked; no production override is supported by the current execution gate.
- PII discovery is read-only and may be used in production with appropriate access. Discovery does not guarantee identification of all PII.
- Apex trigger metadata management is limited to eligible non-namespaced triggers. Flow and validation-rule metadata changes are unsupported.
- Cooperative bypass flags affect only automation explicitly designed to consult them. Do not assume every automation is disabled automatically.
- This release does not provide data seeding or automatic OAuth repair after sandbox refresh.

The last inspected report showed 0.2.0.1 as beta, with 84% coverage. Installation in Pguard was reported successful; later promotion was not confirmed. **A customer production installation and security-review submission require the appropriate released version.** Do not try to install this beta in production.

## 2. Installation checklist and responsibilities

| Preparation | Owner | Done |
|---|---|---|
| Confirm target sandbox, My Domain and package version | Salesforce administrator | [ ] |
| Confirm licensing/package eligibility and installation rights | Salesforce administrator | [ ] |
| Approve synthetic sample data and initial object/field scope | Data owner | [ ] |
| Record recovery/backup arrangements for destructive testing | Data owner / administrator | [ ] |
| Select approved operators and least-privilege access | Security administrator | [ ] |
| Check editable completion checkbox on each target object | Salesforce administrator | [ ] |
| Assign person responsible for OAuth configuration | Integration administrator | [ ] |
| Stop active PrivacyGuard jobs before an upgrade | Operations administrator | [ ] |
| Record current bypass settings before maintenance | Operations administrator | [ ] |

Salesforce labels and available Setup actions may vary by release. If the screen differs materially, inspect the installed component and resolve the discrepancy rather than creating an unmanaged duplicate.

## 3. Install the managed package

### 3.1 Authenticate the sandbox using Salesforce CLI

PowerShell example using the alias Pguard:

```powershell
sf org login web --alias Pguard --instance-url https://test.salesforce.com
```

Sign in to the intended sandbox. To check the target identity without printing tokens:

```powershell
sf data query --target-org Pguard --query "SELECT Id, Name, IsSandbox FROM Organization"
```

Verify `IsSandbox=true` and the expected organization name/ID. Do not use verbose authentication output in screenshots or evidence files because it can expose secrets.

### 3.2 Install the baseline test version

```powershell
sf package install --package 04tQE00000jQRU5YAO --target-org Pguard --security-type AdminsOnly --publish-wait 10 --wait 30
```

Follow any CLI prompts. If the command times out with a request ID, inspect that existing request before starting another install:

```powershell
sf package install report --request-id <installation-request-id> --target-org Pguard
```

Replace angle-bracket placeholders; do not paste them unchanged. For future versions, use the publisher-provided version ID rather than assuming the ID in this guide remains current.

### 3.3 Verify installation

1. Setup → Installed Packages → PrivacyGuard: confirm namespace and version.
2. Review installed components, including the External Credential/provider and Tooling Access permission set.
3. Assign access as below, then open the installed app from App Launcher. The source application API name is `Data_Masking_Framework`; the displayed label may differ.
4. Confirm the main sections are accessible: PII Scan Review, Data Masking Configuration, Masking Jobs, automation management, file management and audit/dashboard views.

`AdminsOnly` is an installation access choice, not a replacement for object/FLS, custom permissions or OAuth principal assignments.

## 4. Assign roles and permissions

API names in CLI commands include the package namespace. Assign only the sets needed for the person's role and verify effective Salesforce object/field permissions separately.

| Permission set | Intended purpose / grant |
|---|---|
| `privacyguard__PrivacyGuard_Admin` | Run, purge, PII management and audit custom permissions; configuration/admin responsibilities. |
| `privacyguard__PrivacyGuard_Operator` | `Run_PrivacyGuard_Masking` for approved masking operators. |
| `privacyguard__PrivacyGuard_Purge_Operator` | `Purge_PrivacyGuard_Files` for destructive file/attachment operators. |
| `privacyguard__PrivacyGuard_Metadata_Deactivation_Break_Glass` | `Use_PrivacyGuard_Metadata_Deactivation` for highly privileged trigger metadata operations; the legacy API name does not enable Flow/validation-rule metadata support. |
| `privacyguard__PrivacyGuard_Tooling_Access` | Access to the packaged per-user OAuth principal. Does not alone grant trigger metadata or Salesforce platform rights. |

**Important:** `PrivacyGuard_Admin` does not grant the metadata-deactivation custom permission in the supplied source. Trigger administrators need the separate metadata permission and principal access, plus appropriate Salesforce API/metadata privileges.

Legacy permission sets named Production Override/Production Break Glass may exist. Do not assign them as a way to enable production masking: the current environment safety gate does not honor a destructive-production override.

### Administrator example

These commands target the authenticated CLI user. For another user, use Setup → Permission Sets → Manage Assignments.

```powershell
sf org assign permset --name privacyguard__PrivacyGuard_Admin --target-org Pguard
```

Only for an approved trigger administrator:

```powershell
sf org assign permset --name privacyguard__PrivacyGuard_Metadata_Deactivation_Break_Glass --target-org Pguard
sf org assign permset --name privacyguard__PrivacyGuard_Tooling_Access --target-org Pguard
```

Also verify:

- Target object access and readable/updateable masking fields.
- Editable completion checkbox access.
- Required job/configuration/history access through appropriate packaged roles.
- Appropriate file/content rights for inventory/deletion.
- API and metadata rights required by the supported trigger operation.
- External Client App user approval policy and User External Credentials effective permissions for Per User OAuth.

Do not grant View All/Modify All or broad administrative rights merely to silence a scanner finding or bypass a validation error.

## 5. Configure the OAuth connection for trigger management

OAuth is required for Tooling API trigger operations. It is not a reason to route ordinary native masking DML through an external service.

The included companion **PrivacyGuard-OAuth-Post-Install-Guide.md** provides detailed screen instructions and troubleshooting. Use this sequence:

1. Record the target sandbox's Salesforce My Domain (`my.salesforce.com`, not `lightning.force.com`).
2. Open the installed `privacyguard__PrivacyGuard_Tooling_OAuth` External Auth Identity Provider and copy its generated callback exactly. A packaged callback can differ from unmanaged PGTEST's callback.
3. Create/configure the customer-owned External Client App in the target sandbox: authorization-code Browser Flow, PKCE, API and refresh-token scopes, and exact callback.
4. Populate the installed provider's client ID/secret using supported Setup actions. Verify target-specific authorize/token endpoints, PKCE and ClientSecretBasic.
5. Verify the installed External Credential uses Browser Flow, the installed provider, `api refresh_token` scope and the existing Per User Principal `PrivacyGuard_User` (sequence 1).
6. Create/update the customer-owned Named Credential using the settings below.
7. Assign the principal-access and metadata-operation permissions to each approved trigger administrator.
8. Each user authenticates from Lightning personal Settings → External Credentials. Do not treat an admin's authentication as authentication for other users.
9. Validate read access and an eligible test-trigger deactivate/reactivate operation, including final-state verification.

| Named Credential setting | Required value |
|---|---|
| API name | **`PrivacyGuard_Tooling`** — customer-owned, unprefixed |
| URL | This sandbox's exact Salesforce My Domain base URL |
| External Credential | Installed `privacyguard__PrivacyGuard_Tooling_OAuth` |
| Enabled for callouts | On |
| Generate Authorization Header | Checked |
| Formula substitution in header/body | Unchecked for this design |
| Allowed Namespaces for Callouts | **`privacyguard`** |
| Certificate / outbound network | None unless the organization has a separately approved requirement |

No Remote Site Setting is required for this named-credential route. Never place client secrets, access tokens or refresh tokens in Git, Apex, Custom Metadata, this guide or screenshots. Do not use PGTEST's domain for Pguard.

If a packaged provider setting or credential action is unavailable, capture the installed component details for investigation. Do not silently replace it with a parallel unmanaged authentication chain.

## 6. Prepare target objects and sample data

1. Choose a small object/field scope and synthetic records.
2. Check the user can read/update the selected fields and that they are eligible for the selected strategy. Calculated, auto-number, unsupported or otherwise protected fields must not be forced into scope.
3. Ensure each object has an editable, non-formula **Checkbox** completion field, normally `Data_Masking_Complete__c`, default false.
4. The package may supply a namespaced completion checkbox on some objects. Use the actual installed field API name; do not create an unnecessary duplicate.
5. If a custom completion field can be configured through the installed job interface/API, verify that exact field; otherwise use the expected conventional checkbox. Resolve missing-field errors before starting a job.
6. Do not select the completion checkbox as a masking target.
7. Review validation rules, duplicate rules, required fields, dependencies and subscriber automation.

The current runtime preflight requires a valid completion checkbox for selected objects, including Full jobs. Checkbox access is not optional merely because you selected Full Masking.

Do not reset completion flags on already masked data without deliberately planning the effect: it can cause records to be masked again.

## 7. Discover PII candidates and review findings

1. Open PrivacyGuard's discovery feature and run the supported schema scan with the intended scope/options.
2. Monitor scan progress and open **PII Scan Review**.
3. Review object/field candidates and confirm business sensitivity with the data owner. Keyword detection is a starting point, not a complete PII classification.
4. Accept appropriate findings into masking configuration. Accepted fields remain inactive until configured.
5. Review excluded/already configured fields and duplicates before repeating discovery.
6. Maintain **PII Keyword Configuration** for subscriber-specific discovery vocabulary.

Use generic discovery words such as `passport` or `dob`. Do not put actual personal values, passwords or OAuth tokens in keyword records. A subscriber override can govern packaged keyword visibility without deleting packaged metadata.

## 8. Configure field masking rules

Open **Data Masking Configuration**.

1. Use accepted discovery fields or choose **Add Fields**, select an object, choose eligible fields and click **Add Selected**.
2. Select a masking strategy for each field.
3. Provide the required pattern/value using the field's displayed help. Different strategies have different formats; do not reuse an example format for an unrelated strategy.
4. Review errors and unsupported-field explanations.
5. Activate only correctly configured fields and choose **Save Changes**.
6. Reopen the configuration to confirm persistence.

| Treatment family | Administrator consideration |
|---|---|
| Email / invalid email | Decide whether preserving the domain is acceptable; preserving part of a value is not full de-identification. |
| Phone / name / random string | Validate length, uniqueness expectations and downstream automation dependencies. |
| Static | Use a non-sensitive value compatible with the Salesforce field type. |
| Regex | Validate the displayed pattern format and replacement on representative samples; consider runtime/complexity limits. |
| Numeric range | Validate type, precision and allowable range. |
| NULL | Only for nullable/eligible fields; not a way to evade required-field constraints. |
| List | Use the supported configured list format and values compatible with the target field. |

The UI offers eligible choices by field type. This table does not mean every strategy works on every field. Packaged defaults and runtime overrides are combined by the application.

Removing configuration excludes a field from future masking; it does not restore values already changed or automatically delete prior discovery/audit history.

## 9. Create and preview a masking job

Open **Masking Jobs** → **Create Masking Job**.

| Setting | Guidance |
|---|---|
| Name / description | Identify purpose, owner and permitted scope clearly. |
| Objects | Select objects with active rules and a valid completion checkbox. |
| Full Masking | Can modify all eligible records in configured objects. |
| Unmasked records only | Processes eligible records whose configured completion checkbox is false; stored mode is `Once`. |
| Serial | Starts object work in sequence; useful for dependencies and initial validation. |
| Parallel | Multiple object batches share one run; native batch limits and dependencies still apply. |
| Batch size | Use an appropriate configured size; start conservatively if subscriber automation is heavy. Do not assume the largest value gives the best throughput. |
| Schedule | Start with Manual — Run Now for validation. |

Legacy `Delta` timestamp mode is not the current supported runtime choice. Edit an older job to Full or Unmasked records only if the application requests it.

### Read-only preview

1. Save the job, then choose its preview action.
2. Select the object and review the limited before/after examples.
3. The supplied source limits preview to up to five accessible records and 100 configured fields; values longer than 500 characters may be truncated.
4. Preview does not update records/completion flags or validate real DML, validation rules or subscriber automation. Random replacements will differ during actual execution.

Before values are real data visible to the authorized user. Do not use unredacted preview screenshots in public documentation or broad-access review evidence.

## 10. Run, monitor, cancel and recover

### Start a controlled run

1. Confirm the intended sandbox and approved scope.
2. Record the four org-default cooperative bypass flags before initial validation (see section 12).
3. Review the job's mode, object list and configured fields.
4. Choose Run and inspect **Review Masking Execution**.
5. Confirm the safety acknowledgement only after assessing the warning. Record counts are not estimated in this version; Full mode may affect every eligible record in the configured objects.
6. Choose **Start Masking** and monitor the run/object statuses.

### Monitor

Use Masking Jobs, dashboard/audit views and Setup → Apex Jobs when needed. Retain run IDs, object statuses, processed/failed counts and error summaries. A queued job is not complete. Refreshing the control panel can trigger reconciliation of batches that failed before normal completion.

### Cancel

Choose the active job's cancellation action and confirm **Cancel Job**. Queued work can be skipped and supported active jobs aborted. Confirm terminal run/object state and original bypass restoration. Previously committed chunks remain changed; cancellation is not rollback.

### Recover failed work

1. Identify the actual failure, such as field access, validation rules, duplicate rules, locking or subscriber automation.
2. Correct the cause without weakening production/sandbox or credential checks.
3. Use the supported recovery/rerun action for the eligible failed parent run belonging to that job.
4. Verify resulting counts and records; do not assume all originally selected records will be reprocessed.
5. If a run appears abandoned, inspect its Apex jobs and use the supported control-panel reconciliation before changing internal state manually.

Deleting the reusable job configuration does not undo historical masking. Review linked history and scheduled work before deleting a job; use the application's confirmation text as the authority for what will be removed.

## 11. Configure schedules

The supplied runtime interface supports **Manual — Run Now, Daily, Weekly and Monthly**.

1. Validate a manual run first.
2. Choose the job's schedule action or schedule controls in its editor.
3. Select frequency and required day/month-day/time.
4. Verify the Salesforce user's timezone: the runtime UI states schedule time uses the scheduling user's timezone. Do not assume all schedules use the org timezone.
5. Save and verify the job's schedule plus Setup → Scheduled Jobs.
6. Use Unschedule/Cancel Schedule to stop future execution; this does not cancel a currently active run.

For monthly days that do not occur in every month, verify Salesforce's actual next-fire date and choose an appropriate business policy. Review timezone/daylight-saving transitions and scheduled-user access. A schedule will not automatically repair missing OAuth, revoked permissions or stale sandbox configuration.

Do not call package-internal public scheduler classes from subscriber Execute Anonymous unless the package exposes a supported global API. Use the installed UI and supported setup actions rather than relying on development-only examples.

## 12. Cooperative bypass settings and restoration

Setup → Custom Settings → installed **Automation Bypass** → Manage. Inspect the **organization-default** row; user/profile hierarchy rows can affect effective subscriber automation behavior independently.

Relevant flags:

- `Bypass_All_Automations__c`
- `Bypass_Triggers__c`
- `Bypass_Flows__c`
- `Bypass_Validation_Rules__c`

The snapshot/owner fields `Bypass_Snapshot__c` and `Bypass_Owner__c` are internal control state. Do not edit them while a run is active. They contain Boolean JSON and an ownership identifier, not authentication credentials.

### Expected behavior

A run saves the original values and applies temporary cooperative bypass values. Runtime terminal paths restore only their own snapshot. A second owner is blocked until restoration. An administrator change to false during execution is preserved. No-owner duplicate restoration is a no-op; wrong-owner or corrupt snapshots are rejected.

### Important limits

- Subscriber automation must explicitly check the flags. These switches do not deactivate arbitrary Flow/trigger/validation metadata.
- A deliberate admin re-save of true cannot be distinguished from package-applied true.
- Legacy callbacks lack per-generation ownership and have stale-callback limitations.
- Abandoned runs depend on existing reconciliation; there is no autonomous recovery watchdog.
- Keep the retired `Use_Metadata_Deactivation__c` option false. Current code rejects its unsupported Flow/validation-rule metadata behavior before applying bypass changes.

### Safe recovery procedure

1. Stop initiating new jobs; record the current flags, owner, snapshot and relevant run/Apex job IDs.
2. Determine whether the owning run still has active batch work. Do not clear an active owner's state just to unblock another job.
3. Use normal completion/cancellation/reconciliation paths where available.
4. If snapshot data is corrupt or ownership cannot be reconciled, escalate with the captured evidence. Establish the approved original flag values before any manual repair.
5. Make a separately approved recovery change only after confirming no active work depends on those flags. This guide intentionally provides no blanket script to clear ownership or set every flag false.

## 13. Configure and use trigger management

Complete OAuth configuration in section 5 and assign both the metadata-operation permission and Tooling principal access.

1. Open Automation Management and refresh the supported trigger list.
2. Choose an eligible test trigger. Namespaced triggers must remain protected/not selectable for changes.
3. Record the initial state and intended change.
4. Submit deactivate/reactivate and monitor operation status.
5. Wait for completion and **verified final state**. Queued/submitted is not successful state change.
6. For validation, reactivate the test trigger and verify the final state again.

This feature uses same-sandbox Tooling calls and controlled deployment containers. Do not change the Named Credential URL to production or another org. Native Salesforce API/metadata permissions still apply even after OAuth authentication succeeds.

Cooperative bypass restoration does not imply every separately toggled trigger is automatically restored. Track and explicitly verify trigger operations and any outstanding deactivated automation records.

## 14. Inventory and delete files/attachments

1. Confirm the operator has explicit purge access and appropriate Salesforce file/object permissions.
2. Review file inventory and metadata; inventory does not scan all file bodies for PII or malware.
3. In Attachment & File Manager, select eligible objects and inspect supported related-content counts/warnings.
4. The current supplied selection paths limit scan/purge to **10 objects** per selection. Do not remove the cap locally without a supported batching change.
5. Resolve count/access warnings before deletion. If an object cannot be counted safely, do not assume purge is allowed.
6. Review file ownership, multiple links and approved retention requirements before confirming cleanup.
7. Run supported deletion, then review batch status/logs and actual remaining test content.

Deleting a ContentDocument can affect every linked record and its versions, not only the record through which it was selected. Do not assume deleting one link is equivalent to deleting the document. Recycle Bin or backup behavior is platform-dependent and is not a guaranteed package rollback facility.

## 15. Audit, logging and routine administration

Use audit/dashboard views to inspect masking, discovery, automation, files and configuration activity where available in the installed version. Restrict access to people with an operational need.

| Routine task | Suggested frequency / trigger |
|---|---|
| Check active/failed jobs and pending trigger operations | During and after every destructive run |
| Verify original bypass state restored | After initial validation, failures/cancellation and significant upgrades |
| Review schedule ownership, timezone and next-fire times | On schedule changes and user/locale changes |
| Review operator permissions and OAuth principal assignments | On personnel changes and periodic access reviews |
| Verify credentials/endpoint after refresh | Every sandbox refresh/domain change |
| Review log growth and sensitive error content | Per subscriber retention/monitoring policy |
| Re-test supported workflows | After package upgrades or significant subscriber automation changes |

Logs can include record IDs, object/field names, technical details and subscriber error messages. Some errors may contain business values; do not assume universal redaction. Retention and cleanup are subscriber policy decisions. The package is not an immutable audit archive.

## 16. Upgrade procedure

1. Review release notes, source/scan provenance and known limitations for the target version.
2. Test the upgrade in a separate subscriber sandbox before wider deployment.
3. Stop or complete active masking/purge work; reconcile outstanding trigger changes and record current flags/settings.
4. Capture subscriber configuration using an approved method. Installing a package is not a substitute for backup.
5. Install the specified compatible successor version. Do not assume a beta or older version is an upgrade target.
6. Verify installed permission sets, new fields, credential/provider links and assignments. Do not assume existing users receive every required new permission automatically.
7. Re-run the acceptance checks below before restoring schedules.

For existing pre-patch runs, a new snapshot field cannot reconstruct historical original flag values. Finish/recover such runs under an approved maintenance plan before depending on the new restoration behavior.

## 17. Sandbox refresh checklist

- [ ] Pause/reconcile relevant jobs and retain approved configuration records before refresh.
- [ ] Confirm refreshed sandbox identity, domain and installed version.
- [ ] Inspect copied External Client App and provider; verify/recreate sandbox-local OAuth registration/credentials as necessary.
- [ ] Copy the refreshed installed provider callback into the app registration.
- [ ] Recheck authorize/token URLs and customer-owned Named Credential target: no production/old-sandbox URL should remain.
- [ ] Verify installed External Credential linkage, namespace allowance and user assignments.
- [ ] Reauthenticate every approved Tooling operator; do not assume copied tokens remain usable.
- [ ] Inspect completion flags and masking policy for refreshed data. Do not blindly reset flags without a data-owner-approved run plan.
- [ ] Verify schedule ownership and next-fire times; keep destructive schedules paused until setup is validated.
- [ ] Complete same-sandbox API read, eligible test-trigger and small masking/cancellation checks.

No automatic refresh repair/bootstrap is supplied by this release.

## 18. Uninstall considerations

Uninstalling PrivacyGuard does not restore already masked records or deleted files. Review Salesforce dependency checks, package data loss implications, history retention and customer-owned credential dependencies before proceeding.

Before uninstalling: stop/reconcile jobs, unschedule future work, resolve independently deactivated triggers, restore approved cooperative flag values through supported paths, and retain required audit/configuration evidence. Separately review whether customer-owned Named Credential/External Client App and user authorizations should be retained or revoked. Do not delete shared integration components without checking other consumers.

## 19. Troubleshooting

| Symptom | Investigation / corrective action |
|---|---|
| App or feature unavailable | Check installed version, app visibility and role/custom-permission assignments. |
| Missing object/field access | Review effective CRUD/FLS and intended scope; avoid broad grants as a shortcut. |
| Completion checkbox missing/invalid | Use the actual installed field; ensure Checkbox, editable, non-formula and accessible. |
| Strategy/pattern rejected | Use the UI's supported options/help for that field type. |
| Preview empty | Check visibility, active rules, selected object and completion state; do not assume the object has no records. |
| Full/Delta mode warning | Current supported runtime choices are Full or Unmasked records only; update legacy jobs deliberately. |
| Another run owns bypass | Inspect the owner and existing work; finish/reconcile it. Do not clear the owner blindly. |
| Snapshot missing/corrupt | Retain state and follow administrator recovery in section 12. |
| Batch fails before finish | Inspect Apex Jobs and control-panel reconciliation; record original error and run IDs. |
| OAuth/principal error | Verify installed principal mapping, app approval, User External Credentials permissions and personal authentication. |
| Same-org validation fails | Correct target domain/identity; do not disable the gate. |
| Trigger action denied despite Admin set | Add approved metadata-operation permission and Tooling principal access; check platform API/metadata rights. |
| Trigger still queued | Inspect deployment/polling result; verify final state before retrying. |
| File selection over 10 objects | Use supported limited selections and appropriate job batching; current cap remains. |
| Wrong schedule time | Check scheduling user's Salesforce timezone, next-fire date and daylight-saving behavior. |

For escalation, supply package version, sandbox org ID/domain, timestamp/timezone, user role, run/operation ID, safe error text and reproduction steps. Exclude secrets/tokens and redact record-level PII. A named support SLA or guaranteed response time is not established by this guide.

## 20. Installation acceptance record

Record Actual Result, tester/date and an evidence reference for each item. The table is a test plan, **not a declaration that these checks have passed**.

| ID | Check | Expected result | Actual result / evidence |
|---|---|---|---|
| IA-01 | Installed version/namespace | Intended package installed | To record |
| IA-02 | User role boundaries | Approved features work; unassigned user denied | To record |
| IA-03 | Discovery and acceptance | Findings reviewed; accepted rules inactive until configured | To record |
| IA-04 | Field configuration validation | Eligible rules save; invalid targets/patterns rejected | To record |
| IA-05 | Preview | Limited authorized read; no record/completion changes | To record |
| IA-06 | Small masking run | Intended synthetic values change; counts/state consistent | To record |
| IA-07 | Mixed-state bypass restoration | Original values restored with documented admin-edit semantics | To record |
| IA-08 | Cancellation/failure | No new queued work; committed work retained; state reconciled | To record |
| IA-09 | Owner isolation | Competing owner blocked; wrong owner cannot restore | To record |
| IA-10 | Same-sandbox Tooling read | Authenticated intended user; correct org verified | To record |
| IA-11 | Eligible trigger toggle | Requested state completed and verified; namespaced triggers protected | To record |
| IA-12 | Files test | Deliberate supported deletion; link consequences verified | To record |
| IA-13 | Schedule/unschedule | Correct next-fire time; future execution stops when unscheduled | To record |
| IA-14 | Production/wrong-org denial | Destructive/cross-org operation blocked without data changes | To record |
| IA-15 | Refresh reconciliation | New environment setup and per-user auth verified | To record |

## 21. Known limits and related documents

Known limits: 10-object file selection cap, finite previews, native governor/batch/API capacity, row-lock contention, legacy callback generation limits, no autonomous abandoned-run watchdog, and no way to identify an admin deliberately re-saving a true checkbox. A successful installation is not security-review approval.

Related documents supplied separately:

- **PrivacyGuard-OAuth-Post-Install-Guide.md** — detailed credential configuration, user authentication and refresh troubleshooting; included in this pack.
- **PrivacyGuard-Solution-Architecture-and-Data-Flows.md** — components, data inventory, trust boundaries and callout register.
- **PrivacyGuard-Security-Review.md** — provisional justification register and evidence gaps for 23 supplied scanner findings.

This guide is based on the supplied implementation and delivered patches, not an independent audit of the current remote repository. Final customer release documentation must reflect the exact installed released version and verified screen behavior.
