@IsTest
private class MaskingJobCrudSecurityTest {
    @IsTest static void usersWithoutObjectAccessCannotCreateOrDeleteJobs() {
        // Keep the test focused on CRUD, independently of the custom permission gate.
        PrivacyGuardSecurityService.bypassPermissionChecksForTests = true;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String login = 'pg-crud-' + String.valueOf(DateTime.now().getTime()) + '@example.invalid';
        User limited = new User(Alias='pgcrud', Email=login, EmailEncodingKey='UTF-8',
            LastName='CRUD Test', LanguageLocaleKey='en_US', LocaleSidKey='en_US',
            ProfileId=p.Id, TimeZoneSidKey='America/Los_Angeles', UserName=login);
        System.runAs(limited) {
            System.assertEquals(false, Masking_Job__c.SObjectType.getDescribe().isCreateable(), 'The test profile must not have job create access.');
            System.assertEquals(false, Masking_Job__c.SObjectType.getDescribe().isDeletable(), 'The test profile must not have job delete access.');
            MaskingJobManagerService.JobInput input = new MaskingJobManagerService.JobInput();
            input.name = 'Security test'; input.objects = new List<String>{'Contact'};
            Boolean createBlocked = false;
            try { MaskingJobManagerService.saveJob(input); }
            catch (AuraHandledException e) { createBlocked = e.getMessage().contains('permission'); }
            Boolean deleteBlocked = false;
            try { MaskingJobManagerService.deleteJob(null); }
            catch (AuraHandledException e) { deleteBlocked = e.getMessage().contains('permission'); }
            System.assert(createBlocked, 'Creating must be blocked without object permissions.');
            System.assert(deleteBlocked, 'Deleting must be blocked without object permissions.');
        }
    }
    @IsTest static void jobReadsAndScheduleCancellationEnforceObjectAccess() {
        PrivacyGuardSecurityService.bypassPermissionChecksForTests=true;
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Profile p=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        Masking_Job__c protectedJob=new Masking_Job__c(Job_Name__c='Protected schedule parent');
        insert protectedJob;
        String login='pg-job-read-'+String.valueOf(DateTime.now().getTime())+'@example.invalid';
        User limited=new User(Alias='pgjread',Email=login,EmailEncodingKey='UTF-8',
            LastName='Job Read Access',LanguageLocaleKey='en_US',LocaleSidKey='en_US',
            ProfileId=p.Id,TimeZoneSidKey='America/Los_Angeles',UserName=login);
        System.runAs(limited) {
            System.assertEquals(false,Masking_Job__c.SObjectType.getDescribe().isAccessible(),
                'The profile must lack job read access.');
            Integer blocked=0;
            try { MaskingJobManagerService.getJobs(); } catch (QueryException ex) { blocked++; }
            try { MaskingJobManagerService.getConfiguredObjects(); } catch (QueryException ex) { blocked++; }
            try { MaskingJobManagerService.getLatestRun(null); } catch (QueryException ex) { blocked++; }
            try { MaskingJobManagerService.cancelJobSchedule(protectedJob.Id); } catch (QueryException ex) { blocked++; }
            System.assertEquals(4,blocked,'Read and schedule cancellation endpoints must enforce CRUD independently of custom permissions.');
        }
    }
}
