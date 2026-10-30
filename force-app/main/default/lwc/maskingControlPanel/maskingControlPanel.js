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

 detailJobId; detailRunId;detailTimer;clockTimer;detailGeneration=0;detailBusy=false;detailError='';lastUpdated;clockNow=Date.now();
 disconnectedCallback(){this.stopMonitor();}
 stopMonitor(){this.detailBusy=false;this.detailGeneration++;clearTimeout(this.detailTimer);clearInterval(this.clockTimer);this.detailTimer=null;this.clockTimer=null;}
 get runIsActive(){return ['Running','Queued','Processing','Preparing','Holding'].includes(this.runDetails?.run?.status);}
 get durationLabel(){return this.duration(this.runDetails?.run?.startedAt,this.runDetails?.run?.completedAt);}
 duration(start,end){if(!start)return '—';const seconds=Math.max(0,Math.floor(((end?new Date(end).getTime():this.clockNow)-new Date(start).getTime())/1000));const hours=Math.floor(seconds/3600),minutes=Math.floor(seconds%3600/60);return `${hours?hours+'h ':''}${minutes}m ${seconds%60}s`;}
 get objectResults(){return (this.runDetails?.objects||[]).map(row=>{let fraction=0;const finished=['Completed','Partial','Failed','Skipped'].includes(row.status);if(finished)fraction=1;else if(row.batchesTotal>0)fraction=Math.min(1,Number(row.batchesDone||0)/Number(row.batchesTotal));const percent=Math.round(fraction*100);return {...row,percent,progressStyle:`width:${percent}%`,duration:this.duration(row.startedAt,row.completedAt),batchLabel:row.batchesTotal>0?`${row.batchesDone||0} / ${row.batchesTotal} batches`:(finished?'Processing finished':'Waiting for batch totals'),engineLabel:row.engineStatus||row.status};});}
 get progressPercent(){const rows=this.objectResults;if(!rows.length)return 0;if(['Completed','Completed with Errors'].includes(this.runDetails?.run?.status))return 100;return Math.min(100,Math.floor(rows.reduce((sum,row)=>sum+row.percent,0)/rows.length));}
 get progressStyle(){return `width:${this.progressPercent}%`;}
 get objectCount(){return this.objectResults.length;}
 get finishedObjectCount(){return this.objectResults.filter(row=>['Completed','Partial','Failed','Skipped'].includes(row.status)).length;}
 get activeObjects(){return this.objectResults.filter(row=>row.status==='Running').map(row=>row.objectApiName).join(', ')||(this.runIsActive?'Waiting for execution':'None');}
 get successfulCount(){return Number(this.runDetails?.run?.processed||0);}
 get failedCount(){return Number(this.runDetails?.run?.failed||0);}
 get attemptedCount(){return this.successfulCount+this.failedCount;}
 get throughput(){if(!this.runDetails?.run?.startedAt)return '—';const seconds=((this.runDetails.run.completedAt?new Date(this.runDetails.run.completedAt).getTime():this.clockNow)-new Date(this.runDetails.run.startedAt).getTime())/1000;return seconds>0?`${Math.round(this.successfulCount/seconds).toLocaleString()} records/sec`:'—';}
 get hasRunProblems(){return this.failedCount>0||['Failed','Cancelled','Completed with Errors'].includes(this.runDetails?.run?.status)||this.objectResults.some(row=>row.errorSummary||Number(row.engineErrors||0)>0||['Failed','Partial','Cancelled'].includes(row.status));}
 get errorEmptyMessage(){return this.hasRunProblems?'No record-level error log was captured. Review the object error summary and Apex job for details.':this.runIsActive?'No errors reported so far.':'No errors reported.';}
 get monitorLabel(){return this.runIsActive?'Live · refreshes every 5 seconds':'Run finished';}
 async refreshRun(){clearTimeout(this.detailTimer);if(this.detailBusy||!this.detailJobId)return;const generation=this.detailGeneration;this.detailBusy=true;this.detailError='';try{const result=await getLatestRun({jobId:this.detailJobId});if(generation!==this.detailGeneration)return;if(this.detailRunId&&result.run?.id!==this.detailRunId){this.detailError='A newer run exists. Close this dashboard and open Run Details to view it.';this.stopMonitor();return;}this.runDetails=result;this.detailRunId=result.run?.id;this.clockNow=Date.now();this.lastUpdated=new Date().toLocaleTimeString();}catch(error){if(generation===this.detailGeneration)this.detailError=this.msg(error);}finally{if(generation===this.detailGeneration){this.detailBusy=false;if(this.showDetails&&this.runIsActive)this.detailTimer=setTimeout(()=>this.refreshRun(),5000);}}}
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
 async execute(id,recovery){this.isLoading=true;let started=false;try{recovery?await rerunJob({jobId:id}):await runJob({jobId:id});started=true;await this.refresh();this.toast(recovery?'Recovery rerun started':'Masking job started','Follow progress in the live run dashboard.','success');}catch(e){this.toast('Could not start job',this.msg(e),'error');}finally{this.isLoading=false;}if(started)await this.openLogs(id);}
 async openLogs(id){this.stopMonitor();this.detailJobId=id;this.detailRunId=null;this.runDetails={run:null,objects:[],logs:[]};this.showDetails=true;this.detailError='';this.clockNow=Date.now();this.clockTimer=setInterval(()=>{this.clockNow=Date.now();},1000);await this.refreshRun();}
 closeDetails(){this.showDetails=false;this.stopMonitor();this.detailJobId=null;this.detailRunId=null;}
 get runModeOptions(){return[{label:'Full Masking',value:'Full'},{label:'Unmasked records only',value:'Once'}];} get executionOptions(){return[{label:'Serial',value:'Serial'},{label:'Parallel',value:'Parallel'}];}
 msg(e){return e?.body?.message||e?.message||'Unexpected error';} toast(title,message,variant){this.dispatchEvent(new ShowToastEvent({title,message,variant,mode:variant==='error'?'sticky':'dismissable'}));}
}