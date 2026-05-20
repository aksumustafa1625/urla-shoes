/**
 * @component   fileHub
 * @description Central file management surface. Renders on:
 *              - Home page (no recordId) → shows tabs: My Files / Inbox / Sent
 *              - Record pages (Reseller__c / Loan__c) → shows files linked to that record
 *
 *              Combines the native lightning-file-upload component with a custom
 *              metadata layer (File_Hub_Entry__c) so files have categories, recipients,
 *              read state, and record linkage on top of Salesforce's built-in storage.
 *
 * @author      Mustafa Aksu
 * @project     Urla Shoes
 * @date        2026-05-13
 */
import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';

import getMyFiles from '@salesforce/apex/FileHubController.getMyFiles';
import getInbox from '@salesforce/apex/FileHubController.getInbox';
import getSent from '@salesforce/apex/FileHubController.getSent';
import getFilesForRecord from '@salesforce/apex/FileHubController.getFilesForRecord';
import getUnreadCount from '@salesforce/apex/FileHubController.getUnreadCount';
import getCategoryCounts from '@salesforce/apex/FileHubController.getCategoryCounts';
import getRecentActivity from '@salesforce/apex/FileHubController.getRecentActivity';
import getMonthActivity from '@salesforce/apex/FileHubController.getMonthActivity';
import createEntry from '@salesforce/apex/FileHubController.createEntry';
import markAsRead from '@salesforce/apex/FileHubController.markAsRead';
import deleteEntry from '@salesforce/apex/FileHubController.deleteEntry';

const CATEGORIES = [
    { label: 'All Categories', value: 'All' },
    { label: 'Contract', value: 'Contract' },
    { label: 'Catalog', value: 'Catalog' },
    { label: 'Compliance', value: 'Compliance' },
    { label: 'Marketing', value: 'Marketing' },
    { label: 'Personal', value: 'Personal' },
    { label: 'Other', value: 'Other' }
];

// Tile bar config — order matters (left-to-right in the UI). Each tile renders
// its category name, count, and an icon. 'All' always sits first.
// Color codes are intentionally vibrant — each category gets its own brand identity,
// which then propagates to the file list row stripes for at-a-glance recognition.
const CATEGORY_TILES = [
    { key: 'All',        label: 'All Files',  icon: 'utility:knowledge_base', color: '#0070d2', tint: '#e3f1fc' },
    { key: 'Contract',   label: 'Contracts',  icon: 'utility:contract',       color: '#9333ea', tint: '#f3e8ff' },
    { key: 'Catalog',    label: 'Catalogs',   icon: 'utility:open_folder',    color: '#f59e0b', tint: '#fef3c7' },
    { key: 'Compliance', label: 'Compliance', icon: 'utility:shield',         color: '#10b981', tint: '#d1fae5' },
    { key: 'Marketing',  label: 'Marketing',  icon: 'utility:announcement',   color: '#ec4899', tint: '#fce7f3' },
    { key: 'Personal',   label: 'Personal',   icon: 'utility:user',           color: '#06b6d4', tint: '#cffafe' },
    { key: 'Other',      label: 'Other',      icon: 'utility:file',           color: '#6b7280', tint: '#f3f4f6' }
];

// Quick lookup: category key → color. Used to colorize file row stripes.
const CATEGORY_COLOR_BY_KEY = Object.fromEntries(CATEGORY_TILES.map(t => [t.key, t.color]));

// Heatmap palette — GitHub's exact contribution-graph greens, level 0-4.
// Level 0 (empty) is a neutral light gray so future + zero-activity cells blend in.
const HEATMAP_COLORS = ['#ebedf0', '#9be9a8', '#40c463', '#30a14e', '#216e39'];

// Future days (after today in the current month) render with this softer, almost-
// transparent shade so the eye groups them as "not yet" rather than "no activity".
const HEATMAP_FUTURE_COLOR = '#f6f8fa';

const TAB_MY_FILES = 'myFiles';
const TAB_INBOX = 'inbox';
const TAB_SENT = 'sent';

export default class FileHub extends NavigationMixin(LightningElement) {

    // Record-page binding. When set, the component switches to single-record mode and
    // hides the tab strip in favour of a focused "Files for this record" view.
    @api recordId;

    // Auto-injected by Lightning when the component is placed on a record page.
    // Drives the Reseller-vs-Loan link resolution in _resellerLinkId / _loanLinkId.
    @api objectApiName;

