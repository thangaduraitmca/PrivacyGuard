@IsTest
private class MaskingPreviewServiceTest {
    @TestSetup static void setup() {
        PrivacyGuardPackageTestAccess.grantAdmin();
        List<Contact> people=new List<Contact>();
        for(Integer i=0;i<7;i++)people.add(new Contact(LastName='Private',Email='private@example.com',OtherPostalCode='2153',Data_Masking_Complete__c=i==0));
        insert people;
        insert new List<Masking_Field_Config__c>{
            new Masking_Field_Config__c(Object_API_Name__c='Contact',Field_API_Name__c='OtherPostalCode',Masking_Strategy__c='REGEX',Masking_Pattern__c='[0-9]=>X',Is_Active__c=true),
            new Masking_Field_Config__c(Object_API_Name__c='Contact',Field_API_Name__c='Email',Masking_Strategy__c='NULL',Is_Active__c=true)
        };
        Masking_Job__c job=new Masking_Job__c(Job_Name__c='Preview test',Run_Mode__c='Once',Execution_Mode__c='Serial',Is_Active__c=true);insert job;
        insert new Masking_Job_Object__c(Masking_Job__c=job.Id,Object_API_Name__c='Contact',Sequence__c=1,Is_Active__c=true);
    }
    private static Id jobId(){return [SELECT Id FROM Masking_Job__c LIMIT 1].Id;}
    @IsTest static void examplesAreReadOnlyAndRespectEligibility() {
        Integer beforeDml=Limits.getDmlStatements();
        MaskingPreviewService.PreviewResult result=MaskingPreviewService.preview(jobId(),'Contact');
        System.assertEquals(beforeDml,Limits.getDmlStatements(),'Preview must perform no DML.');
        System.assertEquals(5,result.sampleCount);
        Set<Id> eligible=new Map<Id,Contact>([SELECT Id FROM Contact WHERE Data_Masking_Complete__c=false]).keySet();
        Boolean sawRegex=false,sawNull=false;
        for(MaskingPreviewService.PreviewRow row:result.rows) {
            System.assert(eligible.contains((Id)row.recordId));
            if(row.fieldName=='OtherPostalCode'){sawRegex=true;System.assertEquals('2153',row.beforeValue);System.assertEquals('XXXX',row.afterValue);}
            if(row.fieldName=='Email'){sawNull=true;System.assertEquals('(NULL)',row.afterValue);}
        }
        System.assert(sawRegex&&sawNull);
        System.assertEquals(7,[SELECT count() FROM Contact WHERE OtherPostalCode='2153' AND Email='private@example.com']);
        System.assertEquals(1,[SELECT count() FROM Contact WHERE Data_Masking_Complete__c=true]);
        System.assertEquals(0,[SELECT count() FROM Masking_Job_Run__c]);
    }
    @IsTest static void rejectsObjectOutsideJob() {
        Boolean blocked=false;
        try{MaskingPreviewService.preview(jobId(),'Lead');}catch(AuraHandledException ex){blocked=true;}
        System.assert(blocked);
    }
    @IsTest static void showsUnchangedValues() {
        Masking_Field_Config__c cfg=[SELECT Id,Masking_Pattern__c FROM Masking_Field_Config__c WHERE Field_API_Name__c='OtherPostalCode'];cfg.Masking_Pattern__c='[A-Z]=>X';update cfg;
        MaskingPreviewService.PreviewResult result=MaskingPreviewService.preview(jobId(),'Contact');
        Boolean found=false;
        for(MaskingPreviewService.PreviewRow row:result.rows)if(row.fieldName=='OtherPostalCode'){found=true;System.assert(row.outcome.startsWith('Unchanged'));}
        System.assert(found);
    }
    @IsTest static void fullModeIncludesFlaggedRecords() {
        Masking_Job__c job=[SELECT Id,Run_Mode__c FROM Masking_Job__c LIMIT 1];job.Run_Mode__c='Full';update job;
        List<Contact> people=[SELECT Id,Data_Masking_Complete__c FROM Contact];for(Contact person:people)person.Data_Masking_Complete__c=true;update people;
        System.assertEquals(5,MaskingPreviewService.preview(job.Id,'Contact').sampleCount);
    }
    @IsTest static void noEligibleRecordsReturnsEmptySample() {
        List<Contact> people=[SELECT Id,Data_Masking_Complete__c FROM Contact];for(Contact person:people)person.Data_Masking_Complete__c=true;update people;
        MaskingPreviewService.PreviewResult result=MaskingPreviewService.preview(jobId(),'Contact');
        System.assertEquals(0,result.sampleCount);System.assert(result.rows.isEmpty());
    }
}
