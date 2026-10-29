/** Resolve actual schema names without accepting arbitrary foreign namespaces. */
public with sharing class PrivacyGuardSchema {
    public static String namespacePrefix() {
        String api=Masking_Field_Config__c.SObjectType.getDescribe().getName();
        String local='Masking_Field_Config__c';
        return api.endsWith(local)?api.substring(0,api.length()-local.length()):'';
    }
    public static Map<String,Schema.SObjectField> fields(Schema.DescribeSObjectResult objectInfo) {
        Map<String,Schema.SObjectField> result=new Map<String,Schema.SObjectField>();
        result.putAll(objectInfo.fields.getMap());
        String prefix=namespacePrefix();
        List<Schema.SObjectField> tokens=new List<Schema.SObjectField>(result.values());
        for(Schema.SObjectField token:tokens) {
            String actual=token.getDescribe().getName();result.put(actual,token);result.put(actual.toLowerCase(),token);
            if(prefix!='' && actual.toLowerCase().startsWith(prefix.toLowerCase())) {
                String local=actual.substring(prefix.length());
                if(!result.containsKey(local)){result.put(local,token);result.put(local.toLowerCase(),token);}
            }
        }
        return result;
    }
    public static Schema.SObjectField field(Schema.DescribeSObjectResult objectInfo,String name) {
        if(String.isBlank(name))return null;
        Map<String,Schema.SObjectField> tokens=fields(objectInfo);
        Schema.SObjectField token=tokens.get(name.trim());
        return token==null?tokens.get(name.trim().toLowerCase()):token;
    }
    public static String name(Schema.DescribeSObjectResult objectInfo,String requested) {
        Schema.SObjectField token=field(objectInfo,requested);
        if(token==null)throw new SchemaValidationUtil.InvalidSchemaReferenceException('Unknown field API name: '+requested+' on '+objectInfo.getName());
        return token.getDescribe().getName();
    }
    /** Only schema identifiers are substituted; query values must continue to use binds. */
    public static String qualifyQuery(Schema.SObjectType objectType,String queryText) {
        String prefix=namespacePrefix();if(prefix=='')return queryText;
        for(Schema.SObjectField token:objectType.getDescribe().fields.getMap().values()) {
            String actual=token.getDescribe().getName();
            if(actual.toLowerCase().startsWith(prefix.toLowerCase())) {
                String local=actual.substring(prefix.length());
                queryText=queryText.replaceAll('\\b'+local+'\\b',actual);
            }
        }
        return queryText;
    }
}
