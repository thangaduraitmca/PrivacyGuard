# PrivacyGuard — Salesforce Data Masking Framework

A reusable, metadata-driven data masking framework. Configure new fields, patterns,
and job sequencing entirely through Custom Metadata — no code changes required for
the common case.

## What's included

| Component | Type | Purpose |
|---|---|---|
| `Masking_Configuration__mdt` | Custom Metadata Type | Which Object.Field to mask, with what strategy/pattern |
| `Masking_Job_Sequence__mdt` | Custom Metadata Type | Which jobs run, per object, Serial or Parallel, in what order |
| `Automation_Bypass__c` | Hierarchy Custom Setting | Flags your Flows/Triggers/Validation Rules check to skip themselves during a run |
| `Masking_Run_Tracker__c` | Hierarchy Custom Setting | Internal — tracks how many jobs have finished |
| `Masking_Log__c` | Custom Object | Structured success/error log |
| `IMaskingStrategy` + 6 implementations | Apex | Pluggable masking logic (Email, Phone, Name, Random String, Static, Regex) |
| `MaskingConfigService` | Apex | Reads the two `__mdt` types |
| `AutomationManagerService` | Apex | Flips the bypass flags before/after a run |
| `MaskingBatch` | Apex (Batchable) | Does the masking, per object, with per-record/per-field error handling |
| `MaskingJobOrchestrator` | Apex | Runs jobs Serial (chained) or Parallel (concurrent), re-enables automations once everything finishes |
| `MaskingFrameworkService` | Apex | Single public entry point |
| `MaskingScheduler` | Apex (Schedulable) | Optional — schedule a recurring run |

Sample config for `Contact.Email`, `Contact.Phone`, `Contact.LastName` and a
`Mask_Contact` job are included so it works right after install.

## Install (SFDX)

```bash
sfdx force:auth:web:login -a MyOrgAlias
sfdx force:source:deploy -p force-app -u MyOrgAlias
# or, newer CLI:
sf project deploy start --source-dir force-app --target-org MyOrgAlias
```

Or deploy via `package.xml` with the Metadata API / Workbench if you're not using SFDX.

## Configure a new field to mask

Add a `Masking_Configuration__mdt` record (Setup → Custom Metadata Types → Masking
Configuration → Manage Records, or via SFDX):

| Field | Example |
|---|---|
| Object API Name | `Account` |
| Field API Name | `BillingEmail__c` |
| Field Type | `EMAIL` |
| Masking Strategy Class (Override) | *(blank = use default for Field Type)* |
| Masking Pattern | *(strategy-specific — see below)* |
| Is Active | ✅ |

**Built-in Field Types → default strategy:**
- `EMAIL` → keeps the domain, randomizes the local part
- `PHONE` → keeps formatting/punctuation, randomizes digits
- `NAME` → picks from a small sample-name pool
- `RANDOM_STRING` → random alphanumeric string; `Masking_Pattern__c` = length (e.g. `12`)
- `STATIC` → writes a literal value; `Masking_Pattern__c` = the value (e.g. `MASKED`)
- `REGEX` → `Masking_Pattern__c` = `regex=>replacement` (e.g. `[0-9]=>9`)

**Add your own strategy:** implement `IMaskingStrategy`, deploy it, then either
register it as a new default in `MaskingStrategyFactory.DEFAULT_STRATEGY_BY_FIELD_TYPE`,
or reference the class name directly in `Masking_Strategy_Class__c` on any config record
— no factory change needed for a one-off override.

## Define job sequencing (Serial vs Parallel)

Add a `Masking_Job_Sequence__mdt` record per object:

| Field | Example |
|---|---|
| Job Name | `Mask_Account` |
| Object API Name | `Account` |
| Execution Mode | `Serial` or `Parallel` |
| Sequence Order | `2` *(Serial jobs only — determines order)* |
| Batch Size | `200` |
| Is Active | ✅ |

- **Serial** jobs run one after another — use this when one object's masked data
  feeds into how you'd want to mask a related object, or to control load on the org.
- **Parallel** jobs are all submitted to the batch queue at once — use this for
  independent objects when speed matters more than sequencing.

## Automation bypass — wire this into your Flows/Triggers/Validation Rules

The framework can't force-deactivate a Flow or Trigger mid-run; instead it flips
`Automation_Bypass__c` flags that your automations must check themselves:

- **Flow:** add a Decision element checking `{!$Setup.Automation_Bypass__c.Bypass_Flows__c}`
  and route to an immediate end if true.
- **Trigger:**
  ```apex
  trigger ContactTrigger on Contact (before update) {
      if (Automation_Bypass__c.getInstance().Bypass_Triggers__c) return;
      // ... normal logic
  }
  ```
