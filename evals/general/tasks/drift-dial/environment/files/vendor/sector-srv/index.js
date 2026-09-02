"use strict";
// sector-srv exposes the dashboard runtime; it needs the shared motif lib.
const motif = require("motif");
module.exports = {
  sector: "relay-west",
  stamp: function () {
    return { stream: motif.name, build: motif.ver };
  }
};
