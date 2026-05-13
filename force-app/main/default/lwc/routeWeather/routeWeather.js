/**
 * @component     routeWeather
 * @description   Route & Weather Navigator LWC component for Urla Shoes
 *                Displays a Google Maps driving route from Essen to any destination,
 *                fetches live weather at 5 waypoints via OpenWeather API,
 *                and triggers an Einstein AI safety analysis via Apex.
 *
 *                Key integrations:
 *                - Google Maps Directions API (via Visualforce Page iframe + postMessage)
 *                - OpenWeather API (current weather + forecast)
 *                - Salesforce Einstein LLM (via RouteWeatherAnalysis Apex class)
 *
 * @author        Mustafa Aksu
 * @project       Urla Shoes
 * @version       1.0
 * @date          2026-03-29
 */

import { LightningElement, track } from 'lwc';
import analyzeRoute from '@salesforce/apex/RouteWeatherAnalysis.analyzeRoute';
import getOpenWeatherApiKey from '@salesforce/apex/ApiKeyService.getOpenWeatherApiKey';

/**
 * Visualforce Page URL that hosts the Google Maps iframe.
 * Google Maps cannot be loaded directly in LWC due to Lightning Web Security (LWS),
 * so it runs inside a VF page and communicates via window.postMessage.
 * Relative path resolves to whichever org is currently hosting the LWC,
 * so this works in any environment without per-org edits.
 */
const VF_PAGE_URL = '/apex/RouteMapPage';

export default class RouteWeather extends LightningElement {

    // OpenWeather API key — loaded async from API_Config__c custom setting
    // via ApiKeyService.getOpenWeatherApiKey(). See connectedCallback below.
    // Setup → Custom Settings → API Config → Manage to set the value.
    WEATHER_KEY = '';

    // Essen, Germany — fixed origin coordinates
    ORIGIN_COORD = { lat: 51.4556, lng: 7.0116 };

    // ── Reactive state ─────────────────────────────────────────
    @track destInput       = '';
    @track isLoading       = false;
    @track hasRoute        = false;
    @track showWeather     = false;
    @track showModal       = false;
    @track modal           = {};
    @track aiAnalysis      = '';
    @track aiLoading       = false;
    @track currentTime     = '';
    @track errorMsg        = '';
    @track waypointWeather = [];
    @track destCity        = '';
    @track routeDistance   = '';
    @track routeDuration   = '';

    // ── Private properties ─────────────────────────────────────
    _timer       = null;   // Clock interval reference
    _mapsReady   = false;  // True once VF page signals Maps is loaded
    _pendingDest = null;   // Stores destination if user clicks Go before Maps is ready
    _msgHandler  = null;   // Bound postMessage event handler reference

    // ── Computed properties ────────────────────────────────────

    /** Returns the Visualforce Page URL for the map iframe src attribute. */
    get mapPageUrl() {
        return VF_PAGE_URL;
    }

    /**
     * Controls iframe visibility.
     * The iframe is always present in DOM (so VF page loads immediately),
     * but hidden until a route is successfully drawn.
     */
    get iframeClass() {
        return this.hasRoute ? 'rw-map-iframe visible' : 'rw-map-iframe hidden';
    }

    // ── Lifecycle ──────────────────────────────────────────────

    async connectedCallback() {
        this._updateTime();
        // Update clock every minute
        this._timer = setInterval(() => this._updateTime(), 60000);
        // Listen for postMessage events from the Google Maps VF iframe
        this._msgHandler = this._handleMessage.bind(this);
        window.addEventListener('message', this._msgHandler);

        // Load OpenWeather API key from API_Config__c custom setting.
        // If the key is missing, weather fetches will fail with a clear error.
        try {
            this.WEATHER_KEY = await getOpenWeatherApiKey();
            if (!this.WEATHER_KEY) {
                this.errorMsg = 'OpenWeather API key not configured. ' +
                    'Setup → Custom Settings → API Config → Manage.';
            }
        } catch (e) {
            this.errorMsg = 'Could not load OpenWeather API key: ' + (e.body?.message || e.message || e);
        }
    }

