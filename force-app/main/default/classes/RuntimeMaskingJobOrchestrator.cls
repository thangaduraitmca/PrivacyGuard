/** Executes subscriber-defined PrivacyGuard masking jobs and recovery reruns. */
public without sharing class RuntimeMaskingJobOrchestrator {
    public static Id start(Id jobId, Boolean recovery, Id parentRunId){ PrivacyGuardSecurityService.requireRunPermission();EnvironmentSafetyService.assertExecutionAllowed();
        Masking_Job__c j=[SELECT Id,Job_Name__c,Run_Mode__c,Execution_Mode__c,Batch_Size__c,Is_Active__c FROM Masking_Job__c WHERE Id=:jobId]; if (j.Run_Mode__c == 'Delta') throw new AuraHandledException('Edit this job and select Unmasked records only; timestamp tracking is not required.'); if(!j.Is_Active__c)throw new AuraHandledException('This masking job is inactive.');
        if (![SELECT Id FROM Masking_Job_Run__c WHERE Masking_Job__c=:jobId AND Status__c='Running' LIMIT 1].isEmpty()) throw new AuraHandledException('This masking job already has an active run.');
        List<Masking_Job_Object__c> os=[SELECT Id,Object_API_Name__c,Sequence__c,Delta_Tracking_Field__c FROM Masking_Job_Object__c WHERE Masking_Job__c=:jobId AND Is_Active__c=true ORDER BY Sequence__c]; Map<String,List<MaskingConfigService.FieldConfig>> preflight = MaskingConfigService.getActiveFieldConfigsByObject();
        for (Masking_Job_Object__c item : os) {
            String flag = MaskingCompletionService.requireCheckbox(item.Object_API_Name__c, item.Delta_Tracking_Field__c);
            if (!preflight.containsKey(item.Object_API_Name__c)) throw new AuraHandledException('No active masking configuration for ' + item.Object_API_Name__c);
            for (MaskingConfigService.FieldConfig fc : preflight.get(item.Object_API_Name__c)) {
                SchemaValidationUtil.validateMaskingTarget(SchemaValidationUtil.requireValidObject(item.Object_API_Name__c), fc);
                if (fc.fieldApiName.equalsIgnoreCase(flag)) throw new AuraHandledException('The masking completion checkbox cannot also be a masking target.');
            }
        }
        if(os.isEmpty())throw new AuraHandledException('No objects are configured for this job.');
        Masking_Job_Run__c run=new Masking_Job_Run__c(Masking_Job__c=j.Id,Parent_Run__c=parentRunId,Run_Type__c=recovery?'Rerun':'Run',Status__c='Running',Started_At__c=System.now(),Started_By__c=UserInfo.getName(),Total_Objects__c=os.size(),Completed_Objects__c=0,Processed_Records__c=0,Failed_Records__c=0);insert run;
        List<Masking_Job_Run_Object__c> ros=new List<Masking_Job_Run_Object__c>();for(Masking_Job_Object__c o:os)ros.add(new Masking_Job_Run_Object__c(Masking_Job_Run__c=run.Id,Object_API_Name__c=o.Object_API_Name__c,Sequence__c=o.Sequence__c,Status__c='Queued',Processed_Records__c=0,Failed_Records__c=0));insert ros;
        j.Last_Status__c='Running';j.Last_Run_At__c=System.now();update j; AutomationManagerService.disableAllAutomations();
        if(j.Execution_Mode__c=='Parallel'){for(Masking_Job_Run_Object__c ro:ros)launch(j,run,ro,recovery,parentRunId);}else launch(j,run,ros[0],recovery,parentRunId); return run.Id; }
    private static void launch(Masking_Job__c j,Masking_Job_Run__c run,Masking_Job_Run_Object__c ro,Boolean recovery,Id parentRunId){
        Map<String,List<MaskingConfigService.FieldConfig>> cfg=MaskingConfigService.getActiveFieldConfigsByObject();List<MaskingConfigService.FieldConfig> fields=cfg.get(ro.Object_API_Name__c);if(fields==null||fields.isEmpty()){completeObject(ro.Id,0,1,'No active field configuration found.');return;}
        String tracking; List<Masking_Job_Object__c> jo=[SELECT Delta_Tracking_Field__c FROM Masking_Job_Object__c WHERE Masking_Job__c=:j.Id AND Object_API_Name__c=:ro.Object_API_Name__c LIMIT 1]; if(!jo.isEmpty())tracking=jo[0].Delta_Tracking_Field__c;
        tracking = MaskingCompletionService.requireCheckbox(ro.Object_API_Name__c, tracking);
        if (recovery && parentRunId == null) throw new AuraHandledException('A parent run is required for failed-record recovery.');
        ro.Status__c='Running';ro.Started_At__c=System.now();update ro; Integer bs=j.Batch_Size__c==null?200:Integer.valueOf(j.Batch_Size__c);Id aid = recovery
            ? Database.executeBatch(new MaskingFailedRecordRecoveryBatch(j.Job_Name__c, ro.Object_API_Name__c, fields, j.Run_Mode__c, tracking, run.Id, ro.Id, parentRunId), bs)
            : Database.executeBatch(new MaskingBatch(j.Job_Name__c, ro.Object_API_Name__c, fields, j.Run_Mode__c, tracking, run.Id, ro.Id, null, false), bs);ro.Async_Job_Id__c=String.valueOf(aid);update ro;
    }
    // Reconcile batches that terminate before MaskingBatch.finish() (including start() exceptions).
    // Called by control-panel reads; status transitions are persisted, not inferred only in the UI.
    public static void reconcile(Id jobId) {
        List<Masking_Job_Run__c> runs = [
            SELECT Id, Status__c FROM Masking_Job_Run__c
            WHERE Masking_Job__c = :jobId AND Status__c = 'Running'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (runs.isEmpty()) return;
        Masking_Job_Run__c run = runs[0];
        List<Masking_Job_Run_Object__c> objects = [
            SELECT Id, Status__c, Async_Job_Id__c, Failed_Records__c,
                   Error_Summary__c, Completed_At__c
            FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id ORDER BY Sequence__c
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
                FROM AsyncApexJob WHERE Id IN :asyncIds
            ]);
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
        if (!changes.isEmpty()) update changes;
        if ((hasFailure || hasCancellation) && !hasActive) {
            // Lock and recheck: a parallel batch may have completed in the meantime.
            Masking_Job_Run__c locked = [
                SELECT Id, Status__c FROM Masking_Job_Run__c WHERE Id = :run.Id FOR UPDATE
            ];
            if (locked.Status__c != 'Running') return;
            Integer stillRunning = [SELECT COUNT() FROM Masking_Job_Run_Object__c
                WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Running'];
            if (stillRunning != 0) return;
            locked.Status__c = hasCancellation ? 'Cancelled' : 'Failed';
            locked.Completed_At__c = System.now();
            locked.Summary__c = hasCancellation ? 'Masking job cancelled.'
                : 'Masking batch failed. Check Apex Jobs and object errors.';
            update locked;
            update new Masking_Job__c(Id = jobId, Last_Status__c = locked.Status__c);
            try { AutomationManagerService.enableAllAutomations(); } catch (Exception ignored) {}
        }
    }

    public static void cancel(Id jobId) {
        PrivacyGuardSecurityService.requireRunPermission();
        EnvironmentSafetyService.assertExecutionAllowed();
        reconcile(jobId);
        List<Masking_Job_Run__c> runs = [SELECT Id, Status__c FROM Masking_Job_Run__c
            WHERE Masking_Job__c=:jobId AND Status__c='Running' LIMIT 1 FOR UPDATE];
        if (runs.isEmpty() || runs[0].Status__c != 'Running')
            throw new AuraHandledException('No active masking run is available to cancel.');
        Masking_Job_Run__c run = runs[0];
        List<Masking_Job_Run_Object__c> objects = [SELECT Id, Status__c, Async_Job_Id__c
            FROM Masking_Job_Run_Object__c WHERE Masking_Job_Run__c=:run.Id];
        for (Masking_Job_Run_Object__c ro : objects) {
            if (ro.Status__c == 'Running' && String.isNotBlank(ro.Async_Job_Id__c)) {
                System.abortJob((Id) ro.Async_Job_Id__c);
                ro.Status__c = 'Cancelled';
            } else if (ro.Status__c == 'Queued') ro.Status__c = 'Skipped';
            else continue;
            ro.Completed_At__c = System.now();
        }
        update objects;
        run.Status__c='Cancelled'; run.Completed_At__c=System.now();
        run.Summary__c='Cancelled by ' + UserInfo.getName() + '. Previously committed batches are not rolled back.';
        update run;
        update new Masking_Job__c(Id=jobId,Last_Status__c='Cancelled');
        try { AutomationManagerService.enableAllAutomations(); } catch (Exception ignored) {}
    }
    public static void completeObject(Id runObjectId, Integer processed, Integer failed, String summary) {
        Masking_Job_Run_Object__c ro = [
            SELECT Id, Masking_Job_Run__c, Object_API_Name__c, Status__c
            FROM Masking_Job_Run_Object__c WHERE Id = :runObjectId FOR UPDATE
        ];
        // A cancelled or previously reconciled batch may still invoke finish().
        // Never count it twice, overwrite a terminal status or launch new work.
        if (ro.Status__c != 'Running' && ro.Status__c != 'Queued') return;
        Masking_Job_Run__c run = [
            SELECT Id, Masking_Job__c, Status__c, Completed_Objects__c,
                   Total_Objects__c, Processed_Records__c, Failed_Records__c
            FROM Masking_Job_Run__c WHERE Id = :ro.Masking_Job_Run__c FOR UPDATE
        ];
        if (run.Status__c != 'Running') return;
        ro.Processed_Records__c = processed;
        ro.Failed_Records__c = failed;
        ro.Status__c = failed > 0 ? (processed > 0 ? 'Partial' : 'Failed') : 'Completed';
        ro.Completed_At__c = System.now();
        ro.Error_Summary__c = summary;
        update ro;
        run.Completed_Objects__c = (run.Completed_Objects__c == null ? 0 : run.Completed_Objects__c) + 1;
        run.Processed_Records__c = (run.Processed_Records__c == null ? 0 : run.Processed_Records__c) + processed;
        run.Failed_Records__c = (run.Failed_Records__c == null ? 0 : run.Failed_Records__c) + failed;
        update run;
        Masking_Job__c j = [
            SELECT Id, Job_Name__c, Run_Mode__c, Execution_Mode__c, Batch_Size__c
            FROM Masking_Job__c WHERE Id = :run.Masking_Job__c
        ];
        Integer activeObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Running'];
        Integer queuedObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Queued'];
        Integer failedObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c IN ('Failed', 'Partial')];
        Integer cancelledObjects = [SELECT COUNT() FROM Masking_Job_Run_Object__c
            WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Cancelled'];
        if (j.Execution_Mode__c == 'Serial' && queuedObjects > 0 && failedObjects == 0 && cancelledObjects == 0) {
            List<Masking_Job_Run_Object__c> next = [
                SELECT Id, Object_API_Name__c FROM Masking_Job_Run_Object__c
                WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Queued'
                ORDER BY Sequence__c LIMIT 1
            ];
            if (!next.isEmpty()) {
                Masking_Job_Run__c runDetails = [
                    SELECT Id, Run_Type__c, Parent_Run__c FROM Masking_Job_Run__c WHERE Id = :run.Id
                ];
                launch(j, runDetails, next[0], runDetails.Run_Type__c == 'Rerun', runDetails.Parent_Run__c);
                return;
            }
        }
        // A partial/failed serial step skips subsequent objects; parallel batches
        // are allowed to complete before finalising the overall run.
        if (failedObjects > 0 || cancelledObjects > 0) {
            List<Masking_Job_Run_Object__c> skipped = [
                SELECT Id, Status__c FROM Masking_Job_Run_Object__c
                WHERE Masking_Job_Run__c = :run.Id AND Status__c = 'Queued'
            ];
            for (Masking_Job_Run_Object__c item : skipped) {
                item.Status__c = 'Skipped';
                item.Completed_At__c = System.now();
            }
            if (!skipped.isEmpty()) update skipped;
            queuedObjects = 0;
        }
        if (activeObjects == 0 && queuedObjects == 0) {
            run.Status__c = cancelledObjects > 0 ? 'Cancelled'
                : failedObjects > 0 ? 'Completed with Errors' : 'Completed';
            run.Completed_At__c = System.now();
            run.Summary__c = 'Processed ' + run.Processed_Records__c +
                ' records; ' + run.Failed_Records__c + ' failed.';
            update run;
            update new Masking_Job__c(Id = j.Id, Last_Status__c = run.Status__c);
            // Automation restoration is intentionally unchanged in this patch.
            try { AutomationManagerService.enableAllAutomations(); } catch (Exception e) {}
        }
    }
}
