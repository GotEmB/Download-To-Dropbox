$(document).ready ->
	socket = io.connect()
	socket.on "connect", ->
		throw "new exception"
		socket.emit "request_token_authorized", URL.parse(window.location.toString()).query, ->
			console.log "Connected!"