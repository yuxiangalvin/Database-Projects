/* jshint strict: false */
/* global $: false, google: false */
//
// Portfolio JavaScript
// for EECS 339 Project A at Northwestern University
//
// Originally by Peter Dinda
// Sanitized and improved by Ben Rothman
// Assorted updates for 2018 by Peter Dinda
//
// Global state
//
// html          - the document itself ($. or $(document).)
// map           - the map object
// usermark      - marks the user's position on the map
// markers       - list of markers on the current map (not including the user position)
// curpos        - current user position by geolocation interface
// cliplimit     - geolimit (in degrees) around map center to be queried
//                 <0 => no clipping is done
// amclipped     - Does current map zoom level trigger clipping?
// clipbounds    - current bounds of clipping rectangle for easy access
//                 region is min of map region and cliplimit
// cliprect      - clipping rectangle for the map (if used)
// vsthrottle    - min delay between viewshift requests
//                 to limit update rate and query rate back to server
// vsoutstanding - number of ignored view shift requests
//

//
// When the document has finished loading, the browser
// will invoke the function supplied here.  This
// is an anonymous function that simply requests that the
// brower determine the current position, and when it's
// done, call the "Start" function  (which is at the end
// of this file)
//
//
$(document).ready(function() {
    navigator.geolocation.getCurrentPosition(Start);
  });
  
  // Global variables
  
  var map,
    usermark,
    markers = [],
    curpos,
    cliplimit = 1,
    amclipped = false,
    clipbounds = null,
    cliprect,
    vsthrottle = 100,
    vsoutstanding = 0;
  
  // Clip bounds for a request to avoid overloading the server
  // only makes sense for US, possibly not some possessions
  // Note that this changes the global clipping state
  ClipBounds = function(bounds) {
    if (cliplimit <= 0) {
      amclipped = false;
      return bounds;
    } else {
      var ne = bounds.getNorthEast();
      var sw = bounds.getSouthWest();
      var oldheight = Math.abs(ne.lat() - sw.lat());
      var oldwidth = Math.abs(sw.lng() - ne.lng());
      var height = Math.min(oldheight, cliplimit);
      var width = Math.min(oldwidth, cliplimit);
      var centerlat = (ne.lat() + sw.lat()) / 2.0;
      var centerlng = (ne.lng() + sw.lng()) / 2.0;
      var newne = new google.maps.LatLng(
        centerlat + height / 2.0,
        centerlng + width / 2.0
      );
      var newsw = new google.maps.LatLng(
        centerlat - height / 2.0,
        centerlng - width / 2.0
      );
      amclipped = height < oldheight || width < oldwidth;
      clipbounds = new google.maps.LatLngBounds(newsw, newne);
      return clipbounds;
    }
  };
  
  // UpdateMapById draws markers of a given category (id)
  // onto the map using the data for that id stashed within
  // the document.
  (UpdateMapById = function(id, tag) {
    console.log("UpdateById Called");
    console.log("id input of UpdateById");
    console.log("id:", id);
    console.log("tag input of UpdateById");
    console.log("tag:", tag);
  
    // the document division that contains our data is #committees
    // if id=committees, and so on..
    // We previously placed the data into that division as a string where
    // each line is a separate data item (e.g., a committee) and
    // tabs within a line separate fields (e.g., committee name, committee id, etc)
    //
    // first, we slice the string into an array of strings, one per
    // line / data item
    // var with_id = $("#" + id).html(); // as of 1-20-19 this is always null
    // console.log(with_id ? with_id : null)
    // console.log(with_id);
  
    var rows = $("#" + id)
      .html()
      .split("\n");
    console.log("Rows: ", rows);
    // then, for each line / data item
    for (var i = 0; i < rows.length; i++) {
      // we slice it into tab-delimited chunks (the fields)
      var cols = rows[i].split("\t"),
        // grab specific fields like lat and long
        lat = cols[0],
        long = cols[1];
  
      // then add them to the map.   Here the "new google.maps.Marker"
      // creates the marker and adds it to the map at the lat/long position
      // and "markers.push" adds it to our list of markers so we can
      // delete it later
      markers.push(
        new google.maps.Marker({
          map: map,
          position: new google.maps.LatLng(lat, long),
          title: tag + "\n" + cols.join("\n")
        })
      );
    }
  }),
    //
    // ClearMarkers just removes the existing data markers from
    // the map and from the list of markers.
    //
    (ClearMarkers = function() {
      // clear the markers
      while (markers.length > 0) {
        markers.pop().setMap(null);
      }
    }),
    // draw / erase clipping rect
    (UpdateClipRect = function() {
      if (cliprect != null) {
        cliprect.setMap(null); // erase
        cliprect = null;
      }
      if (amclipped) {
        cliprect = new google.maps.Rectangle({
          strokeColor: "#FFFFFF",
          strokeOpacity: 0.8,
          strokeWeight: 4,
          fillColor: "#000000",
          fillOpacity: 0,
          map: map,
          bounds: clipbounds
        });
      }
    }),
    // UpdateMap takes data sitting in the hidden data division of
    // the document and it draws it appropriately on the map
    //
    (UpdateMap = function() {
      console.log("UpdateMap Called");
      // We're consuming the data, so we'll reset the "color"
      // division to white and to indicate that we are updating
      var color = $("#color");
      color
        .css("background-color", "white")
        .html("<b><blink>Updating Display...</blink></b>");
  
      // Remove any existing data markers from the map
      ClearMarkers();
  
      // Then we'll draw any new markers onto the map, by category
      // Note that there additional categories here that are
      // commented out...  Those might help with the project...
      //
  
      // UpdateMapById("committee_data", "COMMITTEE");
      // UpdateMapById("candidate_data", "CANDIDATE");
      // UpdateMapById("individual_data", "INDIVIDUAL");
      // UpdateMapById("opinion_data", "OPINION");
      categories_selected = getWhatArray();
      cycles_selected = getCyclesArray();
  
      // if (Array.isArray(categories_selected)) {
      //   console.log("categories is an array goddamit");
      // } else {
      //   console.error("categories is not fuqqing array");
      // }
      for (var thing of categories_selected) {
        //console.log("thing is ", thing);
        var stem = thing.toLowerCase();
        var id = stem + "_data";
        var tag = stem.toUpperCase();
        UpdateMapById(id, tag);
      }
      console.log("About to call UpdateClipRect()");
      UpdateClipRect();
      updateSummary();
  
      console.log("Call to UpdateMapbyID ended");
  
      // When we're done with the map update, we mark the color division as
      // Ready.
      color.html("Ready");
  
      // The hand-out code doesn't actually set the color according to the data
      // (that's the student's job), so we'll just assign it a random color for now
      if (Math.random() > 0.5) {
        color.css("background-color", "blue");
      } else {
        color.css("background-color", "red");
      }
    }),
    //
    // NewData is called by the browser after any request
    // for data we have initiated completes
    //
    (NewData = function(data) {
      // All it does is copy the data that came back from the server
      // into the data division of the document.   This is a hidden
      // division we use to cache it locally
      $("#data").html(data);
  
      console.log("NewData Called ====== This is data");
      console.log(data);
  
      UpdateMap();
      console.log(document.getElementById("democ_comm_comm_amount"));
      console.log(document.getElementById("repub_comm_comm_amount"));
      console.log(document.getElementById("democ_comm_cand_amount"));
      console.log(document.getElementById("repub_comm_cand_amount"));
      console.log(document.getElementById("opinion_color_summary"));
      // if (document.getElementById("democ_comm_comm_amount") != null) {
      //   TransColoring()
      // }
  
      // if (document.getElementById("opinion_color_summary") != null) {
      //   OpinionsColoring()
      // }
  
      // if (document.getElementById("ind_transfer_summary") != null) {
      //   IndividualColoring();
      // }
  
      // Now that the new data is in the document, we use it to
      // update the map
    }),
    //
    // The Google Map calls us back at ViewShift when some aspect
    // of the map changes (for example its bounds, zoom, etc)
    //
  
    (ViewShift = function() {
      console.log("ViewShift Called");
      // viewshift is throttled so that trains of calls (for example,
      // from rapid UI or GPS input) collapses into one or two calls
      if (vsoutstanding > 0) {
        // we are in a train, lengthen it
        vsoutstanding++;
        return;
      } else {
        // we are about to start a train
        vsoutstanding = 1;
        // call us back at the end of the throttle interval
        setTimeout(function() {
          if (vsoutstanding > 1) {
            vsoutstanding = 0;
            ViewShift();
          } else {
            vsoutstanding = 0;
          }
        }, vsthrottle);
      }
  
      // We determine the new bounds of the map
      // the bounds are clipped to limit the query size
      // Queries SHOULD also be constrained within the application layer
      // (portfolio.pl) and, most importantly, within the database itself
      var bounds = ClipBounds(map.getBounds()),
        ne = bounds.getNorthEast(),
        sw = bounds.getSouthWest();
  
      var what_arr = getWhatArray();
      var new_arr = [];
      for (var thing of what_arr) {
        var lower_thing = thing.toLowerCase();
        var with_s = lower_thing + "s";
        new_arr.push(with_s);
      }
  
      var what_str = new_arr.join(",");
  
      var cycles_arr = getCyclesArray();
      var cycles_str = cycles_arr.join(",");
      console.log(cycles_str);
      cycles_str = "(" + cycles_str + ")";
  
      // Some debug console log
      console.log("This is what string");
      console.log(what_str);
      console.log("This is cycle string");
      console.log(cycles_str);
  
      // Now we need to update our data based on those bounds
      // first step is to mark the color division as white and to say "Querying"
      $("#color")
        .css("background-color", "white")
        .html(
          "<b><blink>Querying...(" +
            ne.lat() +
            "," +
            ne.lng() +
            ") to (" +
            sw.lat() +
            "," +
            sw.lng() +
            ")</blink></b>"
        );
  
      // Now we make a web request.   Here we are invoking portfolio.pl on the
      // server, passing it the act, latne, etc, parameters for the current
      // map info, requested data, etc.
      // the browser will also automatically send back the cookie so we keep
      // any authentication state
      //
      // This *initiates* the request back to the server.  When it is done,
      // the browser will call us back at the function NewData (given above)
  
      $.get(
        "portfolio.pl",
        {
          act: "near",
          latne: ne.lat(),
          longne: ne.lng(),
          latsw: sw.lat(),
          longsw: sw.lng(),
          format: "raw",
          what: what_str,
          cycle: cycles_str
        },
        NewData
      );
    }),
    // InviteParse = function() {
    //   var email = document.getElementById('invite_email');
    //   var given_permissions_arr = [];
    //   var given_permissions_str = given_permissions_arr;
    //   $.get("portfolio.pl",
    //     {
    //       act: "near",
    //       latne: ne.lat(),
    //       longne: ne.lng(),
    //       latsw: sw.lat(),
    //       longsw: sw.lng(),
    //       format: "raw",
    //       what: what_str,
    //       cycle: cycles_str
    //     }, NewData);
    // }
  
    (TransColoring = function() {
      var democ_comm_amount = document.getElementById("democ_comm_comm_amount")
        .innerHTML;
      if (democ_comm_amount == "(null)") {
        democ_comm_amount = 0;
      }
      var democ_cand_amount = document.getElementById("democ_comm_cand_amount")
        .innerHTML;
      if (democ_cand_amount == "(null)") {
        democ_cand_amount = 0;
      }
      var democ_count = Number(democ_comm_amount) + Number(democ_cand_amount);
  
      var repub_comm_amount = document.getElementById("repub_comm_comm_amount")
        .innerHTML;
      console.log("This is republican committe amnt: ", repub_comm_amount);
      if (repub_comm_amount == "(null)") {
        repub_comm_amount = 0;
      }
      var repub_cand_amount = document.getElementById("repub_comm_cand_amount")
        .innerHTML;
      console.log("This is republican candidate amnt: ", repub_cand_amount);
  
      if (repub_cand_amount == "(null)") {
        repub_cand_amount = 0;
      }
      var repub_count = Number(repub_comm_amount) + Number(repub_cand_amount);
  
      var difference = democ_count - repub_count;
  
      var summary = document.getElementById("summary_comm");
  
      if (difference > 0) {
        summary.style.backgroundColor = "blue";
      }
  
      if (difference < 0) {
        summary.style.backgroundColor = "red";
      }
  
      console.log("Transaction Summary Coloring Finish");
    }),
    (OpinionsColoring = function() {
      var opinion_numbers = document.getElementById("opinion_color_stats_summary")
        .innerHTML;
      var vals = opinion_numbers.split("\t");
      console.log("this is vals", vals);
      var mean_str = vals[0];
      var mean = Number(mean_str);
      var opinion_color = document.getElementById("summary_op");
      if (mean > 0) {
        opinion_color.style.backgroundColor = "blue";
      }
      if (mean < 0) {
        opinion_color.style.backgroundColor = "red";
      }
  
      if (mean == 0) {
        opinion_color.style.backgroundColor = "snow";
      }
    }),
    (IndividualColoring = function() {
      //var summary = document.getElementById("summary");
      var rep_ind_element = document.getElementById(
        "repub_ind_tran_amount_summary"
      );
      var dem_ind_element = document.getElementById(
        "democ_ind_tran_amount_summary"
      );
  
      var dem_ind_amt = Number(dem_ind_element.innerHTML);
      var rep_ind_amt = Number(rep_ind_element.innerHTML);
  
      var diff = dem_ind_amt - rep_ind_amt;
      console.log("This is diff", diff);
      if (diff > 0) {
        $("#summary_ind").css("background-color", "red");
      } else if (diff < 0) {
        $("#summary_ind").css("background-color", "blue");
      } else {
        $("#summary_ind").css("background-color", "snow");
      }
    }),
    //
    // If the browser determines the current location has changed, it
    // will call us back via this function, giving us the new location
    //
    (Reposition = function(pos) {
      // We parse the new location into latitude and longitude
      var lat = pos.coords.latitude,
        long = pos.coords.longitude;
  
      if (lat == curpos.coords.latitude && long == curpos.coords.longitude) {
        // we haven't moved, no need to change the map or get new data
        return;
      } else {
        // we have moved, update position ...
        curpos = pos;
      }
  
      // ... and scroll the map to be centered at that position
      // this should trigger the map to call us back at ViewShift()
      map.setCenter(new google.maps.LatLng(lat, long));
      // ... and set our user's marker on the map to the new position
      usermark.setPosition(new google.maps.LatLng(lat, long));
    });
  
  //
  // The start function is called back once the document has
  // been loaded and the browser has determined the current location
  //
  Start = function(location) {
    // Parse the current location into latitude and longitude
    var lat = location.coords.latitude,
      long = location.coords.longitude,
      acc = location.coords.accuracy,
      // Get a pointer to the "map" division of the document
      // We will put a google map into that division
      mapc = $("#map");
  
    var opinion_url =
      "portfolio.pl?" +
      "act=give-opinion-data&latitude=" +
      String(lat) +
      "&longitude=" +
      String(long);
    if (document.getElementById("give_opinion") != null) {
      document.getElementById("give_opinion").setAttribute("href", opinion_url);
    }
    curpos = location;
  
    // Create a new google map centered at the current location
    // and place it into the map division of the document
    map = new google.maps.Map(mapc[0], {
      zoom: 16,
      center: new google.maps.LatLng(lat, long),
      mapTypeId: google.maps.MapTypeId.HYBRID
    });
  
    // create a marker for the user's location and place it on the map
    usermark = new google.maps.Marker({
      map: map,
      position: new google.maps.LatLng(lat, long),
      title: "You are here"
    });
  
    // clear list of markers we added to map (none yet)
    // these markers are committees, candidates, etc
    markers = [];
  
    // set the color for "color" division of the document to white
    // And change it to read "waiting for first position"
    $("#color")
      .css("background-color", "white")
      .html("<b><blink>Waiting for first position</blink></b>");
  
    //
    // These lines register callbacks.   If the user scrolls the map,
    // zooms the map, etc, then our function "ViewShift" (defined above
    // will be called after the map is redrawn
    //
    google.maps.event.addListener(map, "bounds_changed", ViewShift);
    google.maps.event.addListener(map, "center_changed", ViewShift);
    google.maps.event.addListener(map, "zoom_changed", ViewShift);
  
    //
    // Finally, tell the browser that if the current location changes, it
    // should call back to our "Reposition" function (defined above)
    //
    navigator.geolocation.watchPosition(Reposition);
  };
  
  getWhatArray = function() {
    var what_arr = [];
    var what_checkbox_division = document.getElementById(
      "what_checkbox_division"
    );
    // console.log('The checkbox division')
    // console.log(what_checkbox_division)
    var what_checkboxes = what_checkbox_division.getElementsByTagName("input");
    // console.log('This is the checkboxes got through tag')
    // console.log(what_checkboxes)
  
    for (
      var i = 0, what_checkbox_num = what_checkboxes.length;
      i < what_checkbox_num;
      i++
    ) {
      // console.log('Current checkbox')
      // console.log(what_checkboxes[i])
      // console.log(what_checkboxes[i].checked)
      if (what_checkboxes[i].checked == true) {
        what_arr.push(what_checkboxes[i].value);
        // console.log("what", what_checkboxes[i].value)
      }
    }
    // return what_str
    // console.log(what_arr);
    return what_arr;
  };
  
  getCyclesArray = function() {
    var cycles_arr = [];
    var cycle_checkbox_division = document.getElementById(
      "cycle_checkbox_division"
    );
    var cycle_checkboxes = cycle_checkbox_division.getElementsByTagName("input");
  
    console.log("This is the cycles got through tag");
    console.log(cycle_checkboxes);
  
    for (
      var i = 0, cycle_checkbox_num = cycle_checkboxes.length;
      i < cycle_checkbox_num;
      i++
    ) {
      if (cycle_checkboxes[i].checked == true) {
        cycles_arr.push("'" + cycle_checkboxes[i].value + "'");
      }
    }
    // console.log(cycles_arr);
    return cycles_arr;
  };
  // GetLocActOpinion = function(){
  
  //   GetLocation = function(location){
  //     // Parse the current location into latitude and longitude
  //     var lat = location.coords.latitude,
  //         long = location.coords.longitude
  //     var opinion_url = 'https://murphy.wot.eecs.northwestern.edu/~yhl4722/portfolio/portfolio.pl?' + 'act=give-opinion-data&latitude=' + String(lat) + '&longitude=' + String(long);
  //     document.getElementById('give_opinion').setAttribute("href", opinion_url);
  //     //window.open(window.location.search + 'act=give-opinion-data&latitude=' + String(lat) + '&longitude=' + String(long))
  //   }
  //   navigator.geolocation.getCurrentPosition(GetLocation);
  // }
  
  updateSummary = function() {
    $("#summary_comm").html($("#comm_transfer_summary").html());
    $("#summary_ind").html($("#ind_transfer_summary").html());
    $("#summary_op").html($("#opinion_color_summary").html());
  
    what_arr = getWhatArray();
    if (what_arr.includes("Committee")) {
      $("#summary_comm").css("height", "auto");
      TransColoring();
    }
  
    if (what_arr.includes("Opinion")) {
      $("#summary_op").css("height", "auto");
  
      OpinionsColoring();
    }
  
    if (what_arr.includes("Individual")) {
      $("#summary_ind").css("height", "auto");
      IndividualColoring();
    }
  };
  