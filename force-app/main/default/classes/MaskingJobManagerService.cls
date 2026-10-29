/** Runtime job manager for PrivacyGuard masking jobs. */
public without sharing class MaskingJobManagerService {
    public class JobRow { @AuraEnabled public String scheduleCron { get; set; } @AuraEnabled public String scheduleStatus { get; set; } @AuraEnabled public Datetime nextScheduledRun { get; set; } @AuraEnabled public Id id { get; set; } @AuraEnabled public String name { get; set; } @AuraEnabled public String description { get; set; } @AuraEnabled public String runMode { get; set; } @AuraEnabled public String executionMode { get; set; } @AuraEnabled public Boolean active { get; set; } @AuraEnabled public String objects { get; set; } @AuraEnabled public Integer objectCount { get; set; } @AuraEnabled public String lastStatus { get; set; } @AuraEnabled public Datetime lastRunAt { get; set; } @AuraEnabled public Boolean canRerun { get; set; } @AuraEnabled public Boolean canCancel { get; set; } @AuraEnabled public Integer batchSize { get; set; } @AuraEnabled public Boolean configurationReady { get; set; } @AuraEnabled public String configurationIssue { get; set; } }
    public class ObjectOption { @AuraEnabled public String value { get; set; } @AuraEnabled public String label { get; set; } @AuraEnabled public Integer fieldCount { get; set; } @AuraEnabled public Integer activeFieldCount { get; set; } @AuraEnabled public Boolean ready { get; set; } }
    public class JobInput { @AuraEnabled public Id id { get; set; } @AuraEnabled public String name { get; set; } @AuraEnabled public String description { get; set; } @AuraEnabled public String runMode { get; set; } @AuraEnabled public String executionMode { get; set; } @AuraEnabled public Integer batchSize { get; set; } @AuraEnabled public List<String> objects { get; set; } }
    // DTOs deliberately expose primitive properties instead of raw custom-object sObjects.
    // In a managed-package subscriber org, raw sObject JSON keys include the namespace
    // (for example privacyguard__Status__c). LWC templates in the package referenced
    // Status__c, which made every custom field appear blank even though the data existed.
    public class RunSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String runType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Datetime startedAt { get; set; }
        @AuraEnabled public Datetime completedAt { get; set; }
        @AuraEnabled public Decimal processed { get; set; }
        @AuraEnabled public Decimal failed { get; set; }
        @AuraEnabled public String summary { get; set; }
    }
    public class RunObjectSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal processed { get; set; }
        @AuraEnabled public Decimal failed { get; set; }
        @AuraEnabled public Datetime startedAt { get; set; }
        @AuraEnabled public Datetime completedAt { get; set; }
        @AuraEnabled public String errorSummary { get; set; }
    }
    public class RunLogSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String fieldApiName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public String errorCategory { get; set; }
        @AuraEnabled public String adminMessage { get; set; }
        @AuraEnabled public String suggestedAction { get; set; }
        @AuraEnabled public String technicalDetails { get; set; }
    }
    public class RunDetails {
        @AuraEnabled public RunSummary run { get; set; }
        @AuraEnabled public List<RunObjectSummary> objects { get; set; }
        @AuraEnabled public List<RunLogSummary> logs { get; set; }
    }

    @AuraEnabled(cacheable=true) public static List<ObjectOption> getConfiguredObjects() {
        // The Data Masking Configuration object is the source of truth for the Job Manager.
        // Return EVERY object present there, not only objects that currently have active fields.
        Map<String, Integer> totalByObject = new Map<String, Integer>();
        Map<String, Integer> activeByObject = new Map<String, Integer>();
        for (Masking_Field_Config__c cfg : [
            SELECT Object_API_Name__c, Is_Active__c, Masking_Strategy__c
            FROM Masking_Field_Config__c
            WHERE Object_API_Name__c != null
            ORDER BY Object_API_Name__c
        ]) {
            String api = cfg.Object_API_Name__c;
            totalByObject.put(api, (totalByObject.containsKey(api) ? totalByObject.get(api) : 0) + 1);
            if (cfg.Is_Active__c == true && !String.isBlank(cfg.Masking_Strategy__c)) {
                activeByObject.put(api, (activeByObject.containsKey(api) ? activeByObject.get(api) : 0) + 1);
            }
        }
        List<String> names = new List<String>(totalByObject.keySet());
        names.sort();
        List<ObjectOption> out = new List<ObjectOption>();
        for (String api : names) {
            ObjectOption o = new ObjectOption();
            o.value = api;
            o.label = api;
            o.fieldCount = totalByObject.get(api);
            o.activeFieldCount = activeByObject.containsKey(api) ? activeByObject.get(api) : 0;
            o.ready = o.activeFieldCount > 0 && MaskingCompletionService.configurationIssue(api) == null;
            out.add(o);
        }
        return out;
    }
    @AuraEnabled public static List<JobRow> getJobs() {
        PrivacyGuardSecurityService.requireRunPermission();
        for (Masking_Job__c active : [SELECT Id FROM Masking_Job__c WHERE Last_Status__c = 'Running']) RuntimeMaskingJobOrchestrator.reconcile(active.Id);
        List<JobRow> out=new List<JobRow>();
        Map<String, CronTrigger> scheduleByName = new Map<String, CronTrigger>();
        for (CronTrigger ct : [SELECT Id, CronJobDetail.Name, NextFireTime, State, CronExpression FROM CronTrigger WHERE (CronJobDetail.Name LIKE 'PGWeekly_%' OR CronJobDetail.Name LIKE 'PGSchedule_%') AND State NOT IN ('DELETED','COMPLETE')]) {
            scheduleByName.put(ct.CronJobDetail.Name, ct);
        }
        for(Masking_Job__c j:[SELECT Id,Job_Name__c,Description__c,Run_Mode__c,Execution_Mode__c,Batch_Size__c,Is_Active__c,Last_Status__c,Last_Run_At__c,(SELECT Object_API_Name__c,Sequence__c FROM Job_Objects__r WHERE Is_Active__c=true ORDER BY Sequence__c) FROM Masking_Job__c ORDER BY CreatedDate DESC]){
            JobRow r=new JobRow(); r.id=j.Id;r.name=j.Job_Name__c;r.description=j.Description__c;r.runMode=j.Run_Mode__c;r.executionMode=j.Execution_Mode__c;r.batchSize=(Integer)j.Batch_Size__c;r.active=j.Is_Active__c;r.lastStatus=j.Last_Status__c;r.lastRunAt=j.Last_Run_At__c;
            List<String> os=new List<String>(); for(Masking_Job_Object__c x:j.Job_Objects__r)os.add(x.Object_API_Name__c); r.objects=String.join(os,', ');r.objectCount=os.size();r.canRerun=(j.Last_Status__c=='Failed'||j.Last_Status__c=='Completed with Errors');r.canCancel=j.Last_Status__c=='Running';
            CronTrigger ct = scheduleByName.get('PGSchedule_' + String.valueOf(j.Id));
            if(ct==null)ct=scheduleByName.get('PGWeekly_' + String.valueOf(j.Id));
            r.scheduleCron = ct == null ? null : ct.CronExpression;
            r.scheduleStatus = ct == null ? 'Manual' : ct.State;
            r.nextScheduledRun = ct == null ? null : ct.NextFireTime;
            Set<String> runnableObjects = MaskingConfigService.getActiveFieldConfigsByObject().keySet();
            List<String> notReady = new List<String>();
            for (String objectApi : os) if (!runnableObjects.contains(objectApi)) notReady.add(objectApi);
            for (String objectApi : os) { String issue = MaskingCompletionService.configurationIssue(objectApi); if (issue != null) notReady.add(issue); }
            if (j.Run_Mode__c == 'Delta') notReady.add('Edit this job and select Unmasked records only to replace timestamp Delta mode.');
            r.configurationReady = notReady.isEmpty();
            r.configurationIssue = r.configurationReady ? null : 'Inactive masking configuration: ' + String.join(notReady, ', ');
            out.add(r);
        } return out;
    }
    @AuraEnabled public static Id saveJob(JobInput input){ PrivacyGuardSecurityService.requireRunPermission(); if(input==null||String.isBlank(input.name)||input.objects==null||input.objects.isEmpty()) throw client('Job name and at least one configured object are required.');
        requireJobWriteAccess(input.id == null);
        if (input.runMode != null && input.runMode != 'Full' && input.runMode != 'Once') throw client('Choose Full or Unmasked records only. Timestamp Delta mode is no longer offered.');
        for (String o : input.objects) MaskingCompletionService.requireCheckbox(o, null);
        if (input.id != null && ![SELECT Id FROM Masking_Job_Run__c WHERE Masking_Job__c=:input.id AND Status__c='Running' LIMIT 1].isEmpty()) throw client('Wait for the active run to finish before editing this job.');
        Set<String> configured=MaskingConfigService.getActiveFieldConfigsByObject().keySet(); for(String o:input.objects) if(!configured.contains(o)) throw client(o+' does not have an active masking configuration.');
        Masking_Job__c j=input.id==null?new Masking_Job__c():[SELECT Id FROM Masking_Job__c WHERE Id=:input.id WITH USER_MODE]; j.Job_Name__c=input.name.trim();j.Description__c=input.description;j.Run_Mode__c=String.isBlank(input.runMode)?'Once':input.runMode;j.Execution_Mode__c=String.isBlank(input.executionMode)?'Serial':input.executionMode;j.Batch_Size__c=input.batchSize==null?200:input.batchSize;j.Is_Active__c=true; if(input.id==null){j.Last_Status__c='Draft'; insert as user j;} else update as user j;
        if(input.id!=null) { List<Masking_Job_Object__c> existing=[SELECT Id FROM Masking_Job_Object__c WHERE Masking_Job__c=:j.Id]; delete as user existing; } List<Masking_Job_Object__c> rows=new List<Masking_Job_Object__c>(); Integer seq=1; for(String o:input.objects)rows.add(new Masking_Job_Object__c(Masking_Job__c=j.Id,Object_API_Name__c=o,Sequence__c=seq++,Is_Active__c=true,Delta_Tracking_Field__c=MaskingCompletionService.requireCheckbox(o,null))); insert as user rows; return j.Id;
    }
    @AuraEnabled public static void deleteJob(Id jobId){
        PrivacyGuardSecurityService.requireRunPermission();
        if (!Schema.sObjectType.Masking_Job__c.isDeletable()) throw client('You do not have permission to delete masking jobs.');
        Masking_Job__c job=[SELECT Id FROM Masking_Job__c WHERE Id=:jobId WITH USER_MODE];
        delete as user job;
        cancelWeeklySchedule(jobId);
    }
    private static void requireJobWriteAccess(Boolean creating) {
        Schema.DescribeSObjectResult job = Masking_Job__c.SObjectType.getDescribe();
        Schema.DescribeSObjectResult child = Masking_Job_Object__c.SObjectType.getDescribe();
        if ((creating && !job.isCreateable()) || (!creating && !job.isUpdateable()) ||
            !child.isCreateable() || (!creating && !child.isDeletable()))
            throw client('You do not have permission to create or edit masking jobs and their object selections.');
        List<String> jobFields = new List<String>{'Job_Name__c','Description__c','Run_Mode__c','Execution_Mode__c','Batch_Size__c','Is_Active__c'};
        if (creating) jobFields.add('Last_Status__c');
        requireWritableFields(job, jobFields, creating);
        requireWritableFields(child, new List<String>{'Masking_Job__c','Object_API_Name__c','Sequence__c','Is_Active__c','Delta_Tracking_Field__c'}, true);
    }
    private static void requireWritableFields(Schema.DescribeSObjectResult objectInfo, List<String> names, Boolean creating) {
        Map<String, Schema.SObjectField> fields = PrivacyGuardSchema.fields(objectInfo);
        for (String name : names) {
            Schema.SObjectField token=fields.get(name);
            if(token==null)throw client('Missing masking job field: '+name);
            Schema.DescribeFieldResult field = token.getDescribe();
            if ((creating && !field.isCreateable()) || (!creating && !field.isUpdateable()))
                throw client('You do not have permission to edit masking job field ' + field.getLabel() + '.');
        }
    }
    // Keep legacy endpoints callable for cached clients and existing installations.
    @AuraEnabled public static void scheduleWeekly(Id jobId,String dayOfWeek,String localTime) {
        scheduleJob(jobId,'weekly',dayOfWeek,null,localTime);
    }
    @TestVisible private static String buildScheduleCron(String frequency,String dayOfWeek,String monthDay,String localTime) {
        if(String.isBlank(localTime)||!Pattern.matches('^([01][0-9]|2[0-3]):[0-5][0-9]$',localTime))throw client('Time must be HH:mm.');
        List<String> timeParts=localTime.split(':');
        String prefix='0 '+timeParts[1]+' '+timeParts[0];
        if(frequency=='daily')return prefix+' * * ?';
        if(frequency=='weekly') {
            if(!new Set<String>{'MON','TUE','WED','THU','FRI','SAT','SUN'}.contains(dayOfWeek))throw client('Choose a valid weekday.');
            return prefix+' ? * '+dayOfWeek;
        }
        if(frequency=='monthly') {
            if(String.isBlank(monthDay)||!(monthDay=='L'||Pattern.matches('^([1-9]|1[0-9]|2[0-8])$',monthDay)))throw client('Choose day 1 to 28 or Last day of month.');
            return prefix+' '+monthDay+' * ?';
        }
        throw client('Choose Daily, Weekly or Monthly.');
    }
    @AuraEnabled public static void scheduleJob(Id jobId,String frequency,String dayOfWeek,String monthDay,String localTime) {
        PrivacyGuardSecurityService.requireRunPermission();
        EnvironmentSafetyService.assertExecutionAllowed();
        if(jobId==null)throw client('Select a masking job.');
        String cron=buildScheduleCron(frequency,dayOfWeek,monthDay,localTime);
        List<Masking_Job__c> jobs=[SELECT Id,Is_Active__c FROM Masking_Job__c WHERE Id=:jobId LIMIT 1 FOR UPDATE];
        if(jobs.isEmpty()||!jobs[0].Is_Active__c)throw client('Job not found or inactive.');
        validateJobReady(jobId);
        cancelJobSchedule(jobId);
        // Existing scheduler class is retained for managed-package compatibility.
        // System.schedule uses the scheduling user's Salesforce timezone.
        System.schedule('PGSchedule_'+String.valueOf(jobId),cron,new PrivacyGuardWeeklyScheduler(jobId));
        PrivacyGuardAuditService.record('Jobs','Schedule saved',jobId,'Frequency: '+frequency+'; cron: '+cron+'; timezone: '+UserInfo.getTimeZone().getID());
    }
    @AuraEnabled public static void cancelWeeklySchedule(Id jobId) {cancelJobSchedule(jobId);}
    @AuraEnabled public static void cancelJobSchedule(Id jobId) {
        PrivacyGuardSecurityService.requireRunPermission();
        if(jobId==null)return;
        Set<String> scheduleNames=new Set<String>{'PGWeekly_'+String.valueOf(jobId),'PGSchedule_'+String.valueOf(jobId)};
        for(CronTrigger scheduled:[SELECT Id,CronExpression,TimeZoneSidKey FROM CronTrigger WHERE CronJobDetail.Name IN :scheduleNames]) {System.abortJob(scheduled.Id); PrivacyGuardAuditService.record('Jobs','Schedule cancelled',jobId,'Cancelled schedule '+scheduled.Id+'; cron: '+scheduled.CronExpression+'; timezone: '+scheduled.TimeZoneSidKey);}
    }
    @AuraEnabled public static void cancelRunningJob(Id jobId) { RuntimeMaskingJobOrchestrator.cancel(jobId); }
    @AuraEnabled public static Id runJob(Id jobId){ PrivacyGuardSecurityService.requireRunPermission(); RuntimeMaskingJobOrchestrator.reconcile(jobId); validateJobReady(jobId); return RuntimeMaskingJobOrchestrator.start(jobId,false,null); }
    @AuraEnabled public static Id rerunJob(Id jobId){
        PrivacyGuardSecurityService.requireRunPermission();
        RuntimeMaskingJobOrchestrator.reconcile(jobId); validateJobReady(jobId);
        Masking_Job_Run__c prev=[SELECT Id,Status__c FROM Masking_Job_Run__c WHERE Masking_Job__c=:jobId ORDER BY CreatedDate DESC LIMIT 1]; if(prev.Status__c!='Failed'&&prev.Status__c!='Completed with Errors') throw client('Rerun is available only when the previous run failed or completed with errors.'); return RuntimeMaskingJobOrchestrator.start(jobId,true,prev.Id);
    }
    @AuraEnabled
    public static RunDetails getLatestRun(Id jobId) {
        PrivacyGuardSecurityService.requireRunPermission();
        RuntimeMaskingJobOrchestrator.reconcile(jobId);
        RunDetails d = new RunDetails();
        d.objects = new List<RunObjectSummary>();
        d.logs = new List<RunLogSummary>();

        List<Masking_Job_Run__c> rr = [
            SELECT Id, Name, Run_Type__c, Status__c, Started_At__c, Completed_At__c,
                   Processed_Records__c, Failed_Records__c, Summary__c
            FROM Masking_Job_Run__c
            WHERE Masking_Job__c = :jobId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (rr.isEmpty()) return d;

        Masking_Job_Run__c r = rr[0];
        RunSummary rs = new RunSummary();
        rs.id = r.Id;
        rs.name = r.Name;
        rs.runType = r.Run_Type__c;
        rs.status = r.Status__c;
        rs.startedAt = r.Started_At__c;
        rs.completedAt = r.Completed_At__c;
        rs.processed = r.Processed_Records__c == null ? 0 : r.Processed_Records__c;
        rs.failed = r.Failed_Records__c == null ? 0 : r.Failed_Records__c;
        rs.summary = r.Summary__c;
        d.run = rs;

        for (Masking_Job_Run_Object__c ro : [
            SELECT Id, Object_API_Name__c, Status__c, Processed_Records__c, Failed_Records__c,
                   Started_At__c, Completed_At__c, Error_Summary__c
            FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :r.Id
            ORDER BY Sequence__c
        ]) {
            RunObjectSummary os = new RunObjectSummary();
            os.id = ro.Id;
            os.objectApiName = ro.Object_API_Name__c;
            os.status = ro.Status__c;
            os.processed = ro.Processed_Records__c == null ? 0 : ro.Processed_Records__c;
            os.failed = ro.Failed_Records__c == null ? 0 : ro.Failed_Records__c;
            os.startedAt = ro.Started_At__c;
            os.completedAt = ro.Completed_At__c;
            os.errorSummary = ro.Error_Summary__c;
            d.objects.add(os);
        }

        String runtimeRunId = String.valueOf(r.Id);
        for (Masking_Log__c l : [
            SELECT Id, CreatedDate, Object_API_Name__c, Record_Id__c, Field_API_Name__c,
                   Status__c, Error_Message__c, Error_Category__c, Admin_Message__c,
                   Suggested_Action__c, Technical_Details__c
            FROM Masking_Log__c
            WHERE Run_Id__c = :runtimeRunId
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            RunLogSummary ls = new RunLogSummary();
            ls.id = l.Id;
            ls.createdDate = l.CreatedDate;
            ls.objectApiName = l.Object_API_Name__c;
            ls.recordId = l.Record_Id__c;
            ls.fieldApiName = l.Field_API_Name__c;
            ls.status = l.Status__c;
            ls.errorMessage = l.Error_Message__c;
            ls.errorCategory = String.isBlank(l.Error_Category__c) ? 'Masking Error' : l.Error_Category__c;
            ls.adminMessage = String.isBlank(l.Admin_Message__c) ? l.Error_Message__c : l.Admin_Message__c;
            ls.suggestedAction = String.isBlank(l.Suggested_Action__c)
                ? 'Review the technical details and masking configuration, correct the issue, then use Recovery Rerun.'
                : l.Suggested_Action__c;
            ls.technicalDetails = String.isBlank(l.Technical_Details__c) ? l.Error_Message__c : l.Technical_Details__c;
            d.logs.add(ls);
        }
        return d;
    }

    private static void validateJobReady(Id jobId) {
        Masking_Job__c job = [SELECT Run_Mode__c FROM Masking_Job__c WHERE Id=:jobId];
        if (job.Run_Mode__c == 'Delta') throw client('Edit the job and choose Unmasked records only. No timestamp is required.');
        Set<String> runnable = MaskingConfigService.getActiveFieldConfigsByObject().keySet();
        List<String> invalid = new List<String>();
        for (Masking_Job_Object__c item : [SELECT Object_API_Name__c FROM Masking_Job_Object__c WHERE Masking_Job__c=:jobId AND Is_Active__c=true ORDER BY Sequence__c]) {
            if (!runnable.contains(item.Object_API_Name__c)) invalid.add(item.Object_API_Name__c);
            String issue = MaskingCompletionService.configurationIssue(item.Object_API_Name__c); if (issue != null) invalid.add(issue);
        }
        if (!invalid.isEmpty()) throw client('This job is not ready to run. Activate a masking configuration for: ' + String.join(invalid, ', ') + '.');
    }
    private static AuraHandledException client(String m){AuraHandledException e=new AuraHandledException(m);e.setMessage(m);return e;}
}
