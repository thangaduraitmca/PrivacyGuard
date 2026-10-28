import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import availableObjects from '@salesforce/apex/FileAttachmentPurgeController.availableObjects';
import scanObjects from '@salesforce/apex/FileAttachmentPurgeController.scanObjects';
import purgeObjects from '@salesforce/apex/FileAttachmentPurgeController.purgeObjects';

export default class AttachmentFilePurge extends LightningElement {
    @track objects = [];
    @track selected = [];
    @track scanRows = [];
    search = '';
    deleteAttachments = true;
    deleteFiles = false;
    busy = false;
    scanned = false;
    scanGeneration = 0;
    acknowledged = false;
    confirmation = '';
    connectedCallback() { this.loadObjects(); }
    async loadObjects() {
        this.busy = true;
        try {
            const data = await availableObjects();
            this.objects = [...(data || [])].sort((a, b) => (a.label || '').localeCompare(b.label || ''));
        } catch (e) { this.toast('Cannot load objects', this.message(e), 'error'); }
        finally { this.busy = false; }
    }
    get filteredObjects() {
        const term = this.search.toLowerCase();
        return this.objects.filter(o => o.label.toLowerCase().includes(term) || o.value.toLowerCase().includes(term))
            .slice(0, 80).map(o => ({...o, checked: this.selected.includes(o.value)}));
    }
    get selectedCount() { return this.selected.length; }
    get hasSelection() { return this.selected.length > 0; }
    get scanDisabled() { return this.busy || !this.hasSelection || this.selected.length > 10; }
    get totalAttachments() { return this.scanRows.reduce((s,r) => s + (r.attachmentCount || 0), 0); }
    get totalFiles() { return this.scanRows.reduce((s,r) => s + (r.fileLinkCount || 0), 0); }
    get totalItems() { return (this.deleteAttachments ? this.totalAttachments : 0) + (this.deleteFiles ? this.totalFiles : 0); }
    get hasWarnings() { return this.scanRows.some(r => r.warning); }
    get purgeDisabled() { return !this.canPurge; }
    get canPurge() { return this.scanned && !this.busy && !this.hasWarnings && this.totalItems > 0 && this.acknowledged && this.confirmation === 'PURGE'; }
    get scanRowsDisplay() { return this.scanRows.map(r => ({...r, key:r.objectName, warningText:r.warning || '—'})); }
    handleSearch(e) { this.search = e.detail.value || ''; }
    handleSelect(e) {
        const value = e.target.dataset.name;
        if (e.target.checked && this.selected.length >= 10) {
            e.target.checked = false;
            this.toast('Selection limit', 'Select up to 10 objects.', 'warning');
            return;
        }
        this.selected = e.target.checked ? [...this.selected, value] : this.selected.filter(x => x !== value);
        this.resetScan();
    }
    handleAttachments(e) { this.deleteAttachments = e.target.checked; this.resetConfirmation(); }
    handleFiles(e) { this.deleteFiles = e.target.checked; this.resetConfirmation(); }
    handleAcknowledge(e) { this.acknowledged = e.target.checked; }
    handleConfirmation(e) { this.confirmation = e.detail.value || ''; }
    resetConfirmation() { this.acknowledged = false; this.confirmation = ''; }
    resetScan() { this.scanGeneration++; this.scanned = false; this.scanRows = []; this.resetConfirmation(); }
    async handleScan() {
        this.busy = true; this.resetScan();
        const generation = this.scanGeneration;
        const selection = [...this.selected];
        try {
            const rows = await scanObjects({objectApiNames: selection});
            if (generation !== this.scanGeneration) return;
            this.scanRows = [...(rows || [])];
            this.scanned = true;
            if (this.hasWarnings) this.toast('Scan incomplete', 'Some objects could not be counted. Purge is disabled.', 'warning');
        } catch (e) { if (generation === this.scanGeneration) this.toast('Scan failed', this.message(e), 'error'); }
        finally { this.busy = false; }
    }
    async handlePurge() {
        if (!this.canPurge) return;
        this.busy = true;
        try {
            await purgeObjects({objectApiNames:this.selected, deleteAttachments:this.deleteAttachments, deleteFiles:this.deleteFiles});
            this.toast('Purge submitted', 'Background purge was started. Review masking job logs for results.', 'success');
            this.resetScan();
        } catch (e) { this.toast('Purge failed', this.message(e), 'error'); }
        finally { this.busy = false; }
    }
    message(e) { return e?.body?.message || e?.message || 'Unexpected error'; }
    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({title,message,variant})); }
}
