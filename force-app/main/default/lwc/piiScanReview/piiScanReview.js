import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getScanResults from '@salesforce/apex/PIIScanReviewController.getScanResults';
import updateReviewStatus from '@salesforce/apex/PIIScanReviewController.updateReviewStatus';
import runScan from '@salesforce/apex/PIIScanReviewController.runScan';
import getScanStatus from '@salesforce/apex/PIIScanReviewController.getScanStatus';

const STATUS_OPTIONS = [
    { label: 'Pending', value: 'New' }, { label: 'Accepted', value: 'Accepted' },
    { label: 'Removed', value: 'Removed' }, { label: 'All', value: 'All' }
];
const ACTIVE = new Set(['Holding', 'Preparing', 'Queued', 'Processing']);

export default class PiiScanReview extends LightningElement {
    statusOptions = STATUS_OPTIONS; statusFilter = 'New'; searchTerm = ''; selectedIds = [];
    wiredResult; isLoading = false;
    manualObjectApiName = ''; manualFieldApiName = ''; scanStatus; scanJobId; pollHandle;
    expandedObjects = new Set();

    connectedCallback() { this.refreshScanStatus(); }
    disconnectedCallback() { this.stopPolling(); }
    @wire(getScanResults, { statusFilter: '$statusFilter' }) wiredScanResults(result) { this.wiredResult = result; }

    get records() { return this.wiredResult?.data || []; }
    get filteredRecords() {
        const q = (this.searchTerm || '').trim().toLowerCase();
        return this.records.filter(r => {
            const statusMatch = this.statusFilter === 'All' || r.reviewStatus === this.statusFilter;
            const searchMatch = !q || [r.objectApiName, r.fieldApiName, r.fieldLabel, r.salesforceFieldType, r.detectionReason, r.nativeComplianceTag]
                .some(v => (v || '').toLowerCase().includes(q));
            return statusMatch && searchMatch;
        });
    }
    get objectGroups() {
        const map = new Map();
        this.filteredRecords.forEach(r => {
            if (!map.has(r.objectApiName)) map.set(r.objectApiName, []);
            map.get(r.objectApiName).push({ ...r, selected: this.selectedIds.includes(r.id) });
        });
        return [...map.entries()].map(([name, rows]) => ({
            name, rows, count: rows.length, expanded: this.expandedObjects.has(name),
            icon: this.expandedObjects.has(name) ? 'utility:chevrondown' : 'utility:chevronright',
            accepted: rows.filter(r => r.reviewStatus === 'Accepted').length,
            pending: rows.filter(r => r.reviewStatus === 'New').length
        }));
    }
    get candidateCount() { return this.records.length; }
    get objectCount() { return new Set(this.records.map(r => r.objectApiName)).size; }
    get acceptedCount() { return this.records.filter(r => r.reviewStatus === 'Accepted').length; }
    get removedCount() { return this.records.filter(r => r.reviewStatus === 'Removed').length; }
    get noSelection() { return this.selectedIds.length === 0; }
    get acceptSelectedLabel() { return `Accept Selected (${this.selectedIds.length})`; }
    get removeSelectedLabel() { return `Remove Selected (${this.selectedIds.length})`; }
    get hasResults() { return this.filteredRecords.length > 0; }
    get scanRunning() { return !!(this.scanStatus && ACTIVE.has(this.scanStatus.status)); }
    get showScanPanel() { return !!this.scanStatus; }
    get progressValue() { return (!this.scanStatus?.total) ? 0 : Math.min(100, Math.round((this.scanStatus.processed / this.scanStatus.total) * 100)); }
    get scanStatusLabel() { return this.scanStatus ? this.scanStatus.status : 'Not started'; }

