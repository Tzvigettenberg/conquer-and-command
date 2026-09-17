extends SceneTree
## Five sequential requests to a URL (default the local room API), one HTTPRequest node each.
## godot --headless --path . --script res://tools/http_probe.gd -- [url]
var n := 0
var started := false
var url := "http://127.0.0.1:8787/health"

func _process(_dt: float) -> bool:
	if not started:
		started = true
		var a := OS.get_cmdline_user_args()
		if a.size() > 0:
			url = a[0]
		_go()
	return false

func _go() -> void:
	var req := HTTPRequest.new()
	req.timeout = 5.0
	# the two things the game does that this probe did not: a CA override and a JSON content type
	var ca := OS.get_environment("SSL_CERT_FILE")
	if n < 3 and ca != "" and FileAccess.file_exists(ca):
		var cert := X509Certificate.new()
		if cert.load(ca) == OK:
			req.set_tls_options(TLSOptions.client(cert))
			print("  (req %d has tls options)" % n)
	root.add_child(req)
	var t0 := Time.get_ticks_msec()
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		print("req %d -> result %d code %d in %d ms: %s" % [n, result, code, Time.get_ticks_msec() - t0, body.get_string_from_utf8().left(60)])
		req.queue_free()
		n += 1
		if n < 5:
			_go()
		else:
			quit())
	var err := req.request(url, PackedStringArray(["Content-Type: application/json"]))
	if err != OK:
		print("request() failed ", err)
		quit()