    @track activeTab = TAB_MY_FILES;
    @track selectedCategory = 'All';
    @track searchTerm = '';
    @track entries = [];
    @track unreadCount = 0;
    @track showSendModal = false;
    @track isLoading = false;

    // Per-category counts driving the tile bar; refreshed alongside entries.
    @track categoryCounts = { All: 0, Contract: 0, Catalog: 0, Compliance: 0, Marketing: 0, Personal: 0, Other: 0 };

    // Recent Activity panel state — last 10 events involving the current user.
    @track recentActivity = [];

    // Current-month heatmap state — wrapper from getMonthActivity
    // { monthName, daysInMonth, todayDayOfMonth, days: [{dayDate, count, level, isToday, isFuture}] }
    @track monthActivity = { monthName: '', daysInMonth: 0, days: [] };

    _wiredResult;       // refreshApex handle
    _wiredUnread;       // refreshApex handle for unread count
    _searchDebounce;    // setTimeout id

    // ── Computed / template helpers ───────────────────────────────

    get categoryOptions() {
        return CATEGORIES;
    }

    /**
     * Builds the category tile array consumed by the template. Each tile is brand-coloured;
     * active tile fills with its color, inactive tiles show a soft tinted background and
     * coloured icon. Inline styles keep per-tile colors clean without 7 CSS classes.
     */
    get categoryTiles() {
        return CATEGORY_TILES.map(t => {
            const isActive = this.selectedCategory === t.key;
            // Active: solid colored background + white text
            // Inactive: tinted background + colored icon
            const tileStyle = isActive
                ? `background:${t.color};border-color:${t.color};color:#fff;`
                : `background:${t.tint};border-color:${t.tint};color:${t.color};`;
            const iconStyle = isActive
                ? '--sds-c-icon-color-foreground-default:#ffffff;'
                : `--sds-c-icon-color-foreground-default:${t.color};`;
            return {
                key: t.key,
                label: t.label,
                icon: t.icon,
                count: this.categoryCounts[t.key] || 0,
                tileClass: isActive ? 'fh-tile fh-tile-active' : 'fh-tile',
                tileStyle,
                iconStyle
            };
        });
    }

    /**
     * Decorates each day of the current month for the heatmap grid.
     *  - Past + zero activity   → light gray (level 0 green palette)
     *  - Past + activity        → green shade by level (1-4)
     *  - Today                  → activity shade + outlined ring class
     *  - Future                 → very soft gray, no class
     */
    get decoratedHeatmap() {
        const days = (this.monthActivity && this.monthActivity.days) || [];
        return days.map(d => {
            let color;
            if (d.isFuture) {
                color = HEATMAP_FUTURE_COLOR;
            } else {
                color = HEATMAP_COLORS[d.level] || HEATMAP_COLORS[0];
            }
            // Tooltip e.g. "May 13 · 3 files" or "May 20 · upcoming"
            const dateObj = new Date(d.dayDate);
            const dateLabel = dateObj.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
            const fileWord = d.count === 1 ? 'file' : 'files';
            const tooltip = d.isFuture
                ? `${dateLabel} · upcoming`
                : `${dateLabel} · ${d.count} ${fileWord}`;

            // Today gets a special class so CSS can ring it without disturbing the others
            let cellClass = 'fh-heatmap-sq';
            if (d.isToday) cellClass += ' fh-heatmap-sq-today';
            if (d.isFuture) cellClass += ' fh-heatmap-sq-future';

            return {
                key: d.dayDate,
                style: `background:${color};`,
                cellClass,
                tooltip
            };
        });
    }

    get hasHeatmap() {
        return this.monthActivity && this.monthActivity.days && this.monthActivity.days.length > 0;
    }

    get heatmapLabel() {
        const name = (this.monthActivity && this.monthActivity.monthName) || '';
        return name ? `${name} ACTIVITY` : 'MONTHLY ACTIVITY';
    }

    /**
     * Inline grid template — month length varies (28/29/30/31) so the grid columns
     * must match the actual day count, otherwise short months look ragged.
     */
    get heatmapGridStyle() {
        const cols = (this.monthActivity && this.monthActivity.daysInMonth) || 30;
        return `grid-template-columns: repeat(${cols}, minmax(0, 1fr));`;
    }

