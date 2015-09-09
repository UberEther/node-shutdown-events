// Only require coffeescript if it is not already registered
if (!require.extensions[".coffee"]) require("coffee-script/register");

module.exports = require("./shutdownHandler.coffee");
