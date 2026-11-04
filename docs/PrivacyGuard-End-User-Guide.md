# PrivacyGuard: End-User Guide

Version 1.0 · 4 November 2026 (Sydney) · Baseline: PrivacyGuard 0.2.0.1

For approved users working in Salesforce Lightning. Feature availability depends on your assigned role and the installed version. This guide describes the supplied product implementation; it is not evidence that each procedure has been tested in your org.

## 1. Start here

PrivacyGuard helps you find potentially sensitive fields, choose masking rules, run controlled sandbox jobs, manage files and review results. Approved trigger administrators can also change the state of eligible Apex triggers.

**Before a destructive action:** confirm the correct sandbox, obtain approval for the scope and use test records first. Masking does not automatically preserve a recoverable copy of original values. Cancellation does not reverse previously committed batches.

| Task | Changes business data or automation? |
|---|---|
| PII discovery/review | Reads schema and saves findings/review state; does not mask business records. |
| Configure rules/jobs | Saves configuration; does not start masking by itself. |
| Preview | Reads limited accessible values and shows examples; does not update them. |
| Run masking | Changes eligible business records and completion flags. |
| File inventory | Collects accessible file metadata; not a file-content PII scan. |
| Delete files/attachments | Deletes selected content; shared Salesforce Files are affected globally. |
| Trigger deactivate/reactivate | Changes supported Apex trigger metadata after asynchronous processing. |

Production masking and deletion are blocked. Read-only PII discovery can be available in production. Do not try to bypass a blocked environment or permission check.

## 2. Open the application and check access

1. Sign in to the intended Salesforce org using Lightning Experience.
2. Open App Launcher and search for the installed PrivacyGuard application. Your administrator can confirm its displayed name if different.
3. Check the org/sandbox identity before choosing a job or content to delete.
4. Open the feature you need. If it is missing or access is denied, ask your administrator to verify your role; do not borrow another person's credentials.

| Role/task | Access to request from your administrator |
|---|---|
| Discovery/configuration administration | Approved PrivacyGuard administration/PII access and required field/object access. |
| Masking operations | Masking permission and appropriate records/fields. |
| File cleanup | Explicit purge permission and applicable file/object rights. |
| Trigger management | Metadata-operation permission, Salesforce API/metadata rights and personal Tooling OAuth access. |

An administrator role in PrivacyGuard does not automatically authorize every Salesforce operation. The person who configured OAuth cannot authenticate on your behalf for a Per User Principal.

## 3. Find and review PII candidates

### Run discovery

1. Open **PII Discovery & Review**.
2. Choose **Run New Scan** and follow the installed screen's options.
3. Wait for the scan status/results. Use search to find an object, field, label, type or detection reason.
4. Review the **Why identified**, **Configured** and **Status** information.

Discovery uses field/schema indicators and keywords. A candidate is not proof of sensitivity, and an empty result does not prove no PII exists. Confirm decisions with your data owner.

### Accept or remove candidates

1. Select the appropriate fields, then use the displayed Accept Selected action. **Accept Object** applies to an entire object's candidate group; review that wider scope before confirming.
2. Accepted fields become masking configuration and remain inactive until you configure them.
3. Use the Remove action only when you intentionally want to remove candidates from the current review. It is not a command to delete the Salesforce field or business records.
4. Use status filters **Pending**, **Accepted**, **Removed** or **All** to review your decisions.

An already configured field should not be configured a second time just to make it appear in discovery again.

## 4. Maintain discovery keywords — authorized users

Open the installed keyword-configuration feature.

1. Review packaged default words and subscriber-maintained words.
2. Add or change generic words that describe sensitive field names/labels.
3. Save and verify the displayed active state.
4. Review future scan results and remove unsuitable vocabulary through supported controls.

Use terms such as `passport` or `dob`, not actual personal values, credentials or secrets. Removing/disabling a keyword is a discovery-policy decision; it does not erase previously masked or stored business data.

