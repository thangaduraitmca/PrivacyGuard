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
            try { MaskingJobManagerService.getConfiguredObjects(); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.getJobs(); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.getLatestRun(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.runJob(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.rerunJob(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { RuntimeMaskingJobOrchestrator.start(null, false, null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { RuntimeMaskingJobOrchestrator.reconcile(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { RuntimeMaskingJobOrchestrator.cancel(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { RuntimeMaskingJobOrchestrator.completeObject(null, 0, 0, null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.scheduleJob(null,'daily',null,null,'02:00'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.scheduleWeekly(null,'MON','02:00'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.cancelJobSchedule(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.cancelWeeklySchedule(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            try { MaskingJobManagerService.cancelRunningJob(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked++; }
            System.assertEquals(14, blocked, 'Each entry point must reject the user before processing the request.');
        }
    }
    @IsTest static void productionBlocksEveryDirectRuntimeEntryPoint() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests = true;
        Integer blocked = 0;
        Integer beforeDml = Limits.getDmlStatements();
        try { RuntimeMaskingJobOrchestrator.start(null, false, null); }
        catch (EnvironmentSafetyService.ProductionExecutionBlockedException ex) { blocked++; }
        try { RuntimeMaskingJobOrchestrator.reconcile(null); }
        catch (EnvironmentSafetyService.ProductionExecutionBlockedException ex) { blocked++; }
        try { RuntimeMaskingJobOrchestrator.cancel(null); }
        catch (EnvironmentSafetyService.ProductionExecutionBlockedException ex) { blocked++; }
        try { RuntimeMaskingJobOrchestrator.completeObject(null, 0, 0, null); }
        catch (EnvironmentSafetyService.ProductionExecutionBlockedException ex) { blocked++; }
        System.assertEquals(4, blocked, 'Every direct runtime method must reject production.');
        System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Production rejection must precede all writes.');
    }
    @IsTest static void runtimeReadsRequireObjectAccessEvenWhenCustomPermissionIsBypassed() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests = true;
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        String login='pg-runtime-crud-'+String.valueOf(DateTime.now().getTime())+'@example.invalid';
        User limited=new User(Alias='pgrcrud',Email=login,EmailEncodingKey='UTF-8',
            LastName='Runtime CRUD',LanguageLocaleKey='en_US',LocaleSidKey='en_US',
            ProfileId=p.Id,TimeZoneSidKey='America/Los_Angeles',UserName=login);
        System.runAs(limited) {
            System.assertEquals(false,Masking_Job_Run__c.SObjectType.getDescribe().isAccessible(),
                'This profile must not read runtime history.');
            Integer blocked=0;
            Integer beforeDml=Limits.getDmlStatements();
            try { RuntimeMaskingJobOrchestrator.reconcile(null); } catch (QueryException ex) { blocked++; }
            try { RuntimeMaskingJobOrchestrator.completeObject(null,0,0,null); } catch (QueryException ex) { blocked++; }
            System.assertEquals(2,blocked,'Runtime reads must enforce CRUD independently of the custom permission.');
            System.assertEquals(beforeDml,Limits.getDmlStatements(),'Denied history access must not change runtime records.');
        }
    }
}
