import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, MessageContext } from 'lightning/messageService';
import COMPLIANCE_UPDATE from '@salesforce/messageChannel/Compliance_Update__c';
import getResellerEntries from '@salesforce/apex/DocumentIntelligenceService.getResellerEntries';
import classifyAndApply from '@salesforce/apex/DocumentIntelligenceService.classifyAndApply';

export default class DocumentAiClassifier extends LightningElement {
    @api recordId;
    wiredEntries;
    entries = [];
    loadingId;
    results = {}; // entryId -> ClassificationResult

    @wire(MessageContext) messageContext;

    @wire(getResellerEntries, { resellerId: '$recordId' })
    wired(result) {
        this.wiredEntries = result;
        if (result.data) {
            this.entries = result.data;
        }
    }

    get hasEntries() {
        return this.entries && this.entries.length > 0;
    }

    get decoratedEntries() {
        return this.entries.map((e) => {
            const res = this.results[e.entryId];
            return {
                ...e,
                isLoading: this.loadingId === e.entryId,
                hasResult: !!res,
                resultText: res ? res.message : '',
                resultSummary: res && res.summary ? res.summary : '',
                resultApplied: res ? res.applied : false,
                resultClass: res && res.applied ? 'ai-result ai-result-ok' : 'ai-result ai-result-warn',
                expiryLabel: e.expiryDate
                    ? new Date(e.expiryDate).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
                    : ''
            };
        });
    }

    async handleAnalyze(event) {
        const entryId = event.currentTarget.dataset.id;
        this.loadingId = entryId;
        try {
            const res = await classifyAndApply({ entryId });
            this.results = { ...this.results, [entryId]: res };
            this.dispatchEvent(
                new ShowToastEvent({
                    title: res.applied ? 'Document classified' : 'Not classified',
                    message: res.message,
                    variant: res.applied ? 'success' : 'warning'
                })
            );
            await refreshApex(this.wiredEntries);
            if (res.applied) {
                publish(this.messageContext, COMPLIANCE_UPDATE, { resellerId: this.recordId });
            }
        } catch (e) {
            const msg = e && e.body && e.body.message ? e.body.message : 'AI classification failed';
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
        } finally {
            this.loadingId = undefined;
        }
    }

    handleRefresh() {
        return refreshApex(this.wiredEntries);
    }
}
