express = require "express"
http = require "http"
socket_io = require "socket.io"
mongoose = require "mongoose"
request = require "request"
url = require "url"
dbox = require "dbox"
fs = require "fs"
md5 = require "MD5"
{spawn} = require "child_process"
_ = require "underscore"

cp = spawn "cake", ["build"]
await cp.on "exit", defer code
return console.log "Build failed! Run 'cake build' to display build errors." if code isnt 0

pendingRequestTokens = []
currentDownloads = []

dbapp = dbox.app
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
		request_token = _(pendingRequestTokens).select (x) -> x.oauth_token is params.oauth_token
		return callback error: "Invalid Token" if request_token.length is 0
		dbapp.accesstoken request_token[0], (status, access_token) ->
			pendingRequestTokens = _(pendingRequestTokens).select (x) -> x.oauth_token isnt params.oauth_token
			socket.dbclient = dbapp.client access_token
			socket.dbclient.account (status, info) ->
				callback info
	
	socket.on "get_metadata", (path, callback) ->
		socket.dbclient.metadata path, (status, data) ->
			callback data
	
	socket.on "downloadtodropbox", (url, path) ->
		console.log "Start"
		socket.dbclient.put "Cakefile", fs.readFileSync("Cakefile"), (e, r) ->
			console.log e: e, r: r
			console.log "Done"
		# sock.on "drain", -> console.log arguments: arguments
		# sock.on "error", -> console.log error: arguments
		return
		try fs.statSync "dlcache" catch e then fs.mkdirSync "dlcache"
		filehash = md5 url + Date.now() until filehash? and !_(currentDownloads).any (x) -> x is filehash
		currentDownloads.push filehash
		dlf = fs.createWriteStream "dlcache/#{filehash}", flags: "a", encoding: null
		dlr = request.get url
		dlr.on "response", (res) ->
			console.log "Download Size: #{res.headers["content-length"]} bytes."
			dlr.on "data", (chunk) -> dlf.write chunk
			dlr.on "end", ->
				console.log "Download complete."
				dlf.end()

server.listen (port = process.env.PORT ? 5000), -> console.log "Listening on port #{port}"