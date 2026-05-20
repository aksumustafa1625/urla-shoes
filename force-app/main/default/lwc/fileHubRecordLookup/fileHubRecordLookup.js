/**
 * @component   fileHubRecordLookup
 * @description Generic type-ahead lookup that swaps between Reseller__c and Loan__c
 *              based on the `lookup-type` prop. On focus, shows the top 10 records
 *              without requiring the user to type — matches the user-picker UX.
 *
 *              Emits `select` with {recordId, primaryLabel} on choice, `clear` on reset.
 *
 * @author      Mustafa Aksu
* @date        2026-05-13
 */
import { LightningElement, api, track } from 'lwc';
import searchResellers from '@salesforce/apex/FileHubController.searchResellers';
import searchLoans from '@salesforce/apex/FileHubController.searchLoans';

const LOOKUP_RESELLER = 'reseller';
const LOOKUP_LOAN = 'loan';

export default class FileHubRecordLookup extends LightningElement {

    // 'reseller' | 'loan' — drives which Apex method is invoked
    @api lookupType = LOOKUP_RESELLER;

    @api placeholder = 'Search...';

    @track searchTerm = '';
    @track results = [];
    @track selectedLabel = '';
    @track showDropdown = false;
    @track isSearching = false;

    _selected = false;
    _debounceTimer;

    get hasSelection() {
        return !!this.selectedLabel && this._selected;
    }
    get hasResults() {
        return this.results && this.results.length > 0;
    }
    get inputPlaceholder() {
        return this.hasSelection ? '' : this.placeholder;
    }

    handleInput(event) {
        this.searchTerm = event.target.value;
        this._selected = false;
        this.showDropdown = true;
        clearTimeout(this._debounceTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => this._doSearch(), 300);
    }

    handleFocus() {
        this.showDropdown = true;
        if (this.results.length === 0 && !this.isSearching) {
            this._doSearch();
        }
    }

    handleBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showDropdown = false; }, 200);
    }

    _doSearch() {
        this.isSearching = true;
        const promise = this.lookupType === LOOKUP_LOAN
            ? searchLoans({ searchTerm: this.searchTerm || '' })
            : searchResellers({ searchTerm: this.searchTerm || '' });

        promise
            .then(data => {
                this.results = (data || []).map(r => ({
                    ...r,
                    hasSecondary: !!r.secondaryLabel
                }));
                this.isSearching = false;
            })
            .catch(() => {
                this.results = [];
                this.isSearching = false;
            });
    }

    handleSelect(event) {
        const recordId = event.currentTarget.dataset.id;
        const record = this.results.find(r => r.recordId === recordId);
        if (!record) return;

        this.selectedLabel = record.primaryLabel;
        this._selected = true;
        this.searchTerm = '';
        this.results = [];
        this.showDropdown = false;

        this.dispatchEvent(new CustomEvent('select', {
            detail: { recordId: record.recordId, primaryLabel: record.primaryLabel }
        }));
    }

    handleClear() {
        this.selectedLabel = '';
        this.searchTerm = '';
        this._selected = false;
        this.results = [];
        this.showDropdown = false;
        this.dispatchEvent(new CustomEvent('clear'));
    }
}
