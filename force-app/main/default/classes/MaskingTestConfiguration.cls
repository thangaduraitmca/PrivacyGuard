/** Test-owned runtime configuration. Shipped sample CMDT stays inactive. */
@IsTest
public class MaskingTestConfiguration {
    public static void createDefaults() {
        List<Masking_Field_Config__c> rows=new List<Masking_Field_Config__c>();
        add(rows,'Contact','LastName','MASKED_TEST_CONTACT');
        add(rows,'Contact','Email','masked.contact@example.invalid');
        add(rows,'Contact','Phone','000-000-0000');
        add(rows,'Lead','Company','MASKED_TEST_COMPANY');
        add(rows,'Lead','Email','masked.lead@example.invalid');
        add(rows,'Lead','Phone','000-000-0000');
        insert rows;
    }
    private static void add(List<Masking_Field_Config__c> rows,String objectName,String fieldName,String value) {
        rows.add(new Masking_Field_Config__c(Object_API_Name__c=objectName,Field_API_Name__c=fieldName,
            Masking_Strategy__c='STATIC',Masking_Pattern__c=value,Execution_Group__c=1,Is_Active__c=true));
    }
}
