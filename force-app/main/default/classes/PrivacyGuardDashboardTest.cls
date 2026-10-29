/** Dashboard metrics describe configuration readiness, not compliance certification. */
@IsTest
private class PrivacyGuardDashboardTest {
    @IsTest static void emptyDashboardIsNotAssessed() {
        Test.startTest();
        PrivacyGuardHomeController.Overview result = PrivacyGuardHomeController.getOverview();
        Test.stopTest();
        System.assertEquals(0, result.fieldsConfigured);
        System.assertEquals(0, result.completedRuns);
        System.assertEquals('Not Assessed', result.privacyStatus);
        System.assertNotEquals(null, result.environmentName);
        System.assertEquals(null, result.dataWarning, 'An administrator must be able to read dashboard source fields.');
    }
    @IsTest static void acceptedConfiguredFieldsAndCompletedRunAreReady() {
        MaskingTestConfiguration.createDefaults();
        insert new PII_Scan_Result__c(Object_API_Name__c='Contact', Field_API_Name__c='Email', Review_Status__c='Accepted');
        Masking_Job__c job = new Masking_Job__c(Job_Name__c='Dashboard', Run_Mode__c='Full', Execution_Mode__c='Serial', Is_Active__c=true);
        insert job;
        insert new Masking_Job_Run__c(Masking_Job__c=job.Id, Status__c='Completed', Run_Type__c='Run', Started_At__c=System.now());
        Test.startTest();
        PrivacyGuardHomeController.Overview result=PrivacyGuardHomeController.getOverview();
        Test.stopTest();
        System.assertEquals(1, result.acceptedFields);
        System.assertEquals(1, result.protectedFields);
        System.assertEquals(100, result.coverage);
        System.assertEquals(6, result.fieldsConfigured);
        System.assertEquals(2, result.objectsConfigured);
        System.assertEquals(1, result.completedRuns);
        System.assertEquals('Configuration Ready', result.privacyStatus);
        System.assertEquals(1, result.recentRuns.size());
        System.assertEquals('Completed', result.recentRuns[0].status);
    }
    @IsTest static void latestReviewAndAllRunTotalsDriveAttention() {
        MaskingTestConfiguration.createDefaults();
        PII_Scan_Result__c oldRow=new PII_Scan_Result__c(Object_API_Name__c='Contact',Field_API_Name__c='Email',Review_Status__c='New');
        insert oldRow;
        Test.setCreatedDate(oldRow.Id,System.now().addDays(-2));
        insert new List<PII_Scan_Result__c>{
            new PII_Scan_Result__c(Object_API_Name__c='Contact',Field_API_Name__c='Email',Review_Status__c='Accepted'),
            new PII_Scan_Result__c(Object_API_Name__c='Contact',Field_API_Name__c='Fax',Review_Status__c='New'),
            new PII_Scan_Result__c(Object_API_Name__c='Contact',Field_API_Name__c='Description',Review_Status__c='Accepted')};
        Masking_Job__c job=new Masking_Job__c(Job_Name__c='History');insert job;
        List<Masking_Job_Run__c> history=new List<Masking_Job_Run__c>();
        for(Integer i=0;i<6;i++) history.add(new Masking_Job_Run__c(Masking_Job__c=job.Id,Status__c='Completed',Run_Type__c='Run'));
        history.add(new Masking_Job_Run__c(Masking_Job__c=job.Id,Status__c='Failed',Run_Type__c='Run'));
        history.add(new Masking_Job_Run__c(Masking_Job__c=job.Id,Status__c='Completed with Errors',Run_Type__c='Run'));
        insert history;
        Test.startTest();PrivacyGuardHomeController.Overview result=PrivacyGuardHomeController.getOverview();Test.stopTest();
        System.assertEquals(2,result.acceptedFields);
        System.assertEquals(1,result.reviewFields,'Newest Email review must supersede the older pending finding.');
        System.assertEquals(50,result.coverage);
        System.assertEquals(6,result.completedRuns,'Totals must include runs outside the recent list.');
        System.assertEquals(2,result.failedRuns);
        System.assertEquals(5,result.recentRuns.size());
        System.assertEquals('Attention Required',result.privacyStatus);
    }
}
