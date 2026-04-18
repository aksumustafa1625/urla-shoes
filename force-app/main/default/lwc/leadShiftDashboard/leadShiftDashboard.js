import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getShiftOverview from '@salesforce/apex/LeadShiftDashboardController.getShiftOverview';
import getSummary from '@salesforce/apex/LeadShiftDashboardController.getSummary';
import getRecentActivities from '@salesforce/apex/LeadShiftDashboardController.getRecentActivities';
import { refreshApex } from '@salesforce/apex';

const CHANNEL = '/event/Lead_Shift_Event__e';
const SHIFT_COLORS = ['#0070d2', '#2e844a', '#fe9339', '#9553b7', '#005fb2'];
const MAX_ACTIVITIES = 12;

export default class LeadShiftDashboard extends LightningElement {
    shifts = [];
    summary = {};
    error;
    _wiredShifts;
    _wiredSummary;
    subscription = {};
    isLive = false;
    activities = [];
    _activityIdCounter = 0;
    _knownActivityIds = new Set();
    refreshToken = Date.now();
    _cursorInterval;
    _pollInterval;
    _slowPollInterval;
    cursorPosition = 0;

    connectedCallback() {
        this.registerErrorListener();
        this.handleSubscribe();
        this.startCursorTicker();
        this.startPolling();
    }

    disconnectedCallback() {
        this.handleUnsubscribe();
        if (this._cursorInterval) clearInterval(this._cursorInterval);
        if (this._pollInterval) clearInterval(this._pollInterval);
        if (this._slowPollInterval) clearInterval(this._slowPollInterval);
    }

    startPolling() {
        // Seed known IDs so existing history doesn't flood the feed on first load
        this.seedKnownActivities();
        // Fast poll (1s) for summary to feel near-live
        this._pollInterval = setInterval(() => {
            this.refreshToken = Date.now();
            this.pollSummary();
        }, 1000);
        // Slower poll (3s) for heavier queries
        this._slowPollInterval = setInterval(() => {
            this.pollShifts();
            this.pollActivities();
        }, 3000);
    }

    pollSummary() {
        getSummary({ refreshToken: this.refreshToken })
            .then(data => {
                if (data) {
                    this.summary = data;
                    this.updateCursorFromSummary();
                }
            })
            .catch(() => { /* ignore */ });
    }

    pollShifts() {
        getShiftOverview({ refreshToken: this.refreshToken })
            .then(data => {
                if (data) this.applyShiftData(data);
            })
            .catch(() => { /* ignore */ });
    }

    seedKnownActivities() {
        getRecentActivities({ refreshToken: Date.now() })
            .then(data => {
                if (data) data.forEach(a => this._knownActivityIds.add(a.activityId));
            })
            .catch(() => { /* ignore */ });
    }

    pollActivities() {
        getRecentActivities({ refreshToken: this.refreshToken })
            .then(data => {
                if (!data) return;
                // Process oldest first so newest ends up at top after unshift
                const fresh = data
                    .filter(a => !this._knownActivityIds.has(a.activityId))
                    .reverse();
                fresh.forEach(a => {
                    this._knownActivityIds.add(a.activityId);
                    this.pushActivity(a.eventType, a.repName, a.message);
                });
            })
            .catch(() => { /* ignore */ });
    }

    @wire(getShiftOverview, { refreshToken: '$refreshToken' })
    wiredShifts(result) {
        this._wiredShifts = result;
        if (result.data) {
            this.applyShiftData(result.data);
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.shifts = [];
        }
    }

