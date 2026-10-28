/** Resolves and validates per-object masking completion checkboxes. */
public with sharing class MaskingCompletionService {
    public static String requireCheckbox(String objectApiName, String configuredField) {
        Schema.DescribeSObjectResult obj = SchemaValidationUtil.requireValidObject(objectApiName);
        Map<String, Schema.SObjectField> fields = obj.fields.getMap();
        String fieldName = configuredField;
        if (String.isBlank(fieldName)) {
            String packagedName = Contact.Data_Masking_Complete__c.getDescribe().getName();
            if (fields.containsKey(packagedName)) fieldName = packagedName;
            else fieldName = 'Data_Masking_Complete__c';
        }
        SchemaValidationUtil.requireValidField(obj, fieldName);
        Schema.DescribeFieldResult flag = fields.get(fieldName).getDescribe();
        if (flag.getType() != Schema.DisplayType.BOOLEAN || flag.isCalculated() || !flag.isUpdateable()) {
            throw new SchemaValidationUtil.InvalidSchemaReferenceException(
                objectApiName + '.' + fieldName + ' must be an editable Checkbox field.');
        }
        return flag.getName();
    }
    public static String configurationIssue(String objectApiName) {
        try { requireCheckbox(objectApiName, null); return null; }
        catch (Exception ex) { return objectApiName + ': deploy an editable Data_Masking_Complete__c checkbox (default false) before masking.'; }
    }
}