## 5. Set up field masking rules

Open **Data Masking Configuration**.

1. Find accepted fields or choose **Add Fields** → select an object → select eligible fields → **Add Selected**.
2. Select a masking strategy for each field.
3. Enter the required **Pattern / value**, following the help shown for that strategy and field.
4. Review any validation errors or **Not supported** explanation.
5. Activate only the completed rules, then choose **Save Changes**.
6. Reopen the object group to verify the saved rules.

| Strategy family | What to consider |
|---|---|
| Email | Decide whether the chosen option preserves a domain or uses an invalid/test domain. |
| Phone / name / random string | Check field lengths and downstream business dependencies. |
| Static | Use an approved non-sensitive replacement of the correct type. |
| Regex | Follow the supported pattern/replacement help; test representative examples. |
| Numeric range / list | Use suitable values in the exact format the UI requests. |
| NULL | Available only where clearing the field is permitted. |

Only eligible choices should be used. A strategy example is not a guarantee that all subscriber validation rules or automations will accept real updates.

**Removing a rule:** use its Remove Configuration control and read the confirmation. This excludes the field from future masking; it does not restore original values. Discovery/audit history can remain.

## 6. Create a masking job

Your administrator must ensure each selected object has a valid editable completion checkbox and that you can update it. Do not select that checkbox as a masking target.

1. Open **Masking Jobs** → **Create Masking Job**.
2. Enter a clear job name and description.
3. Select objects with saved active rules.
4. Choose a masking mode and execution mode.
5. Start with **Manual — Run Now** scheduling for initial validation.
6. Save the job.

| Setting | Meaning |
|---|---|
| **Full Masking** | Can change all eligible records in the configured objects, even if they were masked before. |
| **Unmasked records only** | Uses the configured completion checkbox to select eligible not-yet-completed records. |
| **Serial** | Processes object work in sequence. |
| **Parallel** | Starts multiple object batches within the run; dependencies and Salesforce limits still matter. |
| Batch size | Use the administrator-approved value for the org's workload. |

An old job showing a Delta/timestamp warning must be deliberately updated to a supported mode. Do not change modes merely to bypass an error.

## 7. Preview before running

1. Choose the saved job's preview action.
2. Select the object.
3. Review **Before**, **After**, strategy and outcome for the available sample.
4. Correct unsuitable rules and preview again before running.

The current preview shows up to five accessible records, with up to 100 configured fields. Long values may be truncated at 500 characters. Random replacements can differ during execution.

Preview is read-only: it does not update records or completion flags and does not prove validation rules, uniqueness constraints or subscriber automation will accept execution. No sample can mean no eligible records are visible for this mode—not necessarily that the object is empty.

Before values may contain real PII. Do not share unredacted screenshots broadly.

## 8. Run a masking job

Before continuing, confirm approval, target sandbox, scope, recovery arrangements and a successful small test. Do not assume record counts have been estimated.

1. Choose the saved job's Run action.
2. In **Review Masking Execution**, verify the job, masking mode, execution mode and object list.
3. Read the Full mode warning where applicable. Every eligible record in the configured objects may be affected.
4. Select **I understand this execution may permanently change sandbox records** only when you are ready to proceed.
5. Choose **Start Masking**.
6. Monitor the run and object-level results until a terminal state is displayed.
7. Inspect representative records and the completion flags/results with your administrator.

Cooperative bypass flags may be temporarily applied and restored by the application. They do not automatically disable every automation in the org. A second run can be blocked while another owner controls bypass state; contact the administrator rather than clearing the setting yourself.

## 9. Monitor, cancel and recover

### Understand the result

Use the job/run detail, dashboard/audit features and object-level error information.

| Displayed state | Action |
|---|---|
| Queued / Running | Work is not finished. Monitor before submitting duplicate work. |
| Completed | Review counts and sample outcomes; completion alone is not a business sign-off. |
| Completed with Errors / Failed / Partial | Read affected object/record errors and correct the cause before recovery. Some chunks may already have committed. |
| Cancelled / Skipped | Confirm what ran before cancellation and which work did not execute. |

