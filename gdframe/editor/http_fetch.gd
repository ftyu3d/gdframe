@tool
extends RefCounted
class_name GDFrameHttpFetch
## 编辑器 HTTP 下载（updater / ext_updater 共用）。


static func get_bytes(
	owner: Node,
	url: String,
	timeout_sec: float,
	user_agent: String,
	in_flight_ref: Array = [],
	status_ref: Array = [],
) -> PackedByteArray:
	if url.is_empty():
		if not status_ref.is_empty():
			status_ref[0] = 0
		return PackedByteArray()

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = timeout_sec
	owner.add_child(http)
	if not in_flight_ref.is_empty():
		in_flight_ref[0] = http
	var headers: PackedStringArray = PackedStringArray(["User-Agent: %s" % user_agent])
	var err: Error = http.request(url, headers)
	if err != OK:
		if not in_flight_ref.is_empty() and in_flight_ref[0] == http:
			in_flight_ref[0] = null
		if not status_ref.is_empty():
			status_ref[0] = 0
		http.queue_free()
		return PackedByteArray()

	var result: Array = await http.request_completed
	if not in_flight_ref.is_empty() and in_flight_ref[0] == http:
		in_flight_ref[0] = null
	http.queue_free()
	if result.size() < 4:
		if not status_ref.is_empty():
			status_ref[0] = 0
		return PackedByteArray()
	var response_code: int = int(result[1])
	if not status_ref.is_empty():
		status_ref[0] = response_code
	if response_code < 200 or response_code >= 300:
		return PackedByteArray()
	return result[3] as PackedByteArray


static func get_text(
	owner: Node,
	url: String,
	timeout_sec: float,
	user_agent: String,
	in_flight_ref: Array = [],
	status_ref: Array = [],
) -> String:
	var bytes: PackedByteArray = await get_bytes(
		owner, url, timeout_sec, user_agent, in_flight_ref, status_ref
	)
	if bytes.is_empty():
		return ""
	return bytes.get_string_from_utf8()
