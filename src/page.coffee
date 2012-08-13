$(document).ready ->
	socket = io.connect()
	socket.on "connect", ->
		socket.emit "request_token_authorized", QueryString.parse URL.parse(window.location.toString()).query, ->
			console.log "Connected!"