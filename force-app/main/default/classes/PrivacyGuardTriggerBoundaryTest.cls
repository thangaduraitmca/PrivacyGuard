/** Trigger management boundaries must reject excluded automation types. */
@IsTest
private class PrivacyGuardTriggerBoundaryTest {
    @IsTest static void discoveryReturnsOnlyTriggersAndConsistentTotals() {
        Test.startTest();
        AutomationManagementController.Summary summary=AutomationManagementController.discover();
        Test.stopTest();
        System.assertEquals(summary.items.size(),summary.total);
        Integer active=0;
        for(AutomationManagementController.AutomationRow row:summary.items) {
            System.assertEquals('APEX_TRIGGER',row.type);
            System.assertNotEquals(null,row.componentId);
            System.assertEquals(false,row.selected);
            if(row.state=='Active')active++;
        }
        System.assertEquals(active,summary.active);
        System.assertEquals(0,summary.tracked);
        System.assertEquals(false,summary.pending);
    }
    @IsTest static void selectionRejectsFlowsAndEmptyRequestsWithoutCreatingWork() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Integer rejected=0;
        try{AutomationManagementController.deactivateSelected('[]');}catch(AuraHandledException ex){rejected++;}
        try{AutomationManagementController.restoreSelected('[]');}catch(AuraHandledException ex){rejected++;}
        try{AutomationManagementController.deactivateSelected('[{"type":"FLOW","componentId":"not-used"}]');}catch(AuraHandledException ex){rejected++;}
        try{AutomationManagementController.restoreSelected('[{"type":"VALIDATION_RULE","componentId":"not-used"}]');}catch(AuraHandledException ex){rejected++;}
        System.assertEquals(4,rejected,'Excluded types and empty selections must all be rejected.');
        System.assertEquals(0,Limits.getQueueableJobs());
        System.assertEquals(0,[SELECT COUNT() FROM Deactivated_Automation__c]);
        System.assertEquals('0 deployment status check(s) queued. No new trigger deployments were submitted.',AutomationManagementController.resumeDeploymentChecks());
    }
}
