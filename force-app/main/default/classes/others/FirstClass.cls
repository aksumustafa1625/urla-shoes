public with sharing class FirstClass {
//     <apex:page showHeader="false" sidebar="false" standardStylesheets="false" applyBodyTag="false" applyHtmlTag="false" docType="html-5.0">
// <html>
// <head>
//     <meta charset="UTF-8"/>
//     <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
//     <style>
//         * { margin: 0; padding: 0; box-sizing: border-box; }
//         html, body, #map { width: 100%; height: 100%; }
//         body { background: #1a2035; }

//         #status {
//             position: absolute;
//             top: 50%;
//             left: 50%;
//             transform: translate(-50%, -50%);
//             color: rgba(255,255,255,0.5);
//             font-family: Arial, sans-serif;
//             font-size: 14px;
//             text-align: center;
//             z-index: 10;
//         }
//         .spinner {
//             width: 32px; height: 32px;
//             border: 3px solid rgba(255,255,255,0.15);
//             border-top-color: #00A4E4;
//             border-radius: 50%;
//             animation: spin 0.8s linear infinite;
//             margin: 0 auto 12px;
//         }
//         @keyframes spin { to { transform: rotate(360deg); } }
//     </style>
// </head>
// <body>
//     <div id="status">
//         <div class="spinner"></div>
//         <div>Initializing map...</div>
//     </div>
//     <div id="map"></div>

//     <script>
//         var MAPS_KEY = 'YOUR_GOOGLE_MAPS_API_KEY'; // load from a Custom Setting — never hardcode

//         var map, directionsRenderer, directionsService;
//         var ORIGIN = { lat: 51.4556, lng: 7.0116 }; // Essen

//         // Load Google Maps
//         var script = document.createElement('script');
//         script.src = 'https://maps.googleapis.com/maps/api/js?key=' + MAPS_KEY + '&libraries=geometry&callback=initMap';
//         script.async = true;
//         script.onerror = function() {
//             document.getElementById('status').innerHTML = '<div style="color:#ff6b6b">Maps API could not load.<br/>Check API key.</div>';
//         };
//         document.head.appendChild(script);

//         // Called by Google Maps when ready
//         window.initMap = function() {
//             document.getElementById('status').style.display = 'none';

//             map = new google.maps.Map(document.getElementById('map'), {
//                 zoom: 7,
//                 center: ORIGIN,
//                 mapTypeId: 'roadmap',
//                 styles: [
//                     { elementType: 'geometry',          stylers: [{ color: '#1a2035' }] },
//                     { elementType: 'labels.text.fill',  stylers: [{ color: '#8ec3b9' }] },
//                     { elementType: 'labels.text.stroke',stylers: [{ color: '#1a3646' }] },
//                     { featureType: 'road',              elementType: 'geometry',         stylers: [{ color: '#304a7d' }] },
//                     { featureType: 'road',              elementType: 'geometry.stroke',  stylers: [{ color: '#255763' }] },
//                     { featureType: 'road.highway',      elementType: 'geometry',         stylers: [{ color: '#2c6675' }] },
//                     { featureType: 'water',             elementType: 'geometry',         stylers: [{ color: '#0e1626' }] },
//                     { featureType: 'water',             elementType: 'labels.text.fill', stylers: [{ color: '#4e6d70' }] },
//                     { featureType: 'administrative',    elementType: 'geometry.stroke',  stylers: [{ color: '#4b6878' }] },
//                     { featureType: 'poi',     stylers: [{ visibility: 'off' }] },
//                     { featureType: 'transit', stylers: [{ visibility: 'off' }] }
//                 ],
//                 zoomControl: true,
//                 streetViewControl: false,
//                 mapTypeControl: false,
//                 fullscreenControl: false
//             });

//             directionsRenderer = new google.maps.DirectionsRenderer({
//                 polylineOptions: {
//                     strokeColor: '#00A4E4',
//                     strokeWeight: 5,
//                     strokeOpacity: 0.85
//                 }
//             });
//             directionsRenderer.setMap(map);
//             directionsService = new google.maps.DirectionsService();

//             // Tell the LWC that Maps is ready
//             window.parent.postMessage({ type: 'MAPS_READY' }, '*');
//         };

//         // Listen for route requests from the LWC
//         window.addEventListener('message', function(event) {
//             if (!event.data || !event.data.type) return;

//             if (event.data.type === 'DRAW_ROUTE') {
//                 var destination = event.data.destination;
//                 drawRoute(destination);
//             }
//         });

//         function drawRoute(destination) {
//             directionsService.route(
//                 {
//                     origin:      new google.maps.LatLng(ORIGIN.lat, ORIGIN.lng),
//                     destination: destination,
//                     travelMode:  google.maps.TravelMode.DRIVING
//                 },
//                 function(result, status) {
//                     if (status === 'OK') {
//                         directionsRenderer.setDirections(result);
//                         var leg = result.routes[0].legs[0];

//                         // Send route info back to LWC
//                         window.parent.postMessage({
//                             type:     'ROUTE_DONE',
//                             distance: leg.distance.text,
//                             duration: leg.duration.text,
//                             destLat:  leg.end_location.lat(),
//                             destLng:  leg.end_location.lng(),
//                             destName: leg.end_address.split(',')[0]
//                         }, '*');
//                     } else {
//                         window.parent.postMessage({
//                             type:  'ROUTE_ERROR',
//                             status: status
//                         }, '*');
//                     }
//                 }
//             );
//         }
//     </script>
// </body>
// </html>
// </apex:page>
}