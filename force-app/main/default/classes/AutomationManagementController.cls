/**
 * PrivacyGuard Apex Trigger discovery and controlled state changes.
 * Trigger changes are queued through AutomationTriggerToggleQueueable.
 */
public with sharing class AutomationManagementController {
    public class AutomationRow {
        @AuraEnabled public String key;
        @AuraEnabled public String componentId;
        @AuraEnabled public String type;
        @AuraEnabled public String name;
        @AuraEnabled public String objectName;
        @AuraEnabled public String state;
        @AuraEnabled public String detail;
        @AuraEnabled public Boolean selected;
        @AuraEnabled public Boolean readOnly;
        @AuraEnabled public String deploymentStatus;
        @AuraEnabled public String deploymentRequestId;
        @AuraEnabled public String deploymentMessage;
        @AuraEnabled public String deploymentTarget;
    }
    public class Summary {
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer active = 0;
        @AuraEnabled public Integer tracked = 0;
        @AuraEnabled public Boolean pending = false;
        @AuraEnabled public Boolean checkRequired = false;
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public List<AutomationRow> items = new List<AutomationRow>();
    }


    @AuraEnabled(cacheable=false)
    public static Summary discover() {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) throw new AuraHandledException('You do not have permission to manage automation metadata.');
        Summary out = new Summary();
        Map<String, Deactivated_Automation__c> tracked = new Map<String, Deactivated_Automation__c>();
        for (Deactivated_Automation__c d : [SELECT Component_Id__c, Component_Type__c, Reactivated__c FROM Deactivated_Automation__c WHERE Reactivated__c=false]) {
            tracked.put(d.Component_Type__c + ':' + d.Component_Id__c, d);
        }
        try { addTriggers(out, tracked); }
        catch (Exception ex) { out.warnings.add('Apex Trigger discovery unavailable: ' + safeDiscoveryError(ex)); }
        Map<String,Deactivated_Automation__c> latest = new Map<String,Deactivated_Automation__c>();
        for (Deactivated_Automation__c d : [SELECT Component_Id__c, Deployment_Status__c,
            Deployment_Request_Id__c, Deployment_Message__c, Deployment_Target__c FROM Deactivated_Automation__c
            WHERE Component_Type__c='APEX_TRIGGER' AND Deployment_Status__c != null ORDER BY CreatedDate DESC, Id DESC LIMIT 10000]) {
            if (!latest.containsKey(d.Component_Id__c)) latest.put(d.Component_Id__c,d);
        }
        for (AutomationRow row : out.items) {
            Deactivated_Automation__c d=latest.get(row.componentId);
            if (d == null) continue;
            row.deploymentStatus=d.Deployment_Status__c;
            row.deploymentRequestId=d.Deployment_Request_Id__c;
            row.deploymentMessage=d.Deployment_Message__c;
            row.deploymentTarget=d.Deployment_Target__c;
            Boolean pending=isPending(d.Deployment_Status__c);
            row.readOnly=row.readOnly || pending || d.Deployment_Status__c == 'Check required';
            out.pending=out.pending || pending;
            out.checkRequired=out.checkRequired || d.Deployment_Status__c == 'Check required';
        }
        out.total = out.items.size();
        out.tracked = 0;
        for (String key : tracked.keySet()) if (key.startsWith('APEX_TRIGGER:')) out.tracked++;
        for (AutomationRow r : out.items) if (r.state == 'Active') out.active++;
        return out;
    }

    private static void addTriggers(Summary out, Map<String, Deactivated_Automation__c> tracked) {
        // ApexTrigger supports native SOQL, so no self-callout or bearer token is needed.
        for (ApexTrigger t : [SELECT Id, Name, Status, TableEnumOrId, NamespacePrefix FROM ApexTrigger ORDER BY Name LIMIT 50000]) {
            AutomationRow r = new AutomationRow();
            r.componentId = String.valueOf(t.Id);
            r.type = 'APEX_TRIGGER';
            r.name = t.Name;
            r.state = String.valueOf(t.Status);
            r.objectName = String.valueOf(t.TableEnumOrId);
            r.readOnly = String.isNotBlank(t.NamespacePrefix);
            r.detail = r.readOnly ? 'Namespaced trigger: cannot be changed by PrivacyGuard.' : 'Apex Trigger';
            r.key = r.type + ':' + r.componentId;
            r.selected = false;
            out.items.add(r);
        }
    }

    @AuraEnabled
    public static String deactivateSelected(String selectionJson) {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) throw new AuraHandledException('You do not have permission to manage automation metadata.');
        assertSandbox();
        List<Object> rows=(List<Object>)JSON.deserializeUntyped(selectionJson);
        if(rows == null || rows.isEmpty()) throw new AuraHandledException('Select at least one Apex Trigger.');
        for (Object item : rows) {
            Map<String,Object> requested = (Map<String,Object>)item;
            if ((String)requested.get('type') != 'APEX_TRIGGER') {
                throw new AuraHandledException('Only Apex Trigger operations are supported.');
            }
        }
        String runId='AUTO-'+Datetime.now().formatGmt('yyyyMMddHHmmss')+'-'+Math.abs(Crypto.getRandomInteger());
        Integer queued=0;
        for (Object item : rows) {
            Map<String,Object> r=(Map<String,Object>)item;
            String id=(String)r.get('componentId');
            List<ApexTrigger> found=[SELECT Id, Name, Status, NamespacePrefix FROM ApexTrigger WHERE Id=:id LIMIT 1];
            if (found.isEmpty() || found[0].Status != 'Active') throw new AuraHandledException('Only active Apex Triggers can be deactivated. Rescan and try again.');
            ApexTrigger triggerRow=found[0];
            if(PrivacyGuardAuditService.isProtectedTrigger(triggerRow.Name)) throw new AuraHandledException('PrivacyGuard audit triggers cannot be deactivated through Automation Management.');
            if (String.isNotBlank(triggerRow.NamespacePrefix)) throw new AuraHandledException('Namespaced triggers cannot be changed by PrivacyGuard: '+triggerRow.Name);
            assertNoPendingDeployment(id);
            insertTrack(runId,'APEX_TRIGGER',id,triggerRow.Name,'Active');
            System.enqueueJob(new AutomationTriggerToggleQueueable(id,triggerRow.Name,runId,'Inactive'));
            queued++;
        }
        return queued+' Apex trigger deployment(s) queued. Scan again after processing to verify status.';
    }

    @AuraEnabled
    public static String restoreSelected(String selectionJson) {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) throw new AuraHandledException('You do not have permission to manage automation metadata.');
        assertSandbox();
        List<Object> rows=(List<Object>)JSON.deserializeUntyped(selectionJson);
        if(rows == null || rows.isEmpty()) throw new AuraHandledException('Select at least one Apex Trigger.');
        for (Object item : rows) {
            Map<String,Object> requested = (Map<String,Object>)item;
            if ((String)requested.get('type') != 'APEX_TRIGGER') {
                throw new AuraHandledException('Only Apex Trigger operations are supported.');
            }
        }
        Integer queued=0;
        for (Object item : rows) {
            Map<String,Object> r=(Map<String,Object>)item;
            String id=(String)r.get('componentId');
            List<ApexTrigger> found=[SELECT Id, Name, NamespacePrefix FROM ApexTrigger WHERE Id=:id LIMIT 1];
            if (found.isEmpty() || String.isNotBlank(found[0].NamespacePrefix)) throw new AuraHandledException('Namespaced or unavailable triggers cannot be changed by PrivacyGuard.');
            assertNoPendingDeployment(id);
            List<Deactivated_Automation__c> tracks=[SELECT Id,Run_Id__c,Component_Name__c,Original_State_Json__c FROM Deactivated_Automation__c WHERE Component_Id__c=:id AND Component_Type__c='APEX_TRIGGER' AND Reactivated__c=false ORDER BY CreatedDate DESC LIMIT 1];
            if (tracks.isEmpty()) continue;
            Deactivated_Automation__c t=tracks[0];
            t.Deployment_Status__c='Queued'; t.Deployment_Target__c='Active';
            t.Deployment_Request_Id__c=null; t.Deployment_Message__c='Waiting for submission to Salesforce.';
            update t;
            System.enqueueJob(new AutomationTriggerToggleQueueable(id,t.Component_Name__c,t.Run_Id__c,'Active'));
            queued++;
        }
        return queued+' Apex trigger restoration deployment(s) queued. Scan again after processing to verify status.';
    }
    @AuraEnabled
    public static String resumeDeploymentChecks() {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) throw new AuraHandledException('You do not have permission to manage automation metadata.');
        assertSandbox();
        List<Deactivated_Automation__c> checks=[SELECT Id,Component_Id__c,Component_Name__c,Run_Id__c,
            Deployment_Request_Id__c,Deployment_Target__c,Deployment_Status__c FROM Deactivated_Automation__c
            WHERE Component_Type__c='APEX_TRIGGER' AND Deployment_Status__c='Check required'
            AND Deployment_Request_Id__c != null LIMIT 20 FOR UPDATE];
        for (Deactivated_Automation__c d : checks) {
            d.Deployment_Status__c='In Progress';
            d.Deployment_Message__c='Checking the existing Salesforce deployment request.';
            System.enqueueJob(AutomationTriggerToggleQueueable.resume(d));
        }
        update checks;
        return checks.size() + ' deployment status check(s) queued. No new trigger deployments were submitted.';
    }
    private static Boolean isPending(String status) { return status == 'Queued' || status == 'In Progress'; }
    private static void assertNoPendingDeployment(String componentId) {
        for (Deactivated_Automation__c d : [SELECT Deployment_Status__c FROM Deactivated_Automation__c
            WHERE Component_Id__c=:componentId AND Component_Type__c='APEX_TRIGGER' AND
            Deployment_Status__c IN ('Queued','In Progress','Check required') LIMIT 1]) {
            throw new AuraHandledException('A trigger deployment is pending or needs a status check. Check its result before submitting another change.');
        }
    }
    private static void assertSandbox() {
        if (!EnvironmentSafetyService.isSandbox()) {
            AuraHandledException ex = new AuraHandledException('PrivacyGuard trigger changes are allowed in sandboxes only.');
            ex.setMessage('PrivacyGuard trigger changes are allowed in sandboxes only.');
            throw ex;
        }
    }
    private static String safeDiscoveryError(Exception ex) {
        return ex == null ? 'Unknown discovery error' : ex.getMessage();
    }

    private static void insertTrack(String runId,String type,String id,String name,String original){ insert new Deactivated_Automation__c(Run_Id__c=runId,Component_Type__c=type,Component_Id__c=id,Component_Name__c=name,Original_State_Json__c=original,Reactivated__c=false,
        Deployment_Status__c='Queued',Deployment_Target__c='Inactive',Deployment_Message__c='Waiting for submission to Salesforce.' ); }
}
