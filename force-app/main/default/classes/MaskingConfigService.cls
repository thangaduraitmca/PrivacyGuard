/**
 * @class         MaskingConfigService
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
 * Reads Masking_Configuration__mdt and Masking_Job_Sequence__mdt and hands back
 * simple wrapper objects the rest of the framework works with.
 */
public with sharing class MaskingConfigService {

    public class FieldConfig {
        public String objectApiName;
        public String fieldApiName;
        public String fieldType;
        public String strategyClass;
        public String maskingPattern;
        public Integer executionGroup;
    }

    public class JobConfig {
        public String jobName;
        public String objectApiName;
        public String executionMode; // Serial or Parallel
        public Integer sequenceOrder;
        public Integer batchSize;
        public String runMode;              // Full, Delta, or Once (FIELD_MASKING jobs only)
        public String deltaTrackingField;   // DateTime field for Delta, Checkbox field for Once (FIELD_MASKING jobs only)
        public String jobType;              // FIELD_MASKING (default), ATTACHMENT_DELETION, or FILE_DELETION
    }

    private static Boolean canMaskField(String objectName, String fieldName) {
        Schema.SObjectType objectToken = Schema.getGlobalDescribe().get(objectName);
        if (objectToken == null) return false;
        Schema.SObjectField fieldToken = objectToken.getDescribe().fields.getMap().get(fieldName);
        if (fieldToken == null) return false;
        Schema.DescribeFieldResult d = fieldToken.getDescribe();
        String name = d.getName().toLowerCase();
        if (name == 'data_masking_complete__c' || name.endsWith('__data_masking_complete__c')) return false;
        return d.isUpdateable() && !d.isCalculated() && !d.isAutoNumber()
            && d.getType() != Schema.DisplayType.PICKLIST
            && d.getType() != Schema.DisplayType.MULTIPICKLIST;
    }

    public static Map<String, List<FieldConfig>> getActiveFieldConfigsByObject() {
        Map<String, List<FieldConfig>> result = new Map<String, List<FieldConfig>>();
        for (Masking_Configuration__mdt cfg : [
            SELECT Object_API_Name__c, Field_API_Name__c, Field_Type__c,
                   Masking_Strategy_Class__c, Masking_Pattern__c, Execution_Group__c
            FROM Masking_Configuration__mdt
            WHERE Is_Active__c = true
        ]) {
            if (!canMaskField(cfg.Object_API_Name__c, cfg.Field_API_Name__c)) continue;
            FieldConfig fc = new FieldConfig();
            fc.objectApiName = cfg.Object_API_Name__c;
            fc.fieldApiName = cfg.Field_API_Name__c;
            fc.fieldType = cfg.Field_Type__c;
            fc.strategyClass = cfg.Masking_Strategy_Class__c;
            fc.maskingPattern = cfg.Masking_Pattern__c;
            fc.executionGroup = cfg.Execution_Group__c != null ? Integer.valueOf(cfg.Execution_Group__c) : 0;

            if (!result.containsKey(fc.objectApiName)) {
                result.put(fc.objectApiName, new List<FieldConfig>());
            }
            result.get(fc.objectApiName).add(fc);
        }
        // Subscriber-managed runtime configuration overrides/adds to packaged CMDT by Object+Field.
        for (Masking_Field_Config__c cfg : [
            SELECT Object_API_Name__c, Field_API_Name__c, Masking_Strategy__c, Masking_Pattern__c, Execution_Group__c
            FROM Masking_Field_Config__c WHERE Is_Active__c = true
        ]) {
            if (!canMaskField(cfg.Object_API_Name__c, cfg.Field_API_Name__c)) continue;
            FieldConfig fc = new FieldConfig();
            fc.objectApiName = cfg.Object_API_Name__c; fc.fieldApiName = cfg.Field_API_Name__c;
            fc.fieldType = cfg.Masking_Strategy__c; fc.strategyClass = null; fc.maskingPattern = cfg.Masking_Pattern__c;
            fc.executionGroup = cfg.Execution_Group__c == null ? 0 : Integer.valueOf(cfg.Execution_Group__c);
            if (!result.containsKey(fc.objectApiName)) result.put(fc.objectApiName, new List<FieldConfig>());
            List<FieldConfig> listForObject = result.get(fc.objectApiName);
            for (Integer i=listForObject.size()-1;i>=0;i--) if (listForObject[i].fieldApiName == fc.fieldApiName) listForObject.remove(i);
            listForObject.add(fc);
        }
        return result;
    }

    public static List<JobConfig> getActiveJobSequence() {
        List<JobConfig> jobs = new List<JobConfig>();
        for (Masking_Job_Sequence__mdt job : [
            SELECT Job_Name__c, Object_API_Name__c, Execution_Mode__c, Sequence_Order__c, Batch_Size__c,
                   Run_Mode__c, Delta_Tracking_Field__c, Job_Type__c
            FROM Masking_Job_Sequence__mdt
            WHERE Is_Active__c = true
            ORDER BY Sequence_Order__c ASC NULLS LAST
        ]) {
            JobConfig jc = new JobConfig();
            jc.jobName = job.Job_Name__c;
            jc.objectApiName = job.Object_API_Name__c;
            jc.executionMode = job.Execution_Mode__c;
            jc.sequenceOrder = job.Sequence_Order__c != null ? Integer.valueOf(job.Sequence_Order__c) : 0;
            jc.batchSize = job.Batch_Size__c != null ? Integer.valueOf(job.Batch_Size__c) : 200;
            jc.runMode = String.isBlank(job.Run_Mode__c) ? 'Full' : job.Run_Mode__c;
            jc.deltaTrackingField = job.Delta_Tracking_Field__c;
            jc.jobType = String.isBlank(job.Job_Type__c) ? 'FIELD_MASKING' : job.Job_Type__c;
            jobs.add(jc);
        }
        return jobs;
    }
}
