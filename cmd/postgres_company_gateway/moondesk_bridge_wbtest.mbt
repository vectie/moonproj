///|
test "moondesk loopback origin allows only local 4201 and 4199 origins" {
  assert_eq(
    moondesk_loopback_origin("http://127.0.0.1:4201"),
    Some("http://127.0.0.1:4201"),
  )
  assert_eq(
    moondesk_loopback_origin("http://127.0.0.1:4201/"),
    Some("http://127.0.0.1:4201"),
  )
  assert_eq(
    moondesk_loopback_origin("http://localhost:4199"),
    Some("http://localhost:4199"),
  )
  assert_eq(moondesk_loopback_origin("http://127.0.0.1:8888"), None)
  assert_eq(moondesk_loopback_origin("https://example.com"), None)
  assert_eq(moondesk_loopback_origin(""), None)
}
