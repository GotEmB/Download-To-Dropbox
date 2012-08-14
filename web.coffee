express = require "express"
http = require "http"
socket_io = require "socket.io"
mongoose = require "mongoose"
request = require "request"
url = require "url"
dbox = require "dbox"
{spawn} = require "child_process"
_ = require "underscore"

cp = spawn "cake", ["build"]
await cp.on "exit", defer code
return console.log "Build failed! Run 'cake build' to display build errors." if code isnt 0

dbapp = dbox.app
	app_key: process.env.DB_KEY
	app_secret: process.env.DB_SECRET

pendingRequestTokens = []

expressServer = express()
expressServer.configure ->
	expressServer.use express.bodyParser()
	expressServer.use (req, res, next) ->
		req.url = "/page.html" if req.query.oauth_token?
		next()
	expressServer.use express.static "#{__dirname}/lib", maxAge: 31557600000, (err) -> console.log "Static: #{err}"
	expressServer.use expressServer.router

expressServer.get "/", (req, res, next) ->
	dbapp.requesttoken (status, request_token) ->
		pendingRequestTokens.push request_token
		res.redirect url.format
			protocol: "http"
			host: "www.dropbox.com"
			pathname: "/1/oauth/authorize"
			query:
				oauth_token: request_token.oauth_token
				oauth_callback: "http://#{process.env.MY_HOSTNAME}"

server = http.createServer(expressServer)

io = socket_io.listen server
io.set "log level", 0
io.sockets.on "connection", (socket) ->
	
	socket.on "sync_info", (params, callback) ->
		console.log request_token: _(pendingRequestTokens).select((x) -> x.oauth_token is params.oauth_token)[0]
		dbapp.accesstoken _(pendingRequestTokens).select((x) -> x.oauth_token is params.oauth_token)[0], (status, access_token) ->
			console.log status: status, access_token: access_token
			socket.dbclient = dbapp.client access_token
			socket.dbclient.account (status, info) ->
				console.log status: status, info: info
				callback info

server.listen (port = process.env.PORT ? 5000), -> console.log "Listening on port #{port}"
