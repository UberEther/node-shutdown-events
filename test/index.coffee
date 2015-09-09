expect = require("chai").expect
rewire = require "rewire"

describe "/lib/index.js", () ->
    it "should load without errors", () ->
        t = rewire "../lib"
        expect(t).to.be.ok