    disconnectedCallback() {
        if (this._timer) clearInterval(this._timer);
        window.removeEventListener('message', this._msgHandler);
    }

    /** Updates the displayed time (HH:MM format). */
    _updateTime() {
        const n = new Date();
        this.currentTime = String(n.getHours()).padStart(2,'0') + ':' + String(n.getMinutes()).padStart(2,'0');
    }

    // ── Modal (waypoint detail card) ───────────────────────────

    /** Opens the detail modal for a clicked waypoint card. */
    handleCardClick(event) {
        const city = event.currentTarget.dataset.city;
        const wp   = this.waypointWeather.find(w => w.city === city);
        if (!wp) return;
        this._fetchModalData(wp);
    }

    /**
     * Fetches detailed current weather + 8-step hourly forecast
     * for the selected waypoint and populates the modal object.
     */
    _fetchModalData(wp) {
        const currentUrl  = `https://api.openweathermap.org/data/2.5/weather?lat=${wp.lat}&lon=${wp.lng}&appid=${this.WEATHER_KEY}&units=metric`;
        const forecastUrl = `https://api.openweathermap.org/data/2.5/forecast?lat=${wp.lat}&lon=${wp.lng}&appid=${this.WEATHER_KEY}&units=metric`;

        Promise.all([
            fetch(currentUrl).then(r => r.json()),
            fetch(forecastUrl).then(r => r.json())
        ]).then(([cur, fcst]) => {
            // Build hourly strip (next 24h in 3-hour steps)
            const hourly = fcst.list.slice(0, 8).map((item, idx) => {
                const d = new Date(item.dt * 1000);
                const h = String(d.getHours()).padStart(2,'0');
                return {
                    time: idx === 0 ? 'Now' : `${h}:00`,
                    temp: Math.round(item.main.temp),
                    icon: this._condToEmoji(item.weather[0].main),
                    cls:  idx === 0 ? 'modal-h-item active' : 'modal-h-item'
                };
            });

            this.modal = {
                type:       wp.type,
                city:       wp.city,
                temp:       Math.round(cur.main.temp),
                tempMax:    Math.round(cur.main.temp_max),
                tempMin:    Math.round(cur.main.temp_min),
                feelsLike:  Math.round(cur.main.feels_like),
                desc:       cur.weather[0].description.toUpperCase(),
                humidity:   cur.main.humidity,
                wind:       `${Math.round(cur.wind.speed * 3.6)} km/h`,
                clouds:     cur.clouds.all,
                pressure:   cur.main.pressure,
                visibility: cur.visibility ? `${(cur.visibility/1000).toFixed(1)} km` : 'N/A',
                icon:       this._condToEmoji(cur.weather[0].main),
                condition:  cur.weather[0].main,
                hourly
            };
            this.showModal = true;
        }).catch(err => console.error('Modal weather error:', err));
    }

    handleOverlayClick() { this.closeModal(); }
    handleModalClick(event) { event.stopPropagation(); } // Prevent overlay click from bubbling
    closeModal() { this.showModal = false; }

    /** Returns the modal background CSS class based on weather condition. */
    get modalBgClass() {
        if (!this.modal || !this.modal.condition) return 'modal-bg modal-bg-default';
        const map = { Clear:'modal-bg-sunny', Clouds:'modal-bg-cloudy', Rain:'modal-bg-rainy', Drizzle:'modal-bg-rainy', Thunderstorm:'modal-bg-stormy', Snow:'modal-bg-snowy' };
        return `modal-bg ${map[this.modal.condition] || 'modal-bg-default'}`;
    }

    // ── postMessage handler (VF iframe → LWC) ─────────────────

