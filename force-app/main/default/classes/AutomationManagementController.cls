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
        for (Deactivated_Automation__c d : [SELECT Component_Id__c, Component_Type__c, Reactivated__c FROM Deactivated_Automation__c WHERE Reactivated__c=false WITH USER_MODE ]) {
            tracked.put(d.Component_Type__c + ':' + d.Component_Id__c, d);
        }
        try { addTriggers(out, tracked); }
        catch (Exception ex) { out.warnings.add('Apex Trigger discovery unavailable: ' + safeDiscoveryError(ex)); }
        Map<String,Deactivated_Automation__c> latest = new Map<String,Deactivated_Automation__c>();
        for (Deactivated_Automation__c d : [SELECT Component_Id__c, Deployment_Status__c,
            Deployment_Request_Id__c, Deployment_Message__c, Deployment_Target__c FROM Deactivated_Automation__c
            WHERE Component_Type__c='APEX_TRIGGER' AND Deployment_Status__c != null WITH USER_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 10000]) {
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
        for (ApexTrigger t : [SELECT Id, Name, Status, TableEnumOrId, NamespacePrefix FROM ApexTrigger WITH USER_MODE ORDER BY Name LIMIT 50000]) {
            AutomationRow r = new AutomationRow();
            r.componentId = String.valueOf(t.Id);
            r.type = 'APEX_TRIGGER';
            r.name = t.Name;
            r.state = String.valueOf(t.Status);
            r.objectName = String.valueOf(t.TableEnumOrId);
            r.readOnly = String.isNotBlank(t.NamespacePrefix) || PrivacyGuardAuditService.isProtectedTrigger(t.Name);
            r.detail = r.readOnly ? 'Namespaced trigger: cannot be changed by PrivacyGuard.' : 'Apex Trigger';
            r.key = r.type + ':' + r.componentId;
            r.selected = false;
            out.items.add(r);
        }
    }

    @AuraEnabled
    public static String deactivateSelected(String selectionJson) {
        return queueChanges(selectionJson, false);
    }
    @AuraEnabled
    public static String restoreSelected(String selectionJson) {
        return queueChanges(selectionJson, true);
    }
    private static String queueChanges(String selectionJson, Boolean restoring) {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) throw new AuraHandledException('You do not have permission to manage automation metadata.');
        assertSandbox();
        Set<Id> ids = parseSelection(selectionJson);
        if (ids.size() > Limits.getLimitQueueableJobs() - Limits.getQueueableJobs()) {
            throw new AuraHandledException('Select fewer triggers for this submission; the Salesforce queue capacity would be exceeded.');
        }
        Map<Id,ApexTrigger> triggers = new Map<Id,ApexTrigger>([
            SELECT Id,Name,Status,NamespacePrefix FROM ApexTrigger WHERE Id IN :ids WITH USER_MODE
        ]);
        if (triggers.size() != ids.size()) throw new AuraHandledException('One or more triggers are unavailable. Rescan and try again.');
        Set<String> componentIds = new Set<String>();
        for (Id triggerId : ids) componentIds.add(String.valueOf(triggerId));
        Map<String,Deactivated_Automation__c> latest = new Map<String,Deactivated_Automation__c>();
        for (Deactivated_Automation__c track : [
            SELECT Id,Component_Id__c,Run_Id__c,Component_Name__c,Deployment_Status__c,Reactivated__c
            FROM Deactivated_Automation__c
            WHERE Component_Id__c IN :componentIds AND Component_Type__c='APEX_TRIGGER'
            WITH USER_MODE ORDER BY CreatedDate DESC,Id DESC
        ]) {
            if (isPending(track.Deployment_Status__c) || track.Deployment_Status__c == 'Check required') {
                throw new AuraHandledException('A trigger deployment is pending or needs a status check. Check its result before submitting another change.');
            }
            if (!track.Reactivated__c && !latest.containsKey(track.Component_Id__c)) latest.put(track.Component_Id__c,track);
        }
        String runId='AUTO-'+Datetime.now().formatGmt('yyyyMMddHHmmss')+'-'+Math.abs(Crypto.getRandomInteger());
        List<Deactivated_Automation__c> changes = new List<Deactivated_Automation__c>();
        List<AutomationTriggerToggleQueueable> jobs = new List<AutomationTriggerToggleQueueable>();
        // Validate the whole request before writing or enqueuing any component.
        for (Id triggerId : ids) {
            ApexTrigger triggerRow=triggers.get(triggerId);
            if (String.isNotBlank(triggerRow.NamespacePrefix)) throw new AuraHandledException('Namespaced triggers cannot be changed by PrivacyGuard.');
            if (PrivacyGuardAuditService.isProtectedTrigger(triggerRow.Name)) throw new AuraHandledException('PrivacyGuard audit triggers cannot be changed.');
            if (!restoring && triggerRow.Status != 'Active') throw new AuraHandledException('Only active Apex Triggers can be deactivated.');
            String componentId=String.valueOf(triggerId);
            Deactivated_Automation__c track;
            if (restoring) {
                track=latest.get(componentId);
                if (track == null) continue;
                track.Deployment_Request_Id__c=null;
            } else {
                track=new Deactivated_Automation__c(Run_Id__c=runId,Component_Type__c='APEX_TRIGGER',
                    Component_Id__c=componentId,Component_Name__c=triggerRow.Name,
                    Original_State_Json__c='Active',Reactivated__c=false);
            }
            track.Deployment_Status__c='Queued';track.Deployment_Target__c=restoring?'Active':'Inactive';
            track.Deployment_Message__c='Waiting for submission to Salesforce.';
            changes.add(track);
            jobs.add(new AutomationTriggerToggleQueueable(componentId,triggerRow.Name,track.Run_Id__c,track.Deployment_Target__c));
        }
        // Deployment status fields are read-only to users. Permission/sandbox-gated
        // system writes preserve tracking integrity without granting audit-edit FLS.
        if (!changes.isEmpty()) {
            if (restoring) update as system changes;
            else insert as system changes;
        }
        for (AutomationTriggerToggleQueueable job : jobs) System.enqueueJob(job);
        return jobs.size()+' Apex trigger deployment(s) queued. Scan again after processing to verify status.';
    }
    private static Set<Id> parseSelection(String selectionJson) {
        List<Object> rows;
        try { rows=(List<Object>)JSON.deserializeUntyped(selectionJson); }
        catch (Exception ex) { throw new AuraHandledException('Select valid Apex Trigger records.'); }
        if (rows == null || rows.isEmpty()) throw new AuraHandledException('Select at least one Apex Trigger.');
        Set<Id> ids=new Set<Id>();
        for (Object item : rows) {
            try {
                Map<String,Object> requested=(Map<String,Object>)item;
                if ((String)requested.get('type') != 'APEX_TRIGGER') throw new IllegalArgumentException('Unsupported type');
                Id triggerId=Id.valueOf((String)requested.get('componentId'));
                if (triggerId == null || triggerId.getSObjectType() != ApexTrigger.SObjectType) throw new IllegalArgumentException('Invalid trigger');
                ids.add(triggerId);
            } catch (Exception ex) { throw new AuraHandledException('Only valid Apex Trigger records are supported.'); }
        }
        return ids;
    }
    @AuraEnabled
    public static String resumeDeploymentChecks() {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) throw new AuraHandledException('You do not have permission to manage automation metadata.');
        assertSandbox();
        List<Deactivated_Automation__c> checks=[SELECT Id,Component_Id__c,Component_Name__c,Run_Id__c,
            Deployment_Request_Id__c,Deployment_Target__c,Deployment_Status__c FROM Deactivated_Automation__c
            WHERE Component_Type__c='APEX_TRIGGER' AND Deployment_Status__c='Check required'
            AND Deployment_Request_Id__c != null WITH USER_MODE LIMIT 20 FOR UPDATE];
        for (Deactivated_Automation__c d : checks) {
            d.Deployment_Status__c='In Progress';
            d.Deployment_Message__c='Checking the existing Salesforce deployment request.';
            System.enqueueJob(AutomationTriggerToggleQueueable.resume(d));
        }
        update as system checks;
        return checks.size() + ' deployment status check(s) queued. No new trigger deployments were submitted.';
    }
    private static Boolean isPending(String status) { return status == 'Queued' || status == 'In Progress'; }
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

}
