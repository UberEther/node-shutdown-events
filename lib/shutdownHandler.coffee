cluster = require "cluster"
Promise = require "bluebird"
EventEmitter = require("events").EventEmitter

class ShutdownHandler
    basicShutdownEvents: ["shutdown", "shutdown0", "shutdown1", "shutdown2", "shutdown3", "shutdown4", "shutdown5", "shutdown6", "shutdown7", "shutdown8", "shutdown9"]
    additionalShutdownEvents: []
    finalShutdownEvents: ["shutdownFinal"]

    constructor: (config) ->
        self = this
        @process = config.process || process # Testing override
        @cluster = config?.cluster || cluster # Testing override

        # Sanity checks - we should be the only handler for all of these...
        if @process.nodeShutdownHandler then throw new Error "ShutdownManager already installed"
        if EventEmitter.listenerCount @process, "SIGTERM" then throw new Error "process.SIGTERM is already hooked"
        if EventEmitter.listenerCount @process, "SIGINT" then throw new Error "process.SIGINT is already hooked"
        if EventEmitter.listenerCount @process, "uncaughtException" then throw new Error "process.uncaughtException is already hooked"
        if EventEmitter.listenerCount @process, "unhandledRejection" then throw new Error "process.unhandledRejection is already hooked"
        if config.domain && EventEmitter.listenerCount config.domain, "error" then throw new Error "domain.error is already hooked"

        @unexpectedExceptionExitCode = if config?.unexpectedExceptionExitCode? then config.unexpectedExceptionExitCode else 1
        @exitTimeout = config?.exitTimeout || 20000
        @log = config?.log || console
        @domain = config?.domain # Note: We do not automatically hook in process.domain!

        # Pre-bind common methods
        @handleUnexpectedError = @handleUnexpectedError.bind @
        @_onProcessNewListener = @_onProcessNewListener.bind @
        @_onExitListener = @_onExitListener.bind @

        # Hook events
        @process.on "SIGTERM", () -> self.shutdown "SIGTERM", 128+15
        @process.on "SIGINT", () -> self.shutdown "SIGINT", 128+2
        @process.on "uncaughtException", @handleUnexpectedError
        @process.on "unhandledRejection", @handleUnexpectedError
        @process.on "newListener", @_onProcessNewListener
        @process.on "exit", @_onExitListener

        if @domain then @hookErrorEvent @domain

        @process.nodeShutdownHandler = @

    _onExitListener: (errorLevel) ->
        @log.warn "***** Exiting with errorLevel %d", errorLevel

    _onProcessNewListener: (e, l) ->
        switch e
            when "SIGTERM", "SIGINT", "uncaughtException", "unhandledRejection"
                throw new Error "#{e} is already hooked by ShutdownHandler"

            when "shutdown", "shutdown0", "shutdown1", "shutdown2", "shutdown3", "shutdown4", "shutdown5", "shutdown6", "shutdown7", "shutdown8", "shutdown9", "shutdownFinal"
                break

            else
                if e.match(/^shutdown.*/) && @additionalShutdownEvents.indexOf(e) < 0
                    @additionalShutdownEvents.unshift e


    handleUnexpectedError: (err) ->
        @log.error "Unexpected exception:", err.stack||err.message||err
        @shutdown "UnexpectedException", @unexpectedExceptionExitCode

    hookErrorEvent: (emitter, eventName = "error") ->
        if EventEmitter.listenerCount emitter, eventName then throw new Error "#{eventName} is already hooked"
        emitter.on eventName, @handleUnexpectedError
        emitter.on "newListener", (e, l) -> if e == eventName then throw new Error "#{e} is already hooked by ShutdownHandler"

    shutdown: (signal, errorLevel) ->
        return @shutdownPromise if @shutdownPromise
        @shutdownPromise = Promise.bind @

        shutdownStart = Date.now()
        @log.warn "***** Requesting Shutdown cleanly on %s - waiting up to %d ms", signal, @exitTimeout

        # Disconnect while we shutdwn if we are a clustered worker
        @cluster.worker.disconnect() if @cluster.isWorker

        log = @log # To avoid having to bind every callback
        process = @process # To avoid having to bind every callback

        onExit = (level) ->
            clearTimeout forceExitTimeout
            process.removeListener "exit", onExit
            log.warn "***** Shutdown complete in %d ms", Date.now()-shutdownStart
            process.exit errorLevel

        forceExit = () ->
            log.warn "***** Shutdown timed out - forcing immedate exit"
            onExit()

        process.once "exit", onExit

        forceExitTimeout = setTimeout forceExit, @exitTimeout
        forceExitTimeout.unref()

        @shutdownPromise.return @basicShutdownEvents.concat @additionalShutdownEvents, @finalShutdownEvents
        .each (name) ->
            listeners = process.listeners name
            return if !listeners.length
            log.info "***** Executing %s listeners", name
            Promise.resolve listeners
            .then (vals) -> vals.map (x) -> Promise.try () -> x() # Use try to capture any internal errors
            .settle() # Wait for all promises to complete
            .then (results) ->
                for r in results when r.isRejected()
                    r = r.reason()
                    log.warn "***** Ignoring error in shutdown handler:", r.stack||r.message||r
        .then () -> log.info "***** All shutdown handlers completed - waiting for event queue to empty"
        .catch (err) ->
            log.warn "***** Forcing immediate exit after error occurred in shutdown handling:", err.stack||err.message||err
            onExit()
        # Cannot use Promise.timeout here because the timeout is not unref'ed


        return @shutdownPromise


module.exports = ShutdownHandler
