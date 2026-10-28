@IsTest
private class AutomationTriggerProgressTest {
    private static final String TRIGGER_ID='01q000000000001AAA';
    private static final String REQUEST_ID='1dr000000000001AAA';
    private class ApiMock implements HttpCalloutMock {
        String state, actual, namespacePrefix; Boolean apiError;
        ApiMock(String state,String actual,String namespacePrefix,Boolean apiError) {
            this.state=state;this.actual=actual;this.namespacePrefix=namespacePrefix;this.apiError=apiError;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res=new HttpResponse();
            if (apiError) {res.setStatusCode(503);res.setBody('Service unavailable');return res;}
            if (req.getMethod() == 'POST') {
                Map<String,Object> body=(Map<String,Object>)JSON.deserializeUntyped(req.getBody());
                if (req.getEndpoint().endsWith('/MetadataContainer')) {
                    System.assert(((String)body.get('Name')).startsWith('PG_'));
                    res.setBody('{"id":"1dc000000000001AAA"}');
                } else if (req.getEndpoint().endsWith('/ContainerAsyncRequest')) res.setBody('{"id":"'+REQUEST_ID+'"}');
                else res.setBody('{"id":"400000000000001AAA"}');
                res.setStatusCode(201);return res;
            }
            res.setStatusCode(200);
            if (req.getEndpoint().contains('ContainerAsyncRequest')) {
                res.setBody(JSON.serialize(new Map<String,Object>{'records'=>new List<Object>{new Map<String,Object>{
                    'Id'=>REQUEST_ID,'State'=>state,'ErrorMsg'=>'Compiler rejected change','DeployDetails'=>new Map<String,Object>{'problem'=>'Example compile error'}}}}));
            } else {
                res.setBody(JSON.serialize(new Map<String,Object>{'records'=>new List<Object>{new Map<String,Object>{
                    'Id'=>TRIGGER_ID,'Body'=>'trigger Example on Account (before insert) {}','ApiVersion'=>66.0,
                    'NamespacePrefix'=>namespacePrefix,'Status'=>actual}}}));
            }
            return res;
        }
    }
    private static Deactivated_Automation__c setupTrack(String target, Boolean submitted) {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        AutomationTriggerToggleQueueable.suppressEnqueue=true;
        Deactivated_Automation__c d=new Deactivated_Automation__c(Run_Id__c='TEST',Component_Type__c='APEX_TRIGGER',
            Component_Id__c=TRIGGER_ID,Component_Name__c='Example',Original_State_Json__c='Active',
            Reactivated__c=false,Deployment_Status__c='Queued',Deployment_Target__c=target,
            Deployment_Request_Id__c=submitted ? REQUEST_ID : null);
        insert d;return d;
    }
    private static Deactivated_Automation__c result() {
        return [SELECT Deployment_Status__c,Deployment_Request_Id__c,Deployment_Message__c,Reactivated__c
            FROM Deactivated_Automation__c LIMIT 1];
    }
    private static void poll(String target,Integer count) {
        new AutomationTriggerToggleQueueable(TRIGGER_ID,'Example','TEST',target,REQUEST_ID,count).execute(null);
    }
    @IsTest static void submissionPersistsRequest() {
        setupTrack('Inactive',false);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock(null,'Active',null,false));
        new AutomationTriggerToggleQueueable(TRIGGER_ID,'Example','TEST','Inactive').execute(null);
        Test.stopTest();
        System.assertEquals('Queued',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assertEquals(REQUEST_ID,result().Deployment_Request_Id__c);
    }
    @IsTest static void queuedIsNotFailure() {
        setupTrack('Inactive',true);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock('Queued','Active',null,false));poll('Inactive',8);
        Test.stopTest();
        System.assertEquals('Queued',result().Deployment_Status__c,'The old eight-poll cutoff must not fail pending work. ' + result().Deployment_Message__c);
    }
    @IsTest static void timeoutRetainsRequestForResume() {
        setupTrack('Inactive',true);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock('Queued','Active',null,false));poll('Inactive',60);
        Test.stopTest();
        System.assertEquals('Check required',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assertEquals(REQUEST_ID,result().Deployment_Request_Id__c);
        System.assertEquals(false,result().Reactivated__c);
    }
    @IsTest static void completedRestoreVerified() {
        setupTrack('Active',true);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock('Completed','Active',null,false));poll('Active',1);
        Test.stopTest();
        System.assertEquals('Succeeded',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assertEquals(true,result().Reactivated__c);
    }
    @IsTest static void mismatchedStateIsNotSuccess() {
        setupTrack('Active',true);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock('Completed','Inactive',null,false));poll('Active',1);
        Test.stopTest();
        System.assertEquals('Check required',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assertEquals(false,result().Reactivated__c);
    }
    @IsTest static void terminalFailurePreservesRestoreTracking() {
        setupTrack('Active',true);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock('Failed','Inactive',null,false));poll('Active',1);
        Test.stopTest();
        System.assertEquals('Failed',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assert(result().Deployment_Message__c.contains('Example compile error'));
        System.assertEquals(false,result().Reactivated__c);
    }
    @IsTest static void pollingErrorDoesNotClaimDeploymentFailed() {
        setupTrack('Inactive',true);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock(null,null,null,true));poll('Inactive',1);
        Test.stopTest();
        System.assertEquals('Check required',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assertEquals(REQUEST_ID,result().Deployment_Request_Id__c);
    }
    @IsTest static void namespacedTriggerRejectedByWorker() {
        setupTrack('Inactive',false);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock(null,'Active','vendor',false));
        new AutomationTriggerToggleQueueable(TRIGGER_ID,'Example','TEST','Inactive').execute(null);
        Test.stopTest();
        System.assertEquals('Failed',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assertEquals(null,result().Deployment_Request_Id__c,'No deployment may be submitted for namespaced triggers.');
        System.assert(result().Deployment_Message__c.contains('Namespaced triggers'),result().Deployment_Message__c);
    }
    @IsTest static void staleRequestCannotOverwriteNewerOperation() {
        Deactivated_Automation__c d=setupTrack('Inactive',true);
        d.Deployment_Request_Id__c='1dr000000000002AAA';update d;
        poll('Inactive',1);
        System.assertEquals('Queued',result().Deployment_Status__c,'A stale poll must not change the newer deployment status.');
        System.assertEquals('1dr000000000002AAA',result().Deployment_Request_Id__c);
    }
    @IsTest static void completedDeactivationVerified() {
        setupTrack('Inactive',true);
        Test.startTest();
        Test.setMock(HttpCalloutMock.class,new ApiMock('Completed','Inactive',null,false));poll('Inactive',1);
        Test.stopTest();
        System.assertEquals('Succeeded',result().Deployment_Status__c,result().Deployment_Message__c);
        System.assertEquals(false,result().Reactivated__c);
    }
    @IsTest static void productionBlocksResumingChecks() {
        EnvironmentSafetyService.sandboxOverrideForTests=false;
        Boolean blocked=false;
        try {AutomationManagementController.resumeDeploymentChecks();}
        catch (AuraHandledException ex) {blocked=true;}
        System.assert(blocked,'Status checks must respect the sandbox restriction.');
    }
}
