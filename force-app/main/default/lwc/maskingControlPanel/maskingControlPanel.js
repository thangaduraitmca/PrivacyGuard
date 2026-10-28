import previewMasking from '@salesforce/apex/MaskingControlPanelController.previewMasking';
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getJobs from '@salesforce/apex/MaskingControlPanelController.getJobs';
import getConfiguredObjects from '@salesforce/apex/MaskingControlPanelController.getConfiguredObjects';
import saveJobWithFrequency from '@salesforce/apex/MaskingControlPanelController.saveJobWithFrequency';
import deleteJob from '@salesforce/apex/MaskingControlPanelController.deleteJob';
import runJob from '@salesforce/apex/MaskingControlPanelController.runJob';
import rerunJob from '@salesforce/apex/MaskingControlPanelController.rerunJob';
import cancelRunningJob from '@salesforce/apex/MaskingControlPanelController.cancelRunningJob';
import getLatestRun from '@salesforce/apex/MaskingControlPanelController.getLatestRun';
import scheduleJob from '@salesforce/apex/MaskingControlPanelController.scheduleJob';
import cancelJobSchedule from '@salesforce/apex/MaskingControlPanelController.cancelJobSchedule';

export default class MaskingControlPanel extends LightningElement {
 @track jobs=[]; @track configuredObjects=[]; @track objectOptions=[]; @track selectedObjects=[]; @track runDetails;
 showSchedule=false; scheduleJobId=null; scheduleDay='SUN'; scheduleTime='02:00'; scheduleEnabled=false;scheduleFrequency='weekly';scheduleMonthDay='1';
 showEditor=false; showDetails=false; showRunConfirm=false; runAcknowledged=false; pendingRunId=null; pendingRunRecovery=false; pendingRunJob=null; showDeleteConfirm=false; showCancelConfirm=false; pendingCancelId=null; pendingCancelName=''; isLoading=false; editingId; pendingDeleteId; pendingDeleteName='';
 showPreview=false;previewJobId;previewObject='';previewOptions=[];previewRows=[];previewCount=0;previewError='';previewBusy=false;previewRequest=0;
 jobName='';description='';runMode='Once';executionMode='Serial';batchSize=200;

