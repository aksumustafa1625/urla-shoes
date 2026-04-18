import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import TIER_MEDALS from '@salesforce/resourceUrl/tierMedals';
 
import NAME_FIELD        from '@salesforce/schema/Reseller__c.Name';
import TOTAL_OPP_FIELD   from '@salesforce/schema/Reseller__c.Total_Opportunity_Count__c';
 
const FIELDS = [NAME_FIELD, TOTAL_OPP_FIELD];
 
const TIERS = [
    {
        key        : 'Bronze',
        min        : 0,
        max        : 9,
        next       : 'Silver',
        nextMin    : 10,
        img        : '/bronze.png',
        color      : '#CD7F32',
        bg         : '#FDF0E0',
        description: '10% partner discount · Standard product access'
    },
    {
        key        : 'Silver',
        min        : 10,
        max        : 19,
        next       : 'Gold',
        nextMin    : 20,
        img        : '/silver.png',
        color      : '#707070',
        bg         : '#F0F0F2',
        description: '20% partner discount · Premium product access'
    },
    {
        key        : 'Gold',
        min        : 20,
        max        : 29,
        next       : 'Platinum',
        nextMin    : 30,
        img        : '/gold.png',
        color      : '#B8860B',
        bg         : '#FFFBE6',
        description: '30% partner discount · Exclusive product access'
    },
    {
        key        : 'Platinum',
        min        : 30,
        max        : Infinity,
        next       : null,
        nextMin    : null,
        img        : '/platinium.png',
        color      : '#5C5C5C',
        bg         : '#F5F5F8',
        description: '35% partner discount · All products + early access'
    }
];
 
export default class ResellerTierBadge extends LightningElement {
 
    @api recordId;
 
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    resellerRecord;
 
    get resellerName() {
        return getFieldValue(this.resellerRecord.data, NAME_FIELD) || '';
    }
 
    get totalOpportunities() {
        return getFieldValue(this.resellerRecord.data, TOTAL_OPP_FIELD) || 0;
    }
 
    get currentTier() {
        const count = this.totalOpportunities;
        return TIERS.find(t => count >= t.min && count <= t.max) || TIERS[0];
    }
 
    get tierMedalImg()      { return TIER_MEDALS + this.currentTier.img; }
    get tierLabel()         { return this.currentTier.key; }
    get tierDescription()   { return this.currentTier.description; }
    get nextTierLabel()     { return this.currentTier.next || 'Platinum'; }
    get nextTierThreshold() { return this.currentTier.nextMin || 30; }
    get isMaxTier()         { return this.currentTier.key === 'Platinum'; }
 
    get oppsRemaining() {
        if (this.isMaxTier) return 0;
        return Math.max(this.currentTier.nextMin - this.totalOpportunities, 0);
    }
 
    get progressPercent() {
        if (this.isMaxTier) return 100;
        const min   = this.currentTier.min;
        const max   = this.currentTier.nextMin;
        const count = this.totalOpportunities;
        return Math.min(Math.round(((count - min) / (max - min)) * 100), 100);
    }
 
    get progressStyle() {
        return `width: ${this.progressPercent}%; background: ${this.currentTier.color};`;
    }
 
    get badgeStyle() {
        return `background: ${this.currentTier.bg}; color: ${this.currentTier.color};`;
    }
 
    _isReached(tierKey) {
        return TIERS.findIndex(t => t.key === this.currentTier.key)
            >= TIERS.findIndex(t => t.key === tierKey);
    }
 
    _dotStyle(tierKey) {
        const tier = TIERS.find(t => t.key === tierKey);
        return this._isReached(tierKey)
            ? `background: ${tier.color}; color: #fff; border-color: transparent;`
            : `background: transparent; color: var(--lwc-colorTextDefault); border-color: #ccc;`;
    }
 
    _dotText(tierKey)  { return this._isReached(tierKey) ? '✓' : '○'; }
 
    _lineClass(index) {
        return TIERS.findIndex(t => t.key === this.currentTier.key) >= index
            ? 'roadmap-line roadmap-line-filled'
            : 'roadmap-line';
    }
 
    _labelClass(tierKey) {
        return this._isReached(tierKey)
            ? 'roadmap-label roadmap-label-active'
            : 'roadmap-label';
    }
 
    get bronzeDotStyle()    { return this._dotStyle('Bronze'); }
    get bronzeDotText()     { return this._dotText('Bronze'); }
    get bronzeLabelClass()  { return this._labelClass('Bronze'); }
 
    get silverDotStyle()    { return this._dotStyle('Silver'); }
    get silverDotText()     { return this._dotText('Silver'); }
    get silverLabelClass()  { return this._labelClass('Silver'); }
 
    get goldDotStyle()      { return this._dotStyle('Gold'); }
    get goldDotText()       { return this._dotText('Gold'); }
    get goldLabelClass()    { return this._labelClass('Gold'); }
 
    get platinumDotStyle()  { return this._dotStyle('Platinum'); }
    get platinumDotText()   { return this._dotText('Platinum'); }
    get platinumLabelClass(){ return this._labelClass('Platinum'); }
 
    get line1Class() { return this._lineClass(1); }
    get line2Class() { return this._lineClass(2); }
    get line3Class() { return this._lineClass(3); }
}
 