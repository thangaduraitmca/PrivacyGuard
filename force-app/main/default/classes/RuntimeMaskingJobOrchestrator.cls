/**
 * Executes subscriber-defined PrivacyGuard masking jobs and recovery reruns.
 * Reads enforce current-user visibility and FLS. Internal run-history writes use
 * explicit system mode because packaged history fields are intentionally read-only.
 * All public entry points require masking permission and sandbox execution.
 * Job configuration/status writes continue to enforce user permissions.
 */
public with sharing class RuntimeMaskingJobOrchestrator {
    public static Id start(Id jobId, Boolean recovery, Id parentRunId){ PrivacyGuardSecurityService.requireRunPermission();EnvironmentSafetyService.assertExecutionAllowed();
        Masking_Job__c j=[SELECT Id,Job_Name__c,Run_Mode__c,Execution_Mode__c,Batch_Size__c,Is_Active__c FROM Masking_Job__c WHERE Id=:jobId WITH USER_MODE FOR UPDATE]; if (j.Run_Mode__c == 'Delta') throw new AuraHandledException('Edit this job and select Unmasked records only; timestamp tracking is not required.'); if(!j.Is_Active__c)throw new AuraHandledException('This masking job is inactive.');
        if (j.Run_Mode__c != 'Full' && j.Run_Mode__c != 'Once') {
            throw new AuraHandledException('Choose Full or Unmasked records only before starting this job.');
        }
        if (recovery == true) {
            List<Masking_Job_Run__c> parents = [SELECT Id FROM Masking_Job_Run__c
                WHERE Id=:parentRunId AND Masking_Job__c=:jobId
                AND Status__c IN ('Failed', 'Completed with Errors') WITH USER_MODE LIMIT 1];
            if (parents.isEmpty()) throw new AuraHandledException('Recovery requires a failed run belonging to this job.');
        } else if (parentRunId != null) {
            throw new AuraHandledException('A parent run can only be supplied for recovery.');
        }
        if (![SELECT Id FROM Masking_Job_Run__c WHERE Masking_Job__c=:jobId AND Status__c='Running' WITH USER_MODE LIMIT 1].isEmpty()) throw new AuraHandledException('This masking job already has an active run.');
        List<Masking_Job_Object__c> os=[SELECT Id,Object_API_Name__c,Sequence__c,Delta_Tracking_Field__c FROM Masking_Job_Object__c WHERE Masking_Job__c=:jobId AND Is_Active__c=true WITH USER_MODE ORDER BY Sequence__c]; Map<String,List<MaskingConfigService.FieldConfig>> preflight = MaskingConfigService.getActiveFieldConfigsByObject();
        for (Masking_Job_Object__c item : os) {
            String flag = MaskingCompletionService.requireCheckbox(item.Object_API_Name__c, item.Delta_Tracking_Field__c);
            if (!preflight.containsKey(item.Object_API_Name__c)) throw new AuraHandledException('No active masking configuration for ' + item.Object_API_Name__c);
            for (MaskingConfigService.FieldConfig fc : preflight.get(item.Object_API_Name__c)) {
                SchemaValidationUtil.validateMaskingTarget(SchemaValidationUtil.requireValidObject(item.Object_API_Name__c), fc);
                if (fc.fieldApiName.equalsIgnoreCase(flag)) throw new AuraHandledException('The masking completion checkbox cannot also be a masking target.');
            }
        }
        if(os.isEmpty())throw new AuraHandledException('No objects are configured for this job.');
        Masking_Job_Run__c run=new Masking_Job_Run__c(Masking_Job__c=j.Id,Parent_Run__c=parentRunId,Run_Type__c=recovery?'Rerun':'Run',Status__c='Running',Started_At__c=System.now(),Started_By__c=UserInfo.getName(),Total_Objects__c=os.size(),Completed_Objects__c=0,Processed_Records__c=0,Failed_Records__c=0);insert as system run;
        List<Masking_Job_Run_Object__c> ros=new List<Masking_Job_Run_Object__c>();for(Masking_Job_Object__c o:os)ros.add(new Masking_Job_Run_Object__c(Masking_Job_Run__c=run.Id,Object_API_Name__c=o.Object_API_Name__c,Sequence__c=o.Sequence__c,Status__c='Queued',Processed_Records__c=0,Failed_Records__c=0));insert as system ros;
        j.Last_Status__c='Running';j.Last_Run_At__c=System.now();update as user j; AutomationManagerService.disableAllAutomations(String.valueOf(run.Id));
        if(j.Execution_Mode__c=='Parallel')launchAll(j,run,ros,recovery,parentRunId);else launch(j,run,ros[0],recovery,parentRunId); return run.Id; }
    private static void launch(Masking_Job__c j,Masking_Job_Run__c run,Masking_Job_Run_Object__c ro,Boolean recovery,Id parentRunId){
        launchAll(j, run, new List<Masking_Job_Run_Object__c>{ ro }, recovery, parentRunId);
    }
    // Starts one batch per run object, then persists every run-object status in a single DML.
    // Batches only begin after this transaction commits, so writing status after enqueueing is safe.
    private static void launchAll(Masking_Job__c j,Masking_Job_Run__c run,List<Masking_Job_Run_Object__c> runObjects,Boolean recovery,Id parentRunId){
        if (recovery && parentRunId == null) throw new AuraHandledException('A parent run is required for failed-record recovery.');
        Map<String,List<MaskingConfigService.FieldConfig>> cfg=MaskingConfigService.getActiveFieldConfigsByObject();
        Map<String,String> trackingByObject=new Map<String,String>();
        for (Masking_Job_Object__c jo : [SELECT Object_API_Name__c, Delta_Tracking_Field__c FROM Masking_Job_Object__c WHERE Masking_Job__c=:j.Id WITH USER_MODE ORDER BY Sequence__c LIMIT 1000]) {
            if (!trackingByObject.containsKey(jo.Object_API_Name__c)) trackingByObject.put(jo.Object_API_Name__c, jo.Delta_Tracking_Field__c);
        }
        Integer bs=j.Batch_Size__c==null?200:Integer.valueOf(j.Batch_Size__c);
        List<Masking_Job_Run_Object__c> launched=new List<Masking_Job_Run_Object__c>();
        List<Masking_Job_Run_Object__c> unconfigured=new List<Masking_Job_Run_Object__c>();
        for (Masking_Job_Run_Object__c ro : runObjects) {
            List<MaskingConfigService.FieldConfig> fields=cfg.get(ro.Object_API_Name__c);
            if (fields==null||fields.isEmpty()) { unconfigured.add(ro); continue; }
            String tracking = MaskingCompletionService.requireCheckbox(ro.Object_API_Name__c, trackingByObject.get(ro.Object_API_Name__c));
            Id aid = recovery
                ? Database.executeBatch(new MaskingFailedRecordRecoveryBatch(j.Job_Name__c, ro.Object_API_Name__c, fields, j.Run_Mode__c, tracking, run.Id, ro.Id, parentRunId), bs)
                : Database.executeBatch(new MaskingBatch(j.Job_Name__c, ro.Object_API_Name__c, fields, j.Run_Mode__c, tracking, run.Id, ro.Id, null, false), bs);
            ro.Status__c='Running'; ro.Started_At__c=System.now(); ro.Async_Job_Id__c=String.valueOf(aid);
            launched.add(ro);
        }
        if (!launched.isEmpty()) update as system launched;
        // Not normally reachable: start() preflight rejects objects without active configuration.
        for (Masking_Job_Run_Object__c ro : unconfigured) completeObject(ro.Id, 0, 1, 'No active field configuration found.');
    }
    // Reconcile batches that terminate before MaskingBatch.finish() (including start() exceptions).
    // Called by control-panel reads; status transitions are persisted, not inferred only in the UI.
    public static void reconcile(Id jobId) {
        requireRuntimeAccess();
        List<Masking_Job_Run__c> runs = [
            SELECT Id, Status__c FROM Masking_Job_Run__c
            WHERE Masking_Job__c = :jobId AND Status__c = 'Running' WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (runs.isEmpty()) return;
        Masking_Job_Run__c run = runs[0];
        List<Masking_Job_Run_Object__c> objects = [
            SELECT Id, Status__c, Async_Job_Id__c, Failed_Records__c,
                   Error_Summary__c, Completed_At__c
            FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id WITH USER_MODE ORDER BY Sequence__c
        ];
        Set<Id> asyncIds = new Set<Id>();
        for (Masking_Job_Run_Object__c ro : objects) {
            if (ro.Status__c == 'Running' && String.isNotBlank(ro.Async_Job_Id__c)) {
                asyncIds.add((Id)ro.Async_Job_Id__c);
            }
        }
        Map<Id, AsyncApexJob> asyncJobs = new Map<Id, AsyncApexJob>();
        if (!asyncIds.isEmpty()) {
            asyncJobs = new Map<Id, AsyncApexJob>([
                SELECT Id, Status, NumberOfErrors, ExtendedStatus
                FROM AsyncApexJob WHERE Id IN :asyncIds WITH USER_MODE ]);
        }
        Boolean hasFailure = false;
        Boolean hasCancellation = false;
        Boolean hasActive = false;
        List<Masking_Job_Run_Object__c> changes = new List<Masking_Job_Run_Object__c>();
        for (Masking_Job_Run_Object__c ro : objects) {
            if (ro.Status__c == 'Running' && String.isNotBlank(ro.Async_Job_Id__c)) {
                AsyncApexJob aj = asyncJobs.get((Id)ro.Async_Job_Id__c);
                if (aj != null && (aj.Status == 'Failed' || aj.Status == 'Aborted' ||
                    (aj.Status == 'Completed' && aj.NumberOfErrors > 0))) {
                    ro.Status__c = aj.Status == 'Aborted' ? 'Cancelled' : 'Failed';
                    ro.Error_Summary__c = String.isBlank(aj.ExtendedStatus)
                        ? 'Apex batch ' + aj.Status : aj.ExtendedStatus;
                    ro.Completed_At__c = System.now();
                    changes.add(ro);
                }
            }
            if (ro.Status__c == 'Failed' || ro.Status__c == 'Partial') hasFailure = true;
            if (ro.Status__c == 'Cancelled') hasCancellation = true;
            if (ro.Status__c == 'Running') hasActive = true;
        }
        // A failed serial step cannot start the next queued object. Parallel jobs
        // must be allowed to finish before their parent run is finalised.
        if (hasFailure || hasCancellation) {
            for (Masking_Job_Run_Object__c ro : objects) {
                if (ro.Status__c == 'Queued') {
                    ro.Status__c = 'Skipped';
                    ro.Completed_At__c = System.now();
                    changes.add(ro);
                }
            }
        }
        if (!changes.isEmpty()) update as system changes;
        if ((hasFailure || hasCancellation) && !hasActive) {
            // Lock and recheck: a parallel batch may have completed in the meantime.
            Masking_Job_Run__c locked = [
                SELECT Id, Status__c FROM Masking_Job_Run__c WHERE Id = :run.Id WITH USER_MODE FOR UPDATE
            ];
            if (locked.Status__c != 'Running') return;
            Integer stillRunning = [SELECT COUNT() FROM Masking_Job_Run_Object__c
                WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Running' WITH USER_MODE ];
            if (stillRunning != 0) return;
            locked.Status__c = hasCancellation ? 'Cancelled' : 'Failed';
            locked.Completed_At__c = System.now();
            locked.Summary__c = hasCancellation ? 'Masking job cancelled.'
                : 'Masking batch failed. Check Apex Jobs and object errors.';
            update as system locked;
            update as user new Masking_Job__c(Id = jobId, Last_Status__c = locked.Status__c);
            AutomationManagerService.enableAllAutomations(String.valueOf(run.Id));
        }
    }

    public static void cancel(Id jobId) {
        PrivacyGuardSecurityService.requireRunPermission();
        EnvironmentSafetyService.assertExecutionAllowed();
        reconcile(jobId);
        List<Masking_Job_Run__c> runs = [SELECT Id, Status__c FROM Masking_Job_Run__c
            WHERE Masking_Job__c=:jobId AND Status__c='Running' WITH USER_MODE LIMIT 1 FOR UPDATE];
        if (runs.isEmpty() || runs[0].Status__c != 'Running')
            throw new AuraHandledException('No active masking run is available to cancel.');
        Masking_Job_Run__c run = runs[0];
        List<Masking_Job_Run_Object__c> objects = [SELECT Id, Status__c, Async_Job_Id__c
            FROM Masking_Job_Run_Object__c WHERE Masking_Job_Run__c=:run.Id WITH USER_MODE ];
        for (Masking_Job_Run_Object__c ro : objects) {
            if (ro.Status__c == 'Running' && String.isNotBlank(ro.Async_Job_Id__c)) {
                System.abortJob((Id) ro.Async_Job_Id__c);
                ro.Status__c = 'Cancelled';
            } else if (ro.Status__c == 'Queued') ro.Status__c = 'Skipped';
            else continue;
            ro.Completed_At__c = System.now();
        }
        update as system objects;
        run.Status__c='Cancelled'; run.Completed_At__c=System.now();
        run.Summary__c='Cancelled by ' + UserInfo.getName() + '. Previously committed batches are not rolled back.';
        update as system run;
        update as user new Masking_Job__c(Id=jobId,Last_Status__c='Cancelled');
        AutomationManagerService.enableAllAutomations(String.valueOf(run.Id));
    }
    public static void completeObject(Id runObjectId, Integer processed, Integer failed, String summary) {
        requireRuntimeAccess();
        if (processed == null || failed == null || processed < 0 || failed < 0) {
            throw new AuraHandledException('Completion counts must be nonnegative numbers.');
        }
        Masking_Job_Run_Object__c ro = [
            SELECT Id, Masking_Job_Run__c, Object_API_Name__c, Status__c
            FROM Masking_Job_Run_Object__c WHERE Id = :runObjectId WITH USER_MODE FOR UPDATE
        ];
        // A cancelled or previously reconciled batch may still invoke finish().
        // Never count it twice, overwrite a terminal status or launch new work.
        if (ro.Status__c != 'Running' && ro.Status__c != 'Queued') return;
        Masking_Job_Run__c run = [
            SELECT Id, Masking_Job__c, Status__c, Completed_Objects__c,
                   Total_Objects__c, Processed_Records__c, Failed_Records__c
            FROM Masking_Job_Run__c WHERE Id = :ro.Masking_Job_Run__c WITH USER_MODE FOR UPDATE
        ];
        if (run.Status__c != 'Running') return;
        ro.Processed_Records__c = processed;
        ro.Failed_Records__c = failed;
        ro.Status__c = failed > 0 ? (processed > 0 ? 'Partial' : 'Failed') : 'Completed';
        ro.Completed_At__c = System.now();
        ro.Error_Summary__c = summary;
        update as system ro;
        run.Completed_Objects__c = (run.Completed_Objects__c == null ? 0 : run.Completed_Objects__c) + 1;
        run.Processed_Records__c = (run.Processed_Records__c == null ? 0 : run.Processed_Records__c) + processed;
        run.Failed_Records__c = (run.Failed_Records__c == null ? 0 : run.Failed_Records__c) + failed;
        update as system run;
        Masking_Job__c j = [
            SELECT Id, Job_Name__c, Run_Mode__c, Execution_Mode__c, Batch_Size__c
            FROM Masking_Job__c WHERE Id = :run.Masking_Job__c WITH USER_MODE ];
        Integer activeObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Running' WITH USER_MODE ];
        Integer queuedObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Queued' WITH USER_MODE ];
        Integer failedObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c IN ('Failed', 'Partial') WITH USER_MODE ];
        Integer cancelledObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Cancelled' WITH USER_MODE ];
        if (j.Execution_Mode__c == 'Serial' && queuedObjects > 0 && failedObjects == 0 && cancelledObjects == 0) {
            List<Masking_Job_Run_Object__c> next = [
                SELECT Id, Object_API_Name__c FROM Masking_Job_Run_Object__c
                WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Queued' WITH USER_MODE ORDER BY Sequence__c LIMIT 1
            ];
            if (!next.isEmpty()) {
                Masking_Job_Run__c runDetails = [
                    SELECT Id, Run_Type__c, Parent_Run__c FROM Masking_Job_Run__c WHERE Id = :run.Id WITH USER_MODE ];
                launch(j, runDetails, next[0], runDetails.Run_Type__c == 'Rerun', runDetails.Parent_Run__c);
                return;
            }
        }
        // A partial/failed serial step skips subsequent objects; parallel batches
        // are allowed to complete before finalising the overall run.
        if (failedObjects > 0 || cancelledObjects > 0) {
            List<Masking_Job_Run_Object__c> skipped = [
                SELECT Id, Status__c FROM Masking_Job_Run_Object__c
                WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Queued' WITH USER_MODE ];
            for (Masking_Job_Run_Object__c item : skipped) {
                item.Status__c = 'Skipped';
                item.Completed_At__c = System.now();
            }
            if (!skipped.isEmpty()) update as system skipped;
            queuedObjects = 0;
        }
        if (activeObjects == 0 && queuedObjects == 0) {
            run.Status__c = cancelledObjects > 0 ? 'Cancelled'
                : failedObjects > 0 ? 'Completed with Errors' : 'Completed';
            run.Completed_At__c = System.now();
            run.Summary__c = 'Processed ' + run.Processed_Records__c +
                ' records; ' + run.Failed_Records__c + ' failed.';
            update as system run;
            update as user new Masking_Job__c(Id = j.Id, Last_Status__c = run.Status__c);
            // Restore only the snapshot owned by this run; propagate failure so finalisation can retry.
            AutomationManagerService.enableAllAutomations(String.valueOf(run.Id));
        }
    }
    private static void requireRuntimeAccess() {
        PrivacyGuardSecurityService.requireRunPermission();
        EnvironmentSafetyService.assertExecutionAllowed();
    }
}
