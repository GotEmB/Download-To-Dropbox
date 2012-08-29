socket = null
window.history.pushState null, "", "/"

async = (a, b) ->
	func = if typeof a is "function" then a else if typeof b is "function" then b else null
	timeOut = if typeof a is "number" then a else if typeof b is "number" then b else null
	return unless func?
	setTimeout func, timeOut ? 0

asyncRepeat = (duration, interval, func) ->
	started = Date.now()
	fu = ->
		func()
		if Date.now() - started >= duration
			setTimeout func, interval
		else
			setTimeout fu, interval
	setTimeout fu, interval

setQuotaText = (quota_info) ->
	used = Math.round((quota_info.normal + quota_info.shared) / quota_info.quota * 1000) / 10
	total = Math.round(quota_info.quota / 1024 / 1024 / 1024 * 10) / 10
	$("#quotaused").text "#{used}% of #{total}GB used"

friendlySize = (bytes) ->
	exp = 0
	until bytes / 1024 <= 1
		bytes /= 1024
		exp++
	bytes = Math.round(bytes * 100) / 100
	suffix = switch exp
		when 0 then "bytes"
		when 1 then "KB"
		when 2 then "MB"
		when 3 then "GB"
		when 4 then "TB"
		else "x1024^#{exp} bytes"
	"#{bytes} #{suffix}"

openDir = (path) ->
	columnsContainer = $ "#columnscontainer"
	socket.emit "get_metadata", path, (data, dlds) ->
		columnBox = $ "<div/>", class: "columnbox moveLeft"
		columnBox_inner = $ "<div/>", class: "columnbox_inner"
		columnBox.append columnBox_inner
		columnBox_inner.append $ "<div/>", class: "column_inback"
		newItemBox = (item, insert) ->
			itemBox = $ "<div/>", class: "itembox"
			itemBox.append $ "<div/>", class: "item_image sprite_web #{if item.is_dir then "s_web_folder_32" else "s_web_page_white_32"}"
			itemBox.append $ "<div/>", class: "item_text", text: _(item.path.split "/").last()
			itemBox.click ->
				columnBox.prevUntil().addClass "moveLeft"
				columnsContainer.css width: 50 + columnsContainer.children("div:not(div.moveLeft)").length * 330
				async 500, -> columnBox.prevUntil().remove()
				columnBox_inner.children().removeClass "selected"
				itemBox.addClass "selected"
				openDir item.path if item.is_dir
			if insert is true
				itemBox.insertBefore columnBox_inner.children("div.uploadbox")
			else
				columnBox_inner.append itemBox
		data.contents.forEach newItemBox
		newDldBox = (info, progress) ->
			itemBox = $ "<div/>", class: "itembox"
			itemBox.append $ "<div/>", class: "item_image sprite_web s_web_page_white_get_32"
			itemBox.append $ "<div/>", class: class: "item_text above_progress", text: _(info.path.split "/").last()
			progressBar = $ "<div/>", class: "item_progressbar_back"
			progressBar.append $("<div/>", class: "item_progressbar_front").append $ "<div/>", class: "item_progressbar_anim"
			progressBar.appendTo itemBox
			itemBox.insertBefore columnBox_inner.children("div.uploadbox")
			updateProgress = (progress, state) ->
				progressBar.children("div").css width: "#{progress.percent}%"
				progressBar.attr title: "#{progress.percent}% (#{friendlySize progress.bytes} of #{friendlySize info.fileSize})"
				progressBar.children("div").children("div").css display: if state is "waiting" then "block" else "none"
			updateProgress progress, progress.state if progress?
			socket.on "progress_#{info.hash}", (progress) -> updateProgress progress, "progress"
			socket.on "waiting_#{info.hash}", (progress) -> updateProgress progress, "waiting"
			socket.once "complete_#{info.hash}", (info) ->
				itemBox.remove()
				newItemBox info, true
		do ->
			uploadBox = $ "<div/>", class: "itembox uploadbox"
			uploadBox.append $ "<div/>", class: "item_image sprite_web s_web_page_white_get_32"	
			uploadBox.append $("<div/>", class: "item_text", contenteditable: true, text: "http://")
				.bind("DOMSubtreeModified", -> $(@).text $(@).text())
				.keypress (e) ->
					return if e.which isnt 13
					e.preventDefault()
					socket.emit "downloadtodropbox", $(@).text(), "apath", (info) ->
						uploadBox.children("div.item_text").text "http://"
						newDldBox info
			uploadBox.appendTo columnBox_inner
		dlds.forEach (dld) -> newDldBox dld, dld.progress
		columnBox.css marginLeft: 30 + columnsContainer.children().length * 330
		columnBox.prependTo columnsContainer
		async 25, ->
			columnBox.removeClass "moveLeft"
			startWidth = columnsContainer.width()
			startLeft = $("#mainbox").scrollLeft()
			columnsContainer.css width: 50 + columnsContainer.children().length * 330
			asyncRepeat 600, 1, -> $("#mainbox").scrollLeft startLeft + columnsContainer.width() - startWidth if columnsContainer.css("width") >= $("#mainbox").css "width"

$(document).ready ->
	socket = io.connect()
	socket.on "setupSession", (info) ->
		return alert info.error if info.error?
		$("#displayname").text info.display_name
		setQuotaText info.quota_info
		openDir "/"