    /**
     * Handles messages sent by the Google Maps Visualforce Page via postMessage.
     * Three message types are handled:
     * - MAPS_READY: Google Maps has fully loaded, safe to send route requests
     * - ROUTE_DONE: Route calculated successfully, contains distance/duration/coords
     * - ROUTE_ERROR: Route calculation failed (e.g. invalid city)
     */
    _handleMessage(event) {
        if (!event.data || !event.data.type) return;

        const msg = event.data;

        if (msg.type === 'MAPS_READY') {
            this._mapsReady = true;
            // If user clicked Go before Maps finished loading, send the queued request now
            if (this._pendingDest) {
                this._sendRouteRequest(this._pendingDest);
                this._pendingDest = null;
            }
        }

        if (msg.type === 'ROUTE_DONE') {
            this.routeDistance = msg.distance;
            this.routeDuration = msg.duration;
            this.destCity      = msg.destName || this.destInput;
            this.hasRoute      = true;
            this.isLoading     = false;
            // Fetch weather for all 5 waypoints along the route
            const destCoord = { lat: msg.destLat, lng: msg.destLng };
            this._getWaypointsWeather(this.ORIGIN_COORD, destCoord, this.destCity);
        }

        if (msg.type === 'ROUTE_ERROR') {
            this.isLoading = false;
            this.errorMsg  = `Route could not be calculated (${msg.status}). Try a different city.`;
        }
    }

    // ── User input handlers ────────────────────────────────────

    handleDestInput(event) {
        this.destInput = event.target.value;
        this.errorMsg  = '';
    }

    handleDestKey(event) {
        if (event.key === 'Enter') this.handleGo();
    }

    handleGo() {
        const dest = this.destInput.trim();
        if (!dest) {
            this.errorMsg = 'Please enter a destination city.';
            return;
        }

        this.isLoading   = true;
        this.errorMsg    = '';
        this.hasRoute    = false;
        this.showWeather = false;

        if (this._mapsReady) {
            this._sendRouteRequest(dest);
        } else {
            // Maps iframe still loading — queue the request
            this._pendingDest = dest;
        }
    }

    /** Sends a DRAW_ROUTE message to the Google Maps VF iframe via postMessage. */
    _sendRouteRequest(dest) {
        const iframe = this.template.querySelector('iframe');
        if (iframe && iframe.contentWindow) {
            iframe.contentWindow.postMessage({ type: 'DRAW_ROUTE', destination: dest }, '*');
        }
    }

    // ── Weather fetching ───────────────────────────────────────

    /**
     * Fetches live weather for 5 waypoints distributed along the route:
     * Departure (0%), 1/4 (25%), Midpoint (50%), 3/4 (75%), Destination (100%).
     * Uses linear interpolation between origin and destination coordinates.
     * After all 5 fetches complete, triggers the Einstein AI analysis.
     */
    _getWaypointsWeather(origin, dest, destCityName) {
        const lerp = (a, b, t) => a + (b - a) * t;

        const points = [
            { type: 'DEPARTURE',   lat: origin.lat,                    lng: origin.lng,                    name: 'Essen' },
            { type: '1/4 ROUTE',   lat: lerp(origin.lat,dest.lat,0.25),lng: lerp(origin.lng,dest.lng,0.25),name: null },
            { type: 'MIDPOINT',    lat: lerp(origin.lat,dest.lat,0.50),lng: lerp(origin.lng,dest.lng,0.50),name: null },
            { type: '3/4 ROUTE',   lat: lerp(origin.lat,dest.lat,0.75),lng: lerp(origin.lng,dest.lng,0.75),name: null },
            { type: 'DESTINATION', lat: dest.lat,                       lng: dest.lng,                      name: destCityName }
        ];

        // Fetch all 5 waypoints in parallel for performance
        Promise.all(points.map(p =>
            fetch(`https://api.openweathermap.org/data/2.5/weather?lat=${p.lat}&lon=${p.lng}&appid=${this.WEATHER_KEY}&units=metric`)
                .then(r => r.json())
                .then(data => ({
                    type:      p.type,
                    city:      p.name || data.name,
                    temp:      Math.round(data.main.temp),
                    desc:      data.weather[0].description.toUpperCase(),
                    humidity:  data.main.humidity,
                    wind:      `${Math.round(data.wind.speed * 3.6)} km/h`,
                    icon:      this._condToEmoji(data.weather[0].main),
                    lat:       p.lat,
                    lng:       p.lng,
                    cardClass: `rw-wp-card ${this._condToCardClass(data.weather[0].main)}${p.type === 'DESTINATION' ? ' dest-card' : ''}`
                }))
        ))
        .then(results => {
            this.waypointWeather = results;
            this.showWeather     = true;
            // Trigger Einstein AI safety analysis after weather data is ready
            this._callAgentforce(results);
        })
        .catch(err => { console.error('Weather error:', err); });
    }

