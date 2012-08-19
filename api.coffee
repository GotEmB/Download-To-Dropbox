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
		request req, (err, res, body) => callback JSON.parse body
	getMetaData: (path, callback) ->
		req =
			url = "https://api.dropbox.com/1/metadata/#{@app.root}/#{path}"
			method: "GET"
			headers: Authorization: oauthHeader
		request req, (err, res, body) => callback JSON.parse body
	pipeFile: (url, path) ->
		fifo = []
		srcrequest = request.get url
		srcrequest.on "data"

exports.app = App