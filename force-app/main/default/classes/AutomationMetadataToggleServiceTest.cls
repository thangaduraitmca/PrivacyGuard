/** Regression coverage for retired metadata mutation entry points. */
@IsTest
private class AutomationMetadataToggleServiceTest {
    @IsTest static void deactivationIsBlockedBeforeAnySideEffects() {
        Integer beforeDml = Limits.getDmlStatements();
        Integer beforeCallouts = Limits.getCallouts();
        Boolean blocked = false;
        try {
            AutomationMetadataToggleService.deactivateAllFlowsAndValidationRules('legacy-run');
        } catch (AutomationMetadataToggleService.UnsupportedAutomationException ex) {
            blocked = true;
        }
        System.assert(blocked, 'The legacy deactivation entry point must fail closed.');
        System.assertEquals(beforeDml, Limits.getDmlStatements(), 'Rejection must not write tracking or logs.');
        System.assertEquals(beforeCallouts, Limits.getCallouts(), 'Rejection must not make a metadata callout.');
    }

    @IsTest static void restorationIsBlockedEvenWithTrackedLegacyChanges() {
        insert new Deactivated_Automation__c(Run_Id__c='legacy-run',
            Component_Type__c='FLOW', Component_Id__c='legacy-component',
            Component_Name__c='LegacyFlow', Original_State_Json__c='Active', Reactivated__c=false);
        Integer beforeDml = Limits.getDmlStatements();
        Integer beforeCallouts = Limits.getCallouts();
        Boolean blocked = false;
        try {
            AutomationMetadataToggleService.reactivateAll('legacy-run');
        } catch (AutomationMetadataToggleService.UnsupportedAutomationException ex) {
            blocked = true;
        }
        System.assert(blocked, 'The legacy restoration entry point must require manual review.');
        System.assertEquals(beforeDml, Limits.getDmlStatements(), 'The legacy tracking record must remain unchanged.');
        System.assertEquals(beforeCallouts, Limits.getCallouts(), 'Restoration must not call the Tooling API.');
        System.assertEquals(false, [SELECT Reactivated__c FROM Deactivated_Automation__c
            WHERE Run_Id__c='legacy-run' LIMIT 1].Reactivated__c, 'Do not claim restoration succeeded.');
    }
}
