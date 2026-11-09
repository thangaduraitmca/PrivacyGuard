@IsTest
private class PrivacyGuardLogProtectionTest {
    @IsTest static void rawFailuresAreSuppressedAndAuditCannotBeMutated() {
        Masking_Log__c entry = new Masking_Log__c(Job_Name__c='Security regression',Status__c='Failed',
            Error_Message__c='FIELD_CUSTOM_VALIDATION_EXCEPTION: secret@example.invalid',
            Technical_Details__c='secret@example.invalid');
        insert entry;
        entry = [SELECT Id, Error_Message__c, Technical_Details__c FROM Masking_Log__c WHERE Id=:entry.Id];
        System.assert(!entry.Error_Message__c.contains('secret@example.invalid'));
        System.assertEquals(null,entry.Technical_Details__c);
        entry.Error_Message__c='tampered';
        Database.SaveResult changed=Database.update(entry,false);
        System.assertEquals(false,changed.isSuccess());
        Database.DeleteResult removed=Database.delete(entry,false);
        System.assertEquals(false,removed.isSuccess());
        System.assertEquals(1,[SELECT count() FROM Masking_Log__c WHERE Id=:entry.Id]);
    }
}
