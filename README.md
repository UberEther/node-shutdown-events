[![npm version](https://badge.fury.io/js/node-shutdown-events.svg)](http://badge.fury.io/js/node-shutdown-events)

# Overview

This library provides orderly shutdown for Node.js with ordered shutdown and asynchronous shutdown actions using event listeners.

While there are a number of shutdown libraries, I encountered problems with most of the ones I tried using asynchronous, ordered shutdown actions, so I created this library.

On initialization it does the following:

- Verifies it was not already registered
- Verified none of the relevant handlers are already trapped
- Creates a shutdown handler object and stores it in ```process.nodeShutdownHandler```
- Traps SIGTERM, SIGINT, uncaughtException events from Node
- Traps unhandledRejection events from Bluebird
- Traps error events from the specified domain (optional)
- Provides methods to handle other error events or unexpected errors

Code can then register shutdown events via ```process.on```
- Events can return a Promise if the action is asynchronous.

When a shutdown occurs,
- If the process is a Node cluster worker, the process is disconnected from the cluster
- All event handlers for  ```shutdown``` are called first and the shutdown handler waits until any promises are settled
- All event handlers for  ```shutdown0``` are called and the shutdown handler waits until any promises are settled
- This is repeated for ```shutdown1``` to ```shutdown9```
- Any other event handlers named shutdownXXXX are called (in the reverse of the order they were initially registered) and the shutdown handler waits until any promises are settled
- All handlers for ```shutdownFinal``` are called and the shutdown handler waits until any promises are settled
- Finally it waits until the node queue drains and terminates with the desired error level
- If all of the above takes longer than the timeout specified, the process exits after the timeout.

This sounds more complex to use than it really is.  In general basic non-dependent shutdown actions just register to ```process.on("shutdown")``` and remote connections tend to
register to ```process.on("shutdownFinal")``` - the other options are only used to allow flexibility for ordering shutdown actions (like a log services which depends on a database).

# Examples of use:

## Registration
```
var ShutdownHandler = require("node-shutdown-events");
new ShutdownHandler();
```

## MongoDB
```
var Promise = require("bluebird");
var mongodb = require("mongodb");
Promise.promisifyAll(mongodb);
mongodb.MongoClient.connectAsync() // Add URL and options here...
.tap(function(db) { process.on("shutdownFinal", function () { return db.closeAsync(); }); })
.then(function(db) { /* Do your work here */ });
```

## Mongoose:
```
var Promise = require("bluebird");
var mongoose = require("mongoose");
Promise.promisifyAll(mongoose);
process.on("shutdownFinal", function () { return mongoose.disconnectAsync(); });
```

## ioredis:
```
var ioredis = require("ioredis");
var redis = new ioredis(); // Add options here...
process.on("shutdownFinal", function () { return redis.quit() });
```

# API

## new ShutdownHandler(options)

Creates a new shutdown handler which is automatically registered in process.nodeShutdownHandler.  Will throw an error if another handler is registered OR if any of the events are tapped already.

Options:
- exitTimeout (default is 20000) - Maximum time to wait for shutdown handlers in milliseconds
- unexpectedExceptionExitCode (default is 1) - Exit code to use for the process if an unexpected exception occurs
- domain - If specified, the handler listens for errors on this domain
- log (default is console) - If a console-compatible object is provided, then messages are logged via this object
- process (default is global process object) - Overrides the use of the global process object - mainly used for testing
- cluster (default is ```require("cluster")```) - Overrides the use of the Node cluster module - mainly used for testing

## process.nodeShutdownHandler.handleUnexpectedError(err)

Initiates a shutdown as if an unhandled exception ```err``` was thrown.  Used to hook in other shutdown sources.

## process.nodeShutdownHandler.hookErrorEvent(emitter, eventName = "error")

Adds an error event handler to an event emitter and handles any errors from this event by shutting down.  The
event name defaults to "error" but may be overridden.

## process.nodeShutdownHandler.hookErrorEvent(signal, errorLevel)

Initiates a shutdown.  Signal is the name of the shutdown signal or reason (for logging purposes) and errorLevel is the desired exit error level.  

# Contributing

Any PRs are welcome but please stick to following the general style of the code and stick to [CoffeeScript](http://coffeescript.org/).  I know the opinions on CoffeeScript are...highly varied...I will not go into this debate here - this project is currently written in CoffeeScript and I ask you maintain that for any PRs.