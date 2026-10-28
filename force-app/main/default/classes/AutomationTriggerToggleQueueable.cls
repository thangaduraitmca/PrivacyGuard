/** Persists Tooling deployment progress; never treats a pending deployment as failed. */
public without sharing class AutomationTriggerToggleQueueable implements Queueable, Database.AllowsCallouts {
    private String triggerId, triggerName, runId, targetStatus, requestId;
    private Integer attempt;
    private static final Integer MAX_POLLS = 60;
    @TestVisible private static Boolean suppressEnqueue = false;
    public AutomationTriggerToggleQueueable(String triggerId, String triggerName, String runId, String targetStatus) {
        this(triggerId, triggerName, runId, targetStatus, null, 0);
    }
    @TestVisible private AutomationTriggerToggleQueueable(String a, String b, String c, String d, String e, Integer f) {
        triggerId=a; triggerName=b; runId=c; targetStatus=d; requestId=e; attempt=f;
    }
    public static AutomationTriggerToggleQueueable resume(Deactivated_Automation__c track) {
        return new AutomationTriggerToggleQueueable(track.Component_Id__c, track.Component_Name__c,
            track.Run_Id__c, track.Deployment_Target__c, track.Deployment_Request_Id__c, 0);
    }
    public void execute(QueueableContext qc) {
        if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) {
            throw new PrivacyGuardSecurityService.PrivacyGuardAuthorizationException('You do not have permission to manage automation metadata.');
        }
        if (!EnvironmentSafetyService.isSandbox()) {
            throw new EnvironmentSafetyService.ProductionExecutionBlockedException('PrivacyGuard trigger changes are allowed in sandboxes only.');
        }
        List<Deactivated_Automation__c> tracks = [SELECT Id, Deployment_Request_Id__c,
            Deployment_Status__c, Deployment_Target__c FROM Deactivated_Automation__c
            WHERE Run_Id__c=:runId AND Component_Id__c=:triggerId AND Component_Type__c='APEX_TRIGGER'
            ORDER BY CreatedDate DESC LIMIT 1];
        if (tracks.isEmpty()) throw new ToggleException('No restoration tracking record exists for this trigger.');
        Deactivated_Automation__c track = tracks[0];
        // Ignore an obsolete poll from an earlier operation on this tracking record.
        if (requestId != null && requestId != track.Deployment_Request_Id__c) return;
        if (requestId == null && String.isNotBlank(track.Deployment_Request_Id__c)) return;
        try {
            if (targetStatus != 'Active' && targetStatus != 'Inactive') throw new ToggleException('Invalid target trigger state.');
            if (requestId == null) {
                Map<String,Object> q = ToolingApiClient.query('SELECT Id, Body, ApiVersion, NamespacePrefix FROM ApexTrigger WHERE Id = \'' + String.escapeSingleQuotes(triggerId) + '\' LIMIT 1');
                List<Object> rs = (List<Object>)q.get('records');
                if (rs == null || rs.isEmpty()) throw new ToggleException('Trigger not found.');
                Map<String,Object> tr = (Map<String,Object>)rs[0];
                // Server-side defence even when this class is invoked directly.
                if (String.isNotBlank((String)tr.get('NamespacePrefix'))) throw new ToggleException('Namespaced triggers cannot be changed by PrivacyGuard.');
                String containerId = ToolingApiClient.post('MetadataContainer', JSON.serialize(new Map<String,Object>{
                    'Name'=>'PG_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(29)}));
                ToolingApiClient.post('ApexTriggerMember', JSON.serialize(new Map<String,Object>{
                    'MetadataContainerId'=>containerId, 'ContentEntityId'=>triggerId, 'Body'=>tr.get('Body'),
                    'Metadata'=>new Map<String,Object>{'status'=>targetStatus, 'apiVersion'=>tr.get('ApiVersion')}}));
                requestId = ToolingApiClient.post('ContainerAsyncRequest', JSON.serialize(new Map<String,Object>{
                    'MetadataContainerId'=>containerId, 'IsCheckOnly'=>false}));
                // All callouts precede DML. Persist the request before scheduling its first check.
                track.Deployment_Request_Id__c=requestId;
                saveProgress(track, 'Queued', 'Submitted to Salesforce. Waiting for the deployment result.');
                enqueueNext(track);
                return;
            }
            Map<String,Object> q = ToolingApiClient.query('SELECT Id, State, ErrorMsg, DeployDetails FROM ContainerAsyncRequest WHERE Id = \'' + String.escapeSingleQuotes(requestId) + '\'');
            List<Object> requests = (List<Object>)q.get('records');
            if (requests == null || requests.isEmpty()) throw new ToggleException('Deployment request was not returned by Salesforce.');
            Map<String,Object> req=(Map<String,Object>)requests[0];
            String state=(String)req.get('State');
            if (state == 'Completed') {
                // Verify the actual trigger state rather than trusting the Apex job status.
                Map<String,Object> actual=ToolingApiClient.query('SELECT Id, Status FROM ApexTrigger WHERE Id = \'' + String.escapeSingleQuotes(triggerId) + '\'');
                List<Object> records=(List<Object>)actual.get('records');
                if (records == null || records.isEmpty() || (String)((Map<String,Object>)records[0]).get('Status') != targetStatus) {
                    saveProgress(track, 'Check required', 'Salesforce completed the request, but the target trigger state could not be verified. Check status again.');
                    return;
                }
                if (targetStatus == 'Active') {
                    List<Deactivated_Automation__c> restored=[SELECT Id FROM Deactivated_Automation__c
                        WHERE Component_Id__c=:triggerId AND Component_Type__c='APEX_TRIGGER' AND Reactivated__c=false];
                    for (Deactivated_Automation__c row : restored) { row.Reactivated__c=true; row.Reactivated_Date__c=System.now(); }
                    update restored;
                }
                saveProgress(track, 'Succeeded', 'Verified trigger state: ' + targetStatus + '.');
                MaskingLogger.logInfo('AutomationTriggerToggleQueueable', triggerName + ' deployed ' + targetStatus + '. Request: ' + requestId);
            } else if (state == 'Failed' || state == 'Error' || state == 'Aborted' || state == 'Invalidated') {
                String details='Salesforce deployment ' + state + '. ' + String.valueOf(req.get('ErrorMsg'));
                if (req.get('DeployDetails') != null) details += ' ' + JSON.serialize(req.get('DeployDetails'));
                saveProgress(track, 'Failed', details);
                MaskingLogger.logError('AutomationTriggerToggleQueueable','ApexTrigger',null,triggerName,clip(details));
            } else {
                saveProgress(track, state == 'Queued' ? 'Queued' : 'In Progress', 'Salesforce deployment state: ' + state + '.');
                enqueueNext(track);
            }
        } catch (Exception ex) {
            // A polling/API error is not proof that the Salesforce deployment failed.
            String message=requestId == null ? 'Could not submit the trigger deployment. ' : 'Deployment outcome is unknown. Check status again. ';
            saveProgress(track, requestId == null ? 'Failed' : 'Check required', message + ex.getMessage());
            MaskingLogger.logError('AutomationTriggerToggleQueueable','ApexTrigger',null,triggerName,clip(message + ex.getMessage()));
        }
    }
    private void enqueueNext(Deactivated_Automation__c track) {
        if (attempt >= MAX_POLLS) {
            saveProgress(track, 'Check required', 'Automatic checking paused after 60 checks. The deployment has not been marked failed. Click Check Deployment Status to resume.');
        } else if (!suppressEnqueue) {
            System.enqueueJob(new AutomationTriggerToggleQueueable(triggerId,triggerName,runId,targetStatus,requestId,attempt+1), 1);
        }
    }
    private void saveProgress(Deactivated_Automation__c track, String status, String message) {
        track.Deployment_Status__c=status;
        track.Deployment_Target__c=targetStatus;
        track.Deployment_Message__c=clip(message);
        update track;
    }
    private static String clip(String value) { return value == null ? null : value.left(32000); }
    public class ToggleException extends Exception {}
}
