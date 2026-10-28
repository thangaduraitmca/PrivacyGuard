/**
 * @class         MaskingBatch
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
 * 1.1.0       2026-09-16   PG-SEC-002         PrivacyGuard Engineering   Fail-closed record masking; partial failures are never stamped complete.
 */
/**
 * Masks all records of a single object for a single job entry. Per-record and
 * per-field failures are logged and skipped rather than failing the whole batch
 * (Database.update with allOrNone=false).
 *
 * SECURITY NOTES:
 * - Declared `without sharing`, deliberately. A masking job's entire purpose is to
 *   scrub PII from every record of the target object - if this ran `with sharing`,
 *   the org's sharing rules could silently hide records from the batch's query
 *   (e.g. private records the scheduled user's role doesn't grant visibility to),
 *   leaving real PII unmasked. Access to trigger a run at all is controlled
 *   upstream (Permission Set assignment + the Sandbox-only safety gate in
 *   EnvironmentSafetyService), which is the correct control point for a tool whose
 *   job is intentionally to bypass normal per-record restrictions.
 * - Object and field API names are validated against the org's actual schema via
 *   SchemaValidationUtil before being concatenated into dynamic SOQL, closing the
 *   SOQL-injection surface that free-form object/field configuration would
 *   otherwise open up.
 * - This intentionally does NOT enforce field-level security on the masking writes
 *   (no WITH SECURITY_ENFORCED / stripInaccessible) - masking a field the running
 *   user isn't personally permitted to edit is the expected, desired behavior here.
 *
 * Supports three run modes:
 *   - Full: masks every record every run (original behavior).
 *   - Delta: masks only records created/modified since they were last masked, using a
 *     per-record DateTime high-water mark field (deltaTrackingField) rather than a
 *     global "last run time". This avoids the classic self-triggering problem where
 *     the masking update's own LastModifiedDate bump would otherwise make the record
 *     look "changed" to the very next run. The tracking field is stamped with the
 *     current timestamp in the same Database.update call that performs the masking,
 *     so a record only reappears in a future Delta run if something external touched
 *     it (LastModifiedDate later than the tracking field) after it was masked. This
 *     is the only mode that can detect a record being re-populated with real data
 *     after it was already masked.
 *   - Once: masks a record a single time, ever, using a Checkbox field
 *     (deltaTrackingField) set to true after masking and never re-checked against
 *     LastModifiedDate. Simpler than Delta, but structurally cannot detect drift - if
 *     something re-populates real data into an already-masked record, Once mode will
 *     never re-select it, since a boolean carries no information about when it was
 *     set relative to when the record last changed. Use this only where records are
 *     genuinely never expected to receive real data again after their first masking
 *     (e.g. a one-time historical backfill, or closed/archived records).
 */
