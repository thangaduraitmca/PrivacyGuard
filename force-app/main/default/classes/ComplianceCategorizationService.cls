/** Native field classification lookup using Apex SOQL. No callouts or session IDs. */
public with sharing class ComplianceCategorizationService {
    public class ComplianceInfo {
        public String complianceGroup;
        public String securityClassification;
    }
    @TestVisible private static Map<String,Map<String,ComplianceInfo>> testTags;
    @TestVisible private static String testWarning;
    private static String lastWarning;
    public static String getLastWarning(){return lastWarning;}
    public static Map<String,ComplianceInfo> getComplianceTags(String objectApiName) {
        lastWarning=null;
        Map<String,ComplianceInfo> result=new Map<String,ComplianceInfo>();
        try {SchemaValidationUtil.requireValidObject(objectApiName);}
        catch(Exception ex){lastWarning='Classification metadata was not read: unknown object.';return result;}
        if(Test.isRunningTest() && testTags!=null && testTags.containsKey(objectApiName)) {
            lastWarning=testWarning;return testTags.get(objectApiName);
        }
        List<SObject> definitions;
        Boolean includeCompliance=true;
        try {
            definitions=Database.query('SELECT QualifiedApiName, ComplianceGroup, SecurityClassification FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = :objectApiName');
        } catch(Exception ex) {
            // Some org/API combinations expose sensitivity without ComplianceGroup.
            includeCompliance=false;
            try {
                definitions=Database.query('SELECT QualifiedApiName, SecurityClassification FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = :objectApiName');
                lastWarning='Compliance categories could not be read. Sensitivity, keyword and field-type checks were used.';
            } catch(Exception fallback) {
                lastWarning='Classification metadata could not be read. Only keyword and field-type checks were used.';
                return result;
            }
        }
        for(SObject definition:definitions) {
            ComplianceInfo info=new ComplianceInfo();
            info.complianceGroup=includeCompliance?(String)definition.get('ComplianceGroup'):null;
            info.securityClassification=(String)definition.get('SecurityClassification');
            if(String.isNotBlank(info.complianceGroup)||String.isNotBlank(info.securityClassification))
                result.put(((String)definition.get('QualifiedApiName')).toLowerCase(),info);
        }
        return result;
    }
    public static Boolean isSensitive(ComplianceInfo info) {
        if(info==null)return false;
        // Compliance tags identify review candidates, not proof that the field contains PII.
        if(String.isNotBlank(info.complianceGroup))return true;
        String sensitivity=String.isBlank(info.securityClassification)?'':info.securityClassification.toLowerCase().replaceAll('[ _-]','');
        return new Set<String>{'confidential','restricted','missioncritical','sensitive','pii'}.contains(sensitivity);
    }
    public static String describeTags(ComplianceInfo info) {
        if(info==null)return null;
        List<String> parts=new List<String>();
        if(String.isNotBlank(info.complianceGroup))parts.add('Compliance: '+info.complianceGroup);
        if(String.isNotBlank(info.securityClassification))parts.add('Sensitivity: '+info.securityClassification);
        String value=String.join(parts,' | ');
        return value.length()>255?value.substring(0,252)+'...':value;
    }
}
