@IsTest
private class MaskingJobEntrySecurityTest {
    @IsTest static void noPermissionBlocksAllJobEntryPoints() {
        PrivacyGuardSecurityService.bypassPermissionChecksForTests = false;
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String login = 'pg-entry-' + String.valueOf(DateTime.now().getTime()) + '@example.invalid';
        User u = new User(Alias='pgentry', Email=login, EmailEncodingKey='UTF-8',
            LastName='Entry Test', LanguageLocaleKey='en_US', LocaleSidKey='en_US',
            ProfileId=p.Id, TimeZoneSidKey='America/Los_Angeles', UserName=login);
        System.runAs(u) {
            System.assertEquals(false, PrivacyGuardSecurityService.hasPermission(PrivacyGuardSecurityService.RUN_PERMISSION));
            Integer blocked = 0;
            try { MaskingJobManagerService.getJobs(); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.getLatestRun(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.runJob(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.rerunJob(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            System.assertEquals(4, blocked, 'Each entry point must reject the user before processing the request.');
        }
    }
}