public without sharing class MaskingBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final String MODE_FULL = 'Full';
    private static final String MODE_DELTA = 'Delta';
    private static final String MODE_ONCE = 'Once';

    private String jobName;
    private String objectApiName;
    private List<MaskingConfigService.FieldConfig> fieldConfigs;
    private String runMode;
    private String trackingField;
    private Integer recordsProcessed = 0;
    private Integer recordsFailed = 0;
    private Id runtimeRunId;
    private Id runtimeRunObjectId;
    private Set<Id> retryRecordIds = new Set<Id>();
    private Boolean recoveryRun = false;

    /** Full-mode constructor (backward compatible). */
    public MaskingBatch(String jobName, String objectApiName, List<MaskingConfigService.FieldConfig> fieldConfigs) {
        this(jobName, objectApiName, fieldConfigs, MODE_FULL, null);
    }

    public MaskingBatch(String jobName, String objectApiName, List<MaskingConfigService.FieldConfig> fieldConfigs,
                         String runMode, String trackingField) {
        this.jobName = jobName;
        this.objectApiName = objectApiName;
        this.fieldConfigs = fieldConfigs;
        this.runMode = String.isBlank(runMode) ? MODE_FULL : runMode;
        this.trackingField = trackingField;
    }

    public MaskingBatch(String jobName, String objectApiName, List<MaskingConfigService.FieldConfig> fieldConfigs, String runMode, String trackingField, Id runtimeRunId, Id runtimeRunObjectId, Set<Id> retryRecordIds, Boolean recoveryRun) {
        this(jobName, objectApiName, fieldConfigs, runMode, trackingField);
        this.runtimeRunId = runtimeRunId; this.runtimeRunObjectId = runtimeRunObjectId; this.retryRecordIds = retryRecordIds == null ? new Set<Id>() : retryRecordIds; this.recoveryRun = recoveryRun == true;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requireRunPermission();

        Schema.DescribeSObjectResult objDescribe = SchemaValidationUtil.requireValidObject(objectApiName);
        if (!runMode.equalsIgnoreCase(MODE_DELTA)) trackingField = MaskingCompletionService.requireCheckbox(objectApiName, trackingField);
        if (fieldConfigs == null || fieldConfigs.isEmpty()) {
            throw new SchemaValidationUtil.InvalidSchemaReferenceException(
                'Masking job has no configured fields for ' + objectApiName + '. Execution stopped.');
        }
        if (!runMode.equalsIgnoreCase(MODE_FULL) &&
            !runMode.equalsIgnoreCase(MODE_DELTA) &&
            !runMode.equalsIgnoreCase(MODE_ONCE)) {
            throw new SchemaValidationUtil.InvalidSchemaReferenceException(
                'Unsupported masking run mode: ' + runMode + '. Execution stopped.');
        }
        if (!runMode.equalsIgnoreCase(MODE_FULL) && String.isBlank(trackingField)) {
            throw new SchemaValidationUtil.InvalidSchemaReferenceException(
                runMode + ' masking requires a tracking field for ' + objectApiName +
                '. Execution stopped instead of silently running Full masking.');
        }

        // Query only fields used by masking. LastModifiedDate is referenced only
        // by the Delta WHERE predicate; SOQL does not require it in SELECT.
        Set<String> fieldNames = new Set<String>{ 'Id' };
        for (MaskingConfigService.FieldConfig fc : fieldConfigs) {
            SchemaValidationUtil.validateMaskingTarget(objDescribe, fc);
            if (String.isNotBlank(trackingField) &&
                fc.fieldApiName.equalsIgnoreCase(trackingField)) {
                throw new SchemaValidationUtil.InvalidSchemaReferenceException(
                    'Tracking field ' + trackingField + ' cannot also be a masking target.');
            }
            fieldNames.add(fc.fieldApiName);
        }

        Boolean isDelta = isMode(MODE_DELTA);
        Boolean isOnce = isMode(MODE_ONCE);
        if (!isDelta) fieldNames.add(trackingField);

        if (isDelta || isOnce) {
            Schema.DisplayType expectedType = isDelta ? Schema.DisplayType.DATETIME : Schema.DisplayType.BOOLEAN;
            SchemaValidationUtil.requireValidField(objDescribe, trackingField);
            validateTrackingFieldType(objDescribe, expectedType);
            fieldNames.add(trackingField);
        }

        String query = 'SELECT ' + String.join(new List<String>(fieldNames), ', ') + ' FROM ' + objectApiName;

        if (recoveryRun && !retryRecordIds.isEmpty()) {
            if (isDelta) query += ' WHERE Id IN :retryRecordIds';
            else query += ' WHERE Id IN :retryRecordIds';
        } else if (recoveryRun) {
            query += ' WHERE Id = null'; // nothing failed; recovery has no Full-mode work
        } else if (isDelta) {
            query += ' WHERE ' + trackingField + ' = null OR LastModifiedDate > ' + trackingField;
        } else if (isOnce) { query += ' WHERE (' + trackingField + ' = false OR ' + trackingField + ' = null)'; }

        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requireRunPermission();
        List<SObject> recordsToUpdate = new List<SObject>();
        Boolean isDelta = isMode(MODE_DELTA);
        Boolean isOnce = isMode(MODE_ONCE);
        if (!isDelta) trackingField = MaskingCompletionService.requireCheckbox(objectApiName, trackingField);
        DateTime stampTime = System.now();

        // Cache strategy instances and field descriptions for this execute transaction.
        // Each batch chunk gets fresh instances; nothing is retained in Stateful state.
        Map<Integer, IMaskingStrategy> strategiesByIndex = new Map<Integer, IMaskingStrategy>();
        if (scope.isEmpty()) return;
        Map<String, Schema.SObjectField> targetFields =
            scope[0].getSObjectType().getDescribe().fields.getMap();
        Map<String, Schema.DescribeFieldResult> staticFieldDescribes =
            new Map<String, Schema.DescribeFieldResult>();

        for (SObject record : scope) {
            Boolean recordHasError = false;
            for (Integer fieldIndex = 0; fieldIndex < fieldConfigs.size(); fieldIndex++) {
                MaskingConfigService.FieldConfig fc = fieldConfigs[fieldIndex];
                try {
                    if ('NULL'.equalsIgnoreCase(fc.fieldType)) SchemaValidationUtil.validateMaskingTarget(scope[0].getSObjectType().getDescribe(), fc);
                    Object originalValue = record.get(fc.fieldApiName);
                    IMaskingStrategy strategy = strategiesByIndex.get(fieldIndex);
                    if (strategy == null) {
                        strategy = MaskingStrategyFactory.getStrategy(fc.fieldType, fc.strategyClass);
                        strategiesByIndex.put(fieldIndex, strategy);
                    }
                    Object maskedValue = strategy.maskValue(originalValue, fc.maskingPattern, fc.fieldApiName);
                    if ('NUMBER_RANGE'.equalsIgnoreCase(fc.fieldType)) maskedValue = NumericRangeMaskStrategy.convertForField(targetFields.get(fc.fieldApiName).getDescribe(),maskedValue);
                    if ('STATIC'.equalsIgnoreCase(fc.fieldType) && (String.isBlank(fc.strategyClass) || fc.strategyClass.trim().equalsIgnoreCase('StaticValueMaskStrategy') || fc.strategyClass.trim().equalsIgnoreCase('privacyguard.StaticValueMaskStrategy'))) {
                        Schema.DescribeFieldResult targetDescribe = staticFieldDescribes.get(fc.fieldApiName);
                        if (targetDescribe == null) {
                            targetDescribe = targetFields.get(fc.fieldApiName).getDescribe();
                            staticFieldDescribes.put(fc.fieldApiName, targetDescribe);
                        }
                        maskedValue = SchemaValidationUtil.convertStaticMaskValue(targetDescribe, fc.maskingPattern);
                    }
                    record.put(fc.fieldApiName, maskedValue);
                } catch (Exception e) {
                    recordHasError = true;
                    if (runtimeRunId != null) MaskingLogger.queueDetailedLog(runtimeRunId, jobName, objectApiName, record.Id, fc.fieldApiName, 'Error masking field: ' + e.getMessage(), 'Failed');
                    else MaskingLogger.queueLog(jobName, objectApiName, record.Id, fc.fieldApiName, 'Error masking field: ' + e.getMessage(), 'Failed');
                }
            }

            // Fail closed at record level. If any configured field could not be masked,
            // do not persist any of the in-memory changes and do not stamp Delta/Once
            // completion. This prevents a partially masked record being marked complete.
            if (recordHasError) {
                recordsFailed++;
                continue;
            }

            // Stamp the tracking field only after every configured field was masked successfully.
            if (isDelta) {
                record.put(trackingField, stampTime);
            } else {
                record.put(trackingField, true);
            }

            recordsToUpdate.add(record);
        }

        if (recordsToUpdate.isEmpty()) {
            MaskingLogger.flush();
            return;
        }

        List<Database.SaveResult> results = Database.update(recordsToUpdate, false);
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            if (sr.isSuccess()) {
                recordsProcessed++;
            } else {
                recordsFailed++;
                List<String> errorDetails = new List<String>();
                for (Database.Error err : sr.getErrors()) {
                    String detail = String.valueOf(err.getStatusCode()) + ': ' + err.getMessage();
                    List<String> errorFields = err.getFields();
                    if (errorFields != null && !errorFields.isEmpty()) {
                        detail += ' | Fields: ' + String.join(errorFields, ', ');
                    }
                    errorDetails.add(detail);
                }
                String errors = String.join(errorDetails, ' || ');
                String technicalMessage = 'Record update failed. ' + errors;
                if (runtimeRunId != null) MaskingLogger.queueDetailedLog(runtimeRunId, jobName, objectApiName, recordsToUpdate[i].Id, null, technicalMessage, 'Failed');
                else MaskingLogger.queueLog(jobName, objectApiName, recordsToUpdate[i].Id, null, technicalMessage, 'Failed');
            }
        }
        MaskingLogger.flush();
    }

    // Expose per-chunk counters for the log-driven recovery batch.
    public Integer getProcessedCount() { return recordsProcessed; }
    public Integer getFailedCount() { return recordsFailed; }

    public void finish(Database.BatchableContext bc) {
        MaskingLogger.logInfo(jobName,
            'Masking job finished for ' + objectApiName + ' (' + runMode + ' mode). ' +
            'Processed: ' + recordsProcessed + ', Failed: ' + recordsFailed);
        if (runtimeRunObjectId != null) RuntimeMaskingJobOrchestrator.completeObject(runtimeRunObjectId, recordsProcessed, recordsFailed, recordsFailed > 0 ? recordsFailed + ' record(s) require attention. Open Run Details for admin guidance.' : null);
        else MaskingJobOrchestrator.handleJobCompletion(jobName);
    }

    private Boolean isMode(String mode) {
        return runMode.equalsIgnoreCase(mode) && String.isNotBlank(trackingField);
    }

    /** Catches a common misconfiguration early with a clear message, rather than a cryptic SOQL type-mismatch error later. */
    private void validateTrackingFieldType(Schema.DescribeSObjectResult objDescribe, Schema.DisplayType expectedType) {
        Schema.DisplayType actualType = objDescribe.fields.getMap().get(trackingField.toLowerCase()).getDescribe().getType();
        if (actualType != expectedType) {
            throw new SchemaValidationUtil.InvalidSchemaReferenceException(
                'Delta_Tracking_Field__c "' + trackingField + '" on ' + objDescribe.getName() +
                '" is a ' + actualType + ' field, but ' + runMode + ' mode requires ' + expectedType + '.');
        }
    }
}