- **Validation Rule:** wrap your existing formula:
  ```
  AND(
      NOT($Setup.Automation_Bypass__c.Bypass_Validation_Rules__c),
      <your existing rule logic>
  )
  ```

`AutomationManagerService.disableAllAutomations()` runs automatically at the start
of `MaskingFrameworkService.executeMaskingRun()`, and
`enableAllAutomations()` runs automatically once every job (Serial + Parallel)
has finished.

## Run it

```apex
// Anonymous Apex / Developer Console
MaskingFrameworkService.executeMaskingRun();
```

Or schedule a recurring run:
```apex
System.schedule('Nightly Sandbox Mask', '0 0 2 * * ?', new MaskingScheduler());
```

## Check results / errors

```sql
SELECT Job_Name__c, Object_API_Name__c, Record_Id__c, Field_API_Name__c, Status__c, Error_Message__c
FROM Masking_Log__c
ORDER BY CreatedDate DESC
```

## Scanning the org to find PII fields worth masking

Before you can configure masking rules, you need to know what to configure. The
included scanner flags candidate fields for review — it does **not** auto-activate
anything in `Masking_Configuration__mdt`.

**How it scores a field:**
1. **Field type** — `Email` and `Phone` fields are flagged automatically (High confidence). Fields already Shield-encrypted (`EncryptedString`) are flagged too — someone already decided they were sensitive.
2. **Keyword match** — field label + API name checked against `PII_Keyword__mdt` (ssn, dob, passport, salary, address, credit card, tax id, medical, gender, maiden name, etc. included as a starting set — add/edit records to tune it, no code change needed).
3. **Already configured** — cross-checked against active `Masking_Configuration__mdt` so you don't get re-suggested fields you've already wired up.

**Run a full-org scan:**
```apex
// Anonymous Apex
Database.executeBatch(
    new PIIFieldScannerBatch(PIIFieldScannerBatch.getAllScannableObjects()), 1
);
```

**Run it against specific objects:**
```apex
Database.executeBatch(
    new PIIFieldScannerBatch(new List<String>{ 'Contact', 'Lead', 'Account', 'Case' }), 5
);
```

**Review findings:**
```sql
SELECT Object_API_Name__c, Field_API_Name__c, Field_Label__c, Detection_Reason__c,
       Already_Configured__c, Native_Compliance_Tag__c
FROM PII_Scan_Result__c
WHERE Review_Status__c = 'New'
ORDER BY Object_API_Name__c, Field_API_Name__c
```

Set `Review_Status__c` to `Accepted` for fields that belong in masking scope, or `Removed` for candidates you do not want in scope. You can also add fields manually in the PII Scan Review UI. Generated metadata is deliberately inactive and has no masking strategy until an administrator configures and activates it:

```apex
Map<String, String> filesByName = MaskingConfigPromoter.generateMetadataXmlForAcceptedFindings();
for (String fileName : filesByName.keySet()) {
    System.debug(fileName + ':\n' + filesByName.get(fileName));
}
```

Save each file into `force-app/main/default/customMetadata/` and deploy — that
turns an accepted finding into a live masking rule.

**Native Salesforce Data Classification as a 4th signal:**

If your org already tags fields via Setup's built-in Data Classification section
(Compliance Categorization, Data Sensitivity Level), the scanner reads those too, via
the Tooling API, and treats them as High confidence. To enable it:

1. Setup → Remote Site Settings → New → point it at your own org's My Domain URL (e.g. `https://yourdomain.my.salesforce.com`).
2. That's it — `PIIFieldScannerBatch` already calls the scanner with `includeNativeComplianceTags=true`. If the Remote Site Setting isn't configured, or the calling context can't reuse its session for a callout, `ComplianceCategorizationService` catches the failure and the scan just proceeds on field-type + keyword signals — it never blocks the rest of the scan.

**Admin review screen (no SOQL required):**

A Lightning web component, `piiScanReview`, is included. Add it to any App Page, Record
Page, or a custom Tab (Setup → Tabs → New Lightning Component Tab → PII Scan Review).
It lets an admin:
- Filter findings by review status (New / Accepted / Rejected / All)
- Multi-select rows and bulk Accept/Reject
- Trigger a new org-wide scan with one click (runs async — refresh after a minute)
- Generate the Custom Metadata XML for every Accepted finding and copy it straight into `force-app/main/default/customMetadata/` for deployment

