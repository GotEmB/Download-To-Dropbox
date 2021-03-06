request = require "request"
qs = require "querystring"
http = require "http"
events = require "events"
dns = require "dns"

maxChunkSize = 100 * 1024 * 1024 # 100 MB

headerify = (obj) ->
	str = "#{obj.title}"
	first = true
	for key, value of obj
		continue if key is "title"
		str += if first then " " else ", "
		str += "#{key}=\"#{value}\""
		first = false
	str

class App
	constructor: (opts) ->
		throw new Error "app_key and app_secret are mandatory." if !opts? or !opts.app_key? or !opts.app_secret?
		@app_key = opts.app_key
		@app_secret = opts.app_secret
		@root = opts.root ? "sandbox"
	createClient: (callback) =>
		req =
			url: "https://api.dropbox.com/1/oauth/request_token"
			method: "POST"
			headers: Authorization: headerify
				title: "OAuth"
				oauth_version: "1.0"
				oauth_signature_method: "PLAINTEXT"
				oauth_consumer_key: @app_key
				oauth_signature: "#{@app_secret}&"
		request req, (err, res, body) =>
			request_token = qs.parse body
			callback request_token.oauth_token, ([uid]..., callback) =>
				dns.resolve "api.dropbox.com", (err, addr) =>
					req =
						url: "https://#{addr[0]}/1/oauth/access_token"
						method: "POST"
						headers: Authorization: headerify
							title: "OAuth"
							oauth_version: "1.0"
							oauth_signature_method: "PLAINTEXT"
							oauth_consumer_key: @app_key
							oauth_token: request_token.oauth_token
							oauth_signature: "#{@app_secret}&#{request_token.oauth_token_secret}"
					request req, (err, res, body) =>
						callback new Client app: @, uid: uid, access_token: qs.parse body

