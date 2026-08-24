import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import COMPLIANCE_UPDATE from '@salesforce/messageChannel/Compliance_Update__c';
import getResellerCompliance from '@salesforce/apex/ComplianceService.getResellerCompliance';

const STATUS_TEXT = {
    OK: 'On file',
    EXPIRING: 'Expiring soon',
    EXPIRED: 'Expired',
    MISSING: 'Missing'
};

export default class ResellerComplianceChecklist extends NavigationMixin(LightningElement) {
    @api recordId;
    row;
    wiredRow;
    error;
    subscription;

    @wire(MessageContext) messageContext;

    @wire(getResellerCompliance, { resellerId: '$recordId' })
    wired(result) {
        this.wiredRow = result;
        if (result.data) {
            this.row = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.row = undefined;
        }
    }

    connectedCallback() {
        // Live re-score when the AI classifier (or any publisher) reports a change
        // for this reseller — completes the "classify → act → score updates" loop.
        this.subscription = subscribe(this.messageContext, COMPLIANCE_UPDATE, (message) => {
            if (message && message.resellerId === this.recordId) {
                refreshApex(this.wiredRow);
            }
        });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    get hasData() {
        return this.row && this.row.cells;
    }

    get score() {
        return this.row ? this.row.score : 0;
    }

    // Conic-gradient ring: filled portion in score color, rest light gray.
    get ringStyle() {
        if (!this.row) {
            return '';
        }
        const deg = Math.round((this.row.score / 100) * 360);
        return `background: conic-gradient(${this.row.scoreColor} ${deg}deg, #eef1f6 ${deg}deg);`;
    }

    get scoreTextStyle() {
        return this.row ? `color:${this.row.scoreColor};` : '';
    }

    get summaryLine() {
        if (!this.row) {
            return '';
        }
        const parts = [];
        if (this.row.missingCount > 0) {
            parts.push(`${this.row.missingCount} missing`);
        }
        if (this.row.expiredCount > 0) {
            parts.push(`${this.row.expiredCount} expired`);
        }
        if (this.row.expiringCount > 0) {
            parts.push(`${this.row.expiringCount} expiring soon`);
        }
        return parts.length ? parts.join(' · ') : 'All documents on file and valid';
    }

    get decoratedCells() {
        if (!this.row) {
            return [];
        }
        return this.row.cells.map((cell, idx) => ({
            ...cell,
            key: `${this.recordId}-${idx}`,
            iconStyle: `background:${cell.color};`,
            statusText: this.statusText(cell),
            rowClass: cell.status === 'MISSING' || cell.status === 'EXPIRED'
                ? 'checklist-row checklist-row-alert'
                : 'checklist-row',
            hasFile: !!cell.contentDocumentId
        }));
    }

    statusText(cell) {
        const base = STATUS_TEXT[cell.status] || cell.status;
        if (cell.status === 'EXPIRING') {
            return `${base} — ${cell.daysUntilExpiry} day(s)`;
        }
        if (cell.status === 'EXPIRED' && cell.expiryDate) {
            return `${base} — ${this.fmtDate(cell.expiryDate)}`;
        }
        if (cell.status === 'OK' && cell.expiryDate) {
            return `Valid until ${this.fmtDate(cell.expiryDate)}`;
        }
        return base;
    }

    fmtDate(d) {
        if (!d) {
            return '';
        }
        return new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
    }

    handlePreview(event) {
        const docId = event.currentTarget.dataset.docid;
        if (!docId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: docId }
        });
    }

    handleRefresh() {
        return refreshApex(this.wiredRow);
    }
}
