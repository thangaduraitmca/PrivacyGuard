import { LightningElement, track } from 'lwc';
import discover from '@salesforce/apex/AutomationManagementController.discover';
import deactivateSelected from '@salesforce/apex/AutomationManagementController.deactivateSelected';
import restoreSelected from '@salesforce/apex/AutomationManagementController.restoreSelected';
import resumeDeploymentChecks from '@salesforce/apex/AutomationManagementController.resumeDeploymentChecks';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
const TRIGGER_TYPE = 'APEX_TRIGGER';
export default class AutomationManagement extends LightningElement {
 @track rows=[]; @track summary={total:0,active:0,tracked:0}; loading=false; scanRequired=false; discoveryWarning=''; query=''; stateFilter='ALL';
 progressTimer; hasPending=false; checkRequired=false;
 disconnectedCallback(){clearTimeout(this.progressTimer);}
 scheduleRefresh(){clearTimeout(this.progressTimer);if(this.isConnected&&this.hasPending)this.progressTimer=setTimeout(()=>this.load(),15000);}
 async checkDeployments(){this.loading=true;try{const message=await resumeDeploymentChecks();this.toast('Deployment status',message,'info');}catch(e){this.toast('Status check failed',this.msg(e),'error');}finally{this.loading=false;}await this.load();}
 stateOptions=[{label:'All states',value:'ALL'},{label:'Active',value:'Active'},{label:'Inactive',value:'Inactive'}];
 async load(){
  clearTimeout(this.progressTimer);this.loading=true;this.scanRequired=false;this.rows=[];this.summary={total:0,active:0,tracked:0};
  try {
   const result=await discover();
   const triggers=(result.items||[]).filter(r=>r.type===TRIGGER_TYPE);
   this.hasPending=!!result.pending;this.checkRequired=!!result.checkRequired;
   this.rows=triggers.map(r=>this.decorate(r));
   this.summary={total:triggers.length,active:triggers.filter(r=>r.state==='Active').length,tracked:result.tracked||0};
   this.discoveryWarning=(result.warnings||[]).filter(w => /apex trigger|trigger discovery/i.test(w) && !/validation rule|flow inventory|flow discovery/i.test(w)).join(' | ');
   if(this.discoveryWarning)this.toast('Trigger discovery warning',this.discoveryWarning,'warning');
  }catch(e){this.discoveryWarning=this.msg(e);this.toast('Trigger discovery failed',this.discoveryWarning,'error');}
  finally{this.loading=false;this.scheduleRefresh();}
 }
 decorate(r){return {...r,readOnly:!!r.readOnly,selected:false,typeLabel:'Apex Trigger',typeClass:'type apex_trigger',stateClass:'state '+(r.state==='Active'?'active':'inactive')};}
 get filtered(){return this.rows.filter(r=>(this.stateFilter==='ALL'||r.state===this.stateFilter)&&(!this.query||((r.name||'')+' '+(r.objectName||'')+' Apex Trigger').toLowerCase().includes(this.query)));}
 get selected(){return this.rows.filter(r=>r.selected&&r.type===TRIGGER_TYPE).map(r=>({componentId:r.componentId,type:r.type,name:r.name,detail:r.detail}));}
 get noSelectableRows(){return !this.filtered.some(r=>!r.readOnly);} get selectedCount(){return this.selected.length;} get noSelection(){return this.selectedCount===0||this.loading;} get visibleCount(){return this.filtered.length;} get empty(){return !this.loading&&this.filtered.length===0;} get emptyMessage(){return this.scanRequired?'Trigger state may have changed. Click Scan Triggers to retrieve the latest state.':this.summary.total===0?'Click Scan Triggers to discover Apex Triggers.':'No Apex Triggers match your filters.';}
 search(e){this.query=(e.target.value||'').toLowerCase();} filterState(e){this.stateFilter=e.detail.value;}
 toggleOne(e){const k=e.target.dataset.key;this.rows=this.rows.map(r=>r.key===k&&!r.readOnly?{...r,selected:e.target.checked}:r);}
 toggleAll(e){const keys=new Set(this.filtered.filter(r=>!r.readOnly).map(r=>r.key));this.rows=this.rows.map(r=>keys.has(r.key)?{...r,selected:e.target.checked}:r);}
 async deactivate(){await this.act(deactivateSelected,'Trigger deactivation');} async restore(){await this.act(restoreSelected,'Trigger restoration');}
 async act(fn,title){this.loading=true;try{const m=await fn({selectionJson:JSON.stringify(this.selected)});this.toast(title,m,'success');await this.load();}catch(e){this.toast(title+' failed',this.msg(e),'error');}finally{this.loading=false;}}
 toast(title,message,variant){this.dispatchEvent(new ShowToastEvent({title,message,variant,mode:variant==='error'?'sticky':'dismissable'}));} msg(e){return e?.body?.message||e?.message||'Unexpected error';}
}
