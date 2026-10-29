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
    progress = '';
    selectFiltered() { this.selected = [...new Set([...this.selected, ...this.filteredObjects.map(row => row.value)])]; this.resetScan(); }
    clearObjects() { this.selected = []; this.resetScan(); }
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
            .map(o => ({...o, checked: this.selected.includes(o.value)}));
    }
    get selectedCount() { return this.selected.length; }
    get hasSelection() { return this.selected.length > 0; }
    get scanDisabled() { return this.busy || !this.hasSelection; }
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
            for (let offset = 0; offset < selection.length; offset += 10) {
                this.progress = `Scanning ${Math.min(offset + 10, selection.length)} of ${selection.length} objects`;
                const rows = await scanObjects({objectApiNames: selection.slice(offset, offset + 10)});
                if (generation !== this.scanGeneration) return;
                this.scanRows = [...this.scanRows, ...(rows || [])];
            }
            this.progress = `Scan complete: ${selection.length} objects`;
            this.scanned = true;
            if (this.hasWarnings) this.toast('Scan incomplete', 'Some objects could not be counted. Purge is disabled.', 'warning');
        } catch (e) { if (generation === this.scanGeneration) this.toast('Scan failed', this.message(e), 'error'); }
        finally { this.busy = false; }
    }
    async handlePurge() {
        if (!this.canPurge) return;
        this.busy = true;
        try {
            let submitted = 0;
            for (const objectName of [...this.selected]) {
                this.progress = `Submitting ${submitted + 1} of ${this.selected.length}: ${objectName}`;
                try {
                    await purgeObjects({objectApiNames:[objectName], deleteAttachments:this.deleteAttachments, deleteFiles:this.deleteFiles});
                    submitted++;
                } catch (error) {
                    this.progress = `${submitted} object requests submitted; stopped at ${objectName}. Earlier requests may be running. Review job logs before retrying.`;
                    this.resetScan();
                    throw error;
                }
            }
            this.progress = `${submitted} object requests submitted. Review background job logs for completion.`;
            this.toast('Purge submitted', this.progress, 'success');
            this.resetScan();
        } catch (e) { this.toast('Purge failed', this.message(e), 'error'); }
        finally { this.busy = false; }
    }
    message(e) { return e?.body?.message || e?.message || 'Unexpected error'; }
    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({title,message,variant})); }
}
