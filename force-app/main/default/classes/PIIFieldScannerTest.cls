/**
 * @class         PIIFieldScannerTest
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
 * 1.2.0       2026-09-16   PG-PII-TEST        PrivacyGuard Engineering   Updated tests for candidate-only PII discovery governance.
 * 1.2.3       2026-09-16   PG-PII-002         PrivacyGuard Engineering   Added Batch Apex callout regression coverage for native compliance lookup.
 * 1.2.4       2026-09-16   PG-PII-003         PrivacyGuard Engineering   Updated scanner tests for deterministic no-callout discovery.
 * 1.3.0       2026-09-17   PG-PII-007         PrivacyGuard Engineering   Added token-normalization regression coverage for keyword matching.
 * 1.3.1       2026-09-17   PG-PII-008         PrivacyGuard Engineering   Reworked keyword regression test to validate public scanner behavior without calling an internal helper.
 * 1.4.4       2026-09-17   PG-PII-009         PrivacyGuard Engineering   Added regression coverage ensuring configured fields are excluded from discovery.
 */
@isTest
private with sharing class PIIFieldScannerTest {

    @isTest
    static void testScanExcludesConfiguredFieldsAndStillFindsCandidates() {
        Test.startTest();
        List<PII_Scan_Result__c> findings = PIIFieldScannerService.scanObject('Contact', 'test-batch-1');
        Test.stopTest();

        Boolean foundFax = false;
        for (PII_Scan_Result__c f : findings) {
            System.assertNotEquals('Email', f.Field_API_Name__c,
                'Contact.Email is packaged masking configuration and must not be rediscovered.');
            System.assertNotEquals('Phone', f.Field_API_Name__c,
                'Contact.Phone is packaged masking configuration and must not be rediscovered.');
            if (f.Field_API_Name__c == 'Fax') foundFax = true;
        }
        System.assert(foundFax, 'An unconfigured Contact phone-type field should still be discovered.');
    }

    @isTest
    static void testScanFindsKeywordMatchOnMailingPostalCode() {
        Test.startTest();
        List<PII_Scan_Result__c> findings = PIIFieldScannerService.scanObject('Contact', 'test-batch-keyword');
        Test.stopTest();

        PII_Scan_Result__c postalCodeFinding;
        for (PII_Scan_Result__c f : findings) {
            if (f.Field_API_Name__c == 'MailingPostalCode') postalCodeFinding = f;
        }
        System.assertNotEquals(null, postalCodeFinding, 'Contact.MailingPostalCode should be flagged via the postal_code keyword');
        System.assert(postalCodeFinding.Detection_Reason__c.contains('Keyword match'));
    }

    @isTest
    static void testBatchInsertsFindingsAndSkipsUnknownObjects() {
        Test.startTest();
        Database.executeBatch(new PIIFieldScannerBatch(new List<String>{ 'Contact', 'Not_A_Real_Object__x' }), 2);
        Test.stopTest();

        List<PII_Scan_Result__c> results = [SELECT Id, Object_API_Name__c FROM PII_Scan_Result__c WHERE Object_API_Name__c = 'Contact'];
        System.assert(!results.isEmpty(), 'Expected scan results for Contact');
        System.assertEquals(0, [SELECT COUNT() FROM PII_Scan_Result__c WHERE Object_API_Name__c='Not_A_Real_Object__x'],
            'An unknown object must not produce findings.');
    }

    @isTest
    static void testPromoterGeneratesXmlOnlyForAcceptedRows() {
        insert new PII_Scan_Result__c(
            Object_API_Name__c = 'Contact',
            Field_API_Name__c = 'Description',
            Field_Label__c = 'Description',
            Salesforce_Field_Type__c = 'STRING',
            Detection_Reason__c = 'Keyword match: notes',
            Already_Configured__c = false,
            Review_Status__c = 'Accepted'
        );
        insert new PII_Scan_Result__c(
            Object_API_Name__c = 'Contact',
            Field_API_Name__c = 'Fax',
            Field_Label__c = 'Fax',
            Salesforce_Field_Type__c = 'PHONE',
            Detection_Reason__c = 'Field type: Phone',
            Already_Configured__c = false,
            Review_Status__c = 'New'
        );

        Test.startTest();
        Map<String, String> generated = MaskingConfigPromoter.generateMetadataXmlForAcceptedFindings();
        Test.stopTest();

        System.assertEquals(1, generated.size(), 'Only the Accepted row should produce XML');
    }
    @isTest
    static void testShortKeywordDoesNotCreateSubstringFalsePositive() {
        Test.startTest();
        List<PII_Scan_Result__c> findings = PIIFieldScannerService.scanObject('Account', 'test-batch-token');
        Test.stopTest();

        for (PII_Scan_Result__c finding : findings) {
            System.assertNotEquals(
                'OperatingHoursId',
                finding.Field_API_Name__c,
                'OperatingHoursId must not be identified merely because a short keyword such as TIN appears inside another token.'
            );
        }
    }

}
