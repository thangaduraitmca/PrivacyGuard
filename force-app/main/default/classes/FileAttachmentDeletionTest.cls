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

    @isTest static void objectPurgeCannotDeleteEvenWithSandboxAccess() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Integer blocked = 0;
        for (String mode : new List<String>{FileAttachmentDeletionBatch.MODE_ATTACHMENTS, FileAttachmentDeletionBatch.MODE_FILES}) {
            FileAttachmentDeletionBatch batch = new FileAttachmentDeletionBatch('test', 'Contact', mode);
            try { batch.start(null); } catch (FileAttachmentPurgeService.ObjectPurgeDisabledException e) { blocked++; }
            try { batch.execute(null, new List<SObject>{new Attachment()}); }
            catch (FileAttachmentPurgeService.ObjectPurgeDisabledException e) { blocked++; }
        }
        try { FileAttachmentPurgeService.purgeForObjects(new List<String>{'Contact'}, true, true); }
        catch (FileAttachmentPurgeService.ObjectPurgeDisabledException e) { blocked++; }
        System.assertEquals(5, blocked);
        System.assertEquals(1, [SELECT count() FROM Attachment]);
        System.assertEquals(1, [SELECT count() FROM ContentDocument]);
    }
}
