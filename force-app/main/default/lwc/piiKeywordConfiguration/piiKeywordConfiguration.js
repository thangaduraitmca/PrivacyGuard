import { LightningElement, track } from 'lwc';
import getKeywords from '@salesforce/apex/PrivacyGuardConfigurationController.getKeywords';
import saveKeyword from '@salesforce/apex/PrivacyGuardConfigurationController.saveKeyword';
import deleteKeyword from '@salesforce/apex/PrivacyGuardConfigurationController.deleteKeyword';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PiiKeywordConfiguration extends LightningElement {
    @track rows = [];
    keyword = '';
    notes = '';
    busy = false;

    connectedCallback() { this.load(); }
    async load() { this.rows = await getKeywords(); }
    changeKeyword(e) { this.keyword = e.detail.value; }
    changeNotes(e) { this.notes = e.detail.value; }
    rowChange(e) {
        const id=e.target.dataset.id, field=e.target.dataset.field;
        const val=e.target.type==='toggle' ? e.target.checked : e.detail.value;
        this.rows=this.rows.map(r=>r.id===id?{...r,[field]:val}:r);
    }
    async add() {
        if (!this.keyword || !this.keyword.trim()) { this.toast('Keyword required','Enter a keyword before adding it.','error'); return; }
        this.busy=true;
        try {
            await saveKeyword({id:null,keyword:this.keyword.trim(),active:true,notes:this.notes});
            this.keyword=''; this.notes='';
            await this.load();
            this.toast('Keyword added','Keyword saved, activated, and will be used on the next PII scan.','success');
        } catch(e) { this.toast('Unable to add keyword',this.message(e),'error'); }
        finally { this.busy=false; }
    }
    async saveRow(e) {
        const id=e.currentTarget.dataset.id, r=this.rows.find(x=>x.id===id);
        this.busy=true;
        try { await saveKeyword({id:r.id,keyword:r.keyword,active:r.active,notes:r.notes}); await this.load(); this.toast('Updated','Keyword updated.','success'); }
        catch(e){ this.toast('Unable to update keyword',this.message(e),'error'); }
        finally { this.busy=false; }
    }
    async removeRow(e) {
        const key=e.currentTarget.dataset.key, r=this.rows.find(x=>x.key===key);
        if (!r || !confirm(`Delete keyword "${r.keyword}"? It will no longer be used in future PII scans.`)) return;
        this.busy=true;
        try { await deleteKeyword({id:r.id || null,keyword:r.keyword,packagedDefault:!r.editable}); await this.load(); this.toast('Keyword deleted',`"${r.keyword}" will not be used in future scans.`,'success'); }
        catch(e){ this.toast('Unable to delete keyword',this.message(e),'error'); }
        finally { this.busy=false; }
    }
    message(e){ return e?.body?.message || e?.message || 'Unexpected error.'; }
    toast(title,message,variant){this.dispatchEvent(new ShowToastEvent({title,message,variant}));}
}