    /**
     * One-line summary shown under the header.
     * Example: "8 files · 4 categories · 2 unread"
     */
    get summaryLine() {
        const total = this.categoryCounts.All || 0;
        if (total === 0) return 'No files yet';

        const nonZeroCats = CATEGORY_TILES.filter(t => t.key !== 'All' && (this.categoryCounts[t.key] || 0) > 0).length;
        const filePart = total === 1 ? '1 file' : `${total} files`;
        const catPart = nonZeroCats === 1 ? '1 category' : `${nonZeroCats} categories`;

        // Unread is only meaningful on the home page (Inbox-aware context)
        if (this.isHomePage && this.unreadCount > 0) {
            return `${filePart} · ${catPart} · ${this.unreadCount} unread`;
        }
        return `${filePart} · ${catPart}`;
    }

    get hasRecentActivity() {
        return this.recentActivity && this.recentActivity.length > 0;
    }

    get isRecordPage() {
        return !!this.recordId;
    }

    get isHomePage() {
        return !this.recordId;
    }

    get isMyFilesTab() { return this.activeTab === TAB_MY_FILES; }
    get isInboxTab()   { return this.activeTab === TAB_INBOX; }
    get isSentTab()    { return this.activeTab === TAB_SENT; }

    get myFilesTabClass() {
        return this.isMyFilesTab ? 'fh-tab fh-tab-active' : 'fh-tab';
    }
    get inboxTabClass() {
        return this.isInboxTab ? 'fh-tab fh-tab-active' : 'fh-tab';
    }
    get sentTabClass() {
        return this.isSentTab ? 'fh-tab fh-tab-active' : 'fh-tab';
    }

    get inboxTabLabel() {
        return this.unreadCount > 0 ? `Inbox (${this.unreadCount})` : 'Inbox';
    }

    get hasEntries() {
        return this.entries && this.entries.length > 0;
    }

    get emptyStateMessage() {
        if (this.isRecordPage) return 'No files linked to this record yet.';
        if (this.isMyFilesTab) return 'You have no personal files yet. Upload one to get started.';
        if (this.isInboxTab)   return 'No incoming files. When colleagues send you something, it appears here.';
        if (this.isSentTab)    return 'You have not sent any files yet.';
        return 'No files.';
    }

    get acceptedFormats() {
        // Whitelist common business document types. Adjust per org policy.
        return ['.pdf', '.png', '.jpg', '.jpeg', '.gif', '.docx', '.doc', '.xlsx', '.xls', '.pptx', '.ppt', '.csv', '.txt'];
    }

    // ── Data fetching (manual, not @wire — recipient changes mid-session) ───

    connectedCallback() {
        this.loadEntries();
        this.loadCategoryCounts();
        if (!this.recordId) {
            this.loadUnreadCount();
            this.loadRecentActivity();
            this.loadHeatmap();
        }
    }

    /**
     * Determines the viewType string the Apex side expects, based on the current
     * recordId + activeTab. Centralized so both data-loading paths agree on context.
     */
    _currentViewType() {
        if (this.recordId) return 'record';
        if (this.isInboxTab) return 'inbox';
        if (this.isSentTab)  return 'sent';
        return 'myFiles';
    }

    /**
     * Refreshes the tile bar counts. Called on tab switch + after every mutation
     * so the badges stay in sync with the underlying data.
     */
    loadCategoryCounts() {
        getCategoryCounts({
            viewType: this._currentViewType(),
            recordId: this.recordId || null
        })
            .then(counts => {
                this.categoryCounts = counts || { All: 0 };
            })
            .catch(() => { /* silent — tile bar degrades to 0s, not a blocking error */ });
    }

    /**
     * Refreshes the bottom Recent Activity feed. Home page only — record pages don't
     * need a global activity timeline.
     */
    loadRecentActivity() {
        getRecentActivity()
            .then(events => {
                this.recentActivity = (events || []).map(e => this._decorateActivity(e));
            })
            .catch(() => { this.recentActivity = []; });
    }

    /**
     * Refreshes the current-month activity heatmap. Cheap aggregate query; called on
     * init and after any mutation so the grid feels live.
     */
    loadHeatmap() {
        getMonthActivity()
            .then(data => {
                this.monthActivity = data || { monthName: '', daysInMonth: 0, days: [] };
            })
            .catch(() => {
                this.monthActivity = { monthName: '', daysInMonth: 0, days: [] };
            });
    }

    /**
     * Adds template-friendly fields to each activity row.
     */
    _decorateActivity(e) {
        const relative = this._relativeTime(e.timestamp);
        // Compose a one-line summary the template can render without conditionals
        let summary = e.action;
        if (e.action === 'Sent') summary = `Sent to ${e.otherPartyName}`;
        else if (e.action === 'Received') summary = `From ${e.otherPartyName}`;
        // (Uploaded = no other party)

        return {
            ...e,
            relative,
            summary,
            hasContext: !!e.recordContext
        };
    }

