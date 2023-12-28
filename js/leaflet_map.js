// functions and classes for working with a leaflet map

// class for managing map interface
// TODO: build list of standard leaflet tilelayers
class LeafletMap {
  // tag is html element for map, zoom and scale are positions (or null to hide)
  constructor(_tag = 'map', _zoom = 'topright', _scale = 'bottomright', _layers = 'topright') {
    // arguments
    this._map = L.map(_tag, {zoomControl: false}).setView([47.60, -122.33], 12);
    
    this._tiles_lght = L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/{tileType}/{z}/{x}/{y}{r}.png', {
      attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      tileType: 'light_all', //'voyager_labels_under',
      maxZoom: 19
    });

    this._tiles_drk = L.tileLayer('https://{s}.basemaps.cartocdn.com/{tileType}/{z}/{x}/{y}{r}.png', {
      attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      tileType: 'dark_all',
      maxZoom: 19
    });


    this._tiles_hyd = L.tileLayer('https://{s}.tile.openstreetmap.se/hydda/{tileType}/{z}/{x}/{y}.png', {
      attribution: 'Tiles courtesy of <a href="http://openstreetmap.se/" target="_blank">OpenStreetMap Sweden</a>',
      tileType: 'full',
      maxZoom: 20
    });

    // cartodb voyager - types: voyager, voyager_nolabels, voyager_labels_under
    this._tiles_vgr = L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/{tileType}/{z}/{x}/{y}{r}.png', {
      attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      tileType: 'voyager_labels_under',
      maxZoom: 20
    });

    // esri world imagery satellite tiles
    this._tiles_ewi = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
      attribution: 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community'
    });

    // esri world topo map tiles
    this._tiles_ewt = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}', {
        attribution: 'Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ, TomTom, Intermap, iPC, USGS, FAO, NPS, NRCAN, GeoBase, Kadaster NL, Ordnance Survey, Esri Japan, METI, Esri China (Hong Kong), and the GIS User Community'
    });

    this._baseLayers = {
      "Light (CartoDB)": this.tiles_lght,
      "Dark (CartoDB)": this.tiles_drk,
      "Color (Voyager)": this.tiles_vgr,
      "Satellite (ESRI)":  this.tiles_ewi,
      "Terrain (ESRI)": this.tiles_ewt
    };

    this._overlayLayers = {};

    // add tiles and default controls to map
    this._tiles_lght.addTo(this._map);
    if (_zoom) { L.control.zoom({position: _zoom}).addTo(this._map); }
    if (_scale) { L.control.scale({maxWidth: 200, position: _scale}).addTo(this._map); }
    if (_layers) { L.control.layers(this._baseLayers, this._overlayLayers, {position: _layers}).addTo(this._map); }

    // other map elements
    this._time_control = null;

  }

  //********** getters and setters **********//
  get map() { return this._map; }
  get time_control() { return this._time_control; }

  //********** class functions **********//
  // add title control
  add_title(_content, _pos = 'topleft') {
    this._title = L.control({position: _pos});
    this._title.onAdd = () => {
      const _tdiv = L.DomUtil.create('div', 'title');
      _tdiv.innerHTML = _content
      return _tdiv;
    }
    this._title.addTo(this._map);
  }

  // initialize time slider control
  // fmt is date format function, defaults to iso8601
  init_time_slider(_fmt = this.dtm_iso8601, _pos = 'bottomleft') {
    this._time_control = L.timelineSliderControl({
      formatOutput: _fmt,
      //enablePlayback: true,
      //steps: 40
      enableKeyboardControls: true,
      position: _pos
    });
    this._time_control.addTo(this._map);
  }

  // add timeline data to map
  add_timeline(data) {
    if (data) { 
      data.addTo(this._map);
      if (this._time_control) {
        // add timelines, then add to map if not already visible
        //if (this._time_control.timelines.length = 0) { this._time_control.addTo(this._map); }
        this._time_control.addTimelines(data);
        try {
          // update map bounds if possible
          this._map.fitBounds(data.getBounds());
        } catch(e) {}
      }
    }
  }

  // remove timeline data from map
  remove_timeline(data) {
    if (this._time_control) {
      this._time_control.pause();
      this._time_control.removeTimelines(data);
      //if (this._time_control.timelines.length = 0) { this._time_control.remove(this._map); }
    }
    if (data) { data.removeFrom(this._map); }
  }

  // date formats:
  // get ISO8601 formatted datetime YYYY-MM-DD HH:MM:SS
  dtm_iso8601(date) { return new Date(date).toLocaleString('sv-SV'); }
  // get local formatted datetime beginning of month YYYY-MM
  dtm_month(date) {
    try { return new Date(date).toISOString().substr(0,7); }
    catch { return null; }
  }

}
