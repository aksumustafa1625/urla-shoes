import { LightningElement, wire } from 'lwc';
import getShiftOverview from '@salesforce/apex/LeadShiftDashboardController.getShiftOverview';
import getSummary from '@salesforce/apex/LeadShiftDashboardController.getSummary';
import { refreshApex } from '@salesforce/apex';

export default class LeadShiftDashboard extends LightningElement {
    shifts = [];
    summary = {};
    error;
    _wiredShifts;
    _wiredSummary;

    @wire(getShiftOverview)
    wiredShifts(result) {
        this._wiredShifts = result;
        if (result.data) {
            this.shifts = result.data.map(shift => ({
                ...shift,
                statusClass: shift.isOnShift ? 'shift-card on-shift' : 'shift-card off-shift',
                statusLabel: shift.isOnShift ? 'Active' : 'Off',
                statusBadgeClass: shift.isOnShift ? 'badge badge-active' : 'badge badge-off',
                capacityBarClass: this.getCapacityBarClass(shift.capacityPercent),
                capacityBarStyle: `width: ${Math.max(shift.capacityPercent, 5)}%`,
                workingHours: `${this.pad(shift.startHour)}:00 - ${this.pad(shift.endHour)}:00`
            }));
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.shifts = [];
        }
    }

    @wire(getSummary)
    wiredSummary(result) {
        this._wiredSummary = result;
        if (result.data) {
            this.summary = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
        }
    }

    get hasShifts() {
        return this.shifts && this.shifts.length > 0;
    }

    get waitingClass() {
        return this.summary.totalWaiting > 0 ? 'summary-value warning' : 'summary-value';
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
        refreshApex(this._wiredShifts);
        refreshApex(this._wiredSummary);
    }
}