    /**
     * Fetches the right data set based on current tab + recordId.
     * Imperative call (not @wire) so we can fully control refresh after mutations.
     */
    loadEntries() {
        this.isLoading = true;
        let promise;

        if (this.recordId) {
            promise = getFilesForRecord({ recordId: this.recordId });
        } else if (this.isInboxTab) {
            promise = getInbox({ category: this.selectedCategory, searchTerm: this.searchTerm });
        } else if (this.isSentTab) {
            promise = getSent({ category: this.selectedCategory, searchTerm: this.searchTerm });
        } else {
            promise = getMyFiles({ category: this.selectedCategory, searchTerm: this.searchTerm });
        }

        promise
            .then(data => {
                this.entries = (data || []).map(e => this._decorate(e));
                this.isLoading = false;
            })
            .catch(err => {
                this._toast('Error loading files', this._extractError(err), 'error');
                this.entries = [];
                this.isLoading = false;
            });
    }

    loadUnreadCount() {
        getUnreadCount()
            .then(count => { this.unreadCount = count || 0; })
            .catch(() => { /* silent — badge defaults to 0 */ });
    }

    /**
     * Adds template-friendly fields onto each entry so the HTML stays free of
     * conditional logic (which LWC syntax handles awkwardly).
     */
    _decorate(e) {
        const ext = (e.fileExtension || '').toLowerCase();
        const isImage = ['png', 'jpg', 'jpeg', 'gif', 'webp'].includes(ext);
        const isPdf = ext === 'pdf';

        let iconName = 'doctype:unknown';
        if (isPdf) iconName = 'doctype:pdf';
        else if (isImage) iconName = 'doctype:image';
        else if (ext === 'docx' || ext === 'doc') iconName = 'doctype:word';
        else if (ext === 'xlsx' || ext === 'xls' || ext === 'csv') iconName = 'doctype:excel';
        else if (ext === 'pptx' || ext === 'ppt') iconName = 'doctype:ppt';
        else if (ext === 'txt') iconName = 'doctype:txt';

        // "From" line varies by which tab we're on
        let fromLine = '';
        if (this.isInboxTab || (this.isRecordPage && e.senderId !== this._currentUserId)) {
            fromLine = `From: ${e.senderName || 'Unknown'}`;
        } else if (this.isSentTab) {
            fromLine = `To: ${e.recipientName || 'Unknown'}`;
        } else if (this.isMyFilesTab) {
            fromLine = 'Personal';
        } else if (this.isRecordPage) {
            fromLine = `From: ${e.senderName || 'Unknown'}`;
        }

        const dateToShow = e.sentDate || e.createdDate;
        const relativeDate = this._relativeTime(dateToShow);

        // Visual flag for unread entries in the Inbox
        const rowClass = (this.isInboxTab && !e.isRead) ? 'fh-row fh-row-unread' : 'fh-row';
        const showDelete = e.senderId === this._currentUserId;
        const showMarkRead = this.isInboxTab && !e.isRead;

        // Category-coded left stripe + colored tag chip — propagates the tile palette
        // down into the file list so the eye links "purple tile = purple row stripe".
        const categoryColor = CATEGORY_COLOR_BY_KEY[e.category] || '#6b7280';
        const rowStyle = `border-left-color:${categoryColor};`;
        const tagStyle = `background:${categoryColor}20;color:${categoryColor};`;

        return {
            ...e,
            iconName,
            fromLine,
            relativeDate,
            rowClass,
            rowStyle,
            tagStyle,
            showDelete,
            showMarkRead,
            hasMessage: !!e.message,
            hasRelated: !!(e.relatedResellerName || e.relatedLoanName),
            relatedLabel: e.relatedResellerName
                ? `Reseller: ${e.relatedResellerName}`
                : (e.relatedLoanName ? `Loan: ${e.relatedLoanName}` : '')
        };
    }

    get _currentUserId() {
        return USER_ID;
    }

    // ── Tab switching ─────────────────────────────────────────────

