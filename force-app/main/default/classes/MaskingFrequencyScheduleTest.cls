@IsTest
private class MaskingFrequencyScheduleTest {
    private static Id createJob() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        MaskingJobManagerService.JobInput input=new MaskingJobManagerService.JobInput();
        input.name='Schedule test';input.runMode='Once';input.objects=new List<String>{'Contact'};
        return MaskingJobManagerService.saveJob(input);
    }
    private static CronTrigger scheduledFor(Id jobId) {
        String expected='PGSchedule_'+String.valueOf(jobId);
        return [SELECT Id,CronExpression,NextFireTime,TimeZoneSidKey FROM CronTrigger WHERE CronJobDetail.Name=:expected AND State!='DELETED' LIMIT 1];
    }
    @IsTest static void buildsDailyWeeklyMonthlyExpressions() {
        System.assertEquals('0 30 02 * * ?',MaskingJobManagerService.buildScheduleCron('daily',null,null,'02:30'));
        System.assertEquals('0 15 03 ? * MON',MaskingJobManagerService.buildScheduleCron('weekly','MON',null,'03:15'));
        System.assertEquals('0 00 04 15 * ?',MaskingJobManagerService.buildScheduleCron('monthly',null,'15','04:00'));
        System.assertEquals('0 00 04 L * ?',MaskingJobManagerService.buildScheduleCron('monthly',null,'L','04:00'));
    }
    @IsTest static void schedulesAndReplacesWithoutDuplicates() {
        Id jobId=createJob();
        MaskingJobManagerService.scheduleJob(jobId,'daily',null,null,'02:30');
        CronTrigger daily=scheduledFor(jobId);System.assertEquals('0 30 02 * * ?',daily.CronExpression);System.assertEquals(UserInfo.getTimeZone().getID(),daily.TimeZoneSidKey);
        MaskingJobManagerService.scheduleJob(jobId,'monthly',null,'L','03:15');
        System.assertEquals('0 15 03 L * ?',scheduledFor(jobId).CronExpression);
        String expected='PGSchedule_'+String.valueOf(jobId);
        System.assertEquals(1,[SELECT count() FROM CronTrigger WHERE CronJobDetail.Name=:expected AND State!='DELETED']);
        MaskingJobManagerService.cancelJobSchedule(jobId);
    }
    @IsTest static void legacyWeeklyScheduleMigratesAndCancels() {
        Id jobId=createJob();String legacy='PGWeekly_'+String.valueOf(jobId);
        Id old=System.schedule(legacy,'0 0 2 ? * SUN',new PrivacyGuardWeeklyScheduler(jobId));
        Boolean visible=false;for(MaskingJobManagerService.JobRow row:MaskingJobManagerService.getJobs())if(row.id==jobId){visible=true;System.assertEquals('0 0 2 ? * SUN',row.scheduleCron);}System.assert(visible);
        MaskingJobManagerService.scheduleJob(jobId,'daily',null,null,'04:00');
        System.assertEquals(0,[SELECT count() FROM CronTrigger WHERE Id=:old AND State!='DELETED']);
        MaskingJobManagerService.cancelWeeklySchedule(jobId);
        String current='PGSchedule_'+String.valueOf(jobId);
        System.assertEquals(0,[SELECT count() FROM CronTrigger WHERE CronJobDetail.Name=:current AND State!='DELETED']);
    }
    @IsTest static void invalidReplacementPreservesExistingSchedule() {
        Id jobId=createJob();MaskingJobManagerService.scheduleWeekly(jobId,'FRI','02:00');Id original=scheduledFor(jobId).Id;
        Boolean blocked=false;try{MaskingJobManagerService.scheduleJob(jobId,'monthly',null,'31','03:00');}catch(AuraHandledException ex){blocked=true;}System.assert(blocked);
        System.assertEquals(original,scheduledFor(jobId).Id);MaskingJobManagerService.cancelJobSchedule(jobId);
    }
    @IsTest static void rejectsInvalidFrequencyWeekdayAndTime() {
        for(String frequency:new List<String>{null,'hourly'}) {
            Boolean blocked=false;try{MaskingJobManagerService.buildScheduleCron(frequency,'SUN','1','02:00');}catch(AuraHandledException ex){blocked=true;}System.assert(blocked);
        }
        Boolean blocked=false;try{MaskingJobManagerService.buildScheduleCron('weekly','INVALID',null,'02:00');}catch(AuraHandledException ex){blocked=true;}System.assert(blocked);
        blocked=false;try{MaskingJobManagerService.buildScheduleCron('daily',null,null,'24:00');}catch(AuraHandledException ex){blocked=true;}System.assert(blocked);
    }
    @IsTest static void manualSaveCancelsAnyFrequency() {
        Id jobId=createJob();MaskingJobManagerService.scheduleJob(jobId,'monthly',null,'1','02:00');
        MaskingControlPanelController.saveJobWithFrequency(jobId,'Schedule test',null,'Once','Serial',200,'["Contact"]','manual',null,null,null);
        String expected='PGSchedule_'+String.valueOf(jobId);
        System.assertEquals(0,[SELECT count() FROM CronTrigger WHERE CronJobDetail.Name=:expected AND State!='DELETED']);
    }
    @IsTest static void cannotScheduleOutsideApprovedEnvironment() {
        Id jobId=createJob();EnvironmentSafetyService.sandboxOverrideForTests=false;
        Boolean blocked=false;try{MaskingJobManagerService.scheduleJob(jobId,'daily',null,null,'02:00');}catch(EnvironmentSafetyService.ProductionExecutionBlockedException ex){blocked=true;}System.assert(blocked);
    }
}
