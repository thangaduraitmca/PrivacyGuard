/**
 * @class         MaskingConfigServiceTest
 * @description   Apex test class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
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
 * Exercises MaskingConfigService against the sample Masking_Configuration__mdt /
 * Masking_Job_Sequence__mdt records shipped with this package (Custom Metadata
 * records can't be inserted via DML in tests, so this validates against the
 * deployed sample data rather than fixtures created here).
 */
@isTest
private with sharing class MaskingConfigServiceTest {

    @isTest
    static void testGetActiveFieldConfigsByObjectReturnsContactFields() {
        Test.startTest();
        Map<String, List<MaskingConfigService.FieldConfig>> configs = MaskingConfigService.getActiveFieldConfigsByObject();
        Test.stopTest();

        System.assert(configs.containsKey('Contact'), 'Sample package config should include Contact');
        List<MaskingConfigService.FieldConfig> contactFields = configs.get('Contact');
        System.assert(!contactFields.isEmpty());

        Set<String> fieldNames = new Set<String>();
        for (MaskingConfigService.FieldConfig fc : contactFields) {
            fieldNames.add(fc.fieldApiName);
            System.assertEquals('Contact', fc.objectApiName);
        }
        System.assert(fieldNames.contains('Email'));
        System.assert(fieldNames.contains('Phone'));
    }

    @isTest
    static void testGetActiveJobSequenceAppliesDefaultsForBlankFields() {
        Test.startTest();
        List<MaskingConfigService.JobConfig> jobs = MaskingConfigService.getActiveJobSequence();
        Test.stopTest();

        System.assert(!jobs.isEmpty(), 'Sample package job sequence should not be empty');

        MaskingConfigService.JobConfig contactJob;
        for (MaskingConfigService.JobConfig j : jobs) {
            if (j.objectApiName == 'Contact') contactJob = j;
        }
        System.assertNotEquals(null, contactJob, 'Sample Mask_Contact job should be present');

        // Job_Type__c is left blank on the sample record - should default to FIELD_MASKING.
        System.assertEquals('FIELD_MASKING', contactJob.jobType);
        // Batch_Size__c is set on the sample record.
        System.assertEquals(200, contactJob.batchSize);
        // Run_Mode__c is explicitly Full on the shipped sample - it intentionally does not
        // reference the package's own Data_Masking_Applied_Date__c field for Delta mode out
        // of the box, since that field's real name depends on whether this is deployed
        // directly (unprefixed) or installed as the namespaced package
        // (privacyguard__Data_Masking_Applied_Date__c) - see README "Delta masking" section.
        System.assertEquals('Full', contactJob.runMode);
        System.assertEquals(null, contactJob.deltaTrackingField);
    }
}
