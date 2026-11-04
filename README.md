# PrivacyGuard — Salesforce Sandbox Data Masking

PrivacyGuard helps Salesforce administrators discover potentially sensitive fields, define masking policies, and prepare sandbox data for development, testing, and training. It combines a Lightning administration workspace with configurable masking strategies, asynchronous processing, execution history, and controlled Apex Trigger management.

The framework runs within Salesforce. Masking replaces selected field values in place; it does not create a separate anonymised copy or provide a reversal mechanism. Administrators remain responsible for reviewing scope, validating results, and controlling access to the sandbox.

## Documentation

Use the [documentation index](docs/README.md) for the complete guide collection.

| Document | Audience and purpose |
| --- | --- |
| [Installation and administrator guide](docs/guides/PrivacyGuard-Installation-and-Administrator-Guide.md) | Installation, permissions, operations and recovery |
| [End-user guide](docs/guides/PrivacyGuard-End-User-Guide.md) | Discovery, configuration, execution and monitoring |
| [OAuth post-install guide](docs/integrations/PrivacyGuard-OAuth-Post-Install-Guide.md) | Customer credential setup and per-user authorization |
| [API callout documentation](docs/integrations/PrivacyGuard-API-Callout-Documentation.md) | Endpoints, payloads, trust boundaries and error handling |
| [Solution architecture and data flows](docs/architecture/PrivacyGuard-Solution-Architecture-and-Data-Flows.md) | Technical design and data movement |
| [Business capability map](docs/architecture/PrivacyGuard-Business-Capability-Map.pdf) | Capability overview |
| [Consolidated security findings and justifications](docs/security/PrivacyGuard-Consolidated-Security-Findings-and-Justifications.md) | Finding-by-finding assessment, evidence and pending checks |

These relative links use the structured `docs/` layout supplied with the documentation bundle. Preserve that layout when adding documents to this repository.

## Purpose and scope

PrivacyGuard supports a governed lifecycle: discover candidate fields, review findings, configure masking, prepare the environment, execute jobs, and verify results. Discovery decisions and masking activation are separate so that accepting a field as sensitive does not immediately authorise data changes.

| Capability | Purpose |
| --- | --- |
| Dashboard | Show configuration coverage, outstanding review items, and masking run outcomes. |
| PII discovery | Identify candidate fields using field characteristics, keywords, and available Salesforce classification metadata. |
| Masking configuration | Maintain object and field policies, replacement strategies, patterns, and activation state. |
| Job management | Group configured objects into jobs with execution order, batch size, and scheduling. |
| Execution and recovery | Process data asynchronously, record outcomes, and retry records identified by failed-run logs. |
| Automation management | Discover Apex Triggers and submit controlled deactivation or restoration requests for eligible triggers. |
| Attachment & File Manager | Delete Attachments or Salesforce Files associated with selected object scopes in a sandbox. |

Data seeding, Flow and Validation Rule metadata management, and production masking are outside the supported operating scope.

## Architecture overview

PrivacyGuard uses a layered architecture. The administration workspace submits requests to application services; those services validate permissions, environment, configuration, and field compatibility before starting asynchronous work. Results are stored in Salesforce for subsequent reporting and operational review.

| Layer | Responsibility | Main elements |
| --- | --- | --- |
| Administration experience | Present discovery, configuration, job controls, run details, and automation status. | Lightning Web Components and Apex controllers. |
| Governance and validation | Check operation permissions, sandbox eligibility, object and field definitions, strategy compatibility, and completion tracking. | Central security, environment safety, schema validation, and completion services. |
| Configuration | Store administrator-owned masking policies, job definitions, object selections, and keyword overrides. | Salesforce custom objects, supported by packaged metadata defaults. |
| Orchestration | Create run records, launch object processing, reconcile failures, and manage cancellation and completion. | Runtime job orchestrator and scheduling services. |
| Processing | Apply configured replacements and persist results in bounded transactions. | Batch Apex, masking strategy implementations, and recovery batches. |
| Trigger deployment | Submit and monitor asynchronous trigger state changes independently of masking batches. | Queueable Apex, Salesforce Tooling API, and persistent deployment tracking. |
| Operational evidence | Record run status, object outcomes, record failures, and trigger restoration information. | Run history, object-level history, masking logs, and automation tracking records. |

### Configuration model

The current administration experience uses runtime configuration records as the source of truth for field policies and administrator-created jobs. Custom Metadata also exists for packaged defaults and legacy execution paths; it should not be described as the sole configuration mechanism.

