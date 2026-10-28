@IsTest
private class PrivilegedBatchSecurityTest {
    @IsTest static void directBatchCallsRequireTheirOwnPermissions() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests = false;
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String login = 'pg-batch-' + String.valueOf(DateTime.now().getTime()) + '@example.invalid';
        User u = new User(Alias='pgbatch', Email=login, EmailEncodingKey='UTF-8',
            LastName='Batch Test', LanguageLocaleKey='en_US', LocaleSidKey='en_US',
            ProfileId=p.Id, TimeZoneSidKey='America/Los_Angeles', UserName=login);
        System.runAs(u) {
            MaskingBatch masking = new MaskingBatch('test', 'Contact', null);
            MaskingFailedRecordRecoveryBatch recovery = new MaskingFailedRecordRecoveryBatch(
                'test', 'Contact', null, 'Full', null, null, null, null);
            FileAttachmentDeletionBatch purge = new FileAttachmentDeletionBatch(
                'test', 'Contact', FileAttachmentDeletionBatch.MODE_ATTACHMENTS);
            Integer blocked = 0;
            try { masking.start(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { masking.execute(null, new List<SObject>()); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { recovery.start(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { recovery.execute(null, new List<SObject>()); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { purge.start(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { purge.execute(null, new List<SObject>()); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            System.assertEquals(6, blocked, 'Every direct privileged batch entry point must require permission.');
        }
    }
}
