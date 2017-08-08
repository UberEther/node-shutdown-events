try {
  module.exports = require("./shutdownHandler");
} catch(e) {
  if(e.message.startsWith("Cannot find module './shutdownHandler'")) {
    // Only require coffeescript if it is not already registered
    if (!require.extensions[".coffee"]) require("coffee-script/register");

    module.exports = require("./shutdownHandler.coffee");
  } else {
    throw e;
  }
}
