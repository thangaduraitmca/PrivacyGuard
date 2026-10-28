import { LightningElement, track } from 'lwc';
import getConfigurations from '@salesforce/apex/PrivacyGuardConfigurationController.getConfigurations';
import getObjects from '@salesforce/apex/PrivacyGuardConfigurationController.getObjects';
import getEligibleFields from '@salesforce/apex/PrivacyGuardConfigurationController.getEligibleFields';
import saveConfigurations from '@salesforce/apex/PrivacyGuardConfigurationController.saveConfigurations';
import deleteConfigurations from '@salesforce/apex/PrivacyGuardConfigurationController.deleteConfigurations';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const BASE_STRATEGIES=[
 {label:'Not configured',value:''},
 {label:'Randomize text',value:'RANDOM_STRING'},
 {label:'Randomize email (safe)',value:'EMAIL_INVALID'},
 {label:'Randomize email (preserve domain)',value:'EMAIL'},
 {label:'Randomize phone',value:'PHONE'},
 {label:'Randomize name',value:'NAME'},
 {label:'Random value from list',value:'LIST'},
 {label:'Static replacement',value:'STATIC'},
 {label:'Random number within range',value:'NUMBER_RANGE'},
 {label:'Clear value (NULL)',value:'NULL'},
 {label:'Regex replacement',value:'REGEX'}
];
const STRATEGY_MAP={
 EMAIL:['','EMAIL_INVALID','EMAIL','STATIC','REGEX','NULL','LIST'],
 PHONE:['','PHONE','STATIC','REGEX','NULL','LIST']
};
function regexRuleError(row){
 if(row.strategy==='NUMBER_RANGE'){
  const parts=(row.pattern||'').split('|').map(value=>value.trim());
  if(parts.length!==3||!parts[0]||!parts[1]||!parts[2])return 'Use minimum|maximum|decimal places, for example 100|999|0.';
  if(!/^-?[0-9]+(\.[0-9]+)?$/.test(parts[0])||!/^-?[0-9]+(\.[0-9]+)?$/.test(parts[1])||!/^([0-9]|1[0-8])$/.test(parts[2]))return 'Enter numeric bounds and decimal places from 0 to 18.';
  // Server-side Decimal validation is authoritative for ordering, precision and scale.
  return null;
 }
 if((row.strategy||'').trim().toUpperCase()==='LIST'){
  const rule=row.pattern||'';
  if(!rule.trim())return 'Enter replacement values separated by |, for example Morgan|Jordan|Taylor.';
  if(rule.length>255)return 'Replacement list must be 255 characters or fewer.';
  if(rule.split('|').some(value=>!value.trim()))return 'Replacement list cannot contain empty entries.';
  return null;
 }
 if((row.strategy||'').trim().toUpperCase()!=='REGEX') return null;
 const rule=row.pattern||'';
 if(!rule.trim()) return 'Enter a regex rule, for example [0-9]=>X.';
 const separator=rule.indexOf('=>');
 if(separator<1||!rule.slice(0,separator).trim()) return 'Use regex=>replacement, for example [0-9]=>X. An empty replacement after => removes matches.';
 return null;
}
function patternHelp(row){
 if(row.strategy==='NUMBER_RANGE')return 'Format: minimum|maximum|decimal places. Examples: 100|999|0 or 10.00|99.99|2. Inclusive bounds; blank values stay blank.';
 if(row.strategy==='LIST')return 'Separate values with |, for example Morgan|Jordan|Taylor. Maximum 255 characters. Blank source values stay blank. Values may repeat across records.';
 if(row.strategy==='NULL') return 'Removes the stored value. Required fields cannot be cleared.';
 if(row.strategy==='REGEX') return 'Format: regex=>replacement. Example: [0-9]=>X. Leave the replacement empty to remove matches.';
 return null;
}
function patternPlaceholder(row){
 if(row.strategy==='NUMBER_RANGE')return 'Required: 100|999|0';
 if(row.strategy==='LIST')return 'Required: Morgan|Jordan|Taylor';
 if(row.strategy==='NULL') return 'Clears the field value';
 if((row.strategy||'').trim().toUpperCase()==='REGEX') return 'Required: [0-9]=>X';
 if(row.strategy !== 'STATIC') return 'Optional';
 const type=(row.fieldType||'').toUpperCase();
 const hints={
  DATE:'YYYY-MM-DD', DATETIME:'YYYY-MM-DD HH:mm:ss',
  DOUBLE:'123.45', INTEGER:'123', CURRENCY:'123.45', PERCENT:'12.50',
  BOOLEAN:'true or false', EMAIL:'masked@example.com',
  PHONE:'0400000000', URL:'https://example.com'
 };
 return hints[type] || 'Enter replacement text';
}
function strategyOptions(row){
 if(row.unsupported)return [];
 const numeric=['DOUBLE','INTEGER','CURRENCY','PERCENT'];
 if(numeric.includes((row.fieldType||'').toUpperCase()))return BASE_STRATEGIES.filter(o=>['','STATIC','NULL','NUMBER_RANGE'].includes(o.value));
 const typed=['DOUBLE','INTEGER','CURRENCY','PERCENT','DATE','DATETIME','BOOLEAN'];
 if(typed.includes((row.fieldType||'').toUpperCase()))
  return BASE_STRATEGIES.filter(o=>o.value===''||o.value==='STATIC'||o.value==='NULL');
 const type=(row.fieldType||'').toUpperCase();
 let allowed=STRATEGY_MAP[type];
 if(!allowed){
  const looksLikeName=/(^|_)(first|last|middle|full)?name($|_)/i.test(row.fieldApiName||'') || /name/i.test(row.fieldLabel||'');
  allowed=looksLikeName?['','NAME','RANDOM_STRING','STATIC','REGEX','NULL','LIST']:['','RANDOM_STRING','STATIC','REGEX','NULL','LIST'];
 }
 return BASE_STRATEGIES.filter(o=>allowed.includes(o.value));
}
export default class DataMaskingConfiguration extends LightningElement {
 @track groups=[]; @track objectOptions=[]; @track fieldOptions=[];
 showAdd=false; showDelete=false; deleteTarget; selectedObject=''; selectedFields=[];
 searchTerm=''; statusFilter='ALL'; dirty=false; loading=false; dirtyKeys=new Set();
 statusOptions=[{label:'All',value:'ALL'},{label:'Active',value:'ACTIVE'},{label:'Inactive',value:'INACTIVE'},{label:'Needs strategy',value:'NEEDS_STRATEGY'},{label:'Errors',value:'ERRORS'}];
 connectedCallback(){ this.initialise(); }
 async initialise(){ try{this.loading=true; await this.load();}catch(e){this.err(e);}finally{this.loading=false;} }
 async load(){ const rows=await getConfigurations(); const m={}; rows.forEach(r=>{if(!m[r.objectApiName])m[r.objectApiName]={name:r.objectApiName,expanded:false,rows:[]};m[r.objectApiName].rows.push({...r,active:r.unsupported?false:r.active,strategyOptions:strategyOptions(r),patternPlaceholder:patternPlaceholder(r),patternRequired:r.strategy==='REGEX'||r.strategy==='LIST'||r.strategy==='NUMBER_RANGE',patternDisabled:r.strategy==='NULL',patternHelp:patternHelp(r),errorKey:`error-${r.id}`});}); this.allGroups=Object.values(m); this.applyFilters(); }
 applyFilters(){const q=(this.searchTerm||'').toLowerCase(); this.groups=(this.allGroups||[]).map(g=>{let rows=g.rows.filter(r=>{const text=`${g.name} ${r.fieldApiName||''} ${r.fieldLabel||''} ${r.fieldType||''}`.toLowerCase(); const status=this.statusFilter==='ALL'||(this.statusFilter==='ACTIVE'&&r.active)||(this.statusFilter==='INACTIVE'&&!r.active)||(this.statusFilter==='NEEDS_STRATEGY'&&!r.unsupported&&!r.strategy)||(this.statusFilter==='ERRORS'&&!!r.errorMessage);return (!q||text.includes(q))&&status;});return {...g,rows,count:rows.length,chevron:g.expanded?'utility:chevrondown':'utility:chevronright'};}).filter(g=>g.rows.length); }
 get objectCount(){return (this.allGroups||[]).length;} get fieldCount(){return (this.allGroups||[]).reduce((n,g)=>n+g.rows.length,0);} get activeCount(){return (this.allGroups||[]).reduce((n,g)=>n+g.rows.filter(r=>r.active).length,0);} get needsStrategyCount(){return (this.allGroups||[]).reduce((n,g)=>n+g.rows.filter(r=>!r.unsupported&&!r.strategy).length,0);} get hasGroups(){return this.groups.length>0;} get saveDisabled(){return !this.dirty||this.loading;} get errorCount(){return (this.allGroups||[]).reduce((n,g)=>n+g.rows.filter(r=>!!r.errorMessage).length,0);}
 toggle(e){const n=e.currentTarget.dataset.name;this.allGroups=this.allGroups.map(g=>g.name===n?{...g,expanded:!g.expanded}:g);this.applyFilters();}
 expandAll(){this.allGroups=this.allGroups.map(g=>({...g,expanded:true}));this.applyFilters();} collapseAll(){this.allGroups=this.allGroups.map(g=>({...g,expanded:false}));this.applyFilters();}
 searchChanged(e){this.searchTerm=e.target.value;this.applyFilters();} filterChanged(e){this.statusFilter=e.detail.value;this.applyFilters();}
 async openAdd(){this.showAdd=true; if(this.objectOptions.length)return; try{this.loading=true; this.objectOptions=(await getObjects()).slice().sort((a,b)=>a.label.localeCompare(b.label,undefined,{sensitivity:'base'}));}catch(e){this.err(e);}finally{this.loading=false;} } closeAdd(){this.showAdd=false;this.selectedObject='';this.selectedFields=[];this.fieldOptions=[];}
 async objectChanged(e){this.selectedObject=e.detail.value;try{this.fieldOptions=await getEligibleFields({objectApiName:this.selectedObject});}catch(x){this.err(x);}}
 fieldsChanged(e){this.selectedFields=e.detail.value;}
 mutate(id,change){
  // Keep the rendered grid stable while editing. Only update the local draft.
  const updateRow=r=>{
   if(r.id!==id)return r;
   const updated={...r,...change,errorMessage:null};
   if(updated.strategy==='NULL')updated.pattern=null;
   return {...updated,patternPlaceholder:patternPlaceholder(updated),patternRequired:updated.strategy==='REGEX'||updated.strategy==='LIST'||updated.strategy==='NUMBER_RANGE',patternDisabled:updated.strategy==='NULL',patternHelp:patternHelp(updated)};
  };
  this.allGroups=this.allGroups.map(g=>({...g,rows:g.rows.map(updateRow)}));
  // Update visible row hints without reapplying filters or collapsing the editor.
  this.groups=this.groups.map(g=>({...g,rows:g.rows.map(updateRow)}));
  this.dirtyKeys.add(id);
  this.dirty=true;
 }
 strategyChanged(e){this.mutate(e.target.dataset.id,{strategy:e.detail.value});} patternChanged(e){this.mutate(e.target.dataset.id,{pattern:e.detail.value});} activeChanged(e){this.mutate(e.target.dataset.id,{active:e.target.checked});}
 async saveExisting(){
  if(this.loading)return;
  this.loading=true;
  const changed=this.allGroups.flatMap(g=>g.rows).filter(r=>this.dirtyKeys.has(r.id)&&!r.unsupported);
  let saved=0,failed=0;
  // Each field is an independent Apex transaction. Invalid fields never block valid fields.
  for(const row of changed){
   const validationError=regexRuleError(row);
   if(validationError){failed++;this.setRowError(row.id,validationError);continue;}
   try{
    await saveConfigurations({rows:[{objectApiName:row.objectApiName,fieldApiName:row.fieldApiName,strategy:row.strategy,pattern:row.pattern,active:row.active,source:row.source}]});
    this.dirtyKeys.delete(row.id); saved++;
    this.setRowError(row.id,null);
   }catch(e){
    failed++;
    this.setRowError(row.id,e?.body?.message||e?.message||'Unable to save this field.');
   }
  }
  this.dirty=this.dirtyKeys.size>0;
  this.loading=false;
  if(saved&&!failed)this.toast('Configurations saved',`${saved} field(s) saved successfully.`, 'success');
  if(failed){
   // Preserve the current filter and expanded sections after Save.
   this.toast('Review field errors',`${failed} field(s) could not be saved; ${saved} saved. See inline errors below.`, 'error');
  }
 }
 setRowError(id,message){this.allGroups=this.allGroups.map(g=>({...g,rows:g.rows.map(r=>r.id===id?{...r,errorMessage:message}:r)}));this.applyFilters();}
 async addSelected(){if(!this.selectedObject||!this.selectedFields.length)return;try{this.loading=true;const rows=this.selectedFields.map(f=>({objectApiName:this.selectedObject,fieldApiName:f,strategy:'',active:false,source:'Manual'}));await saveConfigurations({rows});this.closeAdd();this.toast('Fields added','Fields were added inactive. Choose a strategy before activation.','success');await this.load();}catch(e){this.err(e);}finally{this.loading=false;}}
 requestDelete(e){const id=e.currentTarget.dataset.id;this.deleteTarget=this.allGroups.flatMap(g=>g.rows).find(r=>r.id===id);this.showDelete=true;} cancelDelete(){this.showDelete=false;this.deleteTarget=null;}
 async confirmDelete(){try{this.loading=true;await deleteConfigurations({configurationIds:[this.deleteTarget.id]});this.toast('Configuration removed',`${this.deleteTarget.objectApiName}.${this.deleteTarget.fieldApiName} will no longer be masked.`,'success');this.cancelDelete();await this.load();}catch(e){this.err(e);}finally{this.loading=false;}}
 toast(title,message,variant){this.dispatchEvent(new ShowToastEvent({title,message,variant}));} err(e){this.toast('Error',e?.body?.message||e.message,'error');}
}
