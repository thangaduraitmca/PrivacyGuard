/**
 * @class         MaskingRunInvocable
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
 * Exposes MaskingFrameworkService.executeMaskingRun() as a Flow/Process Builder
 * Action, so admins can wire a Screen Flow button, a scheduled Flow, or an approval
 * process step to trigger a masking run declaratively - no Apex required on their
 * end. Build a Screen Flow with a single "Action" element selecting "Run Data
 * Masking Jobs", add a Confirm screen before it if you want a safety prompt, and
 * expose it via a Quick Action or a button on a Lightning App Page.
 *
 * Returns a result (rather than letting exceptions propagate as Flow faults) so a
 * Screen Flow can branch on success/failure and show a friendly message - including
 * the Sandbox-only safety block message, which is exactly the kind of thing a Flow
 * user should see plainly rather than as a raw fault.
 */
public with sharing class MaskingRunInvocable {

    public class Result {
        @InvocableVariable(label='Success' description='True if the masking run started without being blocked.')
        public Boolean success;

        @InvocableVariable(label='Message' description='Human-readable outcome, including the Sandbox-only safety message if blocked.')
        public String message;
    }

    @InvocableMethod(
        label='Run Data Masking Jobs'
        description='Runs every active Masking_Job_Sequence__mdt job. Blocked automatically outside of Sandboxes unless explicitly overridden.'
        category='PrivacyGuard'
    )
    public static List<Result> runMaskingJobs() {
        Result r = new Result();
        try {
            MaskingFrameworkService.executeMaskingRun();
            r.success = true;
            r.message = 'Masking run started successfully. It runs asynchronously - check the Masking Logs tab for progress.';
        } catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) {
            r.success = false;
            r.message = e.getMessage();
        } catch (Exception e) {
            r.success = false;
            r.message = 'Unexpected error starting the masking run: ' + e.getMessage();
        }
        return new List<Result>{ r };
    }
}