| Information | Role |
| --- | --- |
| Field configurations | Object and field selection, masking strategy, replacement pattern, and active state. |
| Job definitions | Job name, run mode, execution mode, batch size, and selected objects. |
| Job object selections | Object sequence and completion checkbox selection. |
| Scan findings | Candidate fields, detection reasons, and review decisions. |
| Keyword configuration | Subscriber keywords and exclusions of packaged defaults. |
| Run and object history | Parent run, object statuses, processing counts, timestamps, and summaries. |
| Masking logs | Failure details and administrator guidance used for investigation and recovery. |
| Automation tracking | Original trigger state, deployment target, Salesforce request identifier, progress, and verification messages. |

### Processing model

A job selects active object configurations and validates them before processing. Serial execution advances through objects in sequence; parallel execution submits object batches independently, subject to Salesforce asynchronous processing limits.

Batch Apex divides work into separate transactions. Strategy instances and field descriptions are reused within a processing transaction to reduce repeated work. Failed-record recovery reads the parent run's failure logs rather than treating a retry as permission to reprocess the entire object.

A completed batch transaction remains committed if a later transaction fails or the job is cancelled. Cancellation stops further work where possible; it does not roll back records already masked.

## Discovery and review

Discovery produces candidates for administrator review, not a complete or certified inventory of personal information. Results depend on field metadata, configured keywords, permissions, and the available classification information.

The discovery workflow supports reviewing findings and adding accepted, eligible fields to masking configuration as inactive entries. Administrators then select a strategy and activate each policy. Existing configurations are not automatically overwritten when accepted findings are imported.

Keyword administration supports organisation-specific terms, duplicate checks, and exclusions of packaged defaults. Configured fields are excluded from candidate discovery where recognised by the scanner.

Discovery does not overwrite business-record field values, but it does store findings in Salesforce. Access to those findings should be governed accordingly.

## Masking modes and completion tracking

| Mode | Record selection | Completion behaviour |
| --- | --- | --- |
| Full | Process records in the selected object scope, including records previously marked complete. | Mark successful records complete. |
| Unmasked records only | Process records whose configured completion checkbox is not checked. | Check the flag after successful masking; subsequent runs skip flagged records. |
| Recovery Rerun | Retry records identified by failure logs from an eligible previous run. | Apply the normal masking and completion logic to the recovery scope. |

Each participating object needs an editable completion checkbox, including jobs in Full mode. The framework resolves the applicable packaged or subscriber `Data_Masking_Complete__c` field, or the configured checkbox. Ensure the correct field is available and accessible on every selected object, and do not configure it as a masking target.

A completion checkbox records that masking succeeded. It does not detect whether an integration or user later replaces masked values with sensitive data. Use Full mode when previously completed records need masking again.

Legacy timestamp-based Delta jobs are no longer supported in the current runtime workflow. Edit older jobs to use Full or Unmasked records only before execution.

## Masking strategies

Strategy availability depends on the Salesforce field type and validation rules. The framework validates field compatibility and supplied replacement values before execution.

| Strategy | Intended use |
| --- | --- |
| Email randomisation | Generate replacement email values while preserving the domain. |
| Invalid-domain email | Generate replacement email addresses using an invalid domain. |
| Phone randomisation | Replace phone values with generated alternatives. |
| Name randomisation | Replace names with generated values. |
| Random string | Generate replacement text. |
| Static value | Apply an administrator-defined replacement compatible with the target field. |
| Replacement list | Select replacements from an administrator-defined list. |
| Numeric range | Generate numeric replacements within a configured range and the target field's constraints. |
| Null | Clear eligible fields where a null value is permitted. |
| Regular expression | Apply a validated replacement rule to supported text fields. |

Formula fields and picklist fields are not supported masking targets. Read-only fields, required-field constraints, relationship fields, and incompatible strategies are subject to schema validation. Salesforce validation rules, duplicate rules, and other active automation can still reject an otherwise valid replacement.

Random replacements are not a guarantee of uniqueness or consistent values across related records. Validate business and relationship requirements before selecting a strategy.

## Preview and file handling

Masking preview is read-only and supports built-in strategies. It reads at most five records and up to 100 configured masking fields; displayed values are truncated to 500 characters. Preview can expose original field values to the authorized operator, so restrict access accordingly. It does not test DML success, validation rules or downstream automation.

Attachment & File Manager supports inventory and confirmed deletion. Deleting a Salesforce `ContentDocument` affects all its versions and record links; it is not simply unlinking one selected record. Legacy Attachment deletion affects the selected attachment. Review inventory and scope before confirming deletion.

The object-related scan/purge path currently accepts up to 10 objects per request. This limit is distinct from the collected-file inventory workflow and remains a current implementation constraint.

## Apex Trigger management

Supported automation metadata management is limited to Apex Triggers. Namespaced triggers are read-only and cannot be changed through PrivacyGuard, including triggers carrying the PrivacyGuard namespace.

