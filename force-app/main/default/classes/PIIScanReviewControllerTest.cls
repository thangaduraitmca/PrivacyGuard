/**
 * @class         PIIScanReviewControllerTest
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
 * 1.2.7       2026-09-17   PG-PII-006       PrivacyGuard Engineering   Removed compile-time dependency on controller inner DTO from regression test.
 * 1.3.0       2026-09-17   PG-PII-007       PrivacyGuard Engineering   Updated review tests for latest-scan/manual-candidate scoping.
 * 1.2.6       2026-09-17   PG-PII-005       PrivacyGuard Engineering   Added DTO/result rendering regression coverage.
 * 1.2.0       2026-09-16   PG-PII-TEST        PrivacyGuard Engineering   Updated tests for candidate-only PII discovery governance.
 */
@isTest
private with sharing class PIIScanReviewControllerTest {

    @testSetup
    static void setup() {
        insert new PII_Scan_Result__c(
            Object_API_Name__c = 'Contact',
            Field_API_Name__c = 'Fax',
            Field_Label__c = 'Fax',
            Salesforce_Field_Type__c = 'PHONE',
            Detection_Reason__c = 'Field type: Phone',
            Already_Configured__c = false,
            Review_Status__c = 'New',
            Scan_Batch_Id__c = 'MANUAL-TEST'
        );
    }

    @isTest
    static void testGetScanResultsFiltersByStatus() {
        Object newResultsResponse = PIIScanReviewController.getScanResults('New');
        List<Object> newResults = (List<Object>) JSON.deserializeUntyped(JSON.serialize(newResultsResponse));
        System.assertEquals(1, newResults.size());
        Map<String, Object> firstRow = (Map<String, Object>) newResults[0];
        System.assertEquals('Contact', (String) firstRow.get('objectApiName'));
        System.assertEquals('Fax', (String) firstRow.get('fieldApiName'));

        Object allResultsResponse = PIIScanReviewController.getScanResults('All');
        List<Object> allResults = (List<Object>) JSON.deserializeUntyped(JSON.serialize(allResultsResponse));
        System.assertEquals(1, allResults.size());
    }

    @isTest
    static void testUpdateReviewStatus() {
        PII_Scan_Result__c rec = [SELECT Id FROM PII_Scan_Result__c LIMIT 1];

        Test.startTest();
        PIIScanReviewController.updateReviewStatus(new List<Id>{ rec.Id }, 'Accepted');
        Test.stopTest();

        PII_Scan_Result__c updated = [SELECT Review_Status__c FROM PII_Scan_Result__c WHERE Id = :rec.Id];
        System.assertEquals('Accepted', updated.Review_Status__c);
    }

    @isTest
    static void testRunScanReturnsJobId() {
        Test.startTest();
        Id jobId = PIIScanReviewController.runScan();
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @isTest
    static void testGetGeneratedMetadataFiles() {
        PII_Scan_Result__c rec = [SELECT Id FROM PII_Scan_Result__c LIMIT 1];
        rec.Review_Status__c = 'Accepted';
        update rec;

        Test.startTest();
        List<PIIScanReviewController.GeneratedFile> files = PIIScanReviewController.getGeneratedMetadataFiles();
        Test.stopTest();

        System.assertEquals(1, files.size());
        System.assert(files[0].fileName.contains('Contact_Fax'));
    }
    @isTest
    static void testManualCandidateCanBeAdded() {
        Test.startTest();
        Id candidateId = PIIScanReviewController.addManualCandidate('Contact', 'Description');
        Test.stopTest();
        PII_Scan_Result__c rec = [SELECT Detection_Reason__c, Review_Status__c FROM PII_Scan_Result__c WHERE Id = :candidateId];
        System.assertEquals('Manually added by administrator', rec.Detection_Reason__c);
        System.assertEquals('New', rec.Review_Status__c);
    }

    @isTest
    static void testAcceptNonMaskableFieldDoesNotFailReviewDecision() {
        PII_Scan_Result__c candidate = new PII_Scan_Result__c(
            Object_API_Name__c = 'Contact',
            Field_API_Name__c = 'CreatedDate',
            Field_Label__c = 'Created Date',
            Salesforce_Field_Type__c = 'DATETIME',
            Detection_Reason__c = 'Regression test - system managed field',
            Already_Configured__c = false,
            Review_Status__c = 'New',
            Scan_Batch_Id__c = 'MANUAL-NONMASKABLE-TEST'
        );
        insert candidate;

        Test.startTest();
        PIIScanReviewController.updateReviewStatus(new List<Id>{ candidate.Id }, 'Accepted');
        Test.stopTest();

        candidate = [SELECT Review_Status__c FROM PII_Scan_Result__c WHERE Id = :candidate.Id];
        System.assertEquals('Accepted', candidate.Review_Status__c,
            'Governance acceptance must succeed even when the field cannot be added to masking configuration.');
        System.assertEquals(0, [SELECT COUNT() FROM Masking_Field_Config__c
            WHERE Object_API_Name__c = 'Contact' AND Field_API_Name__c = 'CreatedDate'],
            'System-managed field must not be added to executable masking configuration.');
    }

}
