/**
 * @class         FileAttachmentDeletionTest
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
private with sharing class FileAttachmentDeletionTest {

    @testSetup
    static void setup() {
        Contact c = new Contact(LastName = 'PurgeTestContact');
        insert c;

        insert new Attachment(ParentId = c.Id, Name = 'test.txt', Body = Blob.valueOf('test body'));

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.txt',
            VersionData = Blob.valueOf('test file content')
        );
        insert cv;
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId = contentDocumentId, LinkedEntityId = c.Id, ShareType = 'V');
    }

    @isTest
    static void testAttachmentDeletionBatchDeletesAttachments() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'PurgeTestContact' LIMIT 1];
        System.assertEquals(1, [SELECT COUNT() FROM Attachment WHERE ParentId = :c.Id]);

        Test.startTest();
        Database.executeBatch(new FileAttachmentDeletionBatch('Test_Attach_Purge', 'Contact', FileAttachmentDeletionBatch.MODE_ATTACHMENTS), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Attachment WHERE ParentId = :c.Id]);
    }

    @isTest
    static void testFileDeletionBatchDeletesContentDocuments() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'PurgeTestContact' LIMIT 1];
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id]);

        Test.startTest();
        Database.executeBatch(new FileAttachmentDeletionBatch('Test_File_Purge', 'Contact', FileAttachmentDeletionBatch.MODE_FILES), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id]);
    }

    @isTest
    static void testPurgeServiceDeletesBothAttachmentsAndFiles() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'PurgeTestContact' LIMIT 1];

        Test.startTest();
        FileAttachmentPurgeService.purgeForObjects(new List<String>{ 'Contact' }, true, true);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Attachment WHERE ParentId = :c.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id]);
    }

    @isTest
    static void testPurgeServiceNoOpWhenNothingSelected() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Test.startTest();
        FileAttachmentPurgeService.purgeForObjects(new List<String>{ 'Contact' }, false, false);
        Test.stopTest();
        // No exception, and nothing deleted.
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'PurgeTestContact' LIMIT 1];
        System.assertEquals(1, [SELECT COUNT() FROM Attachment WHERE ParentId = :c.Id]);
    }
}
