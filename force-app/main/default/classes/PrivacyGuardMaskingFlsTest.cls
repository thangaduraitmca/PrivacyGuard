/**
 * Proves that MaskingBatch enforces object and field update access for the running
 * user. Record sharing is still bypassed by design; only CRUD/FLS is enforced.
 *  - No edit access to the object or completion checkbox: the chunk is rejected
 *    before any record is changed.
 *  - Edit access to the checkbox but not to a target field: that record is skipped,
 *    logged as Failed and not marked complete.
 */
@IsTest
private class PrivacyGuardMaskingFlsTest {

    private static MaskingConfigService.FieldConfig staticField(String apiName, String value) {
        MaskingConfigService.FieldConfig f = new MaskingConfigService.FieldConfig();
        f.objectApiName = 'Contact';
        f.fieldApiName = apiName;
        f.fieldType = 'STATIC';
        f.maskingPattern = value;
        return f;
    }

    private static User newUser(String profileName, String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        String login = 'pg-' + alias + '-' + String.valueOf(DateTime.now().getTime()) + '@example.invalid';
        return new User(Alias = alias, Email = login, EmailEncodingKey = 'UTF-8',
            LastName = 'FLS Test', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles', UserName = login);
    }

    /** Contact read/edit plus edit on the completion checkbox only (no access to Email). */
    private static User userWhoCanEditCheckboxButNotEmail() {
        User u = newUser('Minimum Access - Salesforce', 'pgfls1');
        // Setup objects are inserted as the current user to avoid mixed DML with test data.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            PermissionSet ps = new PermissionSet(Name = 'PG_FLS_Test_' + String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
                Label = 'PG FLS Test');
            insert ps;
            insert new ObjectPermissions(ParentId = ps.Id, SobjectType = 'Contact',
                PermissionsRead = true, PermissionsEdit = true);
            String checkboxName = Schema.SObjectType.Contact.fields.Data_Masking_Complete__c.getName();
            insert new FieldPermissions(ParentId = ps.Id, SobjectType = 'Contact',
                Field = 'Contact.' + checkboxName, PermissionsRead = true, PermissionsEdit = true);
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static SObject loadContact(Id contactId) {
        return [SELECT Id, LastName, Email, Data_Masking_Complete__c FROM Contact WHERE Id = :contactId];
    }

    @IsTest
    static void fieldWithoutEditAccessIsSkippedAndLogged() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact person = new Contact(LastName = 'Original', Email = 'original@example.com');
        insert person;
        SObject loaded = loadContact(person.Id);
        User restricted = userWhoCanEditCheckboxButNotEmail();

        MaskingBatch batch = new MaskingBatch('FLS field enforcement', 'Contact',
            new List<MaskingConfigService.FieldConfig>{ staticField('Email', 'masked@example.invalid') },
            'Once', null);

        Test.startTest();
        System.runAs(restricted) {
            System.assertEquals(false, Schema.sObjectType.Contact.fields.Email.isUpdateable(),
                'Precondition: the test user must not be able to edit Contact.Email.');
            batch.execute(null, new List<SObject>{ loaded });
        }
        Test.stopTest();

        Contact result = [SELECT Email, Data_Masking_Complete__c FROM Contact WHERE Id = :person.Id];
        System.assertEquals('original@example.com', result.Email,
            'A field the running user cannot edit must not be masked.');
        System.assertEquals(false, result.Data_Masking_Complete__c,
            'A record that was not fully masked must not be marked complete.');
        System.assertEquals(1, batch.getFailedCount(), 'The record must be counted as failed.');

        List<Masking_Log__c> logs = [
            SELECT Status__c, Field_API_Name__c, Error_Message__c
            FROM Masking_Log__c WHERE Record_Id__c = :String.valueOf(person.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected one failure entry for the restricted field.');
        System.assertEquals('Failed', logs[0].Status__c);
        System.assertEquals('Email', logs[0].Field_API_Name__c);
        System.assert(!logs[0].Error_Message__c.contains('original@example.com'),
            'Failure logs must not contain the original field value.');
    }

    @IsTest
    static void noEditAccessToObjectRejectsChunkBeforeAnyChange() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact person = new Contact(LastName = 'Original', Email = 'original@example.com');
        insert person;
        SObject loaded = loadContact(person.Id);
        User readOnly = newUser('Minimum Access - Salesforce', 'pgfls2');

        MaskingBatch batch = new MaskingBatch('FLS object enforcement', 'Contact',
            new List<MaskingConfigService.FieldConfig>{ staticField('Email', 'masked@example.invalid') },
            'Once', null);

        Boolean rejected = false;
        Test.startTest();
        System.runAs(readOnly) {
            System.assertEquals(false, Schema.sObjectType.Contact.isUpdateable(),
                'Precondition: the test user must not be able to edit Contact.');
            try {
                batch.execute(null, new List<SObject>{ loaded });
            } catch (SchemaValidationUtil.InvalidSchemaReferenceException e) {
                rejected = true;
            }
        }
        Test.stopTest();

        System.assert(rejected, 'A user who cannot edit the completion checkbox must be rejected.');
        Contact result = [SELECT Email, Data_Masking_Complete__c FROM Contact WHERE Id = :person.Id];
        System.assertEquals('original@example.com', result.Email);
        System.assertEquals(false, result.Data_Masking_Complete__c);
    }

    @IsTest
    static void userWithEditAccessMasksAndMarksComplete() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;
        Contact person = new Contact(LastName = 'Original', Email = 'original@example.com');
        insert person;
        SObject loaded = loadContact(person.Id);

        MaskingBatch batch = new MaskingBatch('FLS positive control', 'Contact',
            new List<MaskingConfigService.FieldConfig>{ staticField('Email', 'masked@example.invalid') },
            'Once', null);

        Test.startTest();
        batch.execute(null, new List<SObject>{ loaded });
        Test.stopTest();

        Contact result = [SELECT Email, Data_Masking_Complete__c FROM Contact WHERE Id = :person.Id];
        System.assertEquals('masked@example.invalid', result.Email);
        System.assertEquals(true, result.Data_Masking_Complete__c);
        System.assertEquals(0, batch.getFailedCount());
    }
}
