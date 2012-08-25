express = require "express"
http = require "http"
socket_io = require "socket.io"
request = require "request"
url = require "url"
dropboxApi = require "./api"
md5 = require "MD5"
{spawn} = require "child_process"

cp = spawn "cake", ["build"]
await cp.on "exit", defer code
return console.log "Build failed! Run 'cake build' to display build errors." if code isnt 0

futureClients = {}
currentDownloads = {}

dbapp = dropboxApi.createApp
	app_key: process.env.DB_KEY
	app_secret: process.env.DB_SECRET
	root: "dropbox"

expressServer = express()
expressServer.configure ->
	expressServer.use express.bodyParser()
	expressServer.use (req, res, next) ->
		req.url = "/page.html" if req.query.oauth_token?
		next()
	expressServer.use express.static "#{__dirname}/lib", maxAge: 31557600000, (err) -> console.log "Static: #{err}"
	expressServer.use expressServer.router

expressServer.get "/", (req, res, next) ->
	dbapp.createClient (token, futureClient) ->
		futureClients[token] = futureClient
		res.redirect url.format
			protocol: "http"
			host: "www.dropbox.com"
			pathname: "/1/oauth/authorize"
			query:
				oauth_token: token
				oauth_callback: "http://#{process.env.MY_HOSTNAME}"

server = http.createServer(expressServer)

io = socket_io.listen server
io.set "log level", 0
io.sockets.on "connection", (socket) ->
	
	socket.on "sync_info", (params, callback) ->
		return callback error: "Invalid Token" unless params.oauth_token of futureClients
		futureClients[params.oauth_token] (client) ->
			delete futureClients[params.oauth_token]
			socket.dbclient = client
			socket.dbclient.getAccountInfo (info) ->
				callback info
	
	socket.on "get_metadata", (path, callback) ->
		socket.dbclient.getMetadata path, (meta) ->
			callback meta
	
	socket.on "downloadtodropbox", ([url, path, replace]..., callback) ->
		lastProgress = Date.now()
		hash = md5 "#{url}%&$#{path}%&$#{Date.now().toString()}" until hash? and hash not of currentDownloads
		currentDownloads[hash] = true
		dld = socket.dbclient.pipeFile url, path, (meta) ->
			socket.emit "complete_#{hash}", meta
			delete currentDownloads[hash]
		dld.on "progress", ({percent, bytes}, volatile) ->
			emit = if volatile then socket.volatile.emit else socket.emit
			emit "progress_#{hash}", percent: percent, bytes: bytes
		dld.on "started", (fileSize) ->
			callback hash: hash, fileSize: fileSize

server.listen (port = process.env.PORT ? 5000), -> console.log "Listening on port #{port}"