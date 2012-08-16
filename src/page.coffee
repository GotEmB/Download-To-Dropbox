socket = {}

getParams = QueryString.parse URL.parse(window.location.toString()).query
window.history.pushState null, "", "/"

setQuotaText = (quota_info) ->
	used = Math.round((quota_info.normal + quota_info.shared) / quota_info.quota * 1000) / 10
	total = Math.round(quota_info.quota / 1024 / 1024 / 1024 * 10) / 10
	$("#quotaused").text "#{used}% of #{total}GB used"

$(document).ready ->
	socket = io.connect()
	socket.on "connect", ->
		socket.emit "sync_info", getParams, (info) ->
			return alert info.error if info.error?
			$("#displayname").text info.display_name
			setQuotaText info.quota_info
			socket.emit "get_metadata", "/", (data) ->
				columnBox = $ "<div/>", class: "columnbox"
				columnBox_inner = $ "<div/>", class: "columnbox_inner"
				columnBox.append columnBox_inner
				columnBox_inner.append $ "<div/>", class: "column_inback"
				for item in data.contents
					itemBox = $ "<div/>", class: "itembox"
					itemBox.append $ "<div/>", class: "item_image sprite_web #{if item.is_dir then "s_web_folder_32" else "s_web_page_white_32"}"
					itemBox.append $ "<div/>", class: "item_text", text: _(item.path.split "/").last()
					columnBox_inner.append itemBox
				columnBox.appendTo "#columnscontainer"