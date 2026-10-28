/** PrivacyGuard masking job control panel controller. */
public with sharing class MaskingControlPanelController {
 @AuraEnabled public static MaskingPreviewService.PreviewResult previewMasking(Id jobId,String objectApiName){return MaskingPreviewService.preview(jobId,objectApiName);}
 @AuraEnabled public static List<MaskingJobManagerService.JobRow> getJobs(){return MaskingJobManagerService.getJobs();}
 @AuraEnabled public static List<MaskingJobManagerService.ObjectOption> getConfiguredObjects(){return MaskingJobManagerService.getConfiguredObjects();}
 @AuraEnabled public static Id saveJob(String jobId, String jobName, String description, String runMode, String executionMode, Integer batchSize, List<String> objects, String selectedObjectsJson){
  // Backward-compatible boundary: accept both the original LWC parameter (objects)
  // and the JSON parameter used by the newer LWC bundle. This also protects users
  // who still have an older Lightning bundle cached after deployment.
  List<String> selectedObjects = new List<String>();
  if (String.isNotBlank(selectedObjectsJson)) {
   selectedObjects = (List<String>) JSON.deserialize(selectedObjectsJson, List<String>.class);
  } else if (objects != null) {
   selectedObjects.addAll(objects);
  }
  MaskingJobManagerService.JobInput input = new MaskingJobManagerService.JobInput();
  if (String.isNotBlank(jobId)) input.id = (Id)jobId;
  input.name = jobName;
  input.description = description;
  input.runMode = runMode;
  input.executionMode = executionMode;
  input.batchSize = batchSize;
  input.objects = selectedObjects;
  return MaskingJobManagerService.saveJob(input);
 }
 @AuraEnabled public static Id saveJobWithSchedule(Id jobId, String jobName, String description, String runMode, String executionMode, Integer batchSize, String selectedObjectsJson, Boolean scheduled, String dayOfWeek, String localTime) {
  MaskingJobManagerService.JobInput input = new MaskingJobManagerService.JobInput();
  input.id = jobId;
  input.name = jobName;
  input.description = description;
  input.runMode = runMode;
  input.executionMode = executionMode;
  input.batchSize = batchSize;
  input.objects = (List<String>) JSON.deserialize(selectedObjectsJson, List<String>.class);
  Id savedId = MaskingJobManagerService.saveJob(input);
  if (scheduled == true) MaskingJobManagerService.scheduleWeekly(savedId, dayOfWeek, localTime);
  else MaskingJobManagerService.cancelWeeklySchedule(savedId);
  return savedId;
 }
 @AuraEnabled public static void scheduleJob(Id jobId,String frequency,String dayOfWeek,String monthDay,String localTime){MaskingJobManagerService.scheduleJob(jobId,frequency,dayOfWeek,monthDay,localTime);}
 @AuraEnabled public static void cancelJobSchedule(Id jobId){MaskingJobManagerService.cancelJobSchedule(jobId);}
 @AuraEnabled public static Id saveJobWithFrequency(Id jobId,String jobName,String description,String runMode,String executionMode,Integer batchSize,String selectedObjectsJson,String frequency,String dayOfWeek,String monthDay,String localTime) {
  Savepoint checkpoint=Database.setSavepoint();
  try {
  MaskingJobManagerService.JobInput input=new MaskingJobManagerService.JobInput();
  input.id=jobId;input.name=jobName;input.description=description;input.runMode=runMode;input.executionMode=executionMode;input.batchSize=batchSize;
  input.objects=(List<String>)JSON.deserialize(selectedObjectsJson,List<String>.class);
  Id savedId=MaskingJobManagerService.saveJob(input);
  if(frequency=='manual')MaskingJobManagerService.cancelJobSchedule(savedId);
  else MaskingJobManagerService.scheduleJob(savedId,frequency,dayOfWeek,monthDay,localTime);
  return savedId;
  } catch(Exception ex) {Database.rollback(checkpoint);throw ex;}
 }
 @AuraEnabled public static void scheduleWeekly(Id jobId, String dayOfWeek, String localTime){MaskingJobManagerService.scheduleWeekly(jobId,dayOfWeek,localTime);}
 @AuraEnabled public static void cancelWeeklySchedule(Id jobId){MaskingJobManagerService.cancelWeeklySchedule(jobId);}
 @AuraEnabled public static void deleteJob(Id jobId){MaskingJobManagerService.deleteJob(jobId);}
 @AuraEnabled public static void cancelRunningJob(Id jobId){MaskingJobManagerService.cancelRunningJob(jobId);}
 @AuraEnabled public static Id runJob(Id jobId){return MaskingJobManagerService.runJob(jobId);}
 @AuraEnabled public static Id rerunJob(Id jobId){return MaskingJobManagerService.rerunJob(jobId);}
 @AuraEnabled public static MaskingJobManagerService.RunDetails getLatestRun(Id jobId){return MaskingJobManagerService.getLatestRun(jobId);}
 @AuraEnabled public static void runMaskingNow(){try{MaskingFrameworkService.executeMaskingRun();}catch(Exception e){AuraHandledException x=new AuraHandledException(e.getMessage());x.setMessage(e.getMessage());throw x;}}
}