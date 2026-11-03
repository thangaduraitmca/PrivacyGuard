/** Negative regression coverage for the consolidated security remediation. */
@IsTest
private class PrivacyGuardConsolidatedSecurityTest {
    private static User limitedUser() {
        Profile profile=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        String login='pg-consolidated-'+String.valueOf(DateTime.now().getTime())+'@example.invalid';
        return new User(Alias='pgsecall',Email=login,EmailEncodingKey='UTF-8',LastName='Security',
            LanguageLocaleKey='en_US',LocaleSidKey='en_US',ProfileId=profile.Id,
            TimeZoneSidKey='America/Los_Angeles',UserName=login);
    }
    @IsTest static void directPrivilegedMethodsRejectUnassignedUser() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests=false;
        User limited=limitedUser();
        System.runAs(limited) {
            Integer blocked=0;
            Integer queries=Limits.getQueries();Integer writes=Limits.getDmlStatements();
            try { ToolingApiClient.query('SELECT Id FROM ApexTrigger'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { ToolingApiClient.post('MetadataContainer','{}'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { ToolingApiClient.patch('FlowDefinition','unused','{}'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { ToolingApiClient.diagnoseConnection(); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { AutomationManagerService.disableAllAutomations(); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { AutomationManagerService.enableAllAutomations(); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { MaskingJobOrchestrator.runMaskingJobs(); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { MaskingJobOrchestrator.handleJobCompletion('unused'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { MaskingSchedulerUtil.scheduleDaily('unused',2); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { MaskingSchedulerUtil.scheduleWeekly('unused','MON',2); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { MaskingSchedulerUtil.abortScheduledJobsByName('unused'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { PIIFieldScannerService.scanObject('Contact','unused'); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            try { MaskingJobOrchestrator.runJobs(null); } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) { blocked++; }
            System.assertEquals(13,blocked,'Each privileged helper must independently enforce its permission.');
            System.assertEquals(queries,Limits.getQueries(),'Rejection must precede reads.');
            System.assertEquals(writes,Limits.getDmlStatements(),'Rejection must precede writes.');
            System.assertEquals(0,Limits.getCallouts(),'Unauthorized calls must never reach Tooling transport.');
        }
    }
    @IsTest static void malformedAutomationSelectionsHaveNoSideEffects() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests=true;
        Integer blocked=0;Integer writes=Limits.getDmlStatements();Integer queued=Limits.getQueueableJobs();
        for (String value : new List<String>{'not-json','{}','[]','[null]',
            '[{"type":"FLOW","componentId":"001000000000001"}]',
            '[{"type":"APEX_TRIGGER","componentId":"001000000000001"}]'}) {
            try { AutomationManagementController.deactivateSelected(value); }
            catch (AuraHandledException ex) { blocked++; }
        }
        System.assertEquals(6,blocked,'Malformed and wrong-object selections must fail closed.');
        System.assertEquals(writes,Limits.getDmlStatements(),'Malformed input must not write tracking records.');
        System.assertEquals(queued,Limits.getQueueableJobs(),'Malformed input must not enqueue work.');
    }
    @IsTest static void toolingRejectsRetiredAndUnknownResourcesWithoutCallouts() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests=true;
        Integer blocked=0;
        try { ToolingApiClient.query('SELECT Id FROM FlowDefinition'); } catch (ToolingApiClient.ToolingApiException ex) { blocked++; }
        try { ToolingApiClient.post('../FlowDefinition','{}'); } catch (ToolingApiClient.ToolingApiException ex) { blocked++; }
        try { ToolingApiClient.patch('ValidationRule','unused','{}'); } catch (ToolingApiClient.ToolingApiException ex) { blocked++; }
        System.assertEquals(3,blocked,'Unsupported Tooling resources must be rejected.');
        System.assertEquals(0,Limits.getCallouts(),'Rejected resources must never make a callout.');
    }
    @IsTest static void reviewCannotSucceedWhenStatusUpdateIsDenied() {
        PII_Scan_Result__c finding=new PII_Scan_Result__c(Object_API_Name__c='Contact',
            Field_API_Name__c='Email',Review_Status__c='New',Scan_Batch_Id__c='MANUAL-SECURITY');
        insert finding;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests=true;
        User limited=limitedUser();
        System.runAs(limited) {
            Boolean blocked=false;
            try { PIIScanReviewController.updateReviewStatus(new List<Id>{finding.Id},'Accepted'); }
            catch (AuraHandledException ex) { blocked=true; }
            System.assert(blocked,'A denied review update must not be reported as successful.');
        }
        System.assertEquals('New',[SELECT Review_Status__c FROM PII_Scan_Result__c WHERE Id=:finding.Id].Review_Status__c,
            'Denied approval must leave the persisted review decision unchanged.');
        System.assertEquals(0,[SELECT COUNT() FROM Masking_Field_Config__c],
            'Denied approval must not create masking configuration.');
    }
}
