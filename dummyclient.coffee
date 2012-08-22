http = require "http"

req = http.request host: "localhost", port: 4998, method: "POST", path: "/1/chunked_upload"

req.on "error", console.log

req.once "drain", -> process.nextTick ->
	req.once "drain", -> process.nextTick ->
		req.once "drain", -> process.nextTick ->
			console.log "Done 3"
		console.log "Done 2"
		req.end "3"
	console.log "Done 1"
	req.write "2"
req.write "1"

exports.req = req