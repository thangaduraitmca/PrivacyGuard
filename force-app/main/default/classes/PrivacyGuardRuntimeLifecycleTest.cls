/** Tests persisted runtime state, recovery scope and terminal-state idempotency. */
@IsTest
private class PrivacyGuardRuntimeLifecycleTest {
    @TestSetup static void setup(){MaskingTestConfiguration.createDefaults();}
    private static Masking_Job__c job(String mode) {
        Masking_Job__c j=new Masking_Job__c(Job_Name__c='Runtime regression',Run_Mode__c=mode,Execution_Mode__c='Serial',Batch_Size__c=200,Is_Active__c=true);
        insert j;return j;
    }
    private static void selectContact(Id jobId) {
        insert new Masking_Job_Object__c(Masking_Job__c=jobId,Object_API_Name__c='Contact',Sequence__c=1,Is_Active__c=true,Delta_Tracking_Field__c='Data_Masking_Complete__c');
    }
    private static Masking_Job_Run__c run(Id jobId,String status) {
        Masking_Job_Run__c r=new Masking_Job_Run__c(Masking_Job__c=jobId,Status__c=status,Run_Type__c='Run',Total_Objects__c=2,Completed_Objects__c=0,Processed_Records__c=0,Failed_Records__c=0);
        insert r;return r;
    }
    private static Masking_Job_Run_Object__c step(Id runId,String status,Integer seq) {
        Masking_Job_Run_Object__c r=new Masking_Job_Run_Object__c(Masking_Job_Run__c=runId,Object_API_Name__c='Contact',Sequence__c=seq,Status__c=status);
        insert r;return r;
    }
    @IsTest static void onceRunMasksAndFinalisesHistory() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Masking_Job__c j=job('Once');selectContact(j.Id);
        Contact c=new Contact(LastName='Original',Email='real@example.com');insert c;
        Test.startTest();Id runId=MaskingJobManagerService.runJob(j.Id);Test.stopTest();
        Contact masked=[SELECT Email,Data_Masking_Complete__c FROM Contact WHERE Id=:c.Id];
        System.assertEquals('masked.contact@example.invalid',masked.Email);
        System.assertEquals(true,masked.Data_Masking_Complete__c);
        Masking_Job_Run__c result=[SELECT Status__c,Processed_Records__c,Completed_Objects__c FROM Masking_Job_Run__c WHERE Id=:runId];
        System.assertEquals('Completed',result.Status__c);
        System.assertEquals(1,result.Processed_Records__c);
        System.assertEquals(1,result.Completed_Objects__c);
        System.assertEquals('Completed',[SELECT Last_Status__c FROM Masking_Job__c WHERE Id=:j.Id].Last_Status__c);
        System.assertEquals(false,Automation_Bypass__c.getOrgDefaults().Bypass_All_Automations__c);
    }
    @IsTest static void recoveryTouchesOnlyFailedRecords() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Masking_Job__c j=job('Full');selectContact(j.Id);
        Masking_Job_Run__c parent=run(j.Id,'Failed');
        List<Contact> contacts=new List<Contact>{new Contact(LastName='Retry',Email='retry@example.com'),new Contact(LastName='Untouched',Email='untouched@example.com')};insert contacts;
        insert new Masking_Log__c(Job_Name__c=j.Job_Name__c,Object_API_Name__c='Contact',Record_Id__c=String.valueOf(contacts[0].Id),Run_Id__c=String.valueOf(parent.Id),Status__c='Failed',Error_Message__c='Retry this record');
        Test.startTest();Id runId=MaskingJobManagerService.rerunJob(j.Id);Test.stopTest();
        System.assertEquals('masked.contact@example.invalid',[SELECT Email FROM Contact WHERE Id=:contacts[0].Id].Email);
        System.assertEquals('untouched@example.com',[SELECT Email FROM Contact WHERE Id=:contacts[1].Id].Email,'Recovery must never broaden to all records.');
        Masking_Job_Run__c result=[SELECT Status__c,Parent_Run__c,Run_Type__c FROM Masking_Job_Run__c WHERE Id=:runId];
        System.assertEquals(parent.Id,result.Parent_Run__c);System.assertEquals('Rerun',result.Run_Type__c);System.assertEquals('Completed',result.Status__c);
    }
    @IsTest static void partialSerialStepSkipsQueuedWorkAndCountsOnce() {
        Masking_Job__c j=job('Once');Masking_Job_Run__c r=run(j.Id,'Running');
        Masking_Job_Run_Object__c first=step(r.Id,'Running',1);Masking_Job_Run_Object__c next=step(r.Id,'Queued',2);
        Test.startTest();
        RuntimeMaskingJobOrchestrator.completeObject(first.Id,3,1,'One record failed');
        RuntimeMaskingJobOrchestrator.completeObject(first.Id,99,99,'Duplicate callback');
        Test.stopTest();
        Masking_Job_Run__c result=[SELECT Status__c,Processed_Records__c,Failed_Records__c,Completed_Objects__c FROM Masking_Job_Run__c WHERE Id=:r.Id];
        System.assertEquals('Completed with Errors',result.Status__c);System.assertEquals(3,result.Processed_Records__c);System.assertEquals(1,result.Failed_Records__c);System.assertEquals(1,result.Completed_Objects__c);
        System.assertEquals('Skipped',[SELECT Status__c FROM Masking_Job_Run_Object__c WHERE Id=:next.Id].Status__c);
        System.assertEquals('Partial',[SELECT Status__c FROM Masking_Job_Run_Object__c WHERE Id=:first.Id].Status__c);
    }
    @IsTest static void reconcileFinalisesFailedRunAndSkipsQueue() {
        Masking_Job__c j=job('Once');Masking_Job_Run__c r=run(j.Id,'Running');
        step(r.Id,'Failed',1);Masking_Job_Run_Object__c queued=step(r.Id,'Queued',2);
        Test.startTest();RuntimeMaskingJobOrchestrator.reconcile(j.Id);Test.stopTest();
        System.assertEquals('Failed',[SELECT Status__c FROM Masking_Job_Run__c WHERE Id=:r.Id].Status__c);
        System.assertEquals('Skipped',[SELECT Status__c FROM Masking_Job_Run_Object__c WHERE Id=:queued.Id].Status__c);
        System.assertEquals('Failed',[SELECT Last_Status__c FROM Masking_Job__c WHERE Id=:j.Id].Last_Status__c);
    }
    @IsTest static void cancelMarksQueuedWorkAndProtectsTerminalStatus() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Masking_Job__c j=job('Once');Masking_Job_Run__c r=run(j.Id,'Running');
        Masking_Job_Run_Object__c queued=step(r.Id,'Queued',1);
        Test.startTest();MaskingControlPanelController.cancelRunningJob(j.Id);
        RuntimeMaskingJobOrchestrator.completeObject(queued.Id,10,0,null);Test.stopTest();
        System.assertEquals('Cancelled',[SELECT Status__c FROM Masking_Job_Run__c WHERE Id=:r.Id].Status__c);
        System.assertEquals('Skipped',[SELECT Status__c FROM Masking_Job_Run_Object__c WHERE Id=:queued.Id].Status__c);
        System.assertEquals('Cancelled',[SELECT Last_Status__c FROM Masking_Job__c WHERE Id=:j.Id].Last_Status__c);
    }
    @IsTest static void preflightRejectsInactiveAndEmptyJobs() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Masking_Job__c j=job('Once');j.Is_Active__c=false;update j;
        Boolean rejected=false;
        try {RuntimeMaskingJobOrchestrator.start(j.Id,false,null);}catch(AuraHandledException ex){rejected=true;}
        System.assert(rejected,'Inactive jobs must not start.');
        j.Is_Active__c=true;update j;rejected=false;
        try {RuntimeMaskingJobOrchestrator.start(j.Id,false,null);}catch(AuraHandledException ex){rejected=true;}
        System.assert(rejected,'Jobs without objects must not start.');
        System.assertEquals(0,[SELECT COUNT() FROM Masking_Job_Run__c]);
    }
}
