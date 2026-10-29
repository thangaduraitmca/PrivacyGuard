@IsTest
private class PrivacyGuardAuditTest {
    @TestSetup static void packagePermissions() { PrivacyGuardPackageTestAccess.grantAdmin(); }

    private static PrivacyGuardAuditController.AuditPage page(String category) {
        return PrivacyGuardAuditController.load(category,'All',null,null,Date.today().addDays(-1),Date.today().addDays(1),null,null,null);
    }
    @IsTest static void fieldLifecycleCapturesActorAndRedactsPatterns() {
        Masking_Field_Config__c config=new Masking_Field_Config__c(Object_API_Name__c='Contact',Field_API_Name__c='Email',Masking_Strategy__c='STATIC',Masking_Pattern__c='secret@example.invalid',Is_Active__c=true);
        insert config;
        config.Is_Active__c=false;update config;delete config;undelete config;
        String configId=String.valueOf(config.Id);
        List<Masking_Log__c> logs=[SELECT CreatedById,Activity_Action__c,Change_Details__c FROM Masking_Log__c WHERE Record_Id__c=:configId];
        System.assertEquals(4,logs.size());Set<String> actions=new Set<String>();
        for(Masking_Log__c log:logs){actions.add(log.Activity_Action__c);System.assertEquals(UserInfo.getUserId(),log.CreatedById);System.assert(!log.Change_Details__c.contains('secret@example.invalid'));}
        System.assertEquals(new Set<String>{'Created','Updated','Deleted','Restored'},actions);
        System.assertEquals(4,page('Configuration').rows.size());
    }
    @IsTest static void jobAndObjectUpdatesAreTrackedWithoutRuntimeNoise() {
        Masking_Job__c job=new Masking_Job__c(Job_Name__c='Audit test',Run_Mode__c='Full',Execution_Mode__c='Serial',Batch_Size__c=100,Is_Active__c=true);insert job;
        job.Last_Status__c='Running';update job;
        System.assertEquals(1,[SELECT COUNT() FROM Masking_Log__c WHERE Activity_Category__c='Jobs']);
        job.Batch_Size__c=200;update job;
        Masking_Job_Object__c child=new Masking_Job_Object__c(Masking_Job__c=job.Id,Object_API_Name__c='Contact',Sequence__c=1,Is_Active__c=true);insert child;
        child.Sequence__c=2;update child;delete child;
        System.assertEquals(5,[SELECT COUNT() FROM Masking_Log__c WHERE Activity_Category__c='Jobs']);
    }
    @IsTest static void captureIsBulkSafe() {
        List<Masking_Field_Config__c> configs=new List<Masking_Field_Config__c>();
        for(Integer i=0;i<200;i++)configs.add(new Masking_Field_Config__c(Object_API_Name__c='Contact',Field_API_Name__c='Field'+i+'__c',Masking_Strategy__c='STATIC',Is_Active__c=true));
        Test.startTest();insert configs;Test.stopTest();
        System.assertEquals(200,[SELECT COUNT() FROM Masking_Log__c WHERE Activity_Category__c='Configuration']);
    }
    @IsTest static void filtersLegacyClassificationAndPagination() {
        List<Masking_Log__c> logs=new List<Masking_Log__c>();
        for(Integer i=0;i<105;i++)logs.add(new Masking_Log__c(Job_Name__c='PIIFieldScannerBatch',Status__c='Success',Error_Message__c='Scan '+i));
        logs.add(new Masking_Log__c(Job_Name__c='AutomationTriggerToggleQueueable',Status__c='Failed',Error_Message__c='Failed trigger'));
        logs.add(new Masking_Log__c(Job_Name__c='Selected_File_Deletion',Status__c='Success',Error_Message__c='Deleted'));
        logs.add(new Masking_Log__c(Job_Name__c='Customer_Masking',Status__c='Success',Error_Message__c='Masked'));insert logs;
        Test.startTest();
        PrivacyGuardAuditController.AuditPage first=page('PII Discovery');
        PrivacyGuardAuditController.AuditPage second=PrivacyGuardAuditController.load('PII Discovery','All',null,null,Date.today().addDays(-1),Date.today().addDays(1),first.nextTime,first.nextId,first.cutoff);
        System.assertEquals(100,first.rows.size());System.assert(first.hasMore);System.assertEquals(5,second.rows.size());
        Set<Id> seen=new Set<Id>();for(PrivacyGuardAuditController.Row row:first.rows)System.assert(seen.add(row.id));for(PrivacyGuardAuditController.Row row:second.rows)System.assert(seen.add(row.id));
        System.assertEquals(1,page('Automation').rows.size());
        System.assertEquals(1,page('Files').rows.size());
        System.assertEquals(1,page('Data Masking').rows.size());
        PrivacyGuardAuditController.Row detail=PrivacyGuardAuditController.detail(first.rows[0].id);System.assert(detail.message.startsWith('Scan'));System.assertEquals('Inferred from legacy source',detail.classification);
        Test.stopTest();
    }
    @IsTest static void invalidFiltersAndAuditTriggerProtection() {
        Integer denied=0;
        try{page('Unsafe');}catch(AuraHandledException ex){denied++;}
        try{PrivacyGuardAuditController.load('All','All',null,null,Date.today(),Date.today().addDays(-1),null,null,null);}catch(AuraHandledException ex){denied++;}
        System.assertEquals(2,denied);
        System.assert(PrivacyGuardAuditService.isProtectedTrigger('PGAuditMaskingFieldConfig'));
        System.assert(!PrivacyGuardAuditService.isProtectedTrigger('CustomerTrigger'));
    }
    @IsTest static void unauthorizedReaderIsRejected() {
        Profile profile=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User viewer=new User(Alias='pgaudit',Email='audit@example.invalid',EmailEncodingKey='UTF-8',LastName='Audit viewer',LanguageLocaleKey='en_US',LocaleSidKey='en_AU',TimeZoneSidKey='Australia/Sydney',ProfileId=profile.Id,Username='pg-audit-'+UserInfo.getOrganizationId()+'-'+String.valueOf(System.now().getTime())+'@example.invalid');insert viewer;
        System.runAs(viewer){PrivacyGuardSecurityService.bypassPermissionChecksForTests=false;Integer denied=0;
            try{page('All');}catch(AuraHandledException ex){denied++;}
            try{PrivacyGuardAuditController.detail(null);}catch(AuraHandledException ex){denied++;}
            System.assertEquals(2,denied);
        }
    }
}
