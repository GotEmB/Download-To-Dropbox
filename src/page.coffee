socket = {}

getParams = QueryString.parse URL.parse(window.location.toString()).query
window.history.pushState null, "", "/"

async = (a, b) ->
	func = if typeof a is "function" then a else if typeof b is "function" then b else null
	timeOut = if typeof a is "number" then a else if typeof b is "number" then b else null
	console.log func: func ? null, timeOut: timeOut ? null
	return unless func?
	setTimeout func, timeOut ? 0

setQuotaText = (quota_info) ->
	used = Math.round((quota_info.normal + quota_info.shared) / quota_info.quota * 1000) / 10
	total = Math.round(quota_info.quota / 1024 / 1024 / 1024 * 10) / 10
	$("#quotaused").text "#{used}% of #{total}GB used"

openDir = (path) ->
	columnsContainer = $ "#columnscontainer"
	socket.emit "get_metadata", path, (data) ->
		columnBox = $ "<div/>", class: "columnbox moveLeft"
		columnBox_inner = $ "<div/>", class: "columnbox_inner"
		columnBox.append columnBox_inner
		columnBox_inner.append $ "<div/>", class: "column_inback"
		data.contents.forEach (item) ->
			itemBox = $ "<div/>", class: "itembox"
			itemBox.append $ "<div/>", class: "item_image sprite_web #{if item.is_dir then "s_web_folder_32" else "s_web_page_white_32"}"
			itemBox.append $ "<div/>", class: "item_text", text: _(item.path.split "/").last()
			itemBox.click ->
				columnBox_inner.children().removeClass "selected"
				itemBox.addClass "selected"
				openDir item.path if item.is_dir
			columnBox_inner.append itemBox
		columnBox.css marginLeft: 10 + columnsContainer.children().length * 330
		columnBox.prependTo columnsContainer
		async 25, ->
			columnBox.removeClass "moveLeft"
			columnsContainer.css width: 10 + columnsContainer.children().length * 330

$(document).ready ->
	socket = io.connect()
	socket.on "connect", ->
		socket.emit "sync_info", getParams, (info) ->
			return alert info.error if info.error?
			$("#displayname").text info.display_name
			setQuotaText info.quota_info
			openDir "/"