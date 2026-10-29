import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOverview from '@salesforce/apex/PrivacyGuardHomeController.getOverview';
import { refreshApex } from '@salesforce/apex';
import MASKING_LOG_OBJECT from '@salesforce/schema/Masking_Log__c';
const NAV = [
 {id:'overview',label:'Overview',icon:'utility:home'},
 {id:'discovery',label:'PII Discovery',icon:'utility:search'},
 {id:'config',label:'Masking Configuration',icon:'utility:settings'},
 {id:'jobs',label:'Masking Jobs',icon:'utility:layers'},
 {id:'keywords',label:'PII Keywords',icon:'utility:key'},
 {id:'automation',label:'Automation',icon:'utility:flow'},
 {id:'purge',label:'Attachment & File Manager',icon:'utility:file'},
 {id:'logs',label:'Audit Logs',icon:'utility:record'}
];
export default class PrivacyGuardHome extends NavigationMixin(LightningElement) {
 activeSection = 'overview';
 data; error; loading=true; wiredResult;
 @wire(getOverview) wiredOverview(value) { this.wiredResult=value; this.loading=false; if(value.data){this.data=value.data;this.error=undefined;}else if(value.error){this.error=value.error.body?.message || 'Unable to load dashboard';} }
 get navigation(){return NAV.map(item=>({...item,className:item.id===this.activeSection?'nav-link active':'nav-link',selected:item.id===this.activeSection?'page':'false'}));}
 navigate(event){this.activeSection=event.currentTarget.dataset.section;}
 get isOverview(){return this.activeSection==='overview';}
 get isDiscovery(){return this.activeSection==='discovery';}
 get isConfig(){return this.activeSection==='config';}
 get isJobs(){return this.activeSection==='jobs';}
 get isKeywords(){return this.activeSection==='keywords';}
 get isAutomation(){return this.activeSection==='automation';}
 get isPurge(){return this.activeSection==='purge';}
 get isLogs(){return this.activeSection==='logs';}
 openLogs(){this[NavigationMixin.Navigate]({type:'standard__objectPage',attributes:{objectApiName:MASKING_LOG_OBJECT.objectApiName,actionName:'list'}});}
 async refresh(){this.loading=true;try{await refreshApex(this.wiredResult);}finally{this.loading=false;}}
 get dataWarning(){return this.data?.dataWarning;}
 get environmentName(){return this.data?.environmentName || 'Salesforce Sandbox';}
 get scanSummary(){return this.data?.lastScanDate ? `Last PII scan completed ${this.data.lastScanDate}` : 'No completed PII scan available';}
 get coverage(){return this.data?.coverage ?? 0;}
 get coverageLabel(){return this.data?.acceptedFields > 0 && this.data?.coverage != null ? `${this.coverage}%` : 'N/A';}
 get coverageStyle(){return `width:${this.coverage}%`;} 
 get objectsConfigured(){return this.data?.objectsConfigured ?? '—';}
 get fieldsConfigured(){return this.data?.fieldsConfigured ?? '—';}
 get acceptedFields(){return this.data?.acceptedFields === null ? '—' : (this.data?.acceptedFields ?? '—');}
 get protectedFields(){return this.data?.protectedFields === null ? '—' : (this.data?.protectedFields ?? '—');}
 get reviewFields(){return this.data?.reviewFields === null ? '—' : (this.data?.reviewFields ?? '—');}
 get completedRuns(){return this.data?.completedRuns ?? 0;}
 get failedRuns(){return this.data?.failedRuns ?? 0;}
 get privacyStatus(){return this.data?.privacyStatus || 'Not Assessed';}
 get privacyExplanation(){return this.data?.privacyExplanation || 'Complete a PII scan and masking run to assess protection.';}
 get statusClass(){return this.privacyStatus==='Protected'?'status-pill good':'status-pill caution';}
 get runs(){return (this.data?.recentRuns || []).map(r=>({...r,statusClass:r.status==='Completed'?'run-status good-text':'run-status warning-text'}));}
 get hasRuns(){return this.runs.length>0;}
}