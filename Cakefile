{spawn} = require "child_process"

spawnProcess = (prc, args, verbose = true, callback = ->) ->
	cp = spawn prc, args
	std = out: "", err: ""
	cp.stdout.on "data", (data) ->
		std.out += data.toString()
		process.stdout.write data.toString() if verbose
	cp.stderr.on "data", (data) ->
		std.err += data.toString()
		process.stderr.write data.toString() if verbose
	cp.on "exit", (code) ->
		if code isnt 0 and !verbose
			process.stdout.write std.out
			process.stderr.write std.err
		callback code is 0

build = (callback) ->
	spawnProcess "iced", ["-c", "-o", "lib", "src"], false, (result) ->
		return callback? false unless result
		spawnProcess "stylus", ["src", "--out", "lib"], false, (result) ->
			callback? result

task "build", "build 'src/' to 'lib/'", ->
	build (result) -> process.exit if result then 0 else 1

task "run", "run 'iced web.coffee'", ->
	spawnProcess "iced", ["web.coffee"]

task "debug", "run 'iced --nodejs --debug-brk web.coffee", ->
	spawnProcess "iced", ["--nodejs", "--debug-brk", "web.coffee"]