    handleFilterChange(e) { this.statusFilter = e.detail.value; this.selectedIds = []; }
    handleSearch(e) { this.searchTerm = e.target.value; }
    toggleObject(e) { const n=e.currentTarget.dataset.object; const next=new Set(this.expandedObjects); next.has(n)?next.delete(n):next.add(n); this.expandedObjects=next; }
    handleCandidateSelect(e) { const id=e.target.dataset.id; const next=new Set(this.selectedIds); e.target.checked?next.add(id):next.delete(id); this.selectedIds=[...next]; }
    selectObject(e) { const n=e.currentTarget.dataset.object; const ids=this.filteredRecords.filter(r=>r.objectApiName===n).map(r=>r.id); const next=new Set(this.selectedIds); ids.forEach(id=>next.add(id)); this.selectedIds=[...next]; }
    async acceptObject(e) {
        const name = e.currentTarget.dataset.object;
        const rows = this.filteredRecords.filter(r => r.objectApiName === name);
        const selectedInObject = rows.filter(r => this.selectedIds.includes(r.id)).length;
        const extra = selectedInObject ? ` You currently have ${selectedInObject} field(s) selected; this action intentionally applies to all ${rows.length} candidates.` : '';
        const confirmed = await LightningConfirm.open({
            label: 'Accept entire object?',
            message: `Accept all ${rows.length} candidate(s) for ${name}?${extra}`,
            theme: 'warning'
        });
        if (confirmed) await this.setStatus('Accepted', rows.map(r => r.id));
    }
    async removeObject(e) {
        const name = e.currentTarget.dataset.object;
        const rows = this.filteredRecords.filter(r => r.objectApiName === name);
        const confirmed = await LightningConfirm.open({
            label: 'Remove entire object?',
            message: `Mark all ${rows.length} candidate(s) for ${name} as Removed?`,
            theme: 'warning'
        });
        if (confirmed) await this.setStatus('Removed', rows.map(r => r.id));
    }
    async setStatusForObject(name,status) { const ids=this.filteredRecords.filter(r=>r.objectApiName===name).map(r=>r.id); await this.setStatus(status,ids); }
    handleAccept() { this.setStatus('Accepted', this.selectedIds); }
    handleRemove() { this.setStatus('Removed', this.selectedIds); }
    async setStatus(status, ids) {
        if (!ids?.length) return; this.isLoading=true;
        try { await updateReviewStatus({recordIds:ids,newStatus:status}); this.selectedIds=[]; await refreshApex(this.wiredResult); this.toast('Review updated', `${ids.length} candidate(s) marked ${status}.`, 'success'); }
        catch(e){this.toast('Error updating records',this.extractError(e),'error');} finally{this.isLoading=false;}
    }
    async handleRunScan(){this.isLoading=true;try{this.scanJobId=await runScan();await this.refreshScanStatus();this.startPolling();this.toast('PII discovery started','Live progress is shown below.','success');}catch(e){this.toast('Error starting scan',this.extractError(e),'error');}finally{this.isLoading=false;}}
    async refreshScanStatus(){try{const previous=this.scanStatus?.status;const status=await getScanStatus({jobId:this.scanJobId||null});if(!status)return;this.scanStatus=status;this.scanJobId=status.jobId;if(ACTIVE.has(status.status))this.startPolling();else{this.stopPolling();if(previous&&ACTIVE.has(previous)){await refreshApex(this.wiredResult);this.toast(status.status==='Completed'?'PII discovery completed':'PII discovery ended',`Candidates found: ${status.candidatesFound}. Errors: ${status.errors}.`,status.status==='Completed'?'success':'error');}}}catch(e){this.stopPolling();this.toast('Could not refresh scan status',this.extractError(e),'error');}}
    startPolling(){if(!this.pollHandle)this.pollHandle=setInterval(()=>this.refreshScanStatus(),3000);} stopPolling(){if(this.pollHandle){clearInterval(this.pollHandle);this.pollHandle=null;}}
    closeModal(){this.showFilesModal=false;} toast(title,message,variant){this.dispatchEvent(new ShowToastEvent({title,message,variant}));} extractError(e){return e?.body?.message||e?.message||'Unknown error';}
}