    applyShiftData(data) {
        const rankedIds = [...data]
            .sort((a, b) => (b.completedCount || 0) - (a.completedCount || 0))
            .map(s => s.shiftId);

        this.shifts = data.map((shift, index) => {
            const color = SHIFT_COLORS[index % SHIFT_COLORS.length];
            const rank = rankedIds.indexOf(shift.shiftId) + 1;
            const rankInfo = this.getRankInfo(rank);
            return {
                ...shift,
                color,
                colorStyle: `color: ${color};`,
                rank,
                ...rankInfo,
                statusClass: shift.isOnShift ? 'shift-card on-shift' : 'shift-card off-shift',
                statusLabel: shift.isOnShift ? 'Active' : 'Off',
                statusBadgeClass: shift.isOnShift ? 'badge badge-active' : 'badge badge-off',
                capacityBarClass: this.getCapacityBarClass(shift.capacityPercent),
                capacityBarStyle: `width: ${Math.max(shift.capacityPercent, 5)}%`,
                workingHours: `${this.pad(shift.startHour)}:00 - ${this.pad(shift.endHour)}:00`,
                timelineBars: this.buildTimelineBars(shift, color)
            };
        });
    }

    getRankInfo(rank) {
        if (rank === 1) {
            return {
                rankMedal: '🥇',
                rankLabel: 'Champion',
                rankTierClass: 'tier-gold',
                rankBadgeClass: 'rank-badge rank-gold'
            };
        }
        if (rank === 2) {
            return {
                rankMedal: '🥈',
                rankLabel: 'Elite',
                rankTierClass: 'tier-silver',
                rankBadgeClass: 'rank-badge rank-silver'
            };
        }
        if (rank === 3) {
            return {
                rankMedal: '🥉',
                rankLabel: 'Rising',
                rankTierClass: 'tier-bronze',
                rankBadgeClass: 'rank-badge rank-bronze'
            };
        }
        return {
            rankMedal: `#${rank}`,
            rankLabel: 'Starter',
            rankTierClass: 'tier-default',
            rankBadgeClass: 'rank-badge rank-default'
        };
    }

    get leaderboard() {
        if (!this.shifts || this.shifts.length === 0) return [];
        const maxCount = Math.max(...this.shifts.map(s => s.completedCount || 0), 1);
        return [...this.shifts]
            .sort((a, b) => (b.completedCount || 0) - (a.completedCount || 0))
            .map(shift => ({
                ...shift,
                barStyle: `width: ${((shift.completedCount || 0) / maxCount) * 100}%; background: ${shift.color};`,
                rowClass: `leader-row ${shift.rankTierClass}`
            }));
    }

    @wire(getSummary, { refreshToken: '$refreshToken' })
    wiredSummary(result) {
        this._wiredSummary = result;
        if (result.data) {
            this.summary = result.data;
            this.updateCursorFromSummary();
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
        }
    }

    buildTimelineBars(shift, color) {
        // Returns 1 or 2 bars for the timeline depending on overnight wrap
        const start = shift.lagosStartHour;
        const end = shift.lagosEndHour;
        const hourWidth = 100 / 24;

        if (start < end) {
            return [{
                key: `${shift.shiftId}-1`,
                style: `left: ${start * hourWidth}%; width: ${(end - start) * hourWidth}%; background: ${color};`
            }];
        }
        // Overnight wrap → two bars
        return [
            {
                key: `${shift.shiftId}-1`,
                style: `left: ${start * hourWidth}%; width: ${(24 - start) * hourWidth}%; background: ${color};`
            },
            {
                key: `${shift.shiftId}-2`,
                style: `left: 0%; width: ${end * hourWidth}%; background: ${color};`
            }
        ];
    }

    get hours() {
        const arr = [];
        for (let i = 0; i < 24; i++) {
            arr.push({ key: i, label: String(i).padStart(2, '0'), showLabel: i % 3 === 0 });
        }
        return arr;
    }

    get cursorStyle() {
        return `left: ${this.cursorPosition}%;`;
    }

    get hasActivities() {
        return this.activities && this.activities.length > 0;
    }

    updateCursorFromSummary() {
        const h = this.summary.lagosCurrentHour || 0;
        const m = this.summary.lagosCurrentMinute || 0;
        this.cursorPosition = ((h + m / 60) / 24) * 100;
    }

