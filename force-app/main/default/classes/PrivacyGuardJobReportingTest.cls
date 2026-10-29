/** Verifies control-panel DTOs and job edits against persisted history. */
@IsTest
private class PrivacyGuardJobReportingTest {
    @TestSetup static void setup(){
        PrivacyGuardPackageTestAccess.grantAdmin();MaskingTestConfiguration.createDefaults();}
    @IsTest static void controllerCreatesEditsListsAndDeletesJobs() {
        Test.startTest();
        Id jobId=MaskingControlPanelController.saveJob(null,'Lifecycle','Initial','Once','Serial',100,null,'["Contact"]');
        MaskingControlPanelController.saveJob(String.valueOf(jobId),'Edited','Changed','Full','Parallel',50,new List<String>{'Lead'},null);
        List<MaskingJobManagerService.JobRow> jobs=MaskingControlPanelController.getJobs();
        System.assertEquals(1,jobs.size());System.assertEquals('Edited',jobs[0].name);System.assertEquals('Lead',jobs[0].objects);System.assertEquals(50,jobs[0].batchSize);System.assertEquals(true,jobs[0].configurationReady);System.assertEquals('Manual',jobs[0].scheduleStatus);
        System.assertEquals(2,MaskingControlPanelController.getConfiguredObjects().size());
        System.assertEquals(null,MaskingControlPanelController.getLatestRun(jobId).run);
        MaskingControlPanelController.deleteJob(jobId);Test.stopTest();
        System.assertEquals(0,[SELECT COUNT() FROM Masking_Job__c WHERE Id=:jobId]);
        System.assertEquals(0,[SELECT COUNT() FROM Masking_Job_Object__c WHERE Masking_Job__c=:jobId]);
    }
    @IsTest static void runDetailsExposeNamespaceIndependentDtosAndFallbackMessages() {
        Masking_Job__c j=new Masking_Job__c(Job_Name__c='Report',Run_Mode__c='Once',Execution_Mode__c='Serial',Batch_Size__c=200,Last_Status__c='Failed');insert j;
        Masking_Job_Run__c r=new Masking_Job_Run__c(Masking_Job__c=j.Id,Run_Type__c='Run',Status__c='Failed',Summary__c='Record validation failed',Processed_Records__c=2,Failed_Records__c=1);insert r;
        insert new Masking_Job_Run_Object__c(Masking_Job_Run__c=r.Id,Object_API_Name__c='Contact',Status__c='Partial',Sequence__c=1,Processed_Records__c=2,Failed_Records__c=1,Error_Summary__c='Invalid input');
        insert new Masking_Log__c(Run_Id__c=String.valueOf(r.Id),Job_Name__c='Report',Object_API_Name__c='Contact',Field_API_Name__c='Email',Status__c='Failed',Error_Message__c='Validation failed');
        Test.startTest();MaskingJobManagerService.RunDetails d=MaskingControlPanelController.getLatestRun(j.Id);Test.stopTest();
        System.assertEquals(r.Id,d.run.id);System.assertEquals('Failed',d.run.status);System.assertEquals(2,d.run.processed);System.assertEquals(1,d.run.failed);
        System.assertEquals(1,d.objects.size());System.assertEquals('Contact',d.objects[0].objectApiName);System.assertEquals('Partial',d.objects[0].status);System.assertEquals('Invalid input',d.objects[0].errorSummary);
        System.assertEquals(1,d.logs.size());System.assertEquals('Masking Error',d.logs[0].errorCategory);System.assertEquals('Validation failed',d.logs[0].adminMessage);System.assertEquals('Validation failed',d.logs[0].technicalDetails);System.assertNotEquals(null,d.logs[0].suggestedAction);
    }
    @IsTest static void scheduledBoundaryPersistsJobAndManualCancelsSchedule() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        // Do not execute a scheduled scan at stopTest; this test verifies scheduling state only.
        Id jobId=MaskingControlPanelController.saveJobWithSchedule(null,'Scheduled',null,'Once','Serial',100,'["Contact"]',true,'MON','09:30');
        List<MaskingJobManagerService.JobRow> jobs=MaskingControlPanelController.getJobs();
        System.assertEquals('0 30 09 ? * MON',jobs[0].scheduleCron);
        System.assertNotEquals(null,jobs[0].nextScheduledRun);
        MaskingControlPanelController.saveJobWithFrequency(jobId,'Manual',null,'Once','Serial',200,'["Contact"]','manual',null,null,null);
        jobs=MaskingControlPanelController.getJobs();System.assertEquals('Manual',jobs[0].scheduleStatus);System.assertEquals(null,jobs[0].nextScheduledRun);
    }
}
