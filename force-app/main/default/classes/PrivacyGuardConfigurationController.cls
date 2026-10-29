/**
 * @class PrivacyGuardConfigurationController
 * @description Governed configuration API for PrivacyGuard masking scope and subscriber PII keywords.
 * @package PrivacyGuard
 * @namespace privacyguard
 * @apiVersion 66.0
 * @owner PrivacyGuard Engineering
 * @changeControl Peer review, approved work item, automated tests and managed-package promotion required.
 * CHANGE HISTORY
 * 1.4.0 2026-09-17 PG-CONFIG-001 PrivacyGuard Engineering Added expandable masking configuration workspace and subscriber keyword administration.
 * 1.4.1 2026-09-17 PG-CONFIG-002 PrivacyGuard Engineering Added governed configuration removal and refreshed configuration workspace UX.
 * 1.4.2 2026-09-17 PG-CONFIG-003 PrivacyGuard Engineering Made PII acceptance tolerant of fields that cannot safely be masked; ineligible fields are skipped without blocking review approval.
 * 1.4.3 2026-09-17 PG-CONFIG-004 PrivacyGuard Engineering Made configuration reads non-cacheable so add/remove/save mutations render immediately without a browser refresh.
 * 1.4.5 2026-09-17 PG-KEYWORD-005 PrivacyGuard Engineering Added duplicate-safe keyword creation, immediate activation/rendering, and governed delete/exclusion for defaults and org keywords.
 */