Eligible trigger changes follow a separate lifecycle: capture original state, submit a deployment request, monitor Salesforce processing, verify the resulting trigger state, and retain tracking information for restoration.

Queued or in-progress requests are not reported as successful deactivations. A request that requires further checking retains its Salesforce request identifier so monitoring can resume. Administrators should verify the result before masking or proceeding with restoration.

Trigger deactivation and restoration are explicit administrative operations. Creating or running a masking job is not evidence that all Salesforce automation has been disabled. Legacy bypass settings affect only automation that has been designed to honour those flags; they do not universally suspend automation.

Flow and Validation Rule metadata changes are not part of the supported automation management workspace. Legacy implementation elements may remain in the repository and must not be treated as supported product capabilities.

## OAuth and same-sandbox API access

Trigger metadata operations use the customer-configured Named Credential `PrivacyGuard_Tooling` and Salesforce Tooling API v66.0. Apex does not embed OAuth client secrets or construct session-based bearer headers. Salesforce credential infrastructure supplies authorization.

After managed installation, the administrator must configure the customer External Client App and installed provider, create or configure the Named Credential, connect it to the installed External Credential, allow namespace `privacyguard`, assign principal access and complete per-user OAuth authorization. Scopes are `api refresh_token`; platform permissions and the separate metadata-operation custom permission also apply. OAuth tokens are not distributed with the package.

Before Tooling operations, the client verifies that the remote organization ID matches the executing organization and that it is a sandbox. The Named Credential URL must use the exact sandbox My Domain API hostname, not the Lightning UI hostname. Each request has a 20-second timeout. Trigger deployments persist their request ID, poll status and verify the actual final trigger state; an interrupted status check can leave the outcome unknown and requires reconciliation.

Follow the [post-install guide](docs/integrations/PrivacyGuard-OAuth-Post-Install-Guide.md) and [API register](docs/integrations/PrivacyGuard-API-Callout-Documentation.md). A successful package install alone does not establish that OAuth or trigger deployment works.

## Cooperative bypass restoration

Masking runs persist the prior four bypass flags and an ownership marker before applying cooperative bypass. Runtime runs use their run ID as owner. Completion, failure reconciliation and cancellation attempt to restore the saved values; changes to false made by an administrator during execution are preserved. Wrong-owner restoration and invalid snapshots are rejected rather than blindly clearing flags.

The flags affect only subscriber automation that explicitly consults them. They do not replace explicit trigger restoration. An administrator deliberately re-saving true cannot be distinguished from the value applied by PrivacyGuard. The legacy no-argument orchestrator uses a fixed owner and does not provide a per-generation completion token. Public-setting access and stale/duplicate legacy completion require separate assessment. Abandoned runs depend on reconciliation; no autonomous recovery watchdog is claimed.

## Security and environment safeguards

- Masking and Attachment/File deletion are restricted to sandbox organisations. Production overrides are not supported by the current environment safety service.
- Trigger state changes are also restricted to sandboxes.
- Privileged operations use dedicated permission checks for masking, PII administration, file deletion, and metadata deactivation.
- Object and field access checks are applied by relevant application services. Some execution services intentionally operate without sharing to process their authorised scope; permission assignment and sandbox access remain essential controls.
- Sensitive field values and failure details may be present in the sandbox and operational logs. Limit access and define retention practices appropriate to the organisation.
- An unknown or unverifiable environment must not be treated as authorisation to perform destructive operations.

Masking, deletion, and trigger deployments have different authorisation and execution paths. Review each permission set before assigning it; installation alone does not grant an operator every capability.

## Recommended operating lifecycle

1. **Prepare:** Confirm the target sandbox, approved operators, backup or refresh arrangements, and selected object scope.
2. **Discover:** Scan candidate objects and review potentially sensitive fields.
3. **Configure:** Select field strategies, validate replacement values, and activate the approved policies.
4. **Define the job:** Choose Full or Unmasked records only, object order, execution mode, and an appropriate batch size.
5. **Check automation:** Assess active automation; explicitly deactivate eligible triggers when required and verify deployment success.
6. **Preview and run:** Review available masking examples and safety acknowledgements, then submit the job manually or through its schedule.
7. **Monitor:** Review parent and object statuses, processed and failed counts, and diagnostic messages.
8. **Recover:** Correct the cause of failures and use Recovery Rerun for the failed-record scope where appropriate.
9. **Restore and verify:** Restore deliberately deactivated triggers, confirm their resulting state, and inspect representative records and downstream behaviour.

Attachment and File deletion should be reviewed as a separate destructive operation. A Salesforce File may be shared with multiple records; assess the impact of deleting the document rather than assuming only one association will be removed.

