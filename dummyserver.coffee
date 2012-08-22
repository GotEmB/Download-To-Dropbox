http = require "http"

reqs = []

server = http.createServer (req, res) ->
	data = ""
	req.on "data", (d) -> data += d
	req.on "end", (d) ->
		data += d if d?
		req.body = data
		reqs.push req
		console.log req: reqs.length - 1
		res.writeHead 200, 'Content-Type': 'text/plain'
		res.end "Done"

server.listen 4998

exports.reqs = reqs