// functions and classes for working with institution data

// class for managing forms and data interface
class InstitutionInterface {
  // url is path to get data, fn is function to call on load click, sfx is file suffix
  constructor(url, fn, sfx) {
    // arguments
    // use url and search params: https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams
    this._url = new URL(url,`${document.location.protocol}//${document.location.host}`);
    this._file_suffix = `${sfx}.csv`;
    this._filename = this._file_suffix; // default to suffix

    // reference to page elements
    this._title = null;
    this._instruct = document.getElementById('instructions');
    this._modal = document.getElementsByClassName('modal')[0];

    // iniitialize datepicker format to ISO format and set datepicker options for month view
    $.fn.datepicker.dates['en'].format = "yyyy-mm-dd";
    this._dp_opts = { startView: 'years', minViewMode: 'months', maxViewMode: 'years' };

    // form elements
    this._business = d3.select('#business');
    this._start_date = d3.select('#s_date');
    this._end_date = d3.select('#e_date');
    this._load = d3.select('#load');
    this._download = d3.select('#download');

    // populate form elements - institutions and date ranges
    Promise.all([
      d3.json('/institution/institutions'),
      d3.json(`/institution/months?rpt_type=${sfx}`)
    ]).then(([i_data, i_months]) => {
      this._business.selectAll('option')
        .data(i_data)
        .enter()
        .append('option')
        .text(d => `${d.id} - ${d.name}`)
        .attr('value', d => d.id);

      // set datepicker start and end date
      this._dp_opts['startDate'] = i_months[0]._start_month;
      this._dp_opts['endDate'] = i_months[0]._end_month;

      /* get options for months - use spread operator: https://stackoverflow.com/a/65329096
      this._start_date.selectAll('option')
        .data(i_months)
        .enter()
        .append('option')
        .text(d => d.month)
        .attr('value', d => d.month)
        .property('selected', d => { return (d.month === i_months[0].month) });
      this._end_date.selectAll('option')
        .data(i_months)
        .enter()
        .append('option')
        .text(d => d.month)
        .attr('value', d => d.month)
        .property('selected', d => { return (d.month === i_months[i_months.length - 1].month) }); */

      // set business to use select2 (use jQuery selector)
      $('#business').select2({dropdownAutoWidth: true});
      $('#s_date').datepicker(this._dp_opts);
      $('#e_date').datepicker(this._dp_opts);

      // register event for loading data
      // move to function if needed to be overridden: https://stackoverflow.com/a/69950441
      this._load.on('click', () => {
        // build parameters for query
        this._url.searchParams.append('institution_id',this._business.property('value'));
        this._url.searchParams.append('start_date',this._start_date.property('value'));
        this._url.searchParams.append('end_date',this._end_date.property('value'));

        // update file name
        this.set_filename();

        // call passed function from constructor
        fn();

        return false;   // prevent form submit
      });
    });
  }

  //********** getters and setters **********//
  get url() { return this._url.toString(); }
  get start_date() { return this.get_val(this._start_date); }
  get end_date() { return this.get_val(this._end_date); }

  // set file name based on form data selection
  set_filename() {
    const b = this._business.node().selectedOptions[0].text.replace(/([^a-z0-9]+)/gi, '_');
    this._filename = `${b}_${this.get_val(this._start_date)}_${this.get_val(this._end_date)}_${this._file_suffix}`;
  }

  // update title based on selected business from dropdown
  set_title() {
    if (!this._title) { 
      this._title = document.getElementsByTagName('h2')[0].appendChild(document.createElement('span')); 
    }
    const b = this._business.node().selectedOptions[0];
    this._title.textContent = b.text.replace(b.value,'');
  }

  //********** class functions **********//
  // generic function to get value from d3 object
  get_val(d3obj) { return d3obj.property('value'); }

  // attach file to download
  enable_download(data) {
    this._download
      .property('disabled', false)  // make sure not disabled
      .on('click', () => {
        this.save_data_file(this._filename, data);
        return false;   // prevent form submit
      });
  }

  // hide instructions
  hide_instructions() { this._instruct.classList.add('hidden'); }

  // toggle modal visibility
  toggle_modal() { this._modal.classList.toggle('invisible'); }

  // file download function
  save_data_file(filename, object_data, mimetype = 'text/csv') {
    // prepare data based on type
    let str_data;
    if (mimetype == 'text/json') {
      str_data = JSON.stringify(object_data);
    } else if (mimetype == 'text/csv') {
      // get keys based on first row
      const keys = Object.keys(object_data[0]);

      // build header and add data
      str_data = keys.join(',') + '\n';
      object_data.forEach(e => { str_data += keys.map(k => e[k]).join(',') + '\n'; });
    } else {
      mimetype = 'text/plain'
      str_data = object_data.toString();
    }

    const blob = new Blob([str_data], { type: mimetype });
    const link = document.createElement('a');

    link.download = filename;
    link.href = window.URL.createObjectURL(blob);
    link.dataset.downloadurl = [blob.type, link.download, link.href].join(':');

    const evt = new MouseEvent('click', {
      view: window,
      bubbles: true,
      cancelable: true,
    });

    link.dispatchEvent(evt);
    link.remove()
  }

}
