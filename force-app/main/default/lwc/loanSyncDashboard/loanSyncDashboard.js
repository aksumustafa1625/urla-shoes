import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboard from '@salesforce/apex/LoanSyncService.getDashboard';
import retry from '@salesforce/apex/LoanSyncService.retry';

export default class LoanSyncDashboard extends LightningElement {
    @api recordId;
    @track showPayload = false;
    _wiredResult;
    loan;
    logs = [];
    maxRetries = 5;
    loading = false;
    error;

    @wire(getDashboard, { loanId: '$recordId' })
    wiredDashboard(result) {
        this._wiredResult = result;
        if (result.data) {
            this.loan = result.data.loan;
            this.logs = (result.data.logs || []).map((l) => ({
                ...l,
                badgeVariant: l.Success__c ? 'success' : 'error',
                badgeLabel: l.Success__c ? 'OK' : `HTTP ${l.HTTP_Status__c || 'ERR'}`
            }));
            this.maxRetries = result.data.maxRetries;
            this.error = undefined;
        } else if (result.error) {
            this.error = this._extractErrorMessage(result.error);
            this.loan = undefined;
        }
    }

    get statusBadgeVariant() {
        if (!this.loan) return 'inverse';
        if (this.loan.isSynced__c) return 'success';
        if (this.loan.Retry_Count__c >= this.maxRetries) return 'error';
        return 'warning';
    }

    get statusBadgeLabel() {
        if (!this.loan) return 'Loading';
        if (this.loan.isSynced__c) return 'Synced';
        if (this.loan.Retry_Count__c >= this.maxRetries) return 'Failed – Max Retries';
        if ((this.loan.Retry_Count__c || 0) > 0) return `Retrying (${this.loan.Retry_Count__c})`;
        return 'Pending';
    }

    get statusIcon() {
        const v = this.statusBadgeVariant;
        if (v === 'success') return 'utility:success';
        if (v === 'error') return 'utility:error';
        if (v === 'warning') return 'utility:warning';
        return 'utility:clock';
    }

    get lastAttemptFormatted() {
        if (!this.loan || !this.loan.Last_Sync_Attempt__c) return '—';
        return new Date(this.loan.Last_Sync_Attempt__c).toLocaleString();
    }

    get coreRef() {
        return this.loan && this.loan.Core_System_Ref__c
            ? this.loan.Core_System_Ref__c
            : '—';
    }

    get retryCount() {
        return (this.loan && this.loan.Retry_Count__c) || 0;
    }

    get syncError() {
        return this.loan && this.loan.Sync_Error__c ? this.loan.Sync_Error__c : null;
    }

    get payloadPreview() {
        if (!this.loan) return '';
        const body = [{
            Loan: {
                sf_id: this.loan.Id,
                loan_amount: this.loan.Loan_Amount__c === undefined || this.loan.Loan_Amount__c === null
                    ? null
                    : String(this.loan.Loan_Amount__c),
                term_in_months: this.loan.Term_In_Months__c === undefined || this.loan.Term_In_Months__c === null
                    ? null
                    : String(this.loan.Term_In_Months__c),
                monthly_payments: this.loan.Monthly_Payments__c === undefined
                    ? null
                    : this.loan.Monthly_Payments__c
            }
        }];
        return JSON.stringify(body, null, 2);
    }

    get togglePayloadLabel() {
        return this.showPayload ? 'Hide JSON Payload' : 'Show JSON Payload';
    }

    get togglePayloadIcon() {
        return this.showPayload ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get hasLogs() {
        return this.logs && this.logs.length > 0;
    }

    togglePayload() {
        this.showPayload = !this.showPayload;
    }

    async handleRetry() {
        this.loading = true;
        try {
            await retry({ loanId: this.recordId });
            this._toast('Retry queued', 'Sync will run in the next few seconds.', 'success');
            // Poll twice: immediate (to catch fast responses) and after 4s (catching
            // the async queueable completion). Good enough without Platform Events.
            setTimeout(() => refreshApex(this._wiredResult), 500);
            setTimeout(() => refreshApex(this._wiredResult), 4000);
        } catch (e) {
            this._toast('Retry failed', this._extractErrorMessage(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    handleRefresh() {
        refreshApex(this._wiredResult);
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _extractErrorMessage(e) {
        if (!e) return 'Unknown error';
        if (typeof e === 'string') return e;
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return JSON.stringify(e);
    }
}
