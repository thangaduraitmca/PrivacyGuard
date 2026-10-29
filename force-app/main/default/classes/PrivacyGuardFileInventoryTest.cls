/** Inventory pagination, sharing metadata and read-only behaviour. */
@IsTest
private class PrivacyGuardFileInventoryTest {
    @TestSetup static void packagePermissions() { PrivacyGuardPackageTestAccess.grantAdmin(); }

    @IsTest static void filesPageWithoutDuplicatesAndIncludeUserUploads() {
        List<ContentVersion> versions=new List<ContentVersion>();
        for(Integer i=0;i<101;i++) versions.add(new ContentVersion(Title='Inventory '+i,PathOnClient='inventory'+i+'.txt',VersionData=Blob.valueOf('Synthetic test document')));
        insert versions;
        Account account=new Account(Name='Inventory linked account');insert account;
        Id linkedDocument=[SELECT ContentDocumentId FROM ContentVersion WHERE Id=:versions[0].Id].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId=linkedDocument,LinkedEntityId=account.Id,ShareType='V');
        Test.startTest();
        PrivacyGuardFileInventoryController.InventoryPage first=PrivacyGuardFileInventoryController.scanPage('Files',null,null);
        PrivacyGuardFileInventoryController.InventoryPage second=PrivacyGuardFileInventoryController.scanPage('Files',first.nextCursor,first.startedAt);
        Test.stopTest();
        System.assertEquals(100,first.rows.size());System.assertEquals(true,first.hasMore);
        System.assertEquals(1,second.rows.size());System.assertEquals(false,second.hasMore);
        Set<String> ids=new Set<String>();Boolean foundLinked=false;
        List<PrivacyGuardFileInventoryController.InventoryRow> allRows=new List<PrivacyGuardFileInventoryController.InventoryRow>();
        allRows.addAll(first.rows);allRows.addAll(second.rows);
        for(PrivacyGuardFileInventoryController.InventoryRow row:allRows) {
            System.assert(ids.add(row.id),'A document must appear only once.');
            System.assertEquals('Salesforce File',row.kind);System.assert(row.sizeBytes>0);
            if(row.id==String.valueOf(linkedDocument)) {
                foundLinked=true;System.assert(row.linkedRecords.contains(String.valueOf(account.Id)));
                System.assertEquals('Business-record link visible',row.relationshipStatus);
            }
        }
        System.assert(foundLinked);System.assertEquals(101,ids.size());
        System.assertEquals(101,[SELECT COUNT() FROM ContentDocument],'Scanning must not delete or create documents.');
    }
    @IsTest static void attachmentsHaveParentAndInventoryDoesNotReadBody() {
        Account account=new Account(Name='Legacy attachment account');insert account;
        insert new Attachment(ParentId=account.Id,Name='Legacy.txt',ContentType='text/plain',Body=Blob.valueOf('Synthetic legacy document'));
        Test.startTest();PrivacyGuardFileInventoryController.InventoryPage page=PrivacyGuardFileInventoryController.scanPage('Attachments',null,null);Test.stopTest();
        System.assertEquals(1,page.rows.size());System.assertEquals(false,page.hasMore);
        System.assertEquals('Legacy.txt',page.rows[0].title);
        System.assertEquals('Parent record linked',page.rows[0].relationshipStatus);
        System.assertEquals('Account:'+String.valueOf(account.Id),page.rows[0].linkedRecords);
        System.assertEquals(1,[SELECT COUNT() FROM Attachment]);
        System.assert(!JSON.serialize(page).contains('Synthetic legacy document'),'Document contents must never be returned.');
    }
    @IsTest static void invalidKindAndCursorAreRejected() {
        Integer rejected=0;
        try{PrivacyGuardFileInventoryController.scanPage('Delete',null,null);}catch(AuraHandledException ex){rejected++;}
        try{PrivacyGuardFileInventoryController.scanPage('Files',UserInfo.getUserId(),null);}catch(AuraHandledException ex){rejected++;}
        System.assertEquals(2,rejected);
    }
    @IsTest static void unprivilegedUserCannotInventory() {
        Profile standard=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User viewer=new User(Alias='pginv',Email='inventory@example.invalid',EmailEncodingKey='UTF-8',LastName='Inventory viewer',LanguageLocaleKey='en_US',LocaleSidKey='en_AU',TimeZoneSidKey='Australia/Sydney',ProfileId=standard.Id,Username='pg-inventory-'+UserInfo.getOrganizationId()+'-'+String.valueOf(System.now().getTime())+'@example.invalid');
        insert viewer;
        System.runAs(viewer) {
            PrivacyGuardSecurityService.bypassPermissionChecksForTests=false;
            Boolean rejected=false;
            try{PrivacyGuardFileInventoryController.scanPage('Files',null,null);}catch(AuraHandledException ex){rejected=true;}
            System.assert(rejected,'Inventory requires an explicit PrivacyGuard permission.');
        }
    }
    @IsTest static void selectedDeletionIsScopedAndAudited() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Account parent=new Account(Name='Deletion test'); insert parent;
        ContentVersion version=new ContentVersion(Title='Selected',PathOnClient='selected.txt',VersionData=Blob.valueOf('Synthetic'));insert version;
        Id doc=[SELECT ContentDocumentId FROM ContentVersion WHERE Id=:version.Id].ContentDocumentId;
        ContentVersion retainedVersion=new ContentVersion(Title='Retained file',PathOnClient='retained.txt',VersionData=Blob.valueOf('Synthetic'));insert retainedVersion;
        Id retainedDoc=[SELECT ContentDocumentId FROM ContentVersion WHERE Id=:retainedVersion.Id].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId=doc,LinkedEntityId=parent.Id,ShareType='V');
        Attachment selected=new Attachment(ParentId=parent.Id,Name='Selected.txt',Body=Blob.valueOf('Synthetic'));
        Attachment retained=new Attachment(ParentId=parent.Id,Name='Retained.txt',Body=Blob.valueOf('Synthetic'));insert new List<Attachment>{selected,retained};
        Test.startTest();
        List<PrivacyGuardFileInventoryController.DeleteOutcome> results=PrivacyGuardFileInventoryController.deleteSelected(new List<Id>{doc,selected.Id,doc},'DELETE');
        Test.stopTest();
        System.assertEquals(2,results.size(),'Duplicate IDs must be deduplicated.');
        for(PrivacyGuardFileInventoryController.DeleteOutcome result:results) System.assertEquals(true,result.success,result.message);
        System.assertEquals(0,[SELECT COUNT() FROM ContentDocument WHERE Id=:doc]);
        System.assertEquals(1,[SELECT COUNT() FROM ContentDocument WHERE Id=:retainedDoc]);
        System.assertEquals(1,[SELECT COUNT() FROM Attachment WHERE Id=:retained.Id]);
        System.assertEquals(0,[SELECT COUNT() FROM Attachment WHERE Id=:selected.Id]);
        System.assertEquals(2,[SELECT COUNT() FROM Masking_Log__c WHERE Job_Name__c='Selected_File_Deletion' AND Status__c='Success']);
    }
    @IsTest static void deletionRequiresSandboxConfirmationAndSupportedIds() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Integer rejected=0;
        try{PrivacyGuardFileInventoryController.deleteSelected(new List<Id>{UserInfo.getUserId()},'DELETE');}catch(AuraHandledException ex){rejected++;}
        try{PrivacyGuardFileInventoryController.deleteSelected(new List<Id>(),'DELETE');}catch(AuraHandledException ex){rejected++;}
        try{PrivacyGuardFileInventoryController.deleteSelected(new List<Id>{UserInfo.getUserId()},'NO');}catch(AuraHandledException ex){rejected++;}
        EnvironmentSafetyService.sandboxOverrideForTests=false;
        try{PrivacyGuardFileInventoryController.deleteSelected(new List<Id>{UserInfo.getUserId()},'DELETE');}catch(EnvironmentSafetyService.ProductionExecutionBlockedException ex){rejected++;}
        System.assertEquals(4,rejected);
    }
    @IsTest static void unavailableItemsReturnFailureAndAudit() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Account parent=new Account(Name='Missing file parent');insert parent;
        Attachment item=new Attachment(ParentId=parent.Id,Name='Missing.txt',Body=Blob.valueOf('Synthetic'));insert item;delete item;
        List<PrivacyGuardFileInventoryController.DeleteOutcome> result=PrivacyGuardFileInventoryController.deleteSelected(new List<Id>{item.Id},'DELETE');
        System.assertEquals(1,result.size());System.assertEquals(false,result[0].success);
        System.assertEquals(1,[SELECT COUNT() FROM Masking_Log__c WHERE Job_Name__c='Selected_File_Deletion' AND Status__c='Failed']);
    }
    @IsTest static void deletionRejectsMissingCustomPermission() {
        PrivacyGuardSecurityService.bypassPermissionChecksForTests=false;
        // Run as a fresh user without package permission assignments.
        Profile standard=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User viewer=new User(Alias='pgdel',Email='delete@example.invalid',EmailEncodingKey='UTF-8',LastName='Delete viewer',LanguageLocaleKey='en_US',LocaleSidKey='en_AU',TimeZoneSidKey='Australia/Sydney',ProfileId=standard.Id,Username='pg-delete-'+UserInfo.getOrganizationId()+'-'+String.valueOf(System.now().getTime())+'@example.invalid');insert viewer;
        System.runAs(viewer) {
            Boolean rejected=false;
            try{PrivacyGuardFileInventoryController.deleteSelected(new List<Id>{UserInfo.getUserId()},'DELETE');}catch(Exception ex){rejected=true;}
            System.assert(rejected,'Explicit purge permission is required.');
        }
    }
}