    // ── Einstein AI (Agentforce) ───────────────────────────────

    /**
     * Calls the RouteWeatherAnalysis Apex class which invokes the
     * Einstein Prompt Template via ConnectApi.EinsteinLLM.
     * Sends only the fields needed by the Prompt Template (type, city, temp, desc, humidity, wind).
     */
    _callAgentforce(waypoints) {
        this.aiLoading  = true;
        this.aiAnalysis = '';

        const payload = waypoints.map(w => ({
            type:     w.type,
            city:     w.city,
            temp:     w.temp,
            desc:     w.desc,
            humidity: w.humidity,
            wind:     w.wind
        }));

        analyzeRoute({ waypointsJson: JSON.stringify(payload) })
            .then(result => {
                this.aiAnalysis = result;
                this.aiLoading  = false;
            })
            .catch(err => {
                this.aiAnalysis = 'Agentforce analysis unavailable. Please check API connection.';
                this.aiLoading  = false;
                console.error('Agentforce error:', err);
            });
    }

    /**
     * Returns the safety icon based on keywords in the AI analysis text.
     * ⚠️ = dangerous conditions detected
     * 🟡 = caution advised
     * ✅ = route is safe
     */
    get afSafetyIcon() {
        if (!this.aiAnalysis) return '🔍';
        const text = this.aiAnalysis.toLowerCase();
        if (text.includes('dangerous') || text.includes('ice') || text.includes('snow') || text.includes('storm') || text.includes('hazard') || text.includes('slippery') || text.includes('do not depart')) return '⚠️';
        if (text.includes('caution') || text.includes('careful') || text.includes('moderate') || text.includes('exercise') || text.includes('consider departing')) return '🟡';
        return '✅';
    }

    /** Returns the Agentforce card CSS class based on safety level. */
    get afCardClass() {
        if (!this.aiAnalysis) return 'af-card af-neutral';
        const text = this.aiAnalysis.toLowerCase();
        if (text.includes('dangerous') || text.includes('ice') || text.includes('snow') || text.includes('storm') || text.includes('hazard') || text.includes('slippery') || text.includes('do not depart')) return 'af-card af-danger';
        if (text.includes('caution') || text.includes('careful') || text.includes('moderate') || text.includes('exercise') || text.includes('consider departing')) return 'af-card af-warning';
        return 'af-card af-safe';
    }

    // ── Utility helpers ────────────────────────────────────────

    /** Maps OpenWeather condition names to emoji icons. */
    _condToEmoji(cond) {
        const map = { Clear:'☀️', Clouds:'☁️', Rain:'🌧️', Drizzle:'🌦️', Thunderstorm:'⛈️', Snow:'❄️', Mist:'🌫️', Fog:'🌫️', Haze:'🌫️' };
        return map[cond] || '🌡️';
    }

    /** Maps OpenWeather condition names to CSS card class names. */
    _condToCardClass(cond) {
        const map = { Clear:'card-sunny', Clouds:'card-cloudy', Rain:'card-rainy', Drizzle:'card-rainy', Thunderstorm:'card-stormy', Snow:'card-snowy' };
        return map[cond] || 'card-default';
    }
}