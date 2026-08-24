/**
 * @component   fileHubSendModal
 * @description Modal for sending a file to another user. Collects: recipient, category,
 *              optional record link (Reseller / Loan), optional message, and the file.
 *              On success, fires a `success` custom event so the parent can refresh.
 *
 * @author      Mustafa Aksu
 * @date        2026-05-13
 */
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';

import createEntry from '@salesforce/apex/FileHubController.createEntry';

const CATEGORY_OPTIONS = [
    { label: 'Contract', value: 'Contract' },
    { label: 'Tax Document', value: 'Tax Document' },
    { label: 'Insurance', value: 'Insurance' },
    { label: 'Bank Details', value: 'Bank Details' },
    { label: 'Catalog', value: 'Catalog' },
    { label: 'Compliance', value: 'Compliance' },
    { label: 'Marketing', value: 'Marketing' },
    { label: 'Personal', value: 'Personal' },
    { label: 'Other', value: 'Other' }
];

const LINK_TYPE_OPTIONS = [
    { label: 'None', value: 'none' },
    { label: 'Reseller', value: 'reseller' },
    { label: 'Loan', value: 'loan' }
];

export default class FileHubSendModal extends LightningElement {

    @track recipientId;
    @track recipientName = '';
    @track category = 'Contract';
    @track linkType = 'none';
    @track relatedResellerId;
    @track relatedLoanId;
    @track message = '';
    @track uploadedDocumentId;
    @track uploadedFileName = '';
    @track isSubmitting = false;

    // ── Computed ───────────────────────────────────────────────

    get categoryOptions() { return CATEGORY_OPTIONS; }
    get linkTypeOptions() { return LINK_TYPE_OPTIONS; }

    get currentUserId() { return USER_ID; }  // For lightning-file-upload anchor

    get showResellerPicker() { return this.linkType === 'reseller'; }
    get showLoanPicker()     { return this.linkType === 'loan'; }
    get hasUploadedFile()    { return !!this.uploadedDocumentId; }

    get canSubmit() {
        return this.recipientId && this.category && this.uploadedDocumentId && !this.isSubmitting;
    }

    get sendButtonLabel() {
        return this.isSubmitting ? 'Sending...' : 'Send';
    }

    get acceptedFormats() {
        return ['.pdf', '.png', '.jpg', '.jpeg', '.gif', '.docx', '.doc', '.xlsx', '.xls', '.pptx', '.ppt', '.csv', '.txt'];
    }

    // ── Handlers ───────────────────────────────────────────────

    handleRecipientSelect(event) {
        this.recipientId = event.detail.userId;
        this.recipientName = event.detail.name;
    }

    handleRecipientClear() {
        this.recipientId = null;
        this.recipientName = '';
    }

    handleCategoryChange(event) {
        this.category = event.detail.value;
    }

    handleLinkTypeChange(event) {
        this.linkType = event.detail.value;
        // Clear the other lookup when switching to keep state coherent
        if (this.linkType !== 'reseller') this.relatedResellerId = null;
        if (this.linkType !== 'loan')     this.relatedLoanId = null;
    }

    handleResellerSelect(event) {
        // fileHubRecordLookup emits {detail: {recordId, primaryLabel}}
        this.relatedResellerId = event.detail.recordId;
    }

    handleResellerClear() {
        this.relatedResellerId = null;
    }

    handleLoanSelect(event) {
        this.relatedLoanId = event.detail.recordId;
    }

    handleLoanClear() {
        this.relatedLoanId = null;
    }

    handleMessageChange(event) {
        this.message = event.target.value;
    }

    handleUploadFinished(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            this.uploadedDocumentId = files[0].documentId;
            this.uploadedFileName = files[0].name;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSend() {
        if (!this.canSubmit) {
            this._toast('Incomplete', 'Recipient, category, and file are required.', 'warning');
            return;
        }
        this.isSubmitting = true;

        createEntry({
            contentDocumentId: this.uploadedDocumentId,
            recipientId: this.recipientId,
            category: this.category,
            message: this.message || null,
            relatedResellerId: this.relatedResellerId || null,
            relatedLoanId: this.relatedLoanId || null
        })
            .then(() => {
                this.dispatchEvent(new CustomEvent('success'));
            })
            .catch(err => {
                this._toast('Send failed', this._extractError(err), 'error');
                this.isSubmitting = false;
            });
    }

    // ── Helpers ────────────────────────────────────────────────

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _extractError(err) {
        if (!err) return 'Unknown error';
        if (typeof err === 'string') return err;
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }
}
