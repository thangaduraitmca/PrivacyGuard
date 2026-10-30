@IsTest
private class PrivacyGuardRunDashboardTest {
    @TestSetup static void permissions(){PrivacyGuardPackageTestAccess.grantAdmin();}
    @IsTest static void objectCountersAreVisibleBeforeRunCompletes() {
        Masking_Job__c job=new Masking_Job__c(Job_Name__c='Dashboard test',Run_Mode__c='Full',Execution_Mode__c='Serial',Is_Active__c=true,Batch_Size__c=200);insert job;
        Masking_Job_Run__c run=new Masking_Job_Run__c(Masking_Job__c=job.Id,Status__c='Completed',Started_At__c=System.now(),Completed_At__c=System.now(),Processed_Records__c=0,Failed_Records__c=0);insert run;
        insert new Masking_Job_Run_Object__c(Masking_Job_Run__c=run.Id,Object_API_Name__c='Contact',Status__c='Completed',Processed_Records__c=125,Failed_Records__c=2,Started_At__c=System.now(),Completed_At__c=System.now());
        MaskingJobManagerService.RunDetails result=MaskingJobManagerService.getLatestRun(job.Id);
        System.assertEquals(125,result.run.processed,'Object counters drive the live dashboard instead of stale parent totals.');
        System.assertEquals(2,result.run.failed);System.assertEquals(1,result.objects.size());
        System.assertNotEquals(null,result.run.startedAt);
    }
    @IsTest static void batchPersistsSuccessfulAndFailedChunkCounts() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Masking_Job__c job=new Masking_Job__c(Job_Name__c='Chunk test',Run_Mode__c='Full',Execution_Mode__c='Serial',Is_Active__c=true,Batch_Size__c=200);insert job;
        Masking_Job_Run__c run=new Masking_Job_Run__c(Masking_Job__c=job.Id,Status__c='Running',Started_At__c=System.now());insert run;
        Masking_Job_Run_Object__c part=new Masking_Job_Run_Object__c(Masking_Job_Run__c=run.Id,Object_API_Name__c='Contact',Status__c='Running');insert part;
        Contact contact=new Contact(LastName='Original');insert contact;
        MaskingConfigService.FieldConfig config=new MaskingConfigService.FieldConfig();config.objectApiName='Contact';config.fieldApiName='LastName';config.fieldType='STATIC';config.maskingPattern='Masked';
        MaskingBatch batch=new MaskingBatch('Chunk test','Contact',new List<MaskingConfigService.FieldConfig>{config},'Full',null,run.Id,part.Id,null,false);
        batch.execute(null,new List<SObject>{contact});
        part=[SELECT Processed_Records__c,Failed_Records__c FROM Masking_Job_Run_Object__c WHERE Id=:part.Id];
        System.assertEquals(1,part.Processed_Records__c);System.assertEquals(0,part.Failed_Records__c);
        config.maskingPattern=null;
        batch.execute(null,new List<SObject>{contact});
        part=[SELECT Processed_Records__c,Failed_Records__c FROM Masking_Job_Run_Object__c WHERE Id=:part.Id];
        System.assertEquals(1,part.Processed_Records__c);System.assertEquals(1,part.Failed_Records__c);
    }
}
