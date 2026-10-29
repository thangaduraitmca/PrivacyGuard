/**
 * @class         MaskingFrameworkIntegrationTest
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
 * End-to-end test: uses runtime field configurations from MaskingTestConfiguration and
 * Masking_Job_Sequence__mdt records shipped with this package (Contact.Email,
 * Contact.Phone, Contact.LastName / job "Mask_Contact").
 */
@isTest
private with sharing class MaskingFrameworkIntegrationTest {

    @testSetup
    static void setup() {
        MaskingTestConfiguration.createDefaults();
        insert new Contact(LastName = 'OriginalLastName', Email = 'original@example.com', Phone = '415-555-0100');
    }

    @isTest
    static void testFullMaskingRunMasksContactFields() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Test.startTest();
        MaskingFrameworkService.executeMaskingRun();
        Test.stopTest();

        Contact updated = [SELECT LastName, Email, Phone FROM Contact LIMIT 1];
        System.assertNotEquals('OriginalLastName', updated.LastName);
        System.assertNotEquals('original@example.com', updated.Email);
        System.assertNotEquals('415-555-0100', updated.Phone);

        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        System.assertEquals(false, settings.Bypass_All_Automations__c,
            'Automations should be re-enabled once the run completes');
    }

    @isTest
    static void testLoggerWritesEntries() {
        Test.startTest();
        MaskingLogger.logInfo('TestJob', 'Test message');
        Test.stopTest();
        List<Masking_Log__c> logs = [SELECT Job_Name__c, Status__c FROM Masking_Log__c WHERE Job_Name__c = 'TestJob'];
        System.assertEquals(1, logs.size());
        System.assertEquals('Success', logs[0].Status__c);
    }

    @isTest
    static void testLegacyDeltaModeIsRejectedBeforeLaunchingBatch() {
        List<MaskingConfigService.FieldConfig> fields = MaskingConfigService.getActiveFieldConfigsByObject().get('Contact');
        Boolean rejected = false;
        Test.startTest();
        try {
            new MaskingBatch('Legacy_Delta', 'Contact', fields, 'Delta', 'Data_Masking_Applied_Date__c');
        } catch (SchemaValidationUtil.InvalidSchemaReferenceException ex) {
            rejected = true;
            System.assert(ex.getMessage().contains('Delta'), 'The error must identify the unsupported mode.');
            System.assert(ex.getMessage().contains('Unmasked records only'), 'The error must explain how to migrate the job.');
        }
        Test.stopTest();
        System.assert(rejected, 'Legacy Delta jobs must be rejected rather than silently masking a different record scope.');
        Contact unchanged = [SELECT LastName, Data_Masking_Applied_Date__c FROM Contact LIMIT 1];
        System.assertEquals('OriginalLastName', unchanged.LastName);
        System.assertEquals(null, unchanged.Data_Masking_Applied_Date__c, 'Rejected jobs must not stamp a timestamp.');
    }

    @isTest
    static void testFullModeRemasksFlaggedRecordAfterExternalChange() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact original = [SELECT Id FROM Contact LIMIT 1];
        original.Data_Masking_Complete__c = true;
        original.Email = 'reimported-real-data@example.com';
        update original;
        List<MaskingConfigService.FieldConfig> fields = MaskingConfigService.getActiveFieldConfigsByObject().get('Contact');
        Test.startTest();
        Database.executeBatch(new MaskingBatch('Full_Remask', 'Contact', fields, 'Full', 'Data_Masking_Complete__c'), 200);
        Test.stopTest();
        Contact result = [SELECT Email, Data_Masking_Complete__c FROM Contact WHERE Id = :original.Id];
        System.assertNotEquals('reimported-real-data@example.com', result.Email, 'Full mode must mask even an already flagged record.');
        System.assertEquals(true, result.Data_Masking_Complete__c, 'Successful masking must preserve the completion flag.');
    }

    @isTest
    static void testOnceModeMasksUnmaskedRecordAndStampsFlag() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact untouched = [SELECT Id FROM Contact LIMIT 1];
        List<MaskingConfigService.FieldConfig> fields = MaskingConfigService.getActiveFieldConfigsByObject().get('Contact');

        Test.startTest();
        Database.executeBatch(new MaskingBatch('Mask_Contact_Once_Test', 'Contact', fields, 'Once', 'Data_Masking_Complete__c'), 200);
        Test.stopTest();

        Contact result = [SELECT LastName, Data_Masking_Complete__c FROM Contact WHERE Id = :untouched.Id];
        System.assertNotEquals('OriginalLastName', result.LastName, 'Record should be masked on its first Once-mode run');
        System.assertEquals(true, result.Data_Masking_Complete__c, 'Flag should be stamped true after masking');
    }

    @isTest
    static void testOnceModeNeverReSelectsAFlaggedRecordEvenIfLaterModified() {
        // This test documents the deliberate limitation of Once mode, not a bug: unlike
        // Delta mode, a boolean flag carries no timing information, so it cannot detect
        // a record being re-populated with real data after its first masking.
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        c.Data_Masking_Complete__c = true;
        update c;

        // Simulate an external system re-populating real data - LastModifiedDate changes,
        // but the boolean flag (unlike a DateTime high-water mark) is untouched by this.
        c.Email = 'reimported-real-data@example.com';
        update c;

        List<MaskingConfigService.FieldConfig> fields = MaskingConfigService.getActiveFieldConfigsByObject().get('Contact');

        Test.startTest();
        Database.executeBatch(new MaskingBatch('Mask_Contact_Once_Test', 'Contact', fields, 'Once', 'Data_Masking_Complete__c'), 200);
        Test.stopTest();

        Contact result = [SELECT Email FROM Contact WHERE Id = :c.Id];
        System.assertEquals('reimported-real-data@example.com', result.Email,
            'Once mode should NOT re-mask a record whose flag is already true, even though it was modified since - this is the documented trade-off vs. Delta mode');
    }

    @isTest
    static void testMismatchedTrackingFieldTypeThrowsClearError() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        List<MaskingConfigService.FieldConfig> fields = MaskingConfigService.getActiveFieldConfigsByObject().get('Contact');

        Boolean threw = false;
        Test.startTest();
        try {
            // Data_Masking_Applied_Date__c is a DateTime field, but this job claims Once mode (expects Checkbox).
            new MaskingBatch('Mask_Contact_Bad_Config', 'Contact', fields, 'Once', 'Data_Masking_Applied_Date__c').start(null);
        } catch (SchemaValidationUtil.InvalidSchemaReferenceException e) {
            threw = true;
            System.assert(e.getMessage().contains('Data_Masking_Applied_Date__c'), 'Error must identify the invalid field: ' + e.getMessage());
            System.assert(e.getMessage().contains('editable Checkbox'), 'Error must state the required field type: ' + e.getMessage());
        }

        Test.stopTest();
        System.assert(threw, 'A DateTime field configured for Once mode should fail fast with a clear error');
    }
}
