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

expressServer = express.createServer()
expressServer.configure ->
	expressServer.use express.bodyParser()
	expressServer.use (req, res, next) ->
		req.url = "/page.html" if req.query.oauth_token?
		next()
	expressServer.use express.static "#{__dirname}/lib", maxAge: 31557600000, (err) -> console.log "Static: #{err}"
	expressServer.use expressServer.router

expressServer.get "/", (req, res, next) ->
	dbapp.requesttoken (status, request_token) ->
		res.redirect "https://www.dropbox.com/1/oauth/authorize?oauth_token=#{token.oauth_token}"
		res.redirect url.format
			protocol: "http"
			host: process.env.MY_HOSTNAME
			query:
				oauth_token: request_token.oauth_token
				oauth_callback: "http://#{process.env.MY_HOSTNAME}"

io = socket_io.listen server
io.set "log level", 0
io.sockets.on "connection", (socket) ->
	
	socket.on "request_token_authorized", (params, callback) ->
		dbapp.accesstoken params.oauth_token, (status, access_token) ->
			socket.dbclient = dbapp.client access_token
			callback()

http.createServer(expressServer).listen (port = process.env.PORT ? 5000), -> console.log "Listening on port #{port}"