    handleTabClick(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab === this.activeTab) return;
        this.activeTab = tab;
        // Reset to 'All' when switching tabs — per-tab counts are scoped, the
        // previous category may not exist in the new view.
        this.selectedCategory = 'All';
        this.loadEntries();
        this.loadCategoryCounts();
    }

    /**
     * Tile bar click — sets the active category filter and reloads the list.
     */
    handleTileClick(event) {
        const cat = event.currentTarget.dataset.key;
        if (cat === this.selectedCategory) return;
        this.selectedCategory = cat;
        this.loadEntries();
    }

    // ── Filters ───────────────────────────────────────────────────

    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
        this.loadEntries();
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        // Debounce so we don't fire SOQL on every keystroke
        clearTimeout(this._searchDebounce);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchDebounce = setTimeout(() => this.loadEntries(), 300);
    }

    handleRefresh() {
        this.loadEntries();
        this.loadCategoryCounts();
        if (!this.recordId) {
            this.loadUnreadCount();
            this.loadRecentActivity();
            this.loadHeatmap();
        }
    }

    // ── Upload (drag-drop / button) ───────────────────────────────

    handleUploadFinished(event) {
        const files = event.detail.files;
        if (!files || files.length === 0) return;

        // Each upload finishes with a documentId; create one entry per file.
        // For the home page's "My Files" tab, no recipient → personal upload.
        // For the record page, link to the record.
        const promises = files.map(f => createEntry({
            contentDocumentId: f.documentId,
            recipientId: null,
            category: 'Personal',
            message: null,
            relatedResellerId: this._resellerLinkId(),
            relatedLoanId: this._loanLinkId()
        }));

        Promise.all(promises)
            .then(() => {
                const word = files.length === 1 ? 'file' : 'files';
                this._toast('Uploaded', `${files.length} ${word} added.`, 'success');
                this.loadEntries();
                this.loadCategoryCounts();
                if (!this.recordId) {
                    this.loadRecentActivity();
                    this.loadHeatmap();
                }
            })
            .catch(err => {
                this._toast('Upload failed', this._extractError(err), 'error');
            });
    }

    // Auto-link uploads on a Reseller__c record page to that reseller.
    // objectApiName is auto-injected by Lightning when the component is on a record page,
    // so this is reliable across orgs without runtime describe calls.
    _resellerLinkId() {
        return this.objectApiName === 'Reseller__c' ? this.recordId : null;
    }

    _loanLinkId() {
        return this.objectApiName === 'Loan__c' ? this.recordId : null;
    }

    // ── Send modal ────────────────────────────────────────────────

    handleOpenSendModal() {
        this.showSendModal = true;
    }

    handleCloseSendModal() {
        this.showSendModal = false;
    }

    handleSendModalSuccess() {
        this.showSendModal = false;
        this._toast('File sent', 'Your file has been delivered.', 'success');
        this.loadEntries();
        this.loadCategoryCounts();
        this.loadRecentActivity();
        this.loadHeatmap();
    }

    // ── Per-row actions ───────────────────────────────────────────

    handlePreview(event) {
        const docId = event.currentTarget.dataset.docid;
        if (!docId) return;
        // Open the standard Salesforce file preview overlay
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: docId }
        });
    }

    handleMarkRead(event) {
        const entryId = event.currentTarget.dataset.id;
        markAsRead({ entryId })
            .then(() => {
                this.loadEntries();
                this.loadUnreadCount();
            })
            .catch(err => this._toast('Failed', this._extractError(err), 'error'));
    }

    handleDelete(event) {
        const entryId = event.currentTarget.dataset.id;
        // eslint-disable-next-line no-alert
        if (!confirm('Delete this entry? The underlying file is preserved if it is shared elsewhere.')) {
            return;
        }
        deleteEntry({ entryId })
            .then(() => {
                this._toast('Deleted', 'Entry removed.', 'success');
                this.loadEntries();
                this.loadCategoryCounts();
                if (!this.recordId) this.loadRecentActivity();
            })
            .catch(err => this._toast('Delete failed', this._extractError(err), 'error'));
    }

    // ── Helpers ───────────────────────────────────────────────────

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

    /**
     * Returns "2 hours ago", "Yesterday", etc. Keeps the row visually compact.
     */
    _relativeTime(isoOrDate) {
        if (!isoOrDate) return '';
        const d = new Date(isoOrDate);
        const diffMs = Date.now() - d.getTime();
        const diffMin = Math.floor(diffMs / 60000);
        if (diffMin < 1) return 'Just now';
        if (diffMin < 60) return `${diffMin}m ago`;
        const diffHr = Math.floor(diffMin / 60);
        if (diffHr < 24) return `${diffHr}h ago`;
        const diffDay = Math.floor(diffHr / 24);
        if (diffDay === 1) return 'Yesterday';
        if (diffDay < 7) return `${diffDay}d ago`;
        return d.toLocaleDateString();
    }
}