**What this scanner won't catch:**
- **Free text containing PII** (e.g. a `Notes__c` field where someone once pasted an SSN). Keyword matching works on field *names*, not field *contents* — a full content-scan would require querying and pattern-matching actual data across every text field, which is a much heavier (and slower) operation. If that's a real risk in your org, consider Salesforce Shield's Data Detection/classification tooling or a dedicated data-discovery product for content-level scanning, and treat this scanner as the fast, cheap first pass on schema.
- Fields whose name gives no hint of sensitivity (e.g. a custom field literally called `X1__c` storing a national ID).
- Native "Data Classification" tags admins may have set in Setup (Compliance Category, Data Sensitivity Level) aren't read by this scanner by default — they're exposed via the Tooling API (`FieldDefinition`), which requires a callout with an org-authorized endpoint. If your org already uses those fields consistently, that's a stronger signal than keyword-matching and worth wiring in as an additional source.

## Delta masking (only mask new/changed records)

Full masking re-processes every record every run. For a daily or weekly schedule
that's usually wasteful — you only need to catch records that are new or have been
edited since they were last masked (e.g. someone reset a field back to real data
during testing, or a fresh integration sync wrote new PII into old records).

**Why not just filter on `LastModifiedDate > last run time`?** Because the masking
run's own update bumps `LastModifiedDate` — the very next run would see those
records as "recently modified" and re-mask them forever. Instead, this framework
stamps a **per-record high-water mark** field on the target object at the moment it
masks that record, and compares that timestamp to `LastModifiedDate` on the next
run. A record is only picked up again if something external changed it *after* it
was last masked.

**Setup (per object you want in Delta mode):**

1. Add a `DateTime` custom field to the target object, e.g. `Data_Masking_Applied_Date__c`. This package already ships this exact field on `Contact` — but the shipped `Mask_Contact` sample job runs in **Full** mode by default, deliberately, so it doesn't have to hardcode a reference to its own field's namespaced name (see "Namespace" below for why that matters). To try Delta mode with the bundled field, edit the `Mask_Contact` job record and set `Delta_Tracking_Field__c` to:
   - `Data_Masking_Applied_Date__c` if you deployed this directly (no namespace)
   - `privacyguard__Data_Masking_Applied_Date__c` if you installed the packaged, namespaced version
2. On the object's `Masking_Job_Sequence__mdt` record, set:
   - `Run_Mode__c` = `Delta`
   - `Delta_Tracking_Field__c` = the API name of the field you added

That's it — `MaskingBatch` handles the rest: its query becomes
`WHERE Delta_Tracking_Field__c = null OR LastModifiedDate > Delta_Tracking_Field__c`,
and every successful masking update also stamps that field with the current
timestamp, in the same `Database.update` call.

Leave `Run_Mode__c` blank (or set it to `Full`) for objects where you always want a
complete re-mask, e.g. right after a sandbox refresh.

## Once mode (mask a record a single time, ever)

Delta mode's DateTime comparison is what lets it detect a record being
re-populated with real data after it was masked — but that detection is more
than some workflows need. If your records genuinely never receive real data
again once masked (a one-time historical backfill, or closed/archived
records), a simpler mechanism is available: **Once mode**, using a `Checkbox`
field instead of a `DateTime` field.

**How it differs from Delta:**

| | Delta | Once |
|---|---|---|
| Tracking field type | `DateTime` | `Checkbox` |
| Query | `field = null OR LastModifiedDate > field` | `field = false` |
| Stamp on masking | Current timestamp | `true` |
| Detects re-population with real data after masking | **Yes** | **No — this is the trade-off** |

**Why Once mode can't detect drift:** a boolean is a fact ("this was masked at
some point"), not a relationship ("this is still consistent with when it was
last touched"). Once the flag is `true`, nothing resets it — if an integration
later re-syncs real data into that record, `LastModifiedDate` changes but the
flag doesn't, and Once mode will never re-select it. Delta mode's DateTime
comparison exists specifically to catch that case; only use Once mode where
you're confident it can't happen for your data.

`MaskingBatch` validates the tracking field's actual type against the
selected mode before running (`DateTime` for Delta, `Checkbox` for Once) and
fails with a clear error if they don't match, rather than a cryptic SOQL
type-mismatch error.

**Setup:** identical to Delta mode, except the field is a `Checkbox` and
`Run_Mode__c` = `Once`. This package ships a working example field,
`Contact.Data_Masking_Complete__c`, for the same reason `Mask_Contact` doesn't
default to Delta mode out of the box — the shipped sample jobs stay in `Full`
mode so they never self-reference a namespace-sensitive field (see
"Namespace" below).

## Scheduling (daily / weekly)

