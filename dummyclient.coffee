http = require "http"

req = http.request host: "localhost", port: 4998, method: "POST", path: "/1/chunked_upload"

req.on "error", console.log

req.once "drain", -> process.nextTick ->
	req.once "drain", -> process.nextTick ->
		req.once "drain", -> process.nextTick ->
			console.log "Done 3"
		console.log "Done 2"
		req.end "3"
	console.log "Done 1"
	req.write "2"
req.write "1"

exports.req = req


request = require "request"\
src = request.get "http://appldnld.apple.com/QuickTime/041-4337.20120425.sxIv8/QuickTimeInstaller.exe"\
dest = request.post\
    url: "https://api-content.dropbox.com/1/chunked_upload"\
    headers:\
        Authorization: 'OAuth oauth_version="1.0", oauth_signature_method="PLAINTEXT", oauth_consumer_key="pjmupsbonfxm97i", oauth_token="kmaf27vpc9bx48b", oauth_signature="4w7a9pzvx1arbxb&3bcx6vfaj6jf614"'\
        'Content-Length': 20 * 1024 * 1024\
    endOnTick: false\
    , -> console.log destDone: arguments\
done = 0\
src.on "data", (data) ->\
    done += data.length\
    dest.write data\
    console.log data: done\
src.on "end", (data) ->\
    done += data.length if data?\
    dest.end data\
    console.log end: done