## Scheduling, monitoring, and recovery

Jobs support manual execution and daily, weekly, or monthly schedules. Scheduled times follow the scheduling user's Salesforce timezone. A scheduled job remains subject to the same execution eligibility and configuration checks as a manual run.

Run history separates overall job status from object-level outcomes. Partial failures can leave some objects or records successfully processed while others require attention. Serial jobs stop advancing after a failed or partial step; independently submitted parallel work may continue before the overall run is finalised.

Use run details and Salesforce asynchronous job status together when investigating failures. Retain the relevant logs until recovery and verification are complete; failed-record recovery depends on that evidence.

Dashboard coverage measures accepted PII fields with active configuration. It is not Apex test coverage, proof that every sensitive value was masked, or a compliance certification.

## Packaging and environment model

PrivacyGuard is maintained as a Salesforce second-generation managed package using the privacyguard namespace. The namespace development organisation, Dev Hub/package ownership organisation, source-testing sandbox, and package-installation sandbox serve different purposes.

Use a sandbox without a namespace for rapid source deployment and functional testing. Validate the managed package separately in a subscriber-style sandbox to confirm namespace behaviour, permissions, installation, and packaged defaults. A successful source deployment does not by itself prove that a newly built package installs and behaves correctly.

GitHub is the version-controlled source of record. Keep source, metadata companions, tests, and documentation together, and associate package builds with the reviewed source revision. Package IDs and installation links belong in version-specific release information rather than this framework overview.

## Source deployment versus managed installation

The OAuth principal reference differs between the unmanaged source-testing environment and the namespaced managed build. A source deployment to an unmanaged sandbox may require the unprefixed credential-principal reference; the package-ready source uses the verified namespaced reference. Keep environment transformations separate from release source and review the diff before committing. Do not distribute manual XML edits as a customer installation step.

A source deployment updates the target sandbox; it does not update an already-created managed version. Build a new version after final code changes and validate a clean subscriber installation separately. Production installation does not enable production masking or production trigger changes.

## Validation and release readiness

Before promoting a package version, verify full-source deployment with local Apex tests, applicable coverage requirements, functional smoke tests, and managed-package installation testing. Include permission boundaries, production blocking, completion tracking, failure recovery, trigger state verification, and representative data volumes in the validation scope.

As of the 4 November 2026 documentation baseline, the project owner reports successful deployment to PGTEST. The supplied `PrivacyGuardInternalAuthorizationTest` log shows two negative-authorization scenarios completing without assertion failures or fatal errors. The tests exercise seven bypass/tracker entry paths per scenario with real permission checks enabled. This evidence does not establish that the entire regression suite, direct-setting access checks or installed-package OAuth cases passed.

### Security-review status

The latest reviewed Code Analyzer CSV contains **23 findings: 15 high and eight moderate**, comprising 12 CRUD warnings, three dynamic-SOQL warnings and eight potential-auth-token warnings. Query hardening did not remove the three SOQL warnings from the subsequent scan.

The [consolidated register](docs/security/PrivacyGuard-Consolidated-Security-Findings-and-Justifications.md) records proposed false positives, intentional privileged operations and outstanding validation. Documentation is not a blanket waiver, a clean scan or Salesforce approval. Direct access to public bypass state, keyword CRUD/FLS boundaries, legacy completion behavior and final package/source matching remain relevant checks. A Checkmarx report has not been supplied for this documentation baseline.

Before release or security-review submission:

1. Match source commit, package version, reports and tests to the exact candidate release.
2. Run local Apex tests and retain formal results, including authorization, malicious-input, CRUD/FLS and environment-boundary cases.
3. Review Code Analyzer engine/processing errors, selected rules, configuration and exclusions, and retain HTML/CSV reports with scan logs.
4. Assess remaining implementation concerns; fix genuine defects and supply finding-specific evidence for proposed false positives.
5. Complete Checkmarx and review its findings independently.
6. Validate managed installation, permissions, OAuth, same-org verification and trigger restoration in the subscriber test environment.
7. Confirm promotion status and the current Salesforce submission requirements. Package release and Salesforce security-review approval are separate milestones.

Keep credentials, tokens, customer data and unredacted debug logs out of Git. Store reviewed documentation under `docs/`; add only sanitized evidence through the project's approved process.

## Limitations and operational responsibilities

PrivacyGuard does not provide reversible masking, data restoration, complete PII detection, automatic regulatory compliance, or a guarantee of referential consistency across independently masked fields. Data seeding is outside the current scope.

Salesforce platform limits, data volumes, record locking, sharing and permissions, validation rules, and active automation can affect execution. Choose batch sizes and object sequencing based on representative sandbox testing, and verify results before granting wider access to the prepared environment.