 connectedCallback(){this.refresh();}
 async refresh(){
  this.isLoading=true;
  try{
   const [jobs, objects]=await Promise.all([getJobs(),getConfiguredObjects()]);
   this.configuredObjects=objects||[];
   this.jobs=(jobs||[]).map(j=>{
    const configurationReady=j.configurationReady!==false;
    const baseStatus=(!j.lastStatus||j.lastStatus==='Draft')?'Ready':j.lastStatus;
    return {...j,configurationReady,runDisabled:!configurationReady||j.canCancel,displayStatus:configurationReady?baseStatus:'Not Ready',statusTitle:configurationReady?'':j.configurationIssue,
     statusClass:!configurationReady?'slds-text-color_error':(baseStatus==='Completed'||baseStatus==='Ready')?'slds-text-color_success':(baseStatus==='Failed'||baseStatus==='Completed with Errors')?'slds-text-color_error':''};
   });
   this.rebuildObjectOptions();
  }catch(e){this.toast('Error',this.msg(e),'error');}finally{this.isLoading=false;}
 }
 rebuildObjectOptions(){
  const selected=new Set(this.selectedObjects||[]);
  this.objectOptions=(this.configuredObjects||[]).map(o=>{
   const ready=o.ready===true;
   const label=ready?`${o.label} — ${o.activeFieldCount} active / ${o.fieldCount} configured`:`${o.label} — ${o.activeFieldCount} active / ${o.fieldCount} configured — Check active fields and completion checkbox`;
   return {label,value:o.value,disabled:!ready&&!selected.has(o.value)};
  });
 }
 get selectedNotReady(){const selected=new Set(this.selectedObjects||[]);return (this.configuredObjects||[]).filter(o=>selected.has(o.value)&&o.ready!==true).map(o=>o.value);}
 get hasSelectedNotReady(){return this.selectedNotReady.length>0;}
 get selectedNotReadyMessage(){return this.hasSelectedNotReady?`Check active masking fields and deploy Data_Masking_Complete__c (Checkbox, default false) for ${this.selectedNotReady.join(', ')} before saving.`:'';}
 openNew(){this.scheduleFrequency='weekly';this.scheduleMonthDay='1';this.scheduleEnabled=false;this.scheduleDay='SUN';this.scheduleTime='02:00';this.editingId=null;this.jobName='';this.description='';this.runMode='Once';this.executionMode='Serial';this.batchSize=200;this.selectedObjects=[];this.rebuildObjectOptions();this.showEditor=true;}
 closeEditor(){this.showEditor=false;}
 handleName(e){this.jobName=e.target.value;} handleDescription(e){this.description=e.target.value;} handleRunMode(e){this.runMode=e.detail.value;} handleExecution(e){this.executionMode=e.detail.value;} handleBatch(e){this.batchSize=Number(e.target.value);}
 get scheduleOptions(){return [{label:'Manual — Run Now',value:'manual'},{label:'Daily',value:'daily'},{label:'Weekly',value:'weekly'},{label:'Monthly',value:'monthly'}];}
 get frequencyOptions(){return this.scheduleOptions.filter(option=>option.value!=='manual');}
 get scheduleMode(){return this.scheduleEnabled?this.scheduleFrequency:'manual';}
 get isWeekly(){return this.scheduleFrequency==='weekly';}
 get isMonthly(){return this.scheduleFrequency==='monthly';}
 get monthDayOptions(){return [...Array.from({length:28},(_,i)=>({label:String(i+1),value:String(i+1)})),{label:'Last day of month',value:'L'}];}
 handleScheduleMode(event){const value=event.detail.value;this.scheduleEnabled=value!=='manual';if(this.scheduleEnabled)this.scheduleFrequency=value;}
 handleFrequency(event){this.scheduleFrequency=event.detail.value;}
 handleMonthDay(event){this.scheduleMonthDay=event.detail.value;}
 restoreSchedule(job){
  this.scheduleEnabled=!!job.scheduleCron;this.scheduleFrequency='weekly';this.scheduleDay='SUN';this.scheduleMonthDay='1';this.scheduleTime='02:00';
  if(!job.scheduleCron)return;
  const parts=job.scheduleCron.trim().split(/\s+/);
  if(parts.length<6)return;
  this.scheduleTime=`${parts[2].padStart(2,'0')}:${parts[1].padStart(2,'0')}`;
  if(parts[3]==='*')this.scheduleFrequency='daily';
  else if(parts[3]==='?'){this.scheduleFrequency='weekly';this.scheduleDay=parts[5];}
  else{this.scheduleFrequency='monthly';this.scheduleMonthDay=parts[3];}
 }
 handleObjects(e){this.selectedObjects=[...e.detail.value];this.rebuildObjectOptions();}
 async save(){
  if(!this.jobName||!this.selectedObjects.length){this.toast('Missing information','Enter a job name and select at least one object that is ready for masking.','warning');return;}
  if(this.hasSelectedNotReady){this.toast('Configuration not ready',this.selectedNotReadyMessage,'warning');return;}
  this.isLoading=true;
  try{await saveJobWithFrequency({jobId:this.editingId||null,jobName:this.jobName,description:this.description,runMode:this.runMode,executionMode:this.executionMode,batchSize:this.batchSize,selectedObjectsJson:JSON.stringify(this.selectedObjects),frequency:this.scheduleMode,dayOfWeek:this.scheduleDay,monthDay:this.scheduleMonthDay,localTime:this.scheduleTime});this.showEditor=false;await this.refresh();this.toast('Saved','Masking job saved successfully.','success');}
  catch(e){this.toast('Could not save',this.msg(e),'error');}finally{this.isLoading=false;}
 }
 async handleAction(e){
  const id=e.currentTarget.dataset.id, action=e.detail.value, job=this.jobs.find(x=>x.id===id);
  if(action==='preview')return this.openPreview(job);
  if(action==='schedule'){this.restoreSchedule(job);this.scheduleJobId=id;this.showSchedule=true;return;}
  if(action==='unschedule')return this.cancelSchedule(id);
  if(action==='run')return this.reviewRun(id,false); if(action==='rerun')return this.reviewRun(id,true); if(action==='logs')return this.openLogs(id);
  if(action==='edit'){this.restoreSchedule(job);this.editingId=id;this.jobName=job.name;this.description=job.description;this.runMode=job.runMode==='Delta'?'Once':job.runMode;this.executionMode=job.executionMode;this.batchSize=job.batchSize||200;this.selectedObjects=job.objects?job.objects.split(', ').filter(Boolean):[];this.rebuildObjectOptions();this.showEditor=true;return;}
  if(action==='cancel'){this.pendingCancelId=id;this.pendingCancelName=job.name;this.showCancelConfirm=true;return;}
  if(action==='delete'){this.pendingDeleteId=id;this.pendingDeleteName=job.name;this.showDeleteConfirm=true;}
 }
 openPreview(job){
  this.previewJobId=job.id;this.previewOptions=(job.objects||'').split(', ').filter(Boolean).map(value=>({label:value,value}));
  this.previewObject=this.previewOptions[0]?.value||'';this.previewRows=[];this.previewError='';this.showPreview=true;
  if(this.previewObject)this.loadPreview();
 }
 closePreview(){this.showPreview=false;this.previewRows=[];this.previewError='';this.previewRequest++;this.previewBusy=false;}
 changePreviewObject(event){this.previewObject=event.detail.value;this.loadPreview();}
 async loadPreview(){
  const request=++this.previewRequest;this.previewBusy=true;this.previewError='';this.previewRows=[];this.previewCount=0;
  try{const result=await previewMasking({jobId:this.previewJobId,objectApiName:this.previewObject});if(request!==this.previewRequest)return;this.previewRows=result.rows||[];this.previewCount=result.sampleCount||0;}
  catch(error){if(request===this.previewRequest)this.previewError=this.msg(error);}
  finally{if(request===this.previewRequest)this.previewBusy=false;}
 }
 get previewEmpty(){return !this.previewBusy&&!this.previewError&&!this.previewRows.length;}
 get weekdayOptions(){return [{label:'Monday',value:'MON'},{label:'Tuesday',value:'TUE'},{label:'Wednesday',value:'WED'},{label:'Thursday',value:'THU'},{label:'Friday',value:'FRI'},{label:'Saturday',value:'SAT'},{label:'Sunday',value:'SUN'}];}
 handleScheduleDay(e){this.scheduleDay=e.detail.value;}
 handleScheduleTime(e){this.scheduleTime=(e.target.value||'').slice(0,5);}
 closeSchedule(){this.showSchedule=false;}
 async saveSchedule(){this.isLoading=true;try{await scheduleJob({jobId:this.scheduleJobId,frequency:this.scheduleFrequency,dayOfWeek:this.scheduleDay,monthDay:this.scheduleMonthDay,localTime:this.scheduleTime});this.showSchedule=false;await this.refresh();this.toast('Scheduled','Masking job scheduled. Time uses your Salesforce user timezone.','success');}catch(e){this.toast('Could not schedule',this.msg(e),'error');}finally{this.isLoading=false;}}
 async cancelSchedule(id){this.isLoading=true;try{await cancelJobSchedule({jobId:id});await this.refresh();this.toast('Schedule cancelled','Automatic execution stopped.','success');}catch(e){this.toast('Could not cancel schedule',this.msg(e),'error');}finally{this.isLoading=false;}}
 closeCancel(){this.showCancelConfirm=false;this.pendingCancelId=null;this.pendingCancelName='';}
 async confirmCancel(){const id=this.pendingCancelId;if(!id)return;this.isLoading=true;try{await cancelRunningJob({jobId:id});this.closeCancel();await this.refresh();this.toast('Cancellation requested','The active masking batch was aborted. Previously committed records are not rolled back.','success');}catch(e){this.toast('Could not cancel',this.msg(e),'error');}finally{this.isLoading=false;}}
 cancelDelete(){this.showDeleteConfirm=false;this.pendingDeleteId=null;this.pendingDeleteName='';}
 async confirmDelete(){
  const id=this.pendingDeleteId; if(!id)return;
  this.isLoading=true;
  try{await deleteJob({jobId:id});this.cancelDelete();await this.refresh();this.toast('Job deleted','The masking job was deleted. Data Masking Configuration was not changed.','success');}
  catch(e){this.toast('Could not delete job',this.msg(e),'error');}finally{this.isLoading=false;}
 }
 reviewRun(id,recovery){
  const job=this.jobs.find(j=>j.id===id);
  if(!job){this.toast('Job unavailable','Refresh the job list and try again.','error');return;}
  if(!job.configurationReady||job.canCancel){this.toast('Job not ready','This job cannot be started now.','warning');return;}
  this.pendingRunId=id;this.pendingRunRecovery=recovery;this.pendingRunJob={...job,modeLabel:recovery?'Recovery rerun':job.runMode,objectNames:job.objects||'No objects configured',isFull:!recovery&&job.runMode==='Full'};
  this.runAcknowledged=false;this.showRunConfirm=true;
 }
 get runConfirmationDisabled(){return !this.runAcknowledged||this.isLoading;}
 handleRunAcknowledgement(event){this.runAcknowledged=event.target.checked;}
 closeRunReview(){this.showRunConfirm=false;this.runAcknowledged=false;this.pendingRunId=null;this.pendingRunJob=null;this.pendingRunRecovery=false;}
 async confirmRun(){
  if(!this.runAcknowledged||!this.pendingRunId||this.isLoading)return;
  const id=this.pendingRunId,recovery=this.pendingRunRecovery;
  this.closeRunReview();await this.execute(id,recovery);
 }
 async execute(id,recovery){this.isLoading=true;try{recovery?await rerunJob({jobId:id}):await runJob({jobId:id});await this.refresh();this.toast(recovery?'Recovery rerun started':'Masking job started',recovery?'Only records recorded as failed in the previous run will be retried.':'The job is running in the background.','success');}catch(e){this.toast('Could not start job',this.msg(e),'error');}finally{this.isLoading=false;}}
 async openLogs(id){this.isLoading=true;try{this.runDetails=await getLatestRun({jobId:id});this.showDetails=true;}catch(e){this.toast('Could not load run details',this.msg(e),'error');}finally{this.isLoading=false;}}
 closeDetails(){this.showDetails=false;} get runModeOptions(){return[{label:'Full Masking',value:'Full'},{label:'Unmasked records only',value:'Once'}];} get executionOptions(){return[{label:'Serial',value:'Serial'},{label:'Parallel',value:'Parallel'}];}
 msg(e){return e?.body?.message||e?.message||'Unexpected error';} toast(title,message,variant){this.dispatchEvent(new ShowToastEvent({title,message,variant,mode:variant==='error'?'sticky':'dismissable'}));}
}