`MaskingScheduler` (Schedulable) calls `MaskingFrameworkService.executeMaskingRun()`,
which reads every active `Masking_Job_Sequence__mdt` record and respects each job's
Full/Delta setting — so the same schedule can run a Delta job on `Contact` and a Full
job on `Account` side by side.

```apex
// Daily at 2 AM org time
MaskingSchedulerUtil.scheduleDaily('Daily Data Mask', 2);

// Weekly, every Sunday at 2 AM org time
MaskingSchedulerUtil.scheduleWeekly('Weekly Data Mask', 'SUN', 2);

// Stop a scheduled run
MaskingSchedulerUtil.abortScheduledJobsByName('Daily Data Mask');
```

Typical setup: run a one-time **Full** mask immediately after a sandbox refresh
(`MaskingFrameworkService.executeMaskingRun()` in Anonymous Apex), then schedule a
recurring **Delta** run to keep catching new/changed records without re-processing
the whole object every time.

## Deleting Attachments and Files

Masking text fields doesn't help if the actual uploaded document — a scanned ID,
an exported spreadsheet, a signed contract PDF — is still sitting there as an
Attachment or File. This framework can delete both, related to whatever objects you
specify, two ways:

**Option A — direct, ad-hoc (you just supply the objects):**
```apex
// Anonymous Apex
FileAttachmentPurgeService.purgeForObjects(
    new List<String>{ 'Contact', 'Lead', 'Case' },
    true,  // delete Attachments
    true   // delete Files (ContentDocument)
);
```
Or use the included `attachmentFilePurge` LWC — drop it on an App Page, Record Page,
or a Lightning Component Tab. Type in object API names (comma-separated), check
Attachments and/or Files, click Purge. No CMDT setup needed.

**Option B — as part of your scheduled masking sequence:**
Add a `Masking_Job_Sequence__mdt` record with:
- `Job_Type__c` = `ATTACHMENT_DELETION` or `FILE_DELETION`
- `Object_API_Name__c` = the object whose related Attachments/Files to delete
- `Execution_Mode__c`, `Sequence_Order__c`, `Batch_Size__c` same as any other job

This runs it on the same schedule and inside the same automation-bypass/logging
framework as your field-masking jobs — e.g. delete a Lead's Attachments right before
masking its fields, in the same Serial sequence.

**What actually gets deleted:**
- **Attachments** (legacy): every `Attachment` row whose `ParentId` is a record of the object you specified.
- **Files**: the underlying `ContentDocument` for every File linked (`ContentDocumentLink.LinkedEntityId`) to a record of that object — this removes the file itself (and its version history), not just the link. **If a file is shared across multiple records, this deletes it everywhere it's linked, not only from the object you targeted** — check for shared files first if that matters in your org.
- Deletion is irreversible outside of the Recycle Bin's normal retention window — there's no "preview" step. Test in a sandbox first.

## Security controls

Every class has an explicit sharing declaration — no class relies on the ambiguous
default. The choices are deliberate, not uniform:

- **`MaskingBatch` and `FileAttachmentDeletionBatch` are `without sharing`, on purpose.**
  A masking/deletion job's entire job is to process *every* record of the target
  object. If these ran `with sharing`, the org's sharing rules could silently hide
  records from the batch's query — e.g. private records outside the running/scheduled
  user's role visibility — leaving real PII unmasked or files undeleted. Access
  control for this framework lives upstream (Permission Set assignment, the
  Sandbox-only safety gate), which is the correct control point for a tool whose job
  is intentionally to bypass normal per-record restrictions.
- **Everything else is `with sharing`** — config readers, loggers, the orchestrator,
  and both LWC controllers.
- **SOQL injection is closed off**, not just discouraged. `MaskingBatch`,
  `FileAttachmentDeletionBatch`, and `ComplianceCategorizationService` all build
  dynamic SOQL from object/field API names — some of which (in
  `FileAttachmentPurgeService`) come directly from free text typed into the
  Attachment/File Purge LWC. Every one of those names is validated against the org's
  real schema via `SchemaValidationUtil` *before* it's concatenated into a query
  string. Only strings that exactly match a real, describable object/field can ever
  reach a query — there's no way to smuggle SOQL syntax through as if it were an
  object name.
- **CRUD/FLS is enforced where it should be, and deliberately not where it
  shouldn't.** `PIIScanReviewController` and `MaskingConfigPromoter` use
  `WITH SECURITY_ENFORCED` on reads and `Security.stripInaccessible()` on writes,
  since those touch a real custom object (`PII_Scan_Result__c`) through a
  user-facing LWC. `MaskingBatch`'s actual masking writes do **not** enforce the
  running user's FLS — masking a field the user isn't personally permitted to edit
  is the whole point.
