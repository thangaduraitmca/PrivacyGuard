import canPurge from '@salesforce/customPermission/Purge_PrivacyGuard_Files';
import deleteSelected from '@salesforce/apex/PrivacyGuardFileInventoryController.deleteSelected';
import { LightningElement } from 'lwc';
import scanPage from '@salesforce/apex/PrivacyGuardFileInventoryController.scanPage';

const COLUMNS = [
    { label: 'Kind', fieldName: 'kind' },
    { label: 'File name', fieldName: 'title' },
    { label: 'Type', fieldName: 'fileType' },
    { label: 'Bytes', fieldName: 'sizeBytes', type: 'number' },
    { label: 'Owner', fieldName: 'owner' },
    { label: 'Record relationship', fieldName: 'relationshipStatus' },
    { label: 'Libraries', fieldName: 'libraries' }
];
export default class PrivacyGuardFileInventory extends LightningElement {
    deleting = false;
    selectedIds = [];
    confirmation = '';
    showConfirm = false;
    deletionResults = [];
    get selectedCount() { return this.selectedIds.length; }
    get deleteDisabled() { return !canPurge || this.busy || !this.selectedIds.length; }
    get confirmDisabled() { return this.busy || this.confirmation !== 'DELETE' || !canPurge || !this.selectedIds.length; }
    get hasDeleteResults() { return this.deletionResults.length > 0; }
    get confirmationRows() { return this.rows.filter(row => this.selectedIds.includes(row.id)); }
    handleSelection(event) { if (this.busy) return; this.selectedIds = event.detail.selectedRows.map(row => row.id); this.showConfirm = false; }
    selectAll() { this.selectedIds = this.rows.map(row => row.id); this.showConfirm = false; }
    clearSelection() { this.selectedIds = []; this.showConfirm = false; }
    requestDelete() { this.confirmation = ''; this.showConfirm = true; }
    cancelDelete() { this.showConfirm = false; }
    handleDeleteConfirmation(event) { this.confirmation = event.detail.value || ''; }
    async confirmDelete() {
        if (this.confirmDisabled) return;
        const ids = [...this.selectedIds];
        this.busy = true; this.deleting = true; this.stage = 'Deleting selected items'; this.deletionResults = [];
        try {
            for (let offset = 0; offset < ids.length; offset += 100) {
                let results;
                try { results = await deleteSelected({recordIds: ids.slice(offset, offset + 100), confirmation: 'DELETE'}); }
                catch (error) {
                    this.addWarnings([`Deletion stopped: ${error.body?.message || error.message}. Earlier confirmed batches may have committed; review results and rescan before retrying.`]);
                    break;
                }
                const succeeded = new Set(results.filter(row => row.success).map(row => row.id));
                this.deletionResults = [...this.deletionResults, ...results];
                this.rows = this.rows.filter(row => !succeeded.has(row.id));
                this.selectedIds = this.selectedIds.filter(id => !succeeded.has(id));
                this.fileCount = this.rows.filter(row => row.kind === 'Salesforce File').length;
                this.attachmentCount = this.rows.length - this.fileCount;
                this.bytes = this.rows.reduce((sum,row) => sum + Number(row.sizeBytes || 0),0);
                this.previewRows = this.rows;
            }
        } finally { this.busy = false; this.deleting = false; this.showConfirm = false; this.confirmation = ''; }
    }
    columns = COLUMNS;
    rows = [];
    previewRows = [];
    warnings = [];
    busy = false;
    stopped = false;
    complete = false;
    stage = '';
    fileCount = 0;
    attachmentCount = 0;
    bytes = 0;
    startedAt;
    get statusText() {
        if (this.busy) return `${this.stage}: ${this.rows.length} items inventoried. Keep this page open.`;
        if (this.stopped) return `Scan stopped. ${this.rows.length} items collected; report is partial.`;
        if (this.complete) return `Scan completed for the querying user's visible scope. ${this.rows.length} unique file and attachment records.`;
        return 'Scan all query-visible Salesforce Files and legacy Attachments, including files uploaded directly through Files. No object selection is required.';
    }
    get hasWarnings() { return this.warnings.length > 0; }
    get hasRows() { return this.previewRows.length > 0; }
    get downloadDisabled() { return this.busy || this.rows.length === 0; }
    get stopDisabled() { return !this.busy || this.deleting; }
    get downloadLabel() { return this.complete && !this.hasWarnings ? 'Download CSV report' : 'Download partial CSV report'; }
    stop() { this.stopped = true; }
    async scanAll() {
        this.rows = []; this.previewRows = []; this.warnings = []; this.selectedIds = []; this.showConfirm = false; this.deletionResults = [];
        this.fileCount = 0; this.attachmentCount = 0; this.bytes = 0;
        this.complete = false; this.stopped = false; this.busy = true; this.startedAt = null;
        let stageFailed = false;
        try {
            for (const kind of ['Files', 'Attachments']) {
                this.stage = kind;
                let cursor = null;
                let more = true;
                while (more && !this.stopped) {
                    let page;
                    try {
                        page = await scanPage({ kind, afterId: cursor, startedAt: this.startedAt });
                    } catch (error) {
                        this.addWarnings([`${kind}: ${error.body?.message || error.message || 'Scan failed.'}`]);
                        stageFailed = true;
                        break;
                    }
                    this.startedAt = page.startedAt;
                    this.addWarnings(page.warnings || []);
                    const collected = page.rows || [];
                    this.rows.push(...collected);
                    if (kind === 'Files') this.fileCount += collected.length;
                    else this.attachmentCount += collected.length;
                    this.bytes += collected.reduce((total, row) => total + Number(row.sizeBytes || 0), 0);
                    this.previewRows = this.rows;
                    more = page.hasMore;
                    if (more && (!page.nextCursor || page.nextCursor === cursor)) {
                        this.addWarnings([`${kind}: pagination did not advance; scan stopped to prevent duplicate rows.`]);
                        stageFailed = true; break;
                    }
                    cursor = page.nextCursor;
                }
                if (this.stopped) break;
            }
            this.complete = !this.stopped && !stageFailed;
        } finally { this.busy = false; }
    }
    addWarnings(messages) {
        this.warnings = [...new Set([...this.warnings, ...messages])];
    }
    downloadResults() {
        const csv = ['Id,Success,Result', ...this.deletionResults.map(row => [row.id, row.success, row.message].map(value => '"' + ("'" + String(value)).replace(/"/g, '""') + '"').join(','))].join('\r\n');
        const url = URL.createObjectURL(new Blob([csv], {type:'text/plain'}));
        const anchor = document.createElement('a'); anchor.href=url; anchor.download='privacyguard-deletion-results.csv';
        document.body.appendChild(anchor); anchor.click(); anchor.remove(); URL.revokeObjectURL(url);
    }
    download() {
        // Neutralise spreadsheet formula prefixes in untrusted document titles and names.
        const cell = (value) => {
            let text = value === null || value === undefined ? '' : String(value);
            if (/^[\s]*[=+\-@]/.test(text)) text = `'${text}`;
            return `"${text.replace(/"/g, '""')}"`;
        };
        const headers = ['Id', 'Kind', 'File name', 'Type', 'Size bytes', 'Owner', 'Uploaded UTC', 'Modified UTC', 'Linked entity types and IDs', 'Libraries', 'Record relationship', 'Relationship completeness', 'Scan started UTC', 'Report status', 'Scan warnings'];
        const reportStatus = this.complete && !this.hasWarnings ? 'Completed for visible scope' : 'Partial';
        const lines = [headers.map(cell).join(',')];
        for (const row of this.rows) {
            lines.push([row.id, row.kind, row.title, row.fileType, row.sizeBytes, row.owner, row.uploadedAt,
                row.modifiedAt, row.linkedRecords, row.libraries, row.relationshipStatus, row.completeness,
                this.startedAt, reportStatus, this.warnings.join(' | ')].map(cell).join(','));
        }
        const url = URL.createObjectURL(new Blob(['\uFEFF', lines.join('\r\n')], { type: 'text/plain' }));
        const anchor = document.createElement('a'); anchor.href = url;
        anchor.download = `privacyguard-file-inventory-${new Date().toISOString().slice(0, 10)}.csv`;
        document.body.appendChild(anchor); anchor.click(); anchor.remove();
        URL.revokeObjectURL(url);
    }
}