class Client
	oauthHeader = null
	constructor: (opts) ->
		@app = opts.app
		@access_token = opts.access_token
		@uid = opts.uid ? null
		oauthHeader = headerify
			title: "OAuth"
			oauth_version: "1.0"
			oauth_signature_method: "PLAINTEXT"
			oauth_consumer_key: @app.app_key
			oauth_token: @access_token.oauth_token
			oauth_signature: "#{@app.app_secret}&#{@access_token.oauth_token_secret}"
	getAccountInfo: (callback) ->
		dns.resolve "api.dropbox.com", (err, addr) ->
			req =
				url: "https://#{addr[0]}/1/account/info"
				method: "GET"
				headers: Authorization: oauthHeader
			request req, (err, res, body) -> callback JSON.parse body
	getMetadata: (path, callback) =>
		dns.resolve "api.dropbox.com", (err, addr) =>
			req =
				url: "https://#{addr[0]}/1/metadata/#{@app.root}/#{path}"
				method: "GET"
				headers: Authorization: oauthHeader
			request req, (err, res, body) -> callback JSON.parse body
	simpleUpload: (src, path, replace, ret, getAddr, callback) =>
		emitProgress = (volatile = true) ->
			ret.progress = rp =
				state: if volatile then "progress" else "waiting"
				percent: Math.round(uploaded / fileSize * 10000) / 100
				bytes: Math.round(uploaded * 100) / 100
			ret.emit rp.state, percent: rp.percent, bytes: rp.bytes
		fileSize = ret.fileSize
		ret.emit "started", fileSize
		uploaded = 0
		req =
			url: "https://#{getAddr()}/1/files_put/#{@app.root}/#{path}"
			method: "PUT"
			headers: Authorization: oauthHeader
		dest = request req, (err, res, body) =>
			try
				meta = JSON.parse body
			catch ex	
				console.log statusCode: res.statusCode if res?
				src.removeAllListeners()
				return @pipeFile src.url, path, replace, callback
			ret.emit "complete", meta
			callback? meta
		src.on "data", (data) ->
			uploaded += data.length
			emitProgress()
		src.on "end", (data) ->
			uploaded += data.length if data?
			emitProgress false
		src.pipe dest
	rangesChunk: (url, path, replace, ret, getAddr, callback) =>
		emitProgress = (volatile = true) ->
			ret.progress = rp =
				state: if volatile then "progress" else "waiting"
				percent: Math.round(uploaded / fileSize * 10000) / 100
				bytes: Math.round(uploaded * 100) / 100
			ret.emit rp.state, percent: rp.percent, bytes: rp.bytes
		fileSize = ret.fileSize
		ret.emit "started", fileSize
		uploaded = 0
		prevRes = null
		uploadNextRange = =>
			thisChunk = Math.min(fileSize - uploaded, maxChunkSize)
			src = request.get
				url: url
				headers: 'Range': "bytes=#{uploaded}-#{uploaded + Math.min(fileSize - uploaded, maxChunkSize) - 1}"
			req =
				url: "https://#{getAddr()}/1/chunked_upload?" +
					if prevRes? then qs.stringify
						upload_id: prevRes.upload_id
						offset: prevRes.offset
					else ""
				method: "PUT"
				headers:
					Authorization: oauthHeader
					'Content-Length': Math.min fileSize - uploaded, maxChunkSize
				endOnTick: false
			dest = request req, (err, res, body) =>
				src.removeAllListeners()
				try
					prevRes = JSON.parse body
				catch ex
					console.log statusCode: res.statusCode
					uploaded -= thisChunk
					return uploadNextRange()
				unless prevRes.offset? and prevRes.offset is uploaded
					console.log statusCode: res.statusCode
					uploaded -= thisChunk
					return uploadNextRange()
				if uploaded < fileSize
					uploadNextRange()
				else
					req =
						url: "https://#{getAddr()}/1/commit_chunked_upload/#{@app.root}/#{path}"
						method: "POST"
						headers: Authorization: oauthHeader
						form: upload_id: prevRes.upload_id
					request req, (err, res, body) =>
						try
							body = JSON.parse body
						catch ex
							console.log statusCode: res.statusCode
							return @pipeFile url, path, replace, callback
						ret.emit "complete", body
						callback? body
						ret.removeAllListeners()
			src.on "data", (data) ->
				uploaded += data.length
				emitProgress()
			src.on "end", (data) ->
				uploaded += data.length if data?
				emitProgress false
			src.pipe dest
		uploadNextRange()
	manualChunk: (src, path, replace, ret, getAddr, callback) =>
		emitProgress = (volatile = true) ->
			ret.progress = rp =
				state: if volatile then "progress" else "waiting"
				percent: Math.round(uploaded.total / fileSize * 10000) / 100
				bytes: Math.round(uploaded.total * 100) / 100
			ret.emit rp.state, percent: rp.percent, bytes: rp.bytes
		fileSize = ret.fileSize
		ret.emit "started", fileSize
		uploaded = 
			total: 0
			chunk: 0
		prevRes = null
		dest = null
		newDest = =>
			req =
				url: "https://#{getAddr()}/1/chunked_upload?" +
					if prevRes? then qs.stringify
						upload_id: prevRes.upload_id
						offset: prevRes.offset
					else ""
				method: "PUT"
				headers:
					Authorization: oauthHeader
					'Content-Length': Math.min fileSize - uploaded.total, maxChunkSize
				endOnTick: false
			dest = request req, (err, res, body) =>
				try
					prevRes = JSON.parse body
				catch ex
					console.log statusCode: res.statusCode
					src.removeAllListeners()
					src.destroy()
					dest.removeAllListeners()
					return @pipeFile url, path, replace, callback
				unless prevRes.offset? and prevRes.offset is uploaded.total
					console.log statusCode: res.statusCode
					src.removeAllListeners()
					src.destroy()
					dest.removeAllListeners()
					return @pipeFile url, path, replace, ret, callback
				if uploaded.total < fileSize
					oldDest = dest
					newDest()
					uploaded.chunk = 0
					oldDest.emit "resurrected"
					oldDest.removeAllListeners()
				else
					emitProgress false
					req =
						url: "https://#{getAddr()}/1/commit_chunked_upload/#{@app.root}/#{path}"
						method: "POST"
						headers: Authorization: oauthHeader
						form: upload_id: prevRes.upload_id
					request req, (err, res, body) =>
						try
							body = JSON.parse body
						catch ex
							console.log statusCode: res.statusCode
							src.removeAllListeners()
							dest.removeAllListeners()
							return @pipeFile url, path, replace, callback
						ret.emit "complete", body
						callback? body
						ret.removeAllListeners()
					dest.removeAllListeners()
		newDest()
		src.on "data", (data) ->
			if uploaded.chunk + data.length <= maxChunkSize
				uploaded[i] += data.length for i of uploaded
				emitProgress()
				unless dest.write data
					src.pause()
					dest.once "drain", -> src.resume()
			else
				src.pause()
				splitAt = maxChunkSize - uploaded.chunk
				uploaded[i] += splitAt for i of uploaded
				emitProgress false
				dest.end data[0 ... splitAt]
				dest.once "resurrected", ->
					uploaded[i] += data.length - splitAt for i of uploaded
					emitProgress()
					unless dest.write data[splitAt ...]
						dest.once "drain", -> src.resume()
					else
						src.resume()
		src.on "end", (data) ->
			unless data?
				dest.end()
			else if uploaded.chunk + data.length <= maxChunkSize
				uploaded[i] += data.length for i of uploaded
				emitProgress false
				dest.end data
			else
				splitAt = maxChunkSize - uploaded.chunk
				uploaded[i] += splitAt for i of uploaded
				emitProgress false
				dest.end data[0 ... splitAt]
				dest.once "resurrected", ->
					uploaded[i] += data.length - splitAt for i of uploaded
					emitProgress false
					dest.end data[splitAt ...]
	pipeFile: ([url, path, replace, ret]..., callback) =>
		ret ?= new events.EventEmitter()
		ret.client = @
		ret.url = url
		ret.path = path
		dns.resolve "api-content.dropbox.com", (err, addr) =>
			getAddr = -> addr[Math.floor Math.random() * addr.length]
			src = request.get url
			src.once "response", (response) =>
				src.url = url
				ret.fileSize = response.headers['content-length']
				if ret.fileSize <= 150 * 1024 * 1024
					@simpleUpload src, path, replace, ret, getAddr, callback
				else if "accept-ranges" of response.headers and response.headers["accept-ranges"] is "bytes"
					src.destroy()
					@rangesChunk url, path, replace, ret, getAddr, callback
				else
					@manualChunk src, path, replace, ret, getAddr, callback
		ret

exports.createApp = (opts) -> new App opts