/**
 * @class         EnvironmentSafetyService
 * @description   Apex class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
 * @package       PrivacyGuard
 * @namespace     privacyguard
 * @apiVersion    66.0
 * @owner         PrivacyGuard Engineering
 * @changeControl Changes to this class must be peer reviewed, linked to an approved work item, validated by automated tests, and promoted through the managed-package release process.
 *
 * CHANGE HISTORY
 * Masking and deletion are restricted to sandbox orgs without an override.
 */
/**
 * Single source of truth for "is it safe to run masking/deletion jobs in this org?"
 *
 * Default answer: only in a Sandbox. This framework's entire purpose is protecting
 * production data by scrubbing copies of it - actually running its destructive
 * operations (field overwrite, Attachment/File delete) against Production would be
 * exactly backwards. This check is deliberately enforced in two places:
 *   1. MaskingJobOrchestrator.runJobs() - the funnel every declarative/scheduled/ad-hoc
 *      entry point goes through.
 *   2. Each Batchable's start() (MaskingBatch, FileAttachmentDeletionBatch) - so even
 *      code that constructs and executes a batch directly, bypassing the orchestrator,
 *      is still blocked.
 *
 * PII scanning (PIIFieldScannerBatch) is intentionally NOT gated by this check - it's
 * read-only and safe (even useful) to run in Production to build an inventory of what
 * needs masking policies.
 */
public with sharing class EnvironmentSafetyService {

    public class ProductionExecutionBlockedException extends Exception {}

    public static final String BLOCK_MESSAGE =
        'Masking/deletion jobs are blocked in this org because it is not a Sandbox. ' +
        'This framework is designed to run against Sandboxes only, to prevent accidental ' +
        'masking or deletion of real Production data. Production overrides are not supported.';

    /** Test-only escape hatch: lets unit tests force a specific answer regardless of the org they run in. */
    @TestVisible
    private static Boolean sandboxOverrideForTests;

    public static Boolean isExecutionAllowed() {
        return isSandbox();
    }

    public static Boolean isSandbox() {
        if (Test.isRunningTest() && sandboxOverrideForTests != null) {
            return sandboxOverrideForTests;
        }
        try {
            return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        } catch (Exception e) {
            // Fail safe: if org type can't be determined, treat it as Production and block.
            System.debug(LoggingLevel.ERROR,
                'EnvironmentSafetyService could not determine org type - treating as Production for safety: ' + e.getMessage());
            return false;
        }
    }

    public static void assertExecutionAllowed() {
        if (!isExecutionAllowed()) {
            throw new ProductionExecutionBlockedException(BLOCK_MESSAGE);
        }
    }

}