- **LWC-facing exceptions never leak raw stack traces.** Every `@AuraEnabled` method
  catches exceptions and re-throws as `AuraHandledException` with an explicit
  `setMessage()` call — the constructor argument alone isn't reliably surfaced to
  the client (a well-known Salesforce quirk that otherwise shows a generic
  "Script-thrown exception" instead of anything useful).
- **The Sandbox-only safety gate is enforced twice** (see above) so it can't be
  bypassed by code that skips the orchestrator.

## Test coverage

All 44 non-interface Apex classes have dedicated test coverage (some via a matching
`*Test` class, some exercised across several — e.g. `MaskingBatch` is covered by
`MaskingFrameworkIntegrationTest`, `MaskingJobOrchestratorTest`, and
`EnvironmentSafetyServiceTest` from different angles: delta-mode behavior, serial
chaining, and the production safety block respectively). Coverage includes:
- Every masking strategy, individually, including null-input edge cases
- Real serial-chain execution across two different jobs/objects (`Mask_Contact` → `Mask_Lead`), not just a single-job happy path
- The "job configured but no field config found" skip branch, for both Serial and Parallel dispatch
- Delta-mode's actual high-water-mark behavior (untouched record skipped; externally-modified record re-picked-up)
- The production safety gate: blocked by default, allowed in Sandbox, allowed with explicit override, and blocked even on direct batch invocation bypassing the orchestrator
- `ComplianceCategorizationService`'s Tooling API integration via `HttpCalloutMock` (both success-with-parsing and failure-degrades-gracefully paths)
- `AutomationMetadataToggleService`'s Tooling API deactivate/reactivate cycle for Flows and Validation Rules via `HttpCalloutMock` — including the callout-budget limit and total-failure degradation paths
- Every `@AuraEnabled` controller method, including the blocked/error paths surfacing through `AuraHandledException`
- Scheduling (`System.schedule` cron verification) and the abort-by-name helper

Run `sf apex run test --code-coverage --result-format human --target-org YourOrg` after deploying to confirm coverage in your org — Apex coverage is computed live per org and can vary slightly with API version and existing metadata, so treat the >90% target as what this test suite is designed to produce rather than a number guaranteed independent of where it's deployed.

## Kicking off a run from the UI

Three ways, from simplest to most flexible:

1. **One-click button**: the **Masking Control Panel** tab has a single "Run Full
   Masking Sequence Now" button (`maskingControlPanel` LWC → `MaskingControlPanelController`).
2. **Flow/Quick Action**: `MaskingRunInvocable` is exposed as an Invocable Action
   ("Run Data Masking Jobs", category "PrivacyGuard"). Build a Screen Flow
   with a single Action element selecting it, add a confirmation screen before it if
   you want a safety prompt, and expose it as a Quick Action or a button on a
   Lightning App Page — no Apex required on your end. It returns a `success`/`message`
   pair (rather than a raw Flow fault) so you can branch and show a friendly message,
   including the Sandbox-only safety block text if it's blocked.
3. **Programmatic**: `MaskingFrameworkService.executeMaskingRun()` from Anonymous Apex or a scheduled job (see "Scheduling" above).

## Automation bypass — two layers: flag-checks vs. actual deactivation

**Layer 1 (always on): bypass flags.** Covered above — your Flows/Triggers/Validation
Rules must check `Automation_Bypass__c` and skip themselves. This is the only layer
available for Apex Triggers (see why, below).

**Layer 2 (opt-in): real Tooling API deactivation of Flows and Validation Rules.**

Enable it: Setup → Custom Settings → Automation Bypass → Manage → New (org default),
check **Use Metadata Deactivation (Flows/Validation Rules)**.

When enabled, `disableAllAutomations()` doesn't just flip flags — it queries every
active Flow (`FlowDefinition`) and Validation Rule (`ValidationRule`) via the Tooling
API and actually deactivates them (`AutomationMetadataToggleService`), records exactly
what it changed in `Deactivated_Automation__c`, and `enableAllAutomations()` restores
each one to its prior state afterward — Flows back to their original active version
number, Validation Rules back to active. Check the **Deactivated Automations** tab to
see what was touched and confirm everything got restored (`Reactivated__c = true`).

**Why Apex Triggers aren't included in Layer 2:** toggling a trigger's Active/Inactive
status via the Tooling API isn't a simple field update the way it is for Flows and
Validation Rules — it goes through Salesforce's Apex compile pipeline
(`MetadataContainer` + `ApexTriggerMember` + `ContainerAsyncRequest`), which resolves
asynchronously and needs its own polling logic to know when it's actually done. That's
a meaningfully different (and less reliable to get right without live-org validation)
mechanism than a direct metadata PATCH, so triggers stay on the flag-check pattern —
which works reliably as long as your trigger code checks `Bypass_Triggers__c`.

