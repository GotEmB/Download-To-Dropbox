request = require "request"
qs = require "querystring"

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
		(request.head url).on "response", (response) =>
			fileSize = response.headers['content-length']
			console.log fileSize: fileSize
			
			uploadedSize = 0
			uploadedChunkSize = 0
			srcrequest = request.get url
			dstrequest = request
				url: "https://api-content.dropbox.com/1/chunked_upload"
				method: "PUT"
				headers: Authorization: oauthHeader
			srcrequest.on "data", (data) ->
				doStuff = ->
					dstrequest.write data
					uploadedChunkSize += data.length
					uploadedSize += data.length
					console.log progress: "#{uploadedSize / fileSize * 100}%"
				if uploadedChunkSize + data.length > 10 * 1024 * 1024
					dstrequest.once "response", (response) ->
						body = JSON.parse response.body
						dstrequest = request
							url: "https://api-content.dropbox.com/1/chunked_upload?#{qs.stringify upload_id: body.upload_id, offset: body.offset}"
							method: "PUT"
							headers: Authorization: oauthHeader
						console.log uplink "Opened"
						doStuff()
						srcrequest.resume()
					dstrequest.end()
					srcrequest.pause()
					uploadedChunkSize = 0
					console.log uplink: "Closed"
				else
					doStuff()
			srcrequest.once "end", =>
				dstrequest.once "response", (response) =>
					console.log uplink: "Uploaded", response: response
					dstrequest = request
						url: "https://api-content.dropbox.com/1/commit_chunked_upload/#{@app.root}/#{path}"
						method: "POST"
						headers: Authorization: oauthHeader
						body: upload_id: JSON.parse(response.body).upload_id
					dstrequest.once "response", (response) ->
						console.log uplink: "Commited Upload", response: response
						callback JSON.parse response.body
				dstrequest.end()
				console.log downlink: "EOF"

exports.app = App
