import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getMatrix from '@salesforce/apex/ComplianceService.getMatrix';

export default class ComplianceCockpit extends NavigationMixin(LightningElement) {
    matrix;
    wiredMatrix;
    error;

    @wire(getMatrix)
    wired(result) {
        this.wiredMatrix = result;
        if (result.data) {
            this.matrix = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.matrix = undefined;
        }
    }

    get hasData() {
        return this.matrix && this.matrix.rows && this.matrix.rows.length > 0;
    }

    get requirements() {
        return this.matrix ? this.matrix.requirements : [];
    }

    // Decorate each reseller row: build per-cell tooltip + inline style, and a score bar style.
    get decoratedRows() {
        if (!this.matrix) {
            return [];
        }
        return this.matrix.rows.map((row) => {
            const cells = row.cells.map((cell, idx) => ({
                ...cell,
                key: `${row.resellerId}-${idx}`,
                style: `background:${cell.color};`,
                tooltip: this.cellTooltip(cell)
            }));
            return {
                ...row,
                cells,
                scoreBarStyle: `width:${row.score}%;background:${row.scoreColor};`,
                scoreTextStyle: `color:${row.scoreColor};`,
                tierClass: this.tierClass(row.tier),
                location: [row.city, row.country].filter((x) => x).join(', ')
            };
        });
    }

    get avgScoreStyle() {
        const s = this.matrix ? this.matrix.avgScore : 0;
        const color = s >= 100 ? '#2e844a' : s >= 67 ? '#5cb85c' : s >= 34 ? '#fe9339' : '#ea001e';
        return `color:${color};`;
    }

    cellTooltip(cell) {
        if (cell.status === 'MISSING') {
            return `${cell.label}: Missing`;
        }
        if (cell.status === 'EXPIRED') {
            return `${cell.label}: Expired (${this.fmtDate(cell.expiryDate)})`;
        }
        if (cell.status === 'EXPIRING') {
            return `${cell.label}: Expires in ${cell.daysUntilExpiry} day(s) — ${this.fmtDate(cell.expiryDate)}`;
        }
        return cell.expiryDate
            ? `${cell.label}: Valid until ${this.fmtDate(cell.expiryDate)}`
            : `${cell.label}: On file`;
    }

    fmtDate(d) {
        if (!d) {
            return '';
        }
        return new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
    }

    tierClass(tier) {
        const base = 'cockpit-tier';
        if (!tier) {
            return base;
        }
        return `${base} cockpit-tier-${tier.toLowerCase()}`;
    }

    handleCellClick(event) {
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

    handleResellerClick(event) {
        const resellerId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: resellerId, objectApiName: 'Reseller__c', actionName: 'view' }
        });
    }

    handleRefresh() {
        return refreshApex(this.wiredMatrix);
    }
}
