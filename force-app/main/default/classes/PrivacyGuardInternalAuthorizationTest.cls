/** Negative authorization evidence for the internal bypass and legacy tracker.
 * No production behavior is changed. Real custom-permission checks are enabled.
 */
@IsTest
private class PrivacyGuardInternalAuthorizationTest {
    @TestSetup static void createUnprivilegedUser() {
        // No package permission sets are assigned to this user.
        Profile restricted = [SELECT Id FROM Profile
            WHERE UserType = 'Standard' AND PermissionsModifyAllData = false
            ORDER BY Name LIMIT 1];
        String uniqueName = 'pg.auth.' + UserInfo.getOrganizationId() + '.' +
            EncodingUtil.convertToHex(Crypto.generateAesKey(128)) + '@example.invalid';
        insert new User(Username=uniqueName, Email='pg-auth@example.invalid',
            LastName='PG_Internal_Auth_Test', Alias='pgauth',
            TimeZoneSidKey='Australia/Sydney', LocaleSidKey='en_AU',
            EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US', ProfileId=restricted.Id);
    }

    @IsTest static void deniedCallsPreserveExistingState() {
        insert new Automation_Bypass__c(SetupOwnerId=UserInfo.getOrganizationId(),
            Bypass_All_Automations__c=true, Bypass_Triggers__c=false,
            Bypass_Flows__c=true, Bypass_Validation_Rules__c=false,
            Use_Metadata_Deactivation__c=false, Bypass_Owner__c='existing-owner',
            Bypass_Snapshot__c='{"Bypass_All_Automations__c":false,"Bypass_Triggers__c":true,"Bypass_Flows__c":false,"Bypass_Validation_Rules__c":true}');
        insert new Masking_Run_Tracker__c(SetupOwnerId=UserInfo.getOrganizationId(),
            Total_Jobs__c=3, Completed_Jobs__c=1, Run_In_Progress__c=true,
            Run_Started_At__c=System.now());
        verifyAllDenied();
    }

    @IsTest static void deniedCallsDoNotCreateInternalState() {
        System.assertEquals(0, [SELECT count() FROM Automation_Bypass__c]);
        System.assertEquals(0, [SELECT count() FROM Masking_Run_Tracker__c]);
        verifyAllDenied();
    }

    private static void verifyAllDenied() {
        User deniedUser = [SELECT Id FROM User WHERE LastName='PG_Internal_Auth_Test' LIMIT 1];
        String beforeState = stateSnapshot();
        Integer beforeAsync = [SELECT count() FROM AsyncApexJob];
        Boolean previousBypass = PrivacyGuardSecurityService.bypassPermissionChecksForTests;
        Boolean previousSandbox = EnvironmentSafetyService.sandboxOverrideForTests;
        try {
            PrivacyGuardSecurityService.bypassPermissionChecksForTests=false;
            // Isolate authorization from the separate production environment guard.
            EnvironmentSafetyService.sandboxOverrideForTests=true;
            System.runAs(deniedUser) {
                System.assertEquals(false, PrivacyGuardSecurityService.hasPermission(
                    PrivacyGuardSecurityService.RUN_PERMISSION),
                    'Fixture user must not have the masking permission. Review selected profile if this fails.');
                for (Integer operation=0; operation<7; operation++) {
                    Integer dmlBefore=Limits.getDmlStatements();
                    Integer queriesBefore=Limits.getQueries();
                    Boolean denied=false;
                    try {
                        if (operation==0) AutomationManagerService.disableAllAutomations();
                        else if (operation==1) AutomationManagerService.enableAllAutomations();
                        else if (operation==2) AutomationManagerService.disableAllAutomations('existing-owner');
                        else if (operation==3) AutomationManagerService.enableAllAutomations('existing-owner');
                        else if (operation==4) MaskingJobOrchestrator.runMaskingJobs();
                        else if (operation==5) {
                            MaskingConfigService.JobConfig job=new MaskingConfigService.JobConfig();
                            job.jobName='Unauthorized job'; job.objectApiName='Contact';
                            job.jobType='FIELD_MASKING'; job.executionMode='Parallel'; job.batchSize=1;
                            MaskingJobOrchestrator.runJobs(new List<MaskingConfigService.JobConfig>{job});
                        } else MaskingJobOrchestrator.handleJobCompletion('Unauthorized job');
                    } catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException ex) {
                        denied=true;
                    }
                    System.assert(denied, 'Expected authorization denial for operation ' + operation);
                    System.assertEquals(dmlBefore, Limits.getDmlStatements(), 'Denied operation must not write state.');
                    System.assertEquals(queriesBefore, Limits.getQueries(), 'Permission gate must precede state/configuration queries.');
                }
            }
        } finally {
            PrivacyGuardSecurityService.bypassPermissionChecksForTests=previousBypass;
            EnvironmentSafetyService.sandboxOverrideForTests=previousSandbox;
        }
        System.assertEquals(beforeState, stateSnapshot(), 'Denied calls must leave internal state unchanged.');
        System.assertEquals(beforeAsync, [SELECT count() FROM AsyncApexJob], 'Denied calls must not enqueue work.');
    }

    private static String stateSnapshot() {
        return JSON.serialize(new Map<String,Object>{
            'bypass'=>[SELECT Id, SetupOwnerId, Bypass_All_Automations__c,
                Bypass_Triggers__c, Bypass_Flows__c, Bypass_Validation_Rules__c,
                Use_Metadata_Deactivation__c, Bypass_Owner__c, Bypass_Snapshot__c
                FROM Automation_Bypass__c ORDER BY Id],
            'tracker'=>[SELECT Id, SetupOwnerId, Total_Jobs__c, Completed_Jobs__c,
                Run_In_Progress__c, Run_Started_At__c FROM Masking_Run_Tracker__c ORDER BY Id]
        });
    }
}
