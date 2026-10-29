/**
 * @class         PIIFieldScannerBatch
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
 * 1.2.3       2026-09-16   PG-PII-002         PrivacyGuard Engineering   Enabled Batch Apex callouts for optional Salesforce compliance classification lookup.
 * 1.2.4       2026-09-16   PG-PII-003         PrivacyGuard Engineering   Removed compliance callouts from batch discovery to eliminate callout-limit dependency.
 */
/**
 * Org-wide PII scan. Iterates a list of object API names (Database.Batchable<String>
 * so each object gets its own transaction — safe for orgs with hundreds of objects/
 * thousands of fields where a single synchronous describe pass would risk limits).
 *
 * Usage - scan everything queryable and updateable in the org:
 *   Database.executeBatch(new PIIFieldScannerBatch(PIIFieldScannerBatch.getAllScannableObjects()), 1);
 *
 * Usage - scan a specific list:
 *   Database.executeBatch(new PIIFieldScannerBatch(new List<String>{'Contact','Lead','Account'}), 5);
 *
 * IMPORTANT: PII discovery is deterministic and performs no HTTP/Tooling API callouts.
 * Each object is scanned using Schema Describe, PrivacyGuard PII keywords and native FieldDefinition classification metadata.
 */
public with sharing class PIIFieldScannerBatch implements Database.Batchable<String>, Database.Stateful {

    // Deterministic test inventory; inaccessible to production callers.
    @TestVisible private static List<String> scannableObjectsForTests;
    private List<String> objectApiNames;
    private String scanBatchId;

    public PIIFieldScannerBatch(List<String> objectApiNames) {
        this.objectApiNames = objectApiNames;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        this.scanBatchId = bc.getJobId();
        return objectApiNames;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        List<PII_Scan_Result__c> allFindings = new List<PII_Scan_Result__c>();
        for (String objectApiName : scope) {
            try {
                allFindings.addAll(PIIFieldScannerService.scanObject(objectApiName, bc.getJobId()));
            } catch (Exception e) {
                MaskingLogger.logInfo('PIIFieldScannerBatch',
                    'Skipped object ' + objectApiName + ' during PII scan: ' + e.getMessage());
            }
        }
        if (!allFindings.isEmpty()) {
            insert allFindings;
        }
    }

    public void finish(Database.BatchableContext bc) {
        MaskingLogger.logInfo('PIIFieldScannerBatch',
            'PII scan complete for ' + objectApiNames.size() + ' object(s). Review results in PII_Scan_Result__c.');
    }

    /**
     * Convenience helper: every object that's queryable, updateable (so masking can
     * actually write to it), and not a Salesforce-managed system object.
     */
    public static List<String> getAllScannableObjects() {
        if (Test.isRunningTest() && scannableObjectsForTests != null) {
            return new List<String>(scannableObjectsForTests);
        }
        List<String> result = new List<String>();
        for (Schema.SObjectType sobjType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult d = sobjType.getDescribe();
            if (d.isQueryable() && d.isUpdateable() && !d.isCustomSetting()) {
                result.add(d.getName());
            }
        }
        return result;
    }
}
