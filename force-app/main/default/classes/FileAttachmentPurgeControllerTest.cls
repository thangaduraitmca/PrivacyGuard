/**
 * @class         FileAttachmentPurgeControllerTest
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
@isTest
private with sharing class FileAttachmentPurgeControllerTest {

    @testSetup
    static void setup() {
        insert new Contact(LastName = 'PurgeControllerTest');
        insert new Attachment(
            ParentId = [SELECT Id FROM Contact LIMIT 1].Id,
            Name = 'test.txt',
            Body = Blob.valueOf('body')
        );
    }

    @isTest
    static void testPurgeObjectsDeletesAttachments() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        Test.startTest();
        FileAttachmentPurgeController.purgeObjects(new List<String>{ 'Contact' }, true, false);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Attachment]);
    }

    @isTest
    static void testPurgeObjectsSurfacesFriendlyErrorWhenBlocked() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;

        Boolean threw = false;
        Test.startTest();
        try {
            FileAttachmentPurgeController.purgeObjects(new List<String>{ 'Contact' }, true, false);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Sandbox'), 'Expected the Sandbox-only safety message, got: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(threw, 'Expected an AuraHandledException when blocked outside a Sandbox');
        System.assertEquals(1, [SELECT COUNT() FROM Attachment], 'Nothing should be deleted when blocked');
    }
}
