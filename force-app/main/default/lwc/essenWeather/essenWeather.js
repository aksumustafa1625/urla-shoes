import { LightningElement, track } from 'lwc';
import getOpenWeatherApiKey from '@salesforce/apex/ApiKeyService.getOpenWeatherApiKey';

export default class EssenWeather extends LightningElement {
 
    @track weatherData;
    @track forecastData = [];
    @track hourlyData   = [];
    @track error;
    @track isLoading    = true;
    @track currentTime  = '';
    @track searchValue  = '';
    @track showNotFound = false;
 
    // Default city — Essen
    _city = 'Essen,DE';
 
    // SECURITY: never hardcode the key. Load it from the API_Config__c Custom
    // Setting via ApiKeyService (same pattern as the routeWeather component).
    apiKey = '';
    _timer;
 
    // ── Lifecycle ──────────────────────────────────────────────
    async connectedCallback() {
        this.updateTime();
        this._timer = setInterval(() => this.updateTime(), 60000);
        // Load the OpenWeather key from the API_Config__c Custom Setting via
        // ApiKeyService — identical to the routeWeather component. No key ever
        // lives in source control.
        this.apiKey = await getOpenWeatherApiKey();
        this.fetchWeather();
    }
 
    disconnectedCallback() {
        if (this._timer) clearInterval(this._timer);
    }
 
    // ── Clock ──────────────────────────────────────────────────
    updateTime() {
        const now = new Date();
        const h   = String(now.getHours()).padStart(2, '0');
        const m   = String(now.getMinutes()).padStart(2, '0');
        this.currentTime = `${h}:${m}`;
    }
 
    // ── Search handlers ────────────────────────────────────────
    handleSearchInput(event) {
        this.searchValue  = event.target.value;
        this.showNotFound = false;
    }
 
    handleSearchKey(event) {
        if (event.key === 'Enter') {
            this.handleSearchSubmit();
        }
    }
 
    handleSearchSubmit() {
        const val = this.searchValue.trim();
        if (!val) return;
        this._city = val;
        this.fetchWeather();
    }
 
    // ── Location badge label ───────────────────────────────────
    get locationLabel() {
        if (!this.weatherData) return '';
        return (this.weatherData.city + ', ' + this.weatherData.country).toUpperCase();
    }
 
    // ── Fetch ──────────────────────────────────────────────────
    fetchWeather() {
        this.isLoading    = true;
        this.error        = null;
        this.showNotFound = false;
        this.weatherData  = null;
 
        const currentUrl  = `https://api.openweathermap.org/data/2.5/weather?q=${encodeURIComponent(this._city)}&appid=${this.apiKey}&units=metric`;
        const forecastUrl = `https://api.openweathermap.org/data/2.5/forecast?q=${encodeURIComponent(this._city)}&appid=${this.apiKey}&units=metric`;
 
        Promise.all([
            fetch(currentUrl).then(r => r.json()),
            fetch(forecastUrl).then(r => r.json())
        ])
        .then(([current, forecast]) => {
            // API returns cod 404 as a 200 response body when city not found
            if (current.cod === '404' || current.cod === 404) {
                this.showNotFound = true;
                this.isLoading    = false;
                // Reset city to default
                this._city        = 'Essen,DE';
                this.searchValue  = '';
                return;
            }
            this.processCurrentWeather(current);
            this.processForecast(forecast);
            this.processHourly(forecast);
            this.isLoading = false;
        })
        .catch(err => {
            this.error     = err;
            this.isLoading = false;
            console.error('Weather Error:', err);
        });
    }
 
    // ── Current weather ────────────────────────────────────────
    processCurrentWeather(data) {
        this.weatherData = {
            temp:        Math.round(data.main.temp),
            tempMax:     Math.round(data.main.temp_max),
            tempMin:     Math.round(data.main.temp_min),
            feelsLike:   Math.round(data.main.feels_like),
            city:        data.name,
            country:     data.sys.country,
            description: data.weather[0].description.toUpperCase(),
            humidity:    data.main.humidity,
            wind:        `${Math.round(data.wind.speed * 3.6)} km/h`,
            condition:   data.weather[0].main
        };
    }
 
