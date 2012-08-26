express = require "express"
http = require "http"
socket_io = require "socket.io"
request = require "request"
url = require "url"
dropboxApi = require "./api"
md5 = require "MD5"
{spawn} = require "child_process"
_ = require "underscore"

cp = spawn "cake", ["build"]
await cp.on "exit", defer code
return console.log "Build failed! Run 'cake build' to display build errors." if code isnt 0

futureClients = {}
currentDownloads = {}
users = {}

dbapp = dropboxApi.createApp
	app_key: process.env.DB_KEY
	app_secret: process.env.DB_SECRET
	root: "dropbox"

expressServer = express()
expressServer.configure ->
	expressServer.use express.bodyParser()
	expressServer.use express.cookieParser md5 "#{process.env.DB_SECRET}...secretStuff"
	expressServer.use (req, res, next) ->
		if req.query.oauth_token? and params.oauth_token of futureClients
			futureClients[params.oauth_token] (client) ->
				delete futureClients[params.oauth_token]
				user = md5 "#{Date.now()}...userHash" until user? and user not of users
				res.cookie "user", user, signed: true, maxAge: 30 * 24 * 60 * 60 * 1000
				users[user] = client
				socket.dbclient = client
				socket.dbclient.getAccountInfo (info) ->
					req.url = "/page.html"
					return next()
		else if req.cookies.user? and req.cookies.user of user
			req.url = "/page.html"
			res.cookie "user", req.cookies.user, signed: true, maxAge: 30 * 24 * 60 * 60 * 1000
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
		if params.user?
			socket.dbclient = users[params.user]
			socket.dbclient.getAccountInfo (info) ->
				callback info
		else
			return callback error: "Impossible Error!"
	
	socket.on "get_metadata", (path, callback) ->
		socket.dbclient.getMetadata path, (meta) ->
			callback meta
	
	socket.on "dtd_getFileName", (url, callback) ->
		request.head url, (err, res) ->
			url = _(res.request.redirects).last() ? url
			callback _(url).split("/").last()
	
	socket.on "downloadtodropbox", ([url, path, replace]..., callback) ->
		lastProgress = Date.now()
		hash = md5 "#{url}%&$#{path}%&$#{Date.now().toString()}" until hash? and hash not of currentDownloads
		currentDownloads[hash] = dld = socket.dbclient.pipeFile url, path, (meta) ->
			socket.emit "complete_#{hash}", meta
			delete currentDownloads[hash]
		dld.on "progress", ({percent, bytes}) ->
			socket.volatile.emit "progress_#{hash}", percent: percent, bytes: bytes
		dld.on "waiting", ({percent, bytes}) ->
			socket.emit "waiting_#{hash}", percent: percent, bytes: bytes
		dld.once "started", (fileSize) ->
			callback hash: hash, fileSize: fileSize

server.listen (port = process.env.PORT ? 5000), -> console.log "Listening on port #{port}"