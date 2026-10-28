/**
 * Patch 5A: log-driven recovery. The QueryLocator pages over failed log rows
 * instead of materialising all failed record IDs in one Apex transaction.
 * Ordered log rows plus lastRecordId deduplicate failures across batch chunks.
 */
public without sharing class MaskingFailedRecordRecoveryBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    private String jobName;
    private String objectApiName;
    private List<MaskingConfigService.FieldConfig> fieldConfigs;
    private String runMode;
    private String trackingField;
    private Id runtimeRunId;
    private Id runtimeRunObjectId;
    private Id parentRunId;
    private String lastRecordId;
    private Integer processed = 0;
    private Integer failed = 0;

    public MaskingFailedRecordRecoveryBatch(String jobName, String objectApiName,
        List<MaskingConfigService.FieldConfig> fieldConfigs, String runMode,
        String trackingField, Id runtimeRunId, Id runtimeRunObjectId, Id parentRunId) {
        this.jobName = jobName;
        this.objectApiName = objectApiName;
        this.fieldConfigs = fieldConfigs;
        this.runMode = runMode;
        this.trackingField = trackingField;
        this.runtimeRunId = runtimeRunId;
        this.runtimeRunObjectId = runtimeRunObjectId;
        this.parentRunId = parentRunId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requireRunPermission();
        if (parentRunId == null || runtimeRunId == null || runtimeRunObjectId == null) {
            throw new MaskingRecoveryException('Recovery requires parent and current run IDs.');
        }
        Schema.DescribeSObjectResult objDescribe = SchemaValidationUtil.requireValidObject(objectApiName);
        if (fieldConfigs == null || fieldConfigs.isEmpty()) {
            throw new MaskingRecoveryException('No active masking fields configured.');
        }
        for (MaskingConfigService.FieldConfig fc : fieldConfigs) {
            SchemaValidationUtil.validateMaskingTarget(objDescribe, fc);
        }
        if (runMode != 'Delta') trackingField = MaskingCompletionService.requireCheckbox(objectApiName, trackingField);
        if (runMode == 'Delta' || runMode == 'Once') {
            SchemaValidationUtil.requireValidField(objDescribe, trackingField);
            Schema.DescribeFieldResult trackingDescribe = objDescribe.fields.getMap().get(trackingField.toLowerCase()).getDescribe();
            Schema.DisplayType requiredType = runMode == 'Delta' ? Schema.DisplayType.DATETIME : Schema.DisplayType.BOOLEAN;
            if (trackingDescribe.getType() != requiredType) {
                throw new MaskingRecoveryException('Invalid tracking field type for ' + runMode + '.');
            }
        }
        String parentRunKey = String.valueOf(parentRunId);
        return Database.getQueryLocator([
            SELECT Id, Record_Id__c FROM Masking_Log__c
            WHERE Run_Id__c = :parentRunKey AND Object_API_Name__c = :objectApiName
                AND Status__c = 'Failed' AND Record_Id__c != null
            ORDER BY Record_Id__c ASC, Id ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> logs) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requireRunPermission();
        Set<Id> ids = new Set<Id>();
        for (SObject entry : logs) {
            String recordId = (String) entry.get('Record_Id__c');
            if (String.isBlank(recordId) || recordId == lastRecordId) continue;
            lastRecordId = recordId;
            try {
                Id parsed = (Id) recordId;
                if (parsed.getSObjectType().getDescribe().getName() == objectApiName) ids.add(parsed);
            } catch (Exception ignored) {
                // Malformed or stale log references are ignored; no broad query fallback.
            }
        }
        if (ids.isEmpty()) return;
        Schema.DescribeSObjectResult objectDescribe = SchemaValidationUtil.requireValidObject(objectApiName);
        Set<String> fields = new Set<String>{ 'Id' };
        for (MaskingConfigService.FieldConfig fc : fieldConfigs) fields.add(fc.fieldApiName);
        if (runMode != 'Delta') trackingField = MaskingCompletionService.requireCheckbox(objectApiName, trackingField);
        if (String.isNotBlank(trackingField)) fields.add(trackingField);
        String soql = 'SELECT ' + String.join(new List<String>(fields), ',') +
            ' FROM ' + objectDescribe.getName() + ' WHERE Id IN :ids';
        List<SObject> records = Database.query(soql);
        // Use the exact existing field masking, DML and logging logic, but no
        // eligibility predicate: a retry is determined exclusively by failed logs.
        MaskingBatch processor = new MaskingBatch(jobName, objectApiName, fieldConfigs,
            runMode, trackingField, runtimeRunId, null, null, false);
        processor.execute(null, records);
        processed += processor.getProcessedCount();
        failed += processor.getFailedCount();
    }

    public void finish(Database.BatchableContext bc) {
        RuntimeMaskingJobOrchestrator.completeObject(runtimeRunObjectId, processed, failed,
            failed > 0 ? failed + ' failed record(s) in recovery.' : null);
    }

    public class MaskingRecoveryException extends Exception {}
}
