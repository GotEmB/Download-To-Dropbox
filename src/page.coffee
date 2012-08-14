setQuotaText = (quota_info) ->
	used = Math.floor((quota_info.normal + quota_info.shared) / quota_info.quota * 1000) / 10
	total = Math.floor(quota_info.quota / 1024 / 1024 / 1024 * 10) / 10
	$("#quotaused").text "#{used}% of #{total}GB used"

$(document).ready ->
	socket = io.connect()
	socket.on "connect", ->
		socket.emit "sync_info", QueryString.parse(URL.parse(window.location.toString()).query), (info) ->
			$("#displayname").text info.display_name
			setQuotaText info.quota_info