public with sharing class PrivacyGuardConfigurationController {
    private static void auth() { PrivacyGuardSecurityService.requirePiiPermission(); }

    public class OptionRow { @AuraEnabled public String label {get;set;} @AuraEnabled public String value {get;set;} public OptionRow(String l,String v){label=l;value=v;} }
    public class FieldRow {
        @AuraEnabled public Id id {get;set;} @AuraEnabled public String objectApiName {get;set;} @AuraEnabled public String fieldApiName {get;set;}
        @AuraEnabled public String fieldLabel {get;set;} @AuraEnabled public String fieldType {get;set;} @AuraEnabled public Boolean unsupported {get;set;} @AuraEnabled public String unsupportedReason {get;set;} @AuraEnabled public String strategy {get;set;}
        @AuraEnabled public String pattern {get;set;} @AuraEnabled public Boolean active {get;set;} @AuraEnabled public String source {get;set;}
    }
    public class KeywordRow { @AuraEnabled public Id id {get;set;} @AuraEnabled public String keyword {get;set;} @AuraEnabled public Boolean active {get;set;} @AuraEnabled public String notes {get;set;} @AuraEnabled public String source {get;set;} @AuraEnabled public Boolean editable {get;set;} @AuraEnabled public String key {get;set;} }

    @AuraEnabled(cacheable=true) public static List<OptionRow> getObjects() {
        auth(); List<OptionRow> out=new List<OptionRow>();
        Map<String, Schema.SObjectType> objectTypes = Schema.getGlobalDescribe();
        for (Schema.SObjectType token : objectTypes.values()) {
            Schema.DescribeSObjectResult d = token.getDescribe();
            if (d.isQueryable() && !d.isDeprecatedAndHidden()) {
                out.add(new OptionRow(d.getLabel()+' ('+d.getName()+')', d.getName()));
            }
        }
        return out;
    }
    @AuraEnabled(cacheable=true) public static List<OptionRow> getEligibleFields(String objectApiName) {
        auth(); List<OptionRow> out=new List<OptionRow>(); if(String.isBlank(objectApiName)) return out;
        Schema.SObjectType t=Schema.getGlobalDescribe().get(objectApiName); if(t==null) throw client('Unknown object.');
        for(Schema.SObjectField f:t.getDescribe().fields.getMap().values()) { Schema.DescribeFieldResult d=f.getDescribe();
            if(d.isUpdateable() && !d.isCalculated() && !d.isAutoNumber()) out.add(new OptionRow(d.getLabel()+' · '+String.valueOf(d.getType())+' ('+d.getName()+')',d.getName())); }
        return out;
    }
    @AuraEnabled public static List<FieldRow> getConfigurations() {
        auth(); List<FieldRow> out=new List<FieldRow>();
        for(Masking_Field_Config__c c:[SELECT Id,Object_API_Name__c,Field_API_Name__c,Field_Label__c,Salesforce_Field_Type__c,Masking_Strategy__c,Masking_Pattern__c,Is_Active__c,Configuration_Source__c FROM Masking_Field_Config__c WITH SECURITY_ENFORCED ORDER BY Object_API_Name__c,Field_API_Name__c]) { FieldRow r=new FieldRow(); r.id=c.Id;r.objectApiName=c.Object_API_Name__c;r.fieldApiName=c.Field_API_Name__c;r.fieldLabel=c.Field_Label__c;r.fieldType=c.Salesforce_Field_Type__c;r.strategy=c.Masking_Strategy__c;r.pattern=c.Masking_Pattern__c;r.active=c.Is_Active__c;r.source=c.Configuration_Source__c;
            String savedType = String.valueOf(c.Salesforce_Field_Type__c).toUpperCase();
            r.unsupported = savedType == 'PICKLIST' || savedType == 'MULTIPICKLIST';
            r.unsupportedReason = r.unsupported ? 'Picklist fields are not supported for masking. Values remain unchanged.' : null;
            Schema.SObjectType objToken = Schema.getGlobalDescribe().get(c.Object_API_Name__c);
            if (objToken != null) {
                Schema.SObjectField fieldToken = PrivacyGuardSchema.fields(objToken.getDescribe()).get(c.Field_API_Name__c);
                if (fieldToken != null) {
                    Schema.DescribeFieldResult fieldInfo = fieldToken.getDescribe();
                    if (fieldInfo.isCalculated()) { r.unsupported = true; r.unsupportedReason = 'Formula fields are calculated by Salesforce. Mask the underlying source fields instead.'; }
                }
            }
            out.add(r); }
        return out;
    }
    @AuraEnabled public static void saveConfigurations(List<FieldRow> rows) {
        auth(); if(rows==null||rows.isEmpty()) throw client('No configuration rows received. Refresh the page and try again.'); Map<String,Masking_Field_Config__c> existing=new Map<String,Masking_Field_Config__c>();
        for(Masking_Field_Config__c c:[SELECT Id,Object_API_Name__c,Field_API_Name__c FROM Masking_Field_Config__c]) existing.put((c.Object_API_Name__c+'.'+c.Field_API_Name__c).toLowerCase(),c);
        List<Masking_Field_Config__c> saves=new List<Masking_Field_Config__c>();
        for(FieldRow r:rows){ if(r==null||String.isBlank(r.objectApiName)||String.isBlank(r.fieldApiName)) throw client('Configuration object or field is missing. Refresh the page and try again.'); if(r.strategy!=null) r.strategy=r.strategy.trim().toUpperCase(); Schema.SObjectType t=Schema.getGlobalDescribe().get(r.objectApiName); if(t==null) throw client('Unknown object '+r.objectApiName); Schema.SObjectField ft=PrivacyGuardSchema.field(t.getDescribe(),r.fieldApiName); if(ft==null) throw client('Unknown field '+r.fieldApiName); Schema.DescribeFieldResult d=ft.getDescribe(); if(d.isCalculated() || d.getType()==Schema.DisplayType.PICKLIST || d.getType()==Schema.DisplayType.MULTIPICKLIST) { if(existing.containsKey((r.objectApiName+'.'+r.fieldApiName).toLowerCase())) continue; throw client('This field type is not supported for masking: '+r.fieldApiName); } if(!SchemaValidationUtil.isSupportedMaskingField(d)) throw client('Field '+r.fieldApiName+' ('+d.getType()+') is not supported for masking.'); if(r.active==true&&String.isBlank(r.strategy)) throw client('Select a masking strategy before activating '+r.fieldApiName+'.'); validateStrategyForField(d, r.strategy, r.fieldApiName); if ('NUMBER_RANGE'.equalsIgnoreCase(r.strategy)) { try { NumericRangeMaskStrategy.validateRange(d,r.pattern); } catch(Exception ex) { throw client(r.objectApiName+'.'+r.fieldApiName+': '+ex.getMessage()); } } if ('LIST'.equalsIgnoreCase(r.strategy)) { try { ListMaskStrategy.validateValues(d,r.pattern); } catch(Exception ex) { throw client(r.objectApiName+'.'+r.fieldApiName+': '+ex.getMessage()); } } if ('NULL'.equalsIgnoreCase(r.strategy)) r.pattern=null; validateStaticPattern(d, r); if ('REGEX'.equalsIgnoreCase(r.strategy)) { try { RegexReplaceMaskStrategy.validateRule(r.pattern); } catch (Exception ex) { throw client(r.objectApiName+'.'+r.fieldApiName+': '+ex.getMessage()); } } String key=(r.objectApiName+'.'+r.fieldApiName).toLowerCase(); Masking_Field_Config__c c=existing.get(key); if(c==null)c=new Masking_Field_Config__c(); c.Object_API_Name__c=t.getDescribe().getName();c.Field_API_Name__c=d.getName();c.Field_Label__c=d.getLabel();c.Salesforce_Field_Type__c=String.valueOf(d.getType());c.Masking_Strategy__c=r.strategy;c.Masking_Pattern__c=r.pattern;c.Is_Active__c=r.active==true;c.Configuration_Source__c=String.isBlank(r.source)?'Manual':r.source;saves.add(c); }
        List<Masking_Field_Config__c> inserts=new List<Masking_Field_Config__c>(); List<Masking_Field_Config__c> updates=new List<Masking_Field_Config__c>(); for(Masking_Field_Config__c c:saves){if(c.Id==null)inserts.add(c);else updates.add(c);} if(!inserts.isEmpty()){SObjectAccessDecision d=Security.stripInaccessible(AccessType.CREATABLE,inserts);insert d.getRecords();} if(!updates.isEmpty()){SObjectAccessDecision d=Security.stripInaccessible(AccessType.UPDATABLE,updates);update d.getRecords();}
    }
    /**
     * Adds accepted discovery candidates to masking configuration without allowing a
     * single non-maskable field to fail the administrator's Accept action.
     *
     * A field is added only when it exists and is updateable, non-calculated and
     * non-auto-number for the running administrator. Skipped findings remain Accepted
     * in PII discovery and therefore retain their governance/audit decision.
     */
    public static Integer saveAcceptedConfigurations(List<FieldRow> rows) {
        auth();
        if (rows == null || rows.isEmpty()) return 0;

        Map<String, Masking_Field_Config__c> existing = new Map<String, Masking_Field_Config__c>();
        for (Masking_Field_Config__c c : [SELECT Id, Object_API_Name__c, Field_API_Name__c FROM Masking_Field_Config__c]) {
            existing.put((c.Object_API_Name__c + '.' + c.Field_API_Name__c).toLowerCase(), c);
        }

        List<Masking_Field_Config__c> inserts = new List<Masking_Field_Config__c>();
        Set<String> processed = new Set<String>();
        for (FieldRow r : rows) {
            if (r == null || String.isBlank(r.objectApiName) || String.isBlank(r.fieldApiName)) continue;
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(r.objectApiName);
            if (objectType == null) continue;
            Schema.SObjectField fieldToken = PrivacyGuardSchema.field(objectType.getDescribe(),r.fieldApiName);
            if (fieldToken == null) continue;

            Schema.DescribeFieldResult d = fieldToken.getDescribe();
            if (!SchemaValidationUtil.isSupportedMaskingField(d)) continue;

            String objectName = objectType.getDescribe().getName();
            String fieldName = d.getName();
            String key = (objectName + '.' + fieldName).toLowerCase();
            if (processed.contains(key) || existing.containsKey(key)) continue;
            processed.add(key);

            inserts.add(new Masking_Field_Config__c(
                Object_API_Name__c = objectName,
                Field_API_Name__c = fieldName,
                Field_Label__c = d.getLabel(),
                Salesforce_Field_Type__c = String.valueOf(d.getType()),
                Masking_Strategy__c = null,
                Masking_Pattern__c = null,
                Is_Active__c = false,
                Configuration_Source__c = 'PII Discovery'
            ));
        }

        if (!inserts.isEmpty()) {
            SObjectAccessDecision accessDecision = Security.stripInaccessible(AccessType.CREATABLE, inserts);
            List<SObject> permitted = accessDecision.getRecords();
            if (!permitted.isEmpty()) insert permitted;
        }
        return inserts.size();
    }

    private static void validateStrategyForField(Schema.DescribeFieldResult d, String strategy, String fieldApiName) {
        try {
            SchemaValidationUtil.validateMaskingStrategy(d, strategy);
        } catch (Exception ex) {
            throw client(ex.getMessage());
        }
    }

    /** Validate static replacements against the actual Salesforce field before saving. */
    private static void validateStaticPattern(Schema.DescribeFieldResult d, FieldRow row) {
        if (!'STATIC'.equalsIgnoreCase(row.strategy)) return;
        // Inactive drafts may omit a pattern, but supplied values must be valid.
        if (String.isBlank(row.pattern) && row.active != true) return;
        if (String.isBlank(row.pattern)) {
            throw client('Enter a static replacement value for ' + row.fieldApiName + '.');
        }
        try {
            SchemaValidationUtil.convertStaticMaskValue(d, row.pattern);
        } catch (Exception ex) {
            throw client('Invalid static replacement for ' + row.fieldApiName +
                ' (' + String.valueOf(d.getType()) + '): ' + ex.getMessage());
        }
    }

    @AuraEnabled public static void deleteConfigurations(List<Id> configurationIds) {
        auth();
        if (configurationIds == null || configurationIds.isEmpty()) return;
        List<Masking_Field_Config__c> rows = [SELECT Id FROM Masking_Field_Config__c WHERE Id IN :configurationIds];
        if (rows.isEmpty()) return;
        if (!Schema.sObjectType.Masking_Field_Config__c.isDeletable()) {
            throw client('You do not have permission to delete masking configurations.');
        }
        delete rows;
    }

    /** Import accepted PII fields without changing existing masking strategies or activation. */
    @AuraEnabled public static void importAccepted() {
        auth();
        List<FieldRow> rows = new List<FieldRow>();
        Set<String> seen = new Set<String>();
        for (PII_Scan_Result__c finding : [
            SELECT Object_API_Name__c, Field_API_Name__c
            FROM PII_Scan_Result__c
            WHERE Review_Status__c = 'Accepted'
            WITH SECURITY_ENFORCED
        ]) {
            if (String.isBlank(finding.Object_API_Name__c) || String.isBlank(finding.Field_API_Name__c)) continue;
            String key = (finding.Object_API_Name__c.trim() + '.' + finding.Field_API_Name__c.trim()).toLowerCase();
            if (!seen.add(key)) continue;
            FieldRow row = new FieldRow();
            row.objectApiName = finding.Object_API_Name__c;
            row.fieldApiName = finding.Field_API_Name__c;
            row.active = false;
            row.source = 'PII Discovery';
            rows.add(row);
        }
        saveAcceptedConfigurations(rows);
    }
    @AuraEnabled public static List<KeywordRow> getKeywords() {
        auth();
        List<KeywordRow> out = new List<KeywordRow>();
        Map<String, PII_Keyword_Config__c> overrides = new Map<String, PII_Keyword_Config__c>();
        for (PII_Keyword_Config__c k : [SELECT Id, Keyword__c, Is_Active__c, Notes__c FROM PII_Keyword_Config__c WITH SECURITY_ENFORCED ORDER BY Keyword__c]) {
            if (String.isNotBlank(k.Keyword__c)) overrides.put(normalizeKeyword(k.Keyword__c), k);
        }
        for (PII_Keyword__mdt k : [SELECT Keyword__c FROM PII_Keyword__mdt ORDER BY Keyword__c]) {
            if (String.isBlank(k.Keyword__c)) continue;
            PII_Keyword_Config__c overrideRow = overrides.get(normalizeKeyword(k.Keyword__c));
            // An inactive org override is the governed subscriber-level "delete" for a packaged default.
            if (overrideRow != null && overrideRow.Is_Active__c == false) continue;
            KeywordRow r = new KeywordRow();
            r.keyword = k.Keyword__c; r.active = true; r.source = 'PrivacyGuard Default'; r.editable = false; r.key = 'default-' + k.Keyword__c;
            out.add(r);
            if (overrideRow != null) overrides.remove(normalizeKeyword(k.Keyword__c));
        }
        for (PII_Keyword_Config__c k : overrides.values()) {
            if (k.Is_Active__c == false) continue;
            KeywordRow r = new KeywordRow();
            r.id=k.Id; r.keyword=k.Keyword__c; r.active=k.Is_Active__c; r.notes=k.Notes__c; r.source='Org Keyword'; r.editable=true; r.key=String.valueOf(k.Id);
            out.add(r);
        }
        return out;
    }

    @AuraEnabled public static void saveKeyword(Id id, String keyword, Boolean active, String notes) {
        auth();
        if (String.isBlank(keyword)) throw client('Keyword is required.');
        String cleaned = keyword.trim();
        String normalized = normalizeKeyword(cleaned);
        for (PII_Keyword__mdt d : [SELECT Keyword__c FROM PII_Keyword__mdt]) {
            if (normalizeKeyword(d.Keyword__c) == normalized) throw client('Keyword "' + cleaned + '" already exists.');
        }
        for (PII_Keyword_Config__c e : [SELECT Id, Keyword__c FROM PII_Keyword_Config__c]) {
            if (e.Id != id && normalizeKeyword(e.Keyword__c) == normalized) throw client('Keyword "' + cleaned + '" already exists.');
        }
        PII_Keyword_Config__c k = id == null ? new PII_Keyword_Config__c() : new PII_Keyword_Config__c(Id=id);
        k.Keyword__c=cleaned; k.Is_Active__c=active != false; k.Notes__c=notes;
        SObjectAccessDecision d=Security.stripInaccessible(id==null?AccessType.CREATABLE:AccessType.UPDATABLE,new List<PII_Keyword_Config__c>{k});
        if(id==null) insert d.getRecords(); else update d.getRecords();
    }

    @AuraEnabled public static void deleteKeyword(Id id, String keyword, Boolean packagedDefault) {
        auth();
        if (packagedDefault == true) {
            if (String.isBlank(keyword)) throw client('Keyword is required.');
            String normalized = normalizeKeyword(keyword);
            for (PII_Keyword_Config__c existing : [SELECT Id, Keyword__c, Is_Active__c FROM PII_Keyword_Config__c]) {
                if (normalizeKeyword(existing.Keyword__c) == normalized) {
                    existing.Is_Active__c = false;
                    SObjectAccessDecision u = Security.stripInaccessible(AccessType.UPDATABLE, new List<PII_Keyword_Config__c>{existing});
                    update u.getRecords();
                    return;
                }
            }
            PII_Keyword_Config__c exclusion = new PII_Keyword_Config__c(Keyword__c=keyword.trim(), Is_Active__c=false, Notes__c='Excluded packaged default');
            SObjectAccessDecision c = Security.stripInaccessible(AccessType.CREATABLE, new List<PII_Keyword_Config__c>{exclusion});
            insert c.getRecords();
            return;
        }
        if (id == null) throw client('Keyword record is required.');
        if (!Schema.sObjectType.PII_Keyword_Config__c.isDeletable()) throw client('You do not have permission to delete PII keywords.');
        List<PII_Keyword_Config__c> rows = [SELECT Id FROM PII_Keyword_Config__c WHERE Id=:id LIMIT 1];
        if (!rows.isEmpty()) delete rows;
    }

    private static String normalizeKeyword(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase().replaceAll('[_\\-\\s]+','_');
    }
    private static AuraHandledException client(String m){AuraHandledException e=new AuraHandledException(m);e.setMessage(m);return e;}
}