Exact labels depend on the screen. Refresh the control panel when appropriate; it can reconcile certain failed or aborted background batches. Escalate jobs that remain inconsistent.

### Cancel

1. Choose the active job's cancellation action.
2. Read **Cancel Masking Job** and select **Cancel Job** if intended.
3. Wait for the updated state and verify the impact with your administrator.

Cancellation is not rollback. Previously committed batches remain masked. Unscheduling a job stops future scheduled runs and is a different action.

### Recover

1. Identify the error category and affected run/object/record references.
2. Ask the responsible administrator/data owner to resolve access, field rules, locking or automation failures.
3. Use the eligible failed run's recovery/rerun action, where supported.
4. Review resulting failures, counts and records. Do not assume recovery repeats every originally selected record.
5. Ask the administrator to verify bypass restoration after failure/cancellation if state is uncertain.

Do not edit internal owner/snapshot or job history records to force a status change.

## 10. Set or stop a schedule — authorized users

1. Validate the job manually first.
2. Open its schedule action or schedule controls in the editor.
3. Choose **Daily**, **Weekly** or **Monthly**, and provide the requested day/time.
4. Verify the scheduling user's Salesforce timezone and next scheduled execution.
5. Save and confirm the displayed schedule.

For a date that is not present every month, ask your administrator to verify the next-fire behavior. Review daylight-saving changes where relevant.

Use **Unschedule** or **Cancel Schedule** to stop future execution. It does not cancel the active run. Schedule ownership, permissions and environment readiness must remain valid; scheduling does not repair revoked access or post-refresh OAuth configuration.

## 11. Review and delete files — purge-authorized users

### Collect an inventory

1. Open the installed file-inventory view.
2. Choose **Scan All Accessible Files**.
3. Review collected file name, kind/type, size, owner, record relationship and library information.
4. Use **Stop scan** if needed. A stopped scan is incomplete.
5. Use the displayed download action if you need an approved copy of the collected metadata.

“Accessible” refers to what the running user can inventory. File titles/relationships can be sensitive. An inventory is not a file-body PII or malware scan.

### Delete selected inventory items

**Salesforce Files are deleted globally, including versions and shared record links. Legacy Attachments are deleted from their parent.** Do not treat document deletion as simply removing one link.

1. Review the selected items' ownership, names and relationships with the data owner.
2. Select only the intended collected records. **Select all collected** refers to the collected set, which may be incomplete if scanning was stopped.
3. Choose **Delete selected**.
4. Review the confirmation list of names/IDs and the shared-file warning.
5. Type **DELETE** only when the selection is approved, then choose **Confirm deletion**.
6. Inspect **Deletion results** and, if needed, **Download deletion results**.
7. Escalate failed items rather than repeatedly resubmitting the entire selection.

This feature does not promise permanent hard-delete or universal recovery. Recovery depends on Salesforce retention/permissions and approved backup arrangements; it is not a package rollback button.

### Object-related cleanup

Where using **Attachment & File Manager**, choose eligible objects, inspect supported counts and resolve warnings before submitting cleanup. The current object-selection scan/purge paths limit a selection to 10 objects. This cap is distinct from the accessible-file inventory workflow.

## 12. Manage Apex triggers — approved trigger administrators

Ask your administrator to complete the installed Named Credential/OAuth configuration first. Authenticate your own user from Lightning personal **Settings → External Credentials** using the installed PrivacyGuard credential, if required.

1. Open Automation Management and refresh the supported trigger list.
2. Confirm the target sandbox and the test/change approval.
3. Review the current state and select an eligible non-namespaced trigger.
4. Submit the requested deactivate/reactivate action.
5. Monitor queued/deployment status and wait for the **verified final state**.
6. Record the result and restore the approved trigger state after testing.

