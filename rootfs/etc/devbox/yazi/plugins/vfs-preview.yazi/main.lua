-- Previewer for the remote files of yazi (sftp://tailnet, your own SFTP
-- servers), shipped by dev-box. Yazi only previews a remote file once it is
-- downloaded, and says "Remote file, download to preview" until then: this
-- previewer downloads it on its own when it is small enough, and yazi
-- previews it as soon as it lands. A bigger file waits for Enter.
-- 10 MB: a photo, not a video.
local LIMIT = 10 * 1024 * 1024

-- Each file is asked for once per yazi: the previewer runs again at every
-- hover and every redraw.
local asked = ya.sync(function(st, url)
	st.asked = st.asked or {}
	if st.asked[url] then
		return true
	end
	st.asked[url] = true
	return false
end)

local function say(job, text)
	ya.preview_widget(job, ui.Text(ui.Line(text):reverse()):area(job.area):wrap(ui.Wrap.YES))
end

local M = {}

function M:peek(job)
	local size = job.file.cha.len or 0
	if size > LIMIT then
		say(job, string.format("Remote file of %d MB, Enter downloads and opens it", size // (1024 * 1024)))
		return
	end
	if not asked(tostring(job.file.url)) then
		ya.emit("download", { job.file.url })
	end
	say(job, "Downloading to preview...")
end

function M:seek() end

function M:spot(job) require("file"):spot(job) end

return M
