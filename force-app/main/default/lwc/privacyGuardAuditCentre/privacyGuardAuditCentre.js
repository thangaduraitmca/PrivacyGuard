import { LightningElement } from 'lwc';
import load from '@salesforce/apex/PrivacyGuardAuditController.load';
import detail from '@salesforce/apex/PrivacyGuardAuditController.detail';
const CATEGORIES=['All','Data Masking','PII Discovery','Automation','Files','Configuration','Jobs'];
const COLUMNS=[{label:'When',fieldName:'occurredAt',type:'date',typeAttributes:{year:'numeric',month:'short',day:'2-digit',hour:'2-digit',minute:'2-digit'}},{label:'User',fieldName:'userName'},{label:'Category',fieldName:'category'},{label:'Action / source',fieldName:'actionLabel'},{label:'Status',fieldName:'status'},{label:'Object',fieldName:'target'},{type:'button',typeAttributes:{label:'Details',name:'details',variant:'base'}}];
export default class PrivacyGuardAuditCentre extends LightningElement {
    category='All';status='All';search='';actor='';fromDate;toDate;
    rows=[];columns=COLUMNS;busy=false;error='';hasMore=false;cursorTime;cursorId;cutoff;
    selected;changeRows=[];focusPending=false;
    renderedCallback(){if(this.focusPending){this.focusPending=false;this.template.querySelector('[role="dialog"]')?.focus();}}
    modalKey(event){
        if(event.key==='Escape'){event.preventDefault();this.closeDetail();}
        if(event.key==='Tab'){
            const buttons=[...this.template.querySelectorAll('[role="dialog"] lightning-button')];
            if(!buttons.length)return;
            event.preventDefault();this.modalIndex=(this.modalIndex+(event.shiftKey?-1:1)+buttons.length)%buttons.length;buttons[this.modalIndex].focus();
        }
    }
    modalIndex=-1;
    connectedCallback(){const today=new Date();this.toDate=this.localDate(today);today.setDate(today.getDate()-30);this.fromDate=this.localDate(today);this.refresh();}
    localDate(date){return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;}
    get categories(){return CATEGORIES.map(label=>({label,value:label}));}
    get statuses(){return ['All','Success','Failed'].map(label=>({label,value:label}));}
    get loaded(){return this.rows.length;}
    get failed(){return this.rows.filter(row=>row.status==='Failed').length;}
    get changes(){return this.rows.filter(row=>row.category==='Configuration'||row.category==='Jobs').length;}
    get hasRows(){return this.rows.length>0;}
    get noRows(){return !this.busy&&!this.hasRows&&!this.error;}
    get exportDisabled(){return this.busy||!this.hasRows;}
    get hasChanges(){return this.changeRows.length>0;}
    handleFilter(event){this[event.target.dataset.filter]=event.detail.value||'';this.rows=[];this.hasMore=false;this.selected=null;}
    async refresh(){if(this.busy)return;this.rows=[];this.cursorTime=null;this.cursorId=null;this.cutoff=null;this.selected=null;await this.fetch();}
    async more(){if(!this.busy&&this.hasMore)await this.fetch();}
    async fetch(){
        this.busy=true;this.error='';
        try{
            const page=await load({category:this.category,status:this.status,search:this.search,actor:this.actor,fromDate:this.fromDate||null,toDate:this.toDate||null,cursorTime:this.cursorTime,cursorId:this.cursorId,cutoff:this.cutoff});
            this.rows=[...this.rows,...page.rows.map(row=>({...row,actionLabel:row.action||row.source||'Activity'}))];
            this.hasMore=page.hasMore;this.cursorTime=page.nextTime;this.cursorId=page.nextId;this.cutoff=page.cutoff;
        }catch(error){this.error=error.body?.message||error.message||'Unable to load audit activity.';this.hasMore=false;}
        finally{this.busy=false;}
    }
    async showDetail(event){
        if(this.busy)return;this.busy=true;this.error='';
        try{this.selected=await detail({logId:event.detail.row.id});this.focusPending=true;this.modalIndex=-1;this.changeRows=[];
            if(this.selected.changes){const values=JSON.parse(this.selected.changes);this.changeRows=Object.keys(values).sort().map(field=>({field,before:this.format(values[field].before),after:this.format(values[field].after)}));}
        }catch(error){this.error=error.body?.message||error.message;this.selected=null;}
        finally{this.busy=false;}
    }
    format(value){return value===null||value===undefined?'—':typeof value==='object'?JSON.stringify(value):String(value);}
    closeDetail(){this.selected=null;this.changeRows=[];this.template.querySelector('[data-refresh]')?.focus();}
    exportCsv(){
        const cell=value=>{let text=value==null?'':String(value);if(/^\s*[=+\-@]/.test(text))text="'"+text;return '"'+text.replace(/"/g,'""')+'"';};
        const fields=['occurredAt','userName','category','actionLabel','source','status','target','field','recordId','id','classification'];
        const lines=[fields.map(cell).join(','),...this.rows.map(row=>fields.map(field=>cell(row[field])).join(','))];
        const url=URL.createObjectURL(new Blob(['\uFEFF',lines.join('\r\n')],{type:'text/plain'}));
        const anchor=document.createElement('a');anchor.href=url;anchor.download='privacyguard-audit-loaded.csv';document.body.appendChild(anchor);anchor.click();anchor.remove();URL.revokeObjectURL(url);
    }
}