    // ── 5-day forecast ─────────────────────────────────────────
    processForecast(data) {
        const days     = {};
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
 
        data.list.forEach(item => {
            const date = item.dt_txt.split(' ')[0];
            if (!days[date]) days[date] = { highs: [], lows: [], conditions: [] };
            days[date].highs.push(item.main.temp_max);
            days[date].lows.push(item.main.temp_min);
            days[date].conditions.push(item.weather[0].main);
        });
 
        const today   = new Date().toISOString().split('T')[0];
        const entries = Object.entries(days)
            .filter(([date]) => date !== today)
            .slice(0, 5);
 
        const allHighs  = entries.map(([, d]) => Math.max(...d.highs));
        const globalMin = Math.min(...entries.map(([, d]) => Math.min(...d.lows)));
        const globalMax = Math.max(...allHighs);
 
        this.forecastData = entries.map(([date, d]) => {
            const high = Math.round(Math.max(...d.highs));
            const low  = Math.round(Math.min(...d.lows));
            const cond = this.mostFrequent(d.conditions);
            const pct  = globalMax !== globalMin
                ? Math.round(((high - globalMin) / (globalMax - globalMin)) * 100)
                : 60;
            const dow  = new Date(date + 'T12:00:00').getDay();
            return {
                date,
                dayName:  dayNames[dow],
                high,
                low,
                icon:     this.conditionToEmoji(cond),
                desc:     cond,
                barStyle: `width:${pct}%`
            };
        });
    }
 
    // ── Hourly (next 24 h) ─────────────────────────────────────
    processHourly(data) {
        this.hourlyData = data.list.slice(0, 8).map((item, idx) => {
            const d  = new Date(item.dt * 1000);
            const h  = String(d.getHours()).padStart(2, '0');
            return {
                time:     idx === 0 ? 'Now' : `${h}:00`,
                temp:     Math.round(item.main.temp),
                icon:     this.conditionToEmoji(item.weather[0].main),
                cssClass: idx === 0 ? 'hourly-item active' : 'hourly-item'
            };
        });
    }
 
    // ── Helpers ────────────────────────────────────────────────
    mostFrequent(arr) {
        return arr.sort((a, b) =>
            arr.filter(v => v === a).length - arr.filter(v => v === b).length
        ).pop();
    }
 
    conditionToEmoji(cond) {
        const map = {
            Clear:        '☀️',
            Clouds:       '☁️',
            Rain:         '🌧️',
            Drizzle:      '🌦️',
            Thunderstorm: '⛈️',
            Snow:         '❄️',
            Mist:         '🌫️',
            Fog:          '🌫️',
            Haze:         '🌫️'
        };
        return map[cond] || '🌡️';
    }
 
    // ── State flags ────────────────────────────────────────────
    get showData()  { return !this.isLoading && !this.error && !!this.weatherData; }
    get showError() { return !this.isLoading && !!this.error; }
 
    get condition() { return this.weatherData ? this.weatherData.condition : ''; }
 
    get isSunny()  { return this.condition === 'Clear'; }
    get isCloudy() { return this.condition === 'Clouds'; }
    get isRainy()  { return this.condition === 'Rain' || this.condition === 'Drizzle'; }
    get isSnowy()  { return this.condition === 'Snow'; }
    get isStormy() { return this.condition === 'Thunderstorm'; }
    get isDefault(){ return !this.isSunny && !this.isCloudy && !this.isRainy && !this.isSnowy && !this.isStormy; }
 
    // ── Dynamic card class ─────────────────────────────────────
    get computedCardClass() {
        let bg = 'bg-default';
        if (this.isSunny)       bg = 'bg-sunny';
        else if (this.isCloudy) bg = 'bg-cloudy';
        else if (this.isRainy)  bg = 'bg-rainy';
        else if (this.isSnowy)  bg = 'bg-snowy';
        else if (this.isStormy) bg = 'bg-stormy';
        return `weather-card ${bg}`;
    }
}