    startCursorTicker() {
        // Advance cursor locally every 30 seconds without refetching
        this._cursorInterval = setInterval(() => {
            if (this.summary.lagosCurrentHour === undefined) return;
            this.summary = {
                ...this.summary,
                lagosCurrentMinute: (this.summary.lagosCurrentMinute || 0) + 0.5
            };
            if (this.summary.lagosCurrentMinute >= 60) {
                this.summary.lagosCurrentHour = (this.summary.lagosCurrentHour + 1) % 24;
                this.summary.lagosCurrentMinute = 0;
            }
            this.updateCursorFromSummary();
        }, 30000);
    }

    get hasShifts() {
        return this.shifts && this.shifts.length > 0;
    }

    get waitingClass() {
        return this.summary.totalWaiting > 0 ? 'summary-value warning' : 'summary-value';
    }

    get liveIndicatorClass() {
        return this.isLive ? 'live-indicator live' : 'live-indicator';
    }

    get liveLabel() {
        return this.isLive ? 'LIVE' : 'OFFLINE';
    }

    getCapacityBarClass(percent) {
        if (percent >= 100) return 'capacity-bar bar-full';
        if (percent >= 75) return 'capacity-bar bar-high';
        if (percent >= 50) return 'capacity-bar bar-medium';
        return 'capacity-bar bar-low';
    }

    pad(num) {
        return String(num).padStart(2, '0');
    }

    handleRefresh() {
        this.refreshToken = Date.now();
        this.pollSummary();
        this.pollShifts();
        this.pollActivities();
    }

    handleSubscribe() {
        const messageCallback = (response) => {
            const payload = response.data.payload;
            const eventType = payload.Event_Type__c;
            const repName = payload.Rep_Name__c;
            const message = payload.Message__c;

            this.pushActivity(eventType, repName, message);

            // Bump token and refetch immediately on event arrival
            this.refreshToken = Date.now();
            this.pollSummary();
            this.pollShifts();

            if (eventType === 'Completed') {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Lead Completed',
                    message: `${repName} just completed a lead`,
                    variant: 'success',
                    mode: 'dismissable'
                }));
            } else if (eventType === 'NewLead') {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'New Lead',
                    message: message,
                    variant: 'info',
                    mode: 'dismissable'
                }));
            }

            this.triggerPulse();
        };

        subscribe(CHANNEL, -1, messageCallback).then(response => {
            this.subscription = response;
            this.isLive = true;
        });
    }

    pushActivity(eventType, repName, message) {
        this._activityIdCounter += 1;
        const now = new Date();
        const time = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;

        let iconName = 'utility:info';
        let iconClass = 'activity-icon activity-info';
        if (eventType === 'Completed') {
            iconName = 'utility:success';
            iconClass = 'activity-icon activity-success';
        } else if (eventType === 'NewLead') {
            iconName = 'utility:new';
            iconClass = 'activity-icon activity-new';
        }

        const entry = {
            id: this._activityIdCounter,
            time,
            message: message || `${eventType} event`,
            iconName,
            iconClass,
            cardClass: 'activity-item activity-enter'
        };

        this.activities = [entry, ...this.activities].slice(0, MAX_ACTIVITIES);

        // Remove enter class after animation
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.activities = this.activities.map(a =>
                a.id === entry.id ? { ...a, cardClass: 'activity-item' } : a
            );
        }, 400);
    }

    handleUnsubscribe() {
        unsubscribe(this.subscription, () => {
            this.isLive = false;
        });
    }

    registerErrorListener() {
        onError(error => {
            // eslint-disable-next-line no-console
            console.error('empApi error', JSON.stringify(error));
        });
    }

    triggerPulse() {
        const card = this.template.querySelector('.summary-container');
        if (card) {
            card.classList.remove('pulse');
            void card.offsetWidth;
            card.classList.add('pulse');
        }
    }
}
