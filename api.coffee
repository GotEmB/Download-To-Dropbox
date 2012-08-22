request = require "request"
qs = require "querystring"
http = require "http"

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
		throw error: "app_key and app_secret are mandatory." if !opts? or !opts.app_key? or !opts.app_secret?
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
				req =
					url: "https://api.dropbox.com/1/oauth/access_token"
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
		req =
			url: "https://api.dropbox.com/1/account/info"
			method: "GET"
			headers: Authorization: oauthHeader
		request req, (err, res, body) -> callback JSON.parse body
	getMetaData: (path, callback) ->
		req =
			url: "https://api.dropbox.com/1/metadata/#{@app.root}/#{path}"
			method: "GET"
			headers: Authorization: oauthHeader
		request req, (err, res, body) -> callback JSON.parse body
	pipeFile: ([url, path, replace]..., callback) =>
		maxChunkSize = 4 * 1024 * 1024
		fileSize = null
		srcRequest = request.get url
		srcRequest.once "response", (response) =>
			fileSize = response.headers['content-length']
			bufferQueue = []
			uploaded =
				total: 0
				chunk: 0
			prevResBody = null
			uploadChunk = (callback) ->
				req =
					url: "https://api-content.dropbox.com/1/chunked_upload?" +
						if prevResBody? then qs.stringify
							upload_id: prevResBody.upload_id
							offset: prevResBody.offset
						else ""
					method: "PUT"
					headers: Authorization: oauthHeader
					body: bufferQueue
				request req, (err, res, body) ->
					prevResBody = JSON.parse body
					uploaded.chunk = 0
					bufferQueue = []
					console.log uploaded: "#{uploaded.total / fileSize * 100}%"
					callback?()
			bufferData = (data) ->
				bufferQueue.push data
				uploaded[i] += data.length for i of uploaded
				console.log downloaded: "#{uploaded.total / fileSize * 100}%"
			srcRequest.on "data", (data) ->
				if uploaded.chunk + data.length <= maxChunkSize
					bufferData data
				else
					srcRequest.pause()
					uploadChunk ->
						bufferData()
						srcRequest.resume()
			srcRequest.once "end", (data) =>
				srcRequest.removeAllListeners "data"
				commitUpload = =>
					req =
						url: "https://api-content.dropbox.com/1/commit_chunked_upload/#{@app.root}/#{path}"
						method: "POST"
						headers: Authorization: oauthHeader
						json: upload_id: prevResBody.upload_id
					request req, (err, res, body) ->
						console.log pipeFile: "Commited upload"
						callback body
				bufferData data if data?
				if uploaded.chunk isnt 0
					uploadChunk commitUpload
				else
					commitUpload()

exports.app = App