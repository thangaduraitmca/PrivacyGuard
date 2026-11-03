@IsTest
private class AutomationBypassRestorationTest {
    private static void setup() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
    }
    private static Automation_Bypass__c current() {
        return [SELECT Id, Bypass_All_Automations__c, Bypass_Triggers__c,
            Bypass_Flows__c, Bypass_Validation_Rules__c, Bypass_Owner__c,
            Bypass_Snapshot__c FROM Automation_Bypass__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()];
    }
    private class RestoreLater implements Queueable {
        public void execute(QueueableContext context) {
            EnvironmentSafetyService.sandboxOverrideForTests = true;
            AutomationManagerService.enableAllAutomations('run-A');
        }
    }
    @IsTest static void restoresMixedStateAcrossTransactions() {
        setup();
        insert new Automation_Bypass__c(SetupOwnerId=UserInfo.getOrganizationId(),
            Bypass_All_Automations__c=false, Bypass_Triggers__c=true,
            Bypass_Flows__c=false, Bypass_Validation_Rules__c=true);
        Test.startTest();
        AutomationManagerService.disableAllAutomations('run-A');
        System.assertEquals(true, current().Bypass_Flows__c);
        System.enqueueJob(new RestoreLater());
        Test.stopTest();
        Automation_Bypass__c restored=current();
        System.assertEquals(false,restored.Bypass_All_Automations__c);
        System.assertEquals(true,restored.Bypass_Triggers__c);
        System.assertEquals(false,restored.Bypass_Flows__c);
        System.assertEquals(true,restored.Bypass_Validation_Rules__c);
        System.assertEquals(null,restored.Bypass_Owner__c);
        System.assertEquals(null,restored.Bypass_Snapshot__c);
    }
    @IsTest static void overlapAndWrongOwnerCannotOverwriteSnapshot() {
        setup();
        AutomationManagerService.disableAllAutomations('run-A');
        String snapshot=current().Bypass_Snapshot__c;
        Boolean blocked=false;
        try { AutomationManagerService.disableAllAutomations('run-B'); }
        catch(AutomationManagerService.BypassStateException e) { blocked=true; }
        System.assert(blocked);
        blocked=false;
        try { AutomationManagerService.enableAllAutomations('run-B'); }
        catch(AutomationManagerService.BypassStateException e) { blocked=true; }
        System.assert(blocked);
        System.assertEquals(snapshot,current().Bypass_Snapshot__c);
        System.assertEquals('run-A',current().Bypass_Owner__c);
        AutomationManagerService.enableAllAutomations('run-A');
        AutomationManagerService.disableAllAutomations('run-B');
        blocked=false;
        try { AutomationManagerService.enableAllAutomations('run-A'); }
        catch(AutomationManagerService.BypassStateException e) { blocked=true; }
        System.assert(blocked,'Stale runtime callback must not restore a new run.');
        System.assertEquals('run-B',current().Bypass_Owner__c);
    }
    @IsTest static void preserveAdminFalseAndIgnoreDuplicateRestore() {
        setup();
        insert new Automation_Bypass__c(SetupOwnerId=UserInfo.getOrganizationId(),Bypass_Triggers__c=true);
        AutomationManagerService.disableAllAutomations('run-A');
        Automation_Bypass__c edited=current();
        edited.Bypass_Triggers__c=false;
        update edited;
        AutomationManagerService.enableAllAutomations('run-A');
        System.assertEquals(false,current().Bypass_Triggers__c);
        edited=current();edited.Bypass_Flows__c=true;update edited;
        AutomationManagerService.enableAllAutomations('run-A');
        System.assertEquals(true,current().Bypass_Flows__c);
    }
    @IsTest static void missingSnapshotRetainsOwnerAndFlags() {
        setup();
        AutomationManagerService.disableAllAutomations('run-A');
        Automation_Bypass__c edited=current();edited.Bypass_Snapshot__c='{}';update edited;
        Boolean blocked=false;
        try { AutomationManagerService.enableAllAutomations('run-A'); }
        catch(AutomationManagerService.BypassStateException e) { blocked=true; }
        System.assert(blocked);
        System.assertEquals('run-A',current().Bypass_Owner__c);
        System.assertEquals(true,current().Bypass_Flows__c);
    }
    @IsTest static void restoreWithoutSnapshotDoesNotClearExistingFlags() {
        setup();
        insert new Automation_Bypass__c(SetupOwnerId=UserInfo.getOrganizationId(),Bypass_Flows__c=true);
        AutomationManagerService.enableAllAutomations();
        System.assertEquals(true,current().Bypass_Flows__c);
    }
}
