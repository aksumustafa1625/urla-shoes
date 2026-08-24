import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import COMPLIANCE_UPDATE from '@salesforce/messageChannel/Compliance_Update__c';
import getRequests from '@salesforce/apex/ComplianceRequestService.getRequests';
import requestAllGaps from '@salesforce/apex/ComplianceRequestService.requestAllGaps';

export default class DocumentRequests extends LightningElement {
    @api recordId;
    wiredRequests;
    requests = [];
    loading = false;
    subscription;

    @wire(MessageContext) messageContext;

    @wire(getRequests, { resellerId: '$recordId' })
    wired(result) {
        this.wiredRequests = result;
        if (result.data) {
            this.requests = result.data;
        }
    }

    connectedCallback() {
        this.subscription = subscribe(this.messageContext, COMPLIANCE_UPDATE, (message) => {
            if (message && message.resellerId === this.recordId) {
                refreshApex(this.wiredRequests);
            }
        });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    get hasRequests() {
        return this.requests && this.requests.length > 0;
    }

    get openCount() {
        return this.requests.filter((r) => r.status === 'Requested').length;
    }

    get decorated() {
        return this.requests.map((r) => ({
            ...r,
            badgeClass:
                r.status === 'Fulfilled'
                    ? 'req-badge req-badge-ok'
                    : r.status === 'Cancelled'
                    ? 'req-badge req-badge-cancel'
                    : 'req-badge req-badge-open',
            dateLabel:
                r.status === 'Fulfilled' && r.fulfilledDate
                    ? 'Fulfilled ' + new Date(r.fulfilledDate).toLocaleDateString()
                    : r.requestedDate
                    ? 'Requested ' + new Date(r.requestedDate).toLocaleDateString()
                    : ''
        }));
    }

    async handleRequestAll() {
        this.loading = true;
        try {
            const res = await requestAllGaps({ resellerId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Compliance sweep',
                    message: res.message,
                    variant: res.created > 0 ? 'success' : 'info'
                })
            );
            await refreshApex(this.wiredRequests);
            publish(this.messageContext, COMPLIANCE_UPDATE, { resellerId: this.recordId });
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : 'Request failed';
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
        } finally {
            this.loading = false;
        }
    }

    handleRefresh() {
        return refreshApex(this.wiredRequests);
    }
}
