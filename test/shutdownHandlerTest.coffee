expect = require("chai").expect
EventEmitter = require("events").EventEmitter
Domain = require "domain"
rewire = require "rewire"
Promise = require "bluebird"

describe "Shutdown Handler", () ->
    ShutdownHandler = require "../lib/shutdownHandler"

    noLog =
        log: () ->
        debug: () ->
        info: () ->
        warn: () ->
        error: () ->
        fatal: () ->

    describe "ctor", () ->
        it "Work if all met", () ->
            p = new EventEmitter
            domain = Domain.create()
            t = new ShutdownHandler process: p, domain: domain
            expect(t).to.be.ok
            expect(p.nodeShutdownHandler).to.equal(t)
            expect(EventEmitter.listenerCount p, "SIGTERM").to.equal(1)
            expect(EventEmitter.listenerCount p, "SIGINT").to.equal(1)
            expect(EventEmitter.listenerCount p, "uncaughtException").to.equal(1)
            expect(EventEmitter.listenerCount p, "unhandledRejection").to.equal(1)
            expect(EventEmitter.listenerCount p, "newListener").to.be.gt(0)
            expect(EventEmitter.listenerCount p, "exit").to.equal(1)
            expect(EventEmitter.listenerCount domain, "error").to.equal(1)

        it "Fail if already registered", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p
            expect(t).to.be.ok
            expect( () -> new ShutdownHandler process: p ).to.throw("ShutdownManager already installed")

        it "Fail if SIGTERM registered", () ->
            p = new EventEmitter
            p.on "SIGTERM", () ->
            expect( () -> new ShutdownHandler process: p ).to.throw("process.SIGTERM is already hooked")

        it "Fail if SIGINT registered", () ->
            p = new EventEmitter
            p.on "SIGINT", () ->
            expect( () -> new ShutdownHandler process: p ).to.throw("process.SIGINT is already hooked")

        it "Fail if uncaughtException registered", () ->
            p = new EventEmitter
            p.on "uncaughtException", () ->
            expect( () -> new ShutdownHandler process: p ).to.throw("process.uncaughtException is already hooked")

        it "Fail if unhandledRejection registered", () ->
            p = new EventEmitter
            p.on "unhandledRejection", () ->
            expect( () -> new ShutdownHandler process: p ).to.throw("process.unhandledRejection is already hooked")

        it "Fail if domain.error registered", () ->
            p = new EventEmitter
            domain = Domain.create()
            domain.on "error", () ->
            expect( () -> new ShutdownHandler process: p, domain: domain ).to.throw("domain.error is already hooked")

    describe "Listener Handling", () ->
        it "should prevent hooking of error conditions", () ->
            p = new EventEmitter
            domain = Domain.create()
            t = new ShutdownHandler process: p, domain: domain

            expect( () -> p.on "SIGTERM", ()-> ).to.throw("SIGTERM is already hooked by ShutdownHandler")
            expect( () -> p.on "SIGINT", ()-> ).to.throw("SIGINT is already hooked by ShutdownHandler")
            expect( () -> p.on "uncaughtException", ()-> ).to.throw("uncaughtException is already hooked by ShutdownHandler")
            expect( () -> p.on "unhandledRejection", ()-> ).to.throw("unhandledRejection is already hooked by ShutdownHandler")
            expect( () -> domain.on "error", ()-> ).to.throw("error is already hooked")

        it "should not re-register predefined shutdown events", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p

            p.on "shutdown", () ->
            p.on "shutdown0", () ->
            p.on "shutdown1", () ->
            p.on "shutdown2", () ->
            p.on "shutdown3", () ->
            p.on "shutdown4", () ->
            p.on "shutdown5", () ->
            p.on "shutdown6", () ->
            p.on "shutdown7", () ->
            p.on "shutdown8", () ->
            p.on "shutdown9", () ->
            p.on "shutdownFinal", () ->

            expect(t.basicShutdownEvents).to.deep.equal(["shutdown", "shutdown0", "shutdown1", "shutdown2", "shutdown3", "shutdown4", "shutdown5", "shutdown6", "shutdown7", "shutdown8", "shutdown9"])
            expect(t.additionalShutdownEvents).to.deep.equal([])
            expect(t.finalShutdownEvents).to.deep.equal(["shutdownFinal"])

        it "should register shutdown events", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p

            p.on "shutdownA", () ->
            p.on "shutdownB", () ->
            p.on "shutdownC", () ->
            p.on "shutdownB", () ->
            p.on "shutdownC", () ->
            p.on "shutdownA", () ->

            expect(t.basicShutdownEvents).to.deep.equal(["shutdown", "shutdown0", "shutdown1", "shutdown2", "shutdown3", "shutdown4", "shutdown5", "shutdown6", "shutdown7", "shutdown8", "shutdown9"])
            expect(t.additionalShutdownEvents).to.deep.equal(["shutdownC", "shutdownB", "shutdownA"])
            expect(t.finalShutdownEvents).to.deep.equal(["shutdownFinal"])

        it "should fail if error hooked twice", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog
            e2 = new EventEmitter
            t.hookErrorEvent e2, "xyzzy"
            expect( () -> t.hookErrorEvent e2, "xyzzy" ).to.throw("xyzzy is already hooked")
            expect( () -> e2.on "xyzzy", () -> ).to.throw("xyzzy is already hooked by ShutdownHandler")
            e2.on "xyzzy2", () -> # Ensure other events work

    describe "Triggers", () ->
        it "should call shutdown on handleUnexpectedError call", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("UnexpectedException")
                expect(errorLevel).to.equal(1)
            t.handleUnexpectedError new Error "unitTest"
            expect(shutdownCalled).to.be.true

        it "should call shutdown on domain error event", () ->
            p = new EventEmitter
            domain = Domain.create()
            t = new ShutdownHandler process: p, domain: domain, log: noLog

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("UnexpectedException")
                expect(errorLevel).to.equal(1)
            domain.emit "error", new Error "unitTest"
            expect(shutdownCalled).to.be.true

        it "should call shutdown on hooked error events", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog

            e2 = new EventEmitter
            t.hookErrorEvent e2, "xyzzy"

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("UnexpectedException")
                expect(errorLevel).to.equal(1)
            e2.emit "xyzzy", new Error "unitTest"
            expect(shutdownCalled).to.be.true

        it "should call shutdown on SIGTERM", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("SIGTERM")
                expect(errorLevel).to.equal(128+15)
            p.emit "SIGTERM"
            expect(shutdownCalled).to.be.true

        it "should call shutdown on SIGINT", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("SIGINT")
                expect(errorLevel).to.equal(128+2)
            p.emit "SIGINT"
            expect(shutdownCalled).to.be.true

        it "should call shutdown on uncaughtException", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("UnexpectedException")
                expect(errorLevel).to.equal(1)
            p.emit "uncaughtException", new Error "unitTest"
            expect(shutdownCalled).to.be.true

        it "should call shutdown on unhandledRejection", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("UnexpectedException")
                expect(errorLevel).to.equal(1)
            p.emit "unhandledRejection", new Error "unitTest"
            expect(shutdownCalled).to.be.true

        it "should use overriden error level", () ->
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: noLog, unexpectedExceptionExitCode: 99

            shutdownCalled = false
            t.shutdown = (signal, errorLevel) ->
                shutdownCalled = true
                expect(signal).to.equal("UnexpectedException")
                expect(errorLevel).to.equal(99)
            t.handleUnexpectedError new Error "unitTest"
            expect(shutdownCalled).to.be.true

    describe "Shutdown Logic", () ->
        it "should log shutdown error level", () ->
            args = []
            l = warn: () -> args.push arguments
            p = new EventEmitter
            t = new ShutdownHandler process: p, log: l
            p.emit "exit", 99
            expect(args.length).to.equal(1)
            expect(args[0].length).to.equal(2)
            expect(args[0][0]).to.equal("***** Exiting with errorLevel %d")
            expect(args[0][1]).to.equal(99)


        it "should not shutdown twice", (cb) ->
            p = new EventEmitter
            errorLevel = undefined
            p.exit = (errorLevel) ->
                expect(errorLevel).to.equal(99)
                cb()
            t = new ShutdownHandler process: p, log: noLog, exitTimeout: 25

            p1 = t.shutdown "test", 99
            p2 = t.shutdown "test", 98

            expect(p1).to.equal(p2)

        it "should disconnect worker", (cb) ->
            disconnected = false
            cluster =
                isWorker: true
                worker: disconnect: () -> disconnected = true
            p = new EventEmitter
            p.exit = () ->
                expect(disconnected).to.equal(true)
                cb()
            t = new ShutdownHandler process: p, log: noLog,  exitTimeout: 25, cluster: cluster
            t.shutdown "test", 99
                            
        it "should exit on timeout", (cb) ->
            p = new EventEmitter
            errorLevel = undefined
            p.exit = (errorLevel) ->
                expect(errorLevel).to.equal(99)
                cb()
            t = new ShutdownHandler process: p, log: noLog, exitTimeout: 25
            p.on "shutdown", () -> return Promise.delay 60000
            t.shutdown "test", 99
                            
        it "should not be detered by errors in handlers", (cb) ->
            p = new EventEmitter
            errorLevel = undefined
            p.exit = (errorLevel) ->
                expect(errorLevel).to.equal(99)
                cb()
            t = new ShutdownHandler process: p, log: noLog, exitTimeout: 25
            p.on "shutdown", () -> throw new Error "Unit Test"
            p.on "shutdown", () -> Promise.reject new Error "Unit Test2"
            t.shutdown "test", 99

        it "should process handlers in proper order", (cb) ->
            handlers = ""
            nHandlers = 0
            genHandler = (x) -> () ->
                if nHandlers == 2 then throw new Error "Too Many Handlers"
                handlers += x
                nHandlers++
                Promise.delay(5).then () -> nHandlers--

            p = new EventEmitter
            errorLevel = undefined
            p.exit = (errorLevel) ->
                expect(handlers).to.equal("xx00112233445566778899CCBBAAff")
                cb()
            t = new ShutdownHandler process: p, log: noLog, exitTimeout: 90

            p.on "shutdown", genHandler "x"
            p.on "shutdown", genHandler "x"
            p.on "shutdown0", genHandler "0"
            p.on "shutdown0", genHandler "0"
            p.on "shutdown1", genHandler "1"
            p.on "shutdown1", genHandler "1"
            p.on "shutdown2", genHandler "2"
            p.on "shutdown2", genHandler "2"
            p.on "shutdown3", genHandler "3"
            p.on "shutdown3", genHandler "3"
            p.on "shutdown4", genHandler "4"
            p.on "shutdown4", genHandler "4"
            p.on "shutdown5", genHandler "5"
            p.on "shutdown5", genHandler "5"
            p.on "shutdown6", genHandler "6"
            p.on "shutdown6", genHandler "6"
            p.on "shutdown7", genHandler "7"
            p.on "shutdown7", genHandler "7"
            p.on "shutdown8", genHandler "8"
            p.on "shutdown8", genHandler "8"
            p.on "shutdown9", genHandler "9"
            p.on "shutdown9", genHandler "9"
            p.on "shutdownA", genHandler "A"
            p.on "shutdownB", genHandler "B"
            p.on "shutdownC", genHandler "C"
            p.on "shutdownB", genHandler "B"
            p.on "shutdownC", genHandler "C"
            p.on "shutdownA", genHandler "A"
            p.on "shutdownFinal", genHandler "f"
            p.on "shutdownFinal", genHandler "f"

            t.shutdown "test", 99

