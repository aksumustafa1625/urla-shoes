import { LightningElement, api } from 'lwc';
import LOGO from '@salesforce/resourceUrl/urlaShoesBrand';

export default class UrlaShoesHeader extends LightningElement {
    @api brandName = 'URLA SHOES';

    get logoUrl() {
        return LOGO;
    }
}