**Prerequisites for Layer 2:**
1. A Remote Site Setting authorizing callouts to your own org's My Domain URL (same one used for the PII scanner's native-compliance-tag lookup — see above).
2. The running/scheduled user needs API access enabled.

**Important caveats before enabling Layer 2:**
- **Deactivating a Flow affects every use of it** — including Screen Flows a user might be actively running. During the masking window, users temporarily can't launch *any* Flow in the org, not just record-triggered ones.
- **Callout volume is capped.** Each Flow/Validation Rule deactivation is one HTTP callout; Apex allows 100 per transaction. This framework stops at 80 to leave headroom, and logs a warning if your org has more active components than that — anything past the cap is left running, protected only by the Layer 1 flags. For orgs with very large numbers of active Flows/Validation Rules, Layer 1 alone (retrofit the bypass-flag checks) may be the more dependable choice.
- **Every failure here is caught and logged, never thrown** — if the Tooling API call fails entirely (missing Remote Site Setting, permissions issue), the masking run still proceeds protected by the Layer 1 flags alone; nothing blocks or half-completes.
- **This has not been validated against a live org from this environment.** Test it against a small, non-critical set of automations in a sandbox first before relying on it broadly, and check the Deactivated Automations tab after a run to confirm the reactivation actually completed.

## Production safety gate — Sandbox-only by design

This framework's entire purpose is protecting real data by scrubbing copies of it —
actually running its destructive operations (overwriting fields, deleting
Attachments/Files) against Production would defeat that purpose entirely. So it
refuses to run anywhere that isn't a Sandbox, by default, with no configuration
required.

**How it's enforced:** `EnvironmentSafetyService` checks `Organization.IsSandbox`.
This is checked in two places for defense in depth:
1. `MaskingJobOrchestrator.runJobs()` — the funnel every entry point goes through (scheduled runs, `MaskingFrameworkService.executeMaskingRun()`, `FileAttachmentPurgeService.purgeForObjects()`).
2. Inside `MaskingBatch.start()` and `FileAttachmentDeletionBatch.start()` directly — so even code that constructs and executes a batch by hand, bypassing the orchestrator, is still blocked.

If blocked, it throws `EnvironmentSafetyService.ProductionExecutionBlockedException`
with a clear message — nothing is masked or deleted, nothing is left half-done.

**PII scanning is exempt on purpose** — `PIIFieldScannerBatch` is read-only and
genuinely useful to run in Production (that's where you'd want a real inventory of
what needs masking policies). Only the destructive paths are gated.

**If you truly need to run in Production** (rare — e.g. a one-off compliance
deletion request against real data), there's an explicit, deliberate override:
Setup → Custom Settings → Masking Environment Override → Manage → New (org default),
check **Allow Run In Production**. Leave it unchecked otherwise. This is the same
"explicit flag, off by default" pattern used for automation bypass elsewhere in this
framework — nothing runs in Production silently.

## Namespace & proprietary packaging (PrivacyGuard)

This package is namespaced as **`privacyguard`** (set in `sfdx-project.json`), packaged
under the name **PrivacyGuard**. A few things worth knowing:

**On the namespace string itself:** Salesforce namespace prefixes must be 1–15
characters, letters and numbers only, starting with a letter — no spaces, no
underscores. `privacyguard` is a placeholder chosen to fit that constraint and match
the product name; if you've already reserved a different namespace for your
packaging org, update the `namespace` field in `sfdx-project.json` to match it before
running `sf package version create` (namespace registration is a one-time, manual
step done in your packaging org's Setup — see "Building an actual managed package"
below — nothing here does that for you).

**You generally don't need to hand-edit component API names for namespacing.**
Standard SFDX convention: source files stay unprefixed (`Masking_Log__c`,
`Data_Masking_Applied_Date__c`, etc.). Salesforce automatically applies the
`privacyguard__` prefix to every custom component **only when it's created inside the
namespaced packaging org** (or a subscriber org after install) — not when you deploy
this source directly into an ordinary sandbox with `sf project deploy start`, which
creates everything unprefixed. Apex code inside the package also doesn't need
namespace prefixes to reference its own package's objects/fields — that resolves
implicitly at compile time.