A queued request or successful OAuth login is not proof of a completed metadata change. Namespaced triggers are protected. Flow and validation-rule metadata toggling is unsupported.

Do not change the Named Credential URL, use another user's authentication, or request a production override to resolve an error. The application intentionally checks the endpoint is the same sandbox.

Separately toggled trigger metadata is not the same as temporary cooperative bypass flags; confirm each outstanding trigger change explicitly.

## 13. Review audit information and protect data

Use available dashboard/audit views to review masking, discovery, automation, file operations and configuration activity. Record run/operation IDs when investigating problems.

Logs can contain record IDs, field/object names, technical errors and potentially values embedded in subscriber error messages. Limit exports and screenshots to approved recipients. Do not paste OAuth secrets/tokens or unredacted PII into support requests.

Deleting a job or removing masking configuration does not reverse previous masking. Operational history is not represented as an immutable compliance archive; follow your administrator's retention rules.

## 14. Troubleshooting and escalation

| Problem | What you should do |
|---|---|
| Feature missing or access denied | Ask the administrator to verify your role and object/field access. |
| Candidate does not appear | Check filters and already-configured state; discovery keywords are not exhaustive. |
| Rule cannot be saved | Read the field's validation message and use an eligible strategy/pattern. |
| Completion checkbox error | Ask the administrator to verify the editable checkbox and your access. |
| Preview empty or unavailable | Check object/mode/rules and visibility; do not use broad access as an automatic fix. |
| Job says another run owns bypass | Wait for the existing run or ask the administrator to investigate/reconcile it. |
| Masking failed | Capture the run/object/record reference and safe error; resolve cause before recovery. |
| Cancelled but values changed | Previously committed batches remain changed; cancellation does not undo them. |
| File count/access warning | Resolve the warning before cleanup. Do not assume missing counts mean zero files. |
| Trigger action queued or failed | Wait/check operation details; ask an approved administrator to verify auth and platform rights. |
| Wrong-org/sandbox error | Stop; have the administrator correct environment setup. |
| Schedule fires unexpectedly | Confirm scheduling user's timezone, frequency, next-fire date and active schedules. |
| Sandbox was refreshed | Ask the administrator to complete post-refresh checks before resuming jobs. |

Provide: installed version, target sandbox, timestamp/timezone, task, run/operation ID, safe error text and steps to reproduce. Use your organization's approved support route; no specific support address or response SLA is established by this guide.

## 15. First-use checklist

- [ ] I am in the intended sandbox and have approved access.
- [ ] The data owner approved the selected objects/fields/content.
- [ ] I understand the destructive effect and the approved recovery arrangements.
- [ ] Rules are active and valid; the administrator confirmed completion checkbox readiness.
- [ ] I reviewed a limited preview and tested on suitable sample data.
- [ ] I verified job mode, object scope and schedule/timezone.
- [ ] I monitored completion, errors and any cancellation result.
- [ ] I asked for bypass/trigger-state verification where relevant.
- [ ] I retained only authorized, appropriately redacted evidence.

## 16. Terms and related guides

| Term | Meaning |
|---|---|
| PII | Personally identifiable information; discovery identifies candidates, not definitive legal classifications. |
| Masking rule | A selected treatment/pattern for a field. |
| Job | Reusable execution configuration. |
| Run | A particular execution of a job. |
| Completion checkbox | Per-record marker used by supported masking modes. |
| Cooperative bypass | A temporary switch honored only by automation written to check it. |
| Named Credential / OAuth | Administrator-configured authenticated connection used for supported same-sandbox API operations. |

For setup, permission assignments, recovery and refresh procedures, see **PrivacyGuard-Installation-and-Administrator-Guide.md** and **PrivacyGuard-OAuth-Post-Install-Guide.md**. For implementation boundaries, see **PrivacyGuard-Solution-Architecture-and-Data-Flows.md**.

This guide contains instructions, not test-result attestations. Screen labels reflect the supplied source baseline and may vary in another installed version. Have the administrator verify material differences before destructive operations.
