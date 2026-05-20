/**
 * @component   fileHubUserLookup
 * @description Type-ahead user picker. Debounces input by 300ms, queries Apex,
 *              renders a dropdown of matches. Emits `select` with {userId, name}
 *              on choice, `clear` when the selection is removed.
 *
 *              Built custom (not lightning-record-picker) because we need to filter
 *              out the running user — record-picker doesn't expose that filter cleanly.
 *
 * @author      Mustafa Aksu
 * @date        2026-05-13
 */
import { LightningElement, api, track } from 'lwc';
import searchUsers from '@salesforce/apex/FileHubController.searchUsers';

export default class FileHubUserLookup extends LightningElement {

    @api selectedName = '';

    @track searchTerm = '';
    @track results = [];
    @track showDropdown = false;
    @track isSearching = false;

    _debounceTimer;
    _selected = false;

    get hasSelection() {
        return !!this.selectedName && this._selected;
    }

    get displayValue() {
        return this.hasSelection ? this.selectedName : this.searchTerm;
    }

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get inputPlaceholder() {
        return this.hasSelection ? '' : 'Search by name or email...';
    }

    handleInput(event) {
        this.searchTerm = event.target.value;
        this._selected = false;
        this.showDropdown = true;

        clearTimeout(this._debounceTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => this._doSearch(), 300);
    }

    /**
     * Click-to-see-options: as soon as the input gets focus, show the dropdown and
     * fire a blank-term search so the user sees the top 10 active users without
     * having to type anything. Matches the UX of native lookup pickers.
     */
    handleFocus() {
        this.showDropdown = true;
        // Only fire the empty-term query on first focus to avoid re-querying every
        // time the input regains focus during the same modal session.
        if (this.results.length === 0 && !this.isSearching) {
            this._doSearch();
        }
    }

    handleBlur() {
        // Delay so click on a result fires before the dropdown closes
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showDropdown = false; }, 200);
    }

    _doSearch() {
        this.isSearching = true;
        // searchUsers now handles blank terms — returns top 10 active users.
        searchUsers({ searchTerm: this.searchTerm || '' })
            .then(data => {
                this.results = data || [];
                this.isSearching = false;
            })
            .catch(() => {
                this.results = [];
                this.isSearching = false;
            });
    }

    handleSelect(event) {
        const userId = event.currentTarget.dataset.userid;
        const user = this.results.find(u => u.userId === userId);
        if (!user) return;

        this.selectedName = user.name;
        this._selected = true;
        this.searchTerm = '';
        this.results = [];
        this.showDropdown = false;

        this.dispatchEvent(new CustomEvent('select', {
            detail: { userId: user.userId, name: user.name, email: user.email }
        }));
    }

    handleClear() {
        this.selectedName = '';
        this.searchTerm = '';
        this._selected = false;
        this.results = [];
        this.showDropdown = false;
        this.dispatchEvent(new CustomEvent('clear'));
    }
}
