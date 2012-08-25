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
			callback request_token.oauth_token, (callback) =>
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
						callback new Client app: @, access_token: qs.parse body

class Client
	oauthHeader = null
	constructor: (opts) ->
		@app = opts.app
		@access_token = opts.access_token
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
	pipeFile: ([url, path, replace]..., callback) =>
		ret = new events.EventEmitter()
		dns.resolve "api-content.dropbox.com", (err, addr) =>
			getAddr = -> addr[Math.floor Math.random() * addr.length]
			src = request.get url
			src.once "response", (response) =>
				ret.fileSize = fileSize = response.headers['content-length']
				ret.emit "started", fileSize
				uploaded = 
					total: 0
					chunk: 0
				emitProgress = (volatile = true) ->
					ret.emit "progress", percent: Math.round(uploaded.total / fileSize * 10000) / 100, bytes: Math.round(uploaded.total * 100) / 100, volatile
				prevRes = null
				dest = null
				newDest = =>
					req =
						url: "https://#{getAddr()}/1/chunked_upload?"
						method: "PUT"
						headers:
							Authorization: oauthHeader
							'Content-Length': Math.min fileSize - uploaded.total, maxChunkSize
						endOnTick: false
					dest = request req, (err, res, body) =>
						console.log err: err, res: res, body: body
						prevRes = JSON.parse body
						if uploaded.total < fileSize
							oldDest = dest
							newDest()
							uploaded.chunk = 0
							oldDest.emit "resurrected"
							oldDest.removeAllListeners()
						else
							req =
								url: "https://#{getAddr()}/1/commit_chunked_upload/#{@app.root}/#{path}"
								method: "POST"
								headers: Authorization: oauthHeader
								form: upload_id: prevRes.upload_id
							request req, (err, res, body) ->
								body = JSON.parse body
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
		ret

exports.createApp = (opts) -> new App opts