**The one place this DOES bite you: data values that name the package's own fields.**
Any Custom Metadata *value* (not a component declaration — actual stored text, like
`Masking_Job_Sequence__mdt.Delta_Tracking_Field__c`) that references a field this
package itself ships is a plain string, and strings don't get auto-namespaced the way
metadata component names do. If that value says `Data_Masking_Applied_Date__c` but
the field actually deployed as `privacyguard__Data_Masking_Applied_Date__c` (because
you installed the real packaged version), the dynamic SOQL built from that value will
reference a field that doesn't exist. This is exactly why the shipped `Mask_Contact`
sample job defaults to **Full** mode rather than Delta — it avoids baking in a
namespace-sensitive self-reference. If *you* add masking config that points at one of
this package's own fields (rare — most config will point at the subscriber org's
standard/custom fields, which are never namespaced by this package), use the
namespaced name if you're on the installed package, or the plain name if you deployed
source directly.

**Branding:** the Lightning app, permission set, and all labels use "PrivacyGuard" as
the product name; underlying component API names remain the descriptive
`Masking_*`/`PII_*` names they always were — renaming those now would be a large,
disruptive change to already-tested internal code for no functional benefit, since
the namespace prefix already provides package-level ownership and uniqueness.

## Packaging as an installable app

Everything ships as a self-contained Lightning app, **PrivacyGuard**, with
its own tab set:

| Tab | What it is |
|---|---|
| PII Scan Review | LWC — review/accept/reject scan findings, trigger scans |
| PII Scan Results | Raw list view of `PII_Scan_Result__c` |
| PII Keywords | Manage the `PII_Keyword__mdt` dictionary |
| Masking Configurations | Manage `Masking_Configuration__mdt` |
| Masking Job Sequences | Manage `Masking_Job_Sequence__mdt` |
| Attachment & File Purge | LWC — ad-hoc Attachment/File deletion by object |
| Masking Logs | `Masking_Log__c` list view |

A permission set, **PrivacyGuard Admin** (API name `Data_Masking_Framework_Admin`), grants everything a non-admin
team member needs: Apex class access, object/field permissions on `Masking_Log__c`
and `PII_Scan_Result__c`, tab visibility, and app visibility. **It intentionally does
not grant "Customize Application"** — managing the three Custom Metadata Types
(`Masking_Configuration__mdt`, `Masking_Job_Sequence__mdt`, `PII_Keyword__mdt`) still
requires that permission, which System Administrators already have. If you want
non-admins to edit masking config directly, they'll need that permission too (it's a
broad, org-wide grant — most teams keep config changes admin-only on purpose).

### Deploying directly (no packaging) — fastest way to get running

```bash
sf project deploy start --source-dir force-app --target-org YourSandboxAlias
sf org assign permset --name Data_Masking_Framework_Admin --target-org YourSandboxAlias
```
Then in Setup → App Manager, the **PrivacyGuard** app is ready to open, or
assign the permission set to other users who need access.

### Building an actual managed package (for distributing to multiple orgs/production install)

This requires a **Dev Hub**-enabled org and a one-time namespace registration —
neither of which this deliverable can do on your behalf. Steps:

1. **Enable Dev Hub** in a Salesforce org (Setup → Dev Hub → Enable), or use an existing one.
2. **Register a namespace** in a separate Developer Edition org that you'll link as the packaging org (Setup → Package Manager → Edit next to Current Namespace — this is a one-time, permanent choice, e.g. `acmedatamask`). Link that org to your Dev Hub via `sf org login web --set-default-dev-hub`.
3. **Set the namespace** in `sfdx-project.json` to the one you registered (it's left blank in this deliverable since no namespace is registered yet).
4. **Create the package** (one-time):
   ```bash
   sf package create --name "PrivacyGuard" --package-type Managed --path force-app --target-dev-hub YourDevHubAlias
   ```
   This writes a `packageAliases` entry into `sfdx-project.json` — commit that.
5. **Create a package version** (do this after any change you want to ship):
   ```bash
   sf package version create --package "PrivacyGuard" --installation-key-bypass --wait 10 --target-dev-hub YourDevHubAlias
   ```
6. **Install it** in a sandbox or production org using the install URL/ID the previous command outputs:
   ```bash
   sf package install --package <PackageVersionId> --target-org YourTargetOrg --wait 10
   ```
   Or share the install link (`https://login.salesforce.com/packaging/installPackage.apexp?p0=<PackageVersionId>`) for a click-through install.
7. Once installed, run the two commands from "Deploying directly" above's second line (`sf org assign permset ...`) against the target org, or assign the permission set manually in Setup.

**Before installing in Production:** remember the safety gate above still applies —
installing the package into Production does not mean it will *run* there. Masking
and deletion jobs will refuse to execute unless `Allow_Run_In_Production__c` is
explicitly enabled, which is exactly the intended behavior — most teams install this
package into Production only so admins can *configure* jobs there ahead of a sandbox
refresh, without ever intending the jobs to actually execute against Production data.

**A note on managed package constraints once you've shipped v1:** API names of
Custom Metadata Types, custom objects, and fields become permanent once subscribers
install a version — renaming later requires deprecation, not renaming. Review field
names now if you plan to distribute this beyond your own org.

## Known limitations / extension points

- **Automation bypass** relies on your Flows/Triggers/Validation Rules checking the
  bypass flags themselves — it doesn't reach into metadata and flip Active/Inactive
  status. If you need true deactivation (e.g., of Flows via the Tooling API), extend
  `AutomationManagerService` with a callout guarded by a Named Credential.
- **Parallel job tracking** uses a Hierarchy Custom Setting updated from each batch's
  `finish()`. Under heavy concurrent load this can occasionally hit `UNABLE_TO_LOCK_ROW`.
  For very high job counts, consider swapping the counter for a Platform Event or an
  `AsyncApexJob` status poll.
- **Bulk data volumes:** `MaskingBatch` queries the full object with no filter in Full mode. Add a
  `WHERE` clause (e.g., scope to a sandbox refresh window or record type) by extending
  `start()` if you don't want every record masked, or switch the job to Delta mode.
- **Delta tracking field is per-object, not automatic:** you must add the DateTime field
  yourself for each object you want in Delta mode — the framework can't infer or create
  it, since it needs to live permanently on your schema.
- **Ad-hoc (non-CMDT) job lists always run Parallel:** `FileAttachmentPurgeService` builds
  jobs programmatically rather than reading them from `Masking_Job_Sequence__mdt`, so
  `handleJobCompletion()`'s serial-chain lookup (which re-reads CMDT) won't find them by
  name. This is harmless for Parallel jobs — completion tracking and automation
  re-enabling still work correctly — but don't expect ad-hoc jobs to chain in sequence
  the way CMDT-defined Serial jobs do. If you need a purge to run strictly before/after a
  specific masking job, define it as a CMDT `Masking_Job_Sequence__mdt` record instead.
- **Shared Files:** deleting a File linked to multiple records removes it everywhere,
  not just from the object you targeted for purging (see "Deleting Attachments and
  Files" above).
- **Sandbox detection relies on `Organization.IsSandbox`:** Developer Edition orgs and
  Trailhead Playgrounds report `IsSandbox = false` (they are not technically
  Sandboxes), so the safety gate blocks execution there by default too — use the
  `Allow_Run_In_Production__c` override for those environments if you use them for
  development/testing outside of a real Sandbox.


## Managed-package namespace governance

PrivacyGuard uses the registered source namespace `privacyguard`, declared in `sfdx-project.json`. Package-owned components are kept namespace-neutral in Apex, LWC, object and field source references where Salesforce packaging automatically applies the namespace. Do **not** manually prepend `privacyguard__` to same-package Apex type names or package-owned custom object/field references; doing so can break source compilation in the packaging org. Explicit namespace prefixes are retained only where metadata record serialization requires or already represents the namespaced package member. Subscriber-org runtime code must be namespace-aware when dynamically resolving package-owned metadata.

All custom fields included in this baseline contain `inlineHelpText`. All Apex and Apex test classes contain a standard audit/change-control header. New components must follow the same controls before release.

## v1.1 security hardening

PrivacyGuard v1.1 introduces explicit custom-permission gates for masking, purge, PII governance, production break-glass execution, and Tooling API metadata deactivation. Production execution now requires both the org-level override setting and a separately activated break-glass permission. Metadata deactivation likewise requires explicit configuration plus a separately activated break-glass permission. Concurrent destructive runs are blocked, tracker counter updates are row-locked, and a field-level masking error causes the affected record to fail closed rather than being partially updated or marked complete.

See `PRIVACYGUARD_SECURITY_BASELINE.md` for the release gates and residual-risk statement.

## PrivacyGuard v1.2 — governed PII candidate discovery

PII discovery is deliberately non-scoring and non-prescriptive. PrivacyGuard identifies potential candidate fields using deterministic metadata signals (field type, configured keywords, and optional native Salesforce data classification), records the evidence, and places the field in an administrator review queue. It does not assign confidence levels, risk scores, or recommended masking strategies.

Administrators can **Accept** a candidate into masking scope, **Remove/Reject** it from the proposed scope, or **Add Field Manually** when business knowledge identifies additional sensitive data. Accepted candidates generate **inactive** Masking Configuration metadata with no strategy selected. Strategy selection and activation are separate administrator-controlled actions, preserving the governance boundary: **Discover → Review → Scope → Configure → Activate → Execute**.
