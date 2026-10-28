@IsTest
private class AutomationTriggerSecurityTest {
    @IsTest static void productionBlocksControllerActionsEvenWithOverride() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;
        upsert new Masking_Environment_Override__c(
            SetupOwnerId = UserInfo.getOrganizationId(), Allow_Run_In_Production__c = true);
        Boolean blocked = false;
        try { AutomationManagementController.deactivateSelected('[]'); }
        catch (AuraHandledException e) { blocked = e.getMessage().contains('sandboxes only'); }
        System.assert(blocked, 'Deactivation must be blocked in production.');
        blocked = false;
        try { AutomationManagementController.restoreSelected('[]'); }
        catch (AuraHandledException e) { blocked = e.getMessage().contains('sandboxes only'); }
        System.assert(blocked, 'Restoration must be blocked in production.');
    }

    @IsTest static void productionBlocksQueueableBeforeCallouts() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;
        Boolean blocked = false;
        try { new AutomationTriggerToggleQueueable('unused', 'unused', 'unused', 'Inactive').execute(null); }
        catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) { blocked = true; }
        System.assert(blocked, 'A directly invoked queueable must be blocked in production.');
    }

    @IsTest static void sandboxReachesNormalSelectionValidation() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Boolean selectionRequired = false;
        try { AutomationManagementController.deactivateSelected('[]'); }
        catch (AuraHandledException e) { selectionRequired = !e.getMessage().contains('sandboxes only'); }
        System.assert(selectionRequired, 'Sandbox requests should reach selection validation.');
    }

    @IsTest static void queueableRequiresPermission() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        PrivacyGuardSecurityService.bypassPermissionChecksForTests = false;
        Profile profile = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniqueName = 'pg-security-' + String.valueOf(DateTime.now().getTime()) + '@example.invalid';
        User userWithoutPermission = new User(Alias='pgtest', Email=uniqueName,
            EmailEncodingKey='UTF-8', LastName='Security Test', LanguageLocaleKey='en_US',
            LocaleSidKey='en_US', ProfileId=profile.Id, TimeZoneSidKey='America/Los_Angeles',
            UserName=uniqueName);
        System.runAs(userWithoutPermission) {
            Boolean blocked = false;
            try { new AutomationTriggerToggleQueueable('unused', 'unused', 'unused', 'Inactive').execute(null); }
            catch (PrivacyGuardSecurityService.PrivacyGuardAuthorizationException e) { blocked = true; }
            System.assert(blocked, 'A queueable must require metadata deactivation permission.');